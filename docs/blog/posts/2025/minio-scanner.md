---
date: 2025-07-30
categories:
  - MinIO
slug: minio-scanner
draft: false
---

# MinIO 笔记（9）：对象扫描

![](../assert/minio.png)

<!-- more -->

MinIO 中的数据扫描模块（Scanner）用来定期扫描对象来执行修复以及其他操作，包括：

- 统计磁盘使用量。
- 应用 ILM 规则。
- 执行存储桶或站点复制。
- 检查对象是否损坏，执行修复。

## Scanner 子系统

### 主流程
MinIO 启动时会启动一个启动 `initDataScanner` 的协程，用于尝试获取 Scanner 的执行权。`runDataScanner` 函数通过全局的 Leader 锁（一个 shared lock）来确保集群内只有一个 Scanner 实例在运行。当目前的 Scanner 所在实例丢失 Leader 之后，`runDataScanner` 函数会退出，集群开始通过抢锁的方式来获取 Scanner 的执行权。

```go
// initDataScanner will start the scanner in the background.
func initDataScanner(ctx context.Context, objAPI ObjectLayer) {
	go func() {
		r := rand.New(rand.NewSource(time.Now().UnixNano()))
		// Run the data scanner in a loop
		for {
			runDataScanner(ctx, objAPI)
			duration := time.Duration(r.Float64() * float64(scannerCycle.Load()))
			if duration < time.Second {
				// Make sure to sleep at least a second to avoid high CPU ticks.
				duration = time.Second
			}
			time.Sleep(duration)
		}
	}()
}
```

`runDataScanner` 抢到全局锁之后，会启动一个循环，每次循环的主逻辑为：
```mermaid
graph TD
  A[开始] --> B[获取扫描模式];
  B-->C[启动磁盘用量结果搜集协程];
  B-->D[扫描主逻辑];
  D-->E[记录扫描周期的相关指标];
  E-->F[持久化扫描周期相关信息];
```

其中扫描模式是针对对象修复时的检查方式的，包括：

- HealNormalScan：正常扫描模式，会检查对象是否丢失获取过期。
- HealDeepScan：深度扫描模式，会检查 bitrot 错误。

默认情况下，Scanner 不会启用 DeepScan 模式，可以通过环境变量 `MINIO_HEAL_BITROTSCAN` 或 `heal bitrotscan` 配置项来配置，值为：

- 0：HealDeepScan 模式。
- -1：HealNormalScan 模式（默认）。
- [x]m：启用 DeepScan 模式，且扫描时间间隔为 x 月，不能小于 1 个月一次。

当启用了定期使用 DeepScan 时，为了保证每个 Object 都会被检查到，当定期时间到了之后会连续以 1024 次 DeepScan 模式进行扫描，这个数值与后面 Object 被选择进行修复操作的周期相关。

### 磁盘用量结果搜集
该部分会启动一个协程，读取扫描主流程输出的结果，将结果持久化到 `.minio.sys/buckets/.usage.json` 对象中。具体的内容包括如下一些统计信息：

```mermaid
classDiagram
    class DataUsageInfo {
        +uint64 TotalCapacity // 总容量
        +uint64 TotalUsedCapacity // 已使用容量
        +uint64 TotalFreeCapacity // 可用容量
        +time.Time LastUpdate // 最后更新时间
        +uint64 ObjectsTotalCount // 总对象数
        +uint64 VersionsTotalCount // 总版本数
        +uint64 DeleteMarkersTotalCount // 总删除标记数
        +uint64 ObjectsTotalSize // 总对象大小
        +map~string, BucketTargetUsageInfo~ ReplicationInfo // 复制信息
        +uint64 BucketsCount // 总存储桶数
        +map~string, BucketUsageInfo~ BucketsUsage // 存储桶使用信息
        +map~string, uint64~ BucketSizes // 存储桶大小
        +allTierStats TierStats // 存储层统计信息（对应生命周期规则）
    }
    class BucketTargetUsageInfo
    class BucketUsageInfo
    class allTierStats

    DataUsageInfo --* BucketTargetUsageInfo : ReplicationInfo
    DataUsageInfo --* BucketUsageInfo : BucketsUsage
    DataUsageInfo --* allTierStats : TierStats
```

### 扫描主逻辑
在整个集群层面：
```mermaid
graph TD
  A[开始] --> B[获取所有存储桶];
  B --并发进行--> C[在每个 Set 上扫描所有 Bucket];
  B --> D[启动用量扫描结果搜集及合并协程];
  C --> E;
  D --> E["wg.wait()"];
  E --> F[结束];
```
在每一个 ErasureSet 层面，会根据扫描的并发数将所有 Bucket 进行分组进行扫描。并发度计算如下：
```go
// Restrict parallelism for disk usage scanner
// upto GOMAXPROCS if GOMAXPROCS is < len(disks)
maxProcs := runtime.GOMAXPROCS(0)
if maxProcs < len(disks) {
  disks = disks[:maxProcs]
}
```
主要流程如下：

```mermaid
graph TD
  A[开始] --> B[打乱 Bucket 顺序，写入容量为 maxProcs 的channel];
  B --> C[并发启动 maxProcs 个协程，消费 channel];
  C --> D[对消费拿到的 Bucket 执行扫描];
  A --> E[启动 Bucket 扫描结果接收协程];
  D --> F["wg.Wait()"];
  E --> F;
```
针对每个 Bucket 的扫描入口 API 为由 `StorageAPI` 提供的：
```go
NSScanner(ctx context.Context, cache dataUsageCache, updates chan<- dataUsageEntry, scanMode madmin.HealScanMode, shouldSleep func() bool) (dataUsageCache, error)
```
核心实现是通过 `scanDataFolder` 方法，扫描 Bucket 下的对象，并注册一个回调，回调函数内部实现修复、生命周期规则检查等功能。每次扫描并不会把每个对象都扫描到，有一些 skip 的逻辑。下面详细介绍 `scanDataFolder` 的实现。

首先从看贯穿整个扫描过程的 `dataUsageCache` 结构体，该结构体包含了一个 Bucket 下的所有用量统计信息，持久化在 `.minio.sys/buckets/<bucket-name>/..usage-cache.bin` 对象中，包含以下数据：
```mermaid
classDiagram
    class dataUsageCache {
        +dataUsageCacheInfo Info
        +map~string, dataUsageEntry~ Cache
    }
    class dataUsageCacheInfo {
        +string Name
        +uint32 NextCycle
        +time.Time LastUpdate
        +bool SkipHealing
        +lifecycle_Lifecycle lifeCycle
        +chan_dataUsageEntry updates
        +replicationConfig replication
    }
    class dataUsageEntry {
        +dataUsageHashMap Children
        +int64 Size
        +uint64 Objects
        +uint64 Versions
        +uint64 DeleteMarkers
        +sizeHistogram ObjSizes
        +versionsHistogram ObjVersions
        +allTierStats AllTierStats
        +bool Compacted
    }
    class lifecycle_Lifecycle
    class replicationConfig
    class dataUsageHashMap
    class sizeHistogram
    class versionsHistogram
    class allTierStats
    class chan_dataUsageEntry

    dataUsageCache --* dataUsageCacheInfo
    dataUsageCache --* dataUsageEntry
    dataUsageCacheInfo --* lifecycle_Lifecycle
    dataUsageCacheInfo --* replicationConfig
    dataUsageCacheInfo ..> chan_dataUsageEntry
    dataUsageEntry --* dataUsageHashMap
    dataUsageEntry --* sizeHistogram
    dataUsageEntry --* versionsHistogram
    dataUsageEntry --* allTierStats
```

Cache 是一个以 Bucket 目录为根的树形结构，通过 Map 扁平化，所有的 Node 都在 Cache 这个 Map 中，每个 Entry 维护自己的 Children 。树的叶子不一定是一个对象，而可能是其下所有对象的统计信息合并后的结果。

整个扫描过程是一个深度优先遍历，在每一层级，基本流程为：
```mermaid
graph TD
  A[开始] --> B[获取当前目录下所有 Entry];
  B --> C{Entry 是目录？};
  C --Y--> D{上次扫描时是否已存在？};
  D --Y--> E[加入 exist 集合];
  D --N--> F[加入 new 集合];
  C --N--> G[该层级结束，忽略发现的其他目录，对该Entry调用回调];
  E --> H[判断是否应该 Compact];
  F --> H;
  H --> I[递归深入 new 集合];
  H --> J[递归深入 exist 集合];
  J --> M{父级不是 Compact，且当前 Entry 在上次 Cache 中 Compact};

  M --N--> K[根据 Compact 处理 Cache 中的父子关系];
  M --Y--> N[16 轮扫描一次，其余跳过];  
  I-->K;
  K --> L[返回];
  G --> L[返回];
  N --> L[返回];
```
Compact 会发生在：

- 目录（包含子目录）下包含少于 `dataScannerCompactLeastObject`（500） 个 Object
- 目录（非 Bucket 层级）包含至少 `dataScannerCompactAtFolders`（2500） 个子目录。
- 目录只包含 `Object`（完整的 Object 目录，不是指 xl.meta 那一层）没有其他子目录。
- 目录（包含 Bucket 目录）下包含超过 `dataScannerForceCompactAtFolders` （250_000）个子目录。

### ScanItem 操作
上述扫描主逻辑的递归基是发现一个 xl.meta 文件，即一个 ScanItem。在 Scanner 入口处，对每一个 ScanItem 会注册一个回调，回调内部处理各种操作，包括：

- 修复对象
- 生命周期规则
- 副本操作

对于修复、副本操作：依据 Item 是否被选中，决定是否进行修复操作，每个 Object 会在 1024 次扫描中修复一次。

对于生命周期规则的运用：会根据规则进行匹配计算，生成对应的动作，由于扫描 Compact 和 Skip 的机制存在，每个 Object 至少会在 16 轮扫描中被扫描到。