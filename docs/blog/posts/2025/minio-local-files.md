---
date: 2025-07-23
categories:
  - MinIO
draft: false
---

# MinIO 笔记（2）: 本地文件组织

![](../assert/minio.png)

<!-- more -->

根据 MinIO 文档，MinIO 对存储的要求如下：

- 使用本地存储而不是 NAS 等网络存储。
- 使用 XFS 文件系统格式化磁盘。MinIO 在开发和测试时使用的是 XFS，因此使用 XFS 文件系统可以更好的保证可用性。
- 重启之后保证磁盘的挂载和映射一致。

MinIO 采用本地文件系统组织数据，并且推荐使用 XFS 文件系统。MinIO 要求独占单个驱动或存储卷，其他进程不应该访问该卷，否则会导致数据被损坏。


## Object 管理
MinIO 作为一个对象存储系统，使用扁平化的 Bucket 来组织 Object 数据。一个 Bucket 在文件系统中表现为位于顶层目录的一个子目录，Bucket 下可以承载任意数量的 Object。

例如，一个 MinIO 的存储驱动下可能有如下结构的文件系统：
```
/ #root
/images/
   2020-01-02-MinIO-Diagram.png
   2020-01-03-MinIO-Advanced-Deployment.png
   MinIO-Logo.png
/videos/
   2020-01-04-MinIO-Interview.mp4
/articles/
   /john.doe/
      2020-01-02-MinIO-Object-Storage.md
      2020-01-02-MinIO-Object-Storage-comments.json
   /jane.doe/
      2020-01-03-MinIO-Advanced-Deployment.png
      2020-01-02-MinIO-Advanced-Deployment-comments.json
      2020-01-04-MinIO-Interview.md
```

在上述例子中，`/images/`、`/videos/`和`/articles/`都是 Bucket，而 Bucket 下的文件则是 Object 的数据，这些数据经过了 MinIO 的编码。此外，上述结构有另一个特点，我们知道对象存储的 Object 本没有目录层级的概念，而是扁平化的存在于 Bucket 中，通过 ObjectName 区分，但上述有些 Object 存在类似文件系统中的层级关系，这种层级关系是 MinIO 处理带有 `/` 的 Object 名称的方式，Object 名称被`/`切分，每一部分被视为一个前缀，属于对象名称的一部分。用户在上传一个 Object 时（以`/articles/john.doe/ 2020-01-02-MinIO-Object-Storage.md`为例），MinIO 会自动处理`/articles/john.doe/` 这些前缀，通过文件系统的层级关系来管理不同前缀的 Object。

在 Object 目录下，存在数据目录、元数据文件，数据目录下是经过 MinIO 编码后的文件，元数据文件是 MinIO 内部使用的文件，用于存储 Object 的元数据信息。
```bash
2020-01-04-MinIO-Interview.md/
	data-dir/
		part.1
		part.2
	xl.meta
```


如此处理决定了 MinIO 的一个特点，即不能存在如下：
```bash
prefix/object1
prefix/object1/object2
```
上述 object2 以 object1 为前缀，这在 MinIO 中是不允许的。

## 系统保留桶
MinIO 在启动时会自动创建一个`.minio.sys`桶，该桶为系统保留使用，存储一些系统元数据、配置信息以及临时对象。元数据桶下包含如下内容：

- `buckets`: 存放与 Bucket 的一些元数据，包括：Bucket 用量、Scanner 扫描、数据修复等相关信息。
- `config`: 存放系统配置、IAM 配置。
- `format.json`: 一个 JSON 格式的文件，保存磁盘格式化信息，MinIO 依据该文件判断磁盘是否格式化。
- `multipart`: 存放分片上传过程中的中间文件。
- `pool.bin`: 存放存储池相关的元数据。
- `tmp`: 存放临时文件。

与用户Bucket一样，`.minio.sys`桶下的这些目录下的 Object 也是以 EC 的方式被编码到各个节点上进行存储（format.json 除外，该文件是每个磁盘各自的，保存 disk_id 及格式化信息）。

### Buckets
`Buckets`目录下有如下 Object：
```
.
├── .background-heal.json
│   └── xl.meta
├── .bloomcycle.bin
│   └── xl.meta
├── data
│   ├── .metadata.bin
│   │   └── xl.meta
│   ├── .usage-cache.bin
│   │   └── xl.meta
│   └── .usage-cache.bin.bkp
│       └── xl.meta
├── .healing.bin
├── .usage-cache.bin
│   └── xl.meta
├── .usage-cache.bin.bkp
│   └── xl.meta
└── .usage.json
    └── xl.met
```

`.background-heal.json` 存放 Scanner 运行过程中的 Scan 模式，依据 Cycle 信息决定是否采用修复 bitrot：

```go
type backgroundHealInfo struct {
	BitrotStartTime  time.Time           `json:"bitrotStartTime"`
	BitrotStartCycle uint64              `json:"bitrotStartCycle"`
	CurrentScanMode  madmin.HealScanMode `json:"currentScanMode"`
}
```

`.bloomcycle.bin` 存放 Scanner 的周期信息，包括当前周期、下一个周期、扫描开始时间、周期完成时间等。(该名称是历史原因，当前已经没有使用布隆过滤器了)。

```go
type currentScannerCycle struct {
	current        uint64
	next           uint64
	started        time.Time
	cycleCompleted []time.Time
}
```

`.healing.bin` 对应 `healingTracker`，用来持久化一次新磁盘格式化和数据恢复过程中的相关信息：
```go
type healingTracker struct {
        disk StorageAPI    `msg:"-"`
        mu   *sync.RWMutex `msg:"-"`

        ID         string    // Disk ID
        PoolIndex  int       // Pool index
        SetIndex   int       // Set index
        DiskIndex  int       // Disk index
        Path       string    // Path to drive
        Endpoint   string    // Endpoint of drive
        Started    time.Time
        LastUpdate time.Time

        ObjectsTotalCount uint64
        ObjectsTotalSize  uint64

        ItemsHealed uint64
        ItemsFailed uint64

        BytesDone   uint64
        BytesFailed uint64

        // Last object scanned.
        Bucket string `json:"-"`
        Object string `json:"-"`

        // Numbers when current bucket started healing,
        // for resuming with correct numbers.
        ResumeItemsHealed  uint64 `json:"-"`
        ResumeItemsFailed  uint64 `json:"-"`
        ResumeItemsSkipped uint64 `json:"-"`
        ResumeBytesDone    uint64 `json:"-"`
        ResumeBytesFailed  uint64 `json:"-"`
        ResumeBytesSkipped uint64 `json:"-"`

        // Filled on startup/restarts.
        QueuedBuckets []string

        // Filled during heal.
        HealedBuckets []string

        // ID of the current healing operation
        HealID string

        ItemsSkipped uint64
        BytesSkipped uint64

        RetryAttempts uint64

        Finished bool // finished healing, whether with errors or not

        // Add future tracking capabilities
        // Be sure that they are included in toHealingDisk
}
```

`.usage-cache.bin` 缓存 Scanner 过程中搜集的用量信息，一些情况下直接使用缓存中的信息，而不是重新计算。


`.usage.json` 存放总的用量信息，内容如下：
```go
type DataUsageInfo struct {
	TotalCapacity     uint64 `json:"capacity,omitempty"`
	TotalUsedCapacity uint64 `json:"usedCapacity,omitempty"`
	TotalFreeCapacity uint64 `json:"freeCapacity,omitempty"`

	// LastUpdate is the timestamp of when the data usage info was last updated.
	// This does not indicate a full scan.
	LastUpdate time.Time `json:"lastUpdate"`

	// Objects total count across all buckets
	ObjectsTotalCount uint64 `json:"objectsCount"`

	// Versions total count across all buckets
	VersionsTotalCount uint64 `json:"versionsCount"`

	// Delete markers total count across all buckets
	DeleteMarkersTotalCount uint64 `json:"deleteMarkersCount"`

	// Objects total size across all buckets
	ObjectsTotalSize uint64                           `json:"objectsTotalSize"`
	ReplicationInfo  map[string]BucketTargetUsageInfo `json:"objectsReplicationInfo"`

	// Total number of buckets in this cluster
	BucketsCount uint64 `json:"bucketsCount"`

	// Buckets usage info provides following information across all buckets
	// - total size of the bucket
	// - total objects in a bucket
	// - object size histogram per bucket
	BucketsUsage map[string]BucketUsageInfo `json:"bucketsUsageInfo"`
	// Deprecated kept here for backward compatibility reasons.
	BucketSizes map[string]uint64 `json:"bucketsSizes"`

	// TierStats contains per-tier stats of all configured remote tiers
	TierStats *allTierStats `json:"tierStats,omitempty"`
}
```

除上述 Object 外，针对每一个单独的 Bucket，Buckets 目录下都用一个与 Bucket 同名的目录，用来存放 Bucket 的相关信息。例如上述的：
```go
├── data
│   ├── .metadata.bin
│   │   └── xl.meta
│   ├── .usage-cache.bin
│   │   └── xl.meta
│   └── .usage-cache.bin.bkp
│       └── xl.meta
```
`.usage-cache.bin`与上层目录中的作用一致。

`.metadata.bin` 存放该 Bucket 的元信息：
```go
// BucketMetadata contains bucket metadata.
// When adding/removing fields, regenerate the marshal code using the go generate above.
// Only changing meaning of fields requires a version bump.
// bucketMetadataFormat refers to the format.
// bucketMetadataVersion can be used to track a rolling upgrade of a field.
type BucketMetadata struct {
	Name                        string
	Created                     time.Time
	LockEnabled                 bool // legacy not used anymore.
	PolicyConfigJSON            []byte
	NotificationConfigXML       []byte
	LifecycleConfigXML          []byte
	ObjectLockConfigXML         []byte
	VersioningConfigXML         []byte
	EncryptionConfigXML         []byte
	TaggingConfigXML            []byte
	QuotaConfigJSON             []byte
	ReplicationConfigXML        []byte
	BucketTargetsConfigJSON     []byte
	BucketTargetsConfigMetaJSON []byte

	PolicyConfigUpdatedAt            time.Time
	ObjectLockConfigUpdatedAt        time.Time
	EncryptionConfigUpdatedAt        time.Time
	TaggingConfigUpdatedAt           time.Time
	QuotaConfigUpdatedAt             time.Time
	ReplicationConfigUpdatedAt       time.Time
	VersioningConfigUpdatedAt        time.Time
	LifecycleConfigUpdatedAt         time.Time
	NotificationConfigUpdatedAt      time.Time
	BucketTargetsConfigUpdatedAt     time.Time
	BucketTargetsConfigMetaUpdatedAt time.Time
	// Add a new UpdatedAt field and update lastUpdate function

	// Unexported fields. Must be updated atomically.
	policyConfig           *policy.BucketPolicy
	notificationConfig     *event.Config
	lifecycleConfig        *lifecycle.Lifecycle
	objectLockConfig       *objectlock.Config
	versioningConfig       *versioning.Versioning
	sseConfig              *bucketsse.BucketSSEConfig
	taggingConfig          *tags.Tags
	quotaConfig            *madmin.BucketQuota
	replicationConfig      *replication.Config
	bucketTargetConfig     *madmin.BucketTargets
	bucketTargetConfigMeta map[string]string
}
```

### config

### format.json
存储磁盘的格式化信息，包括 ID、版本、格式以及纠删集配置、磁盘信息。
```go
// formatErasureV3 struct is same as formatErasureV2 struct except that formatErasureV3.Erasure.Version is "3" indicating
// the simplified multipart backend which is a flat hierarchy now.
// In .minio.sys/multipart we have:
// sha256(bucket/object)/uploadID/[xl.meta, part.1, part.2 ....]
type formatErasureV3 struct {
	formatMetaV1
	Erasure struct {
		Version string `json:"version"` // Version of 'xl' format.
		This    string `json:"this"`    // This field carries assigned disk uuid.
		// Sets field carries the input disk order generated the first
		// time when fresh disks were supplied, it is a two dimensional
		// array second dimension represents list of disks used per set.
		Sets [][]string `json:"sets"`
		// Distribution algorithm represents the hashing algorithm
		// to pick the right set index for an object.
		DistributionAlgo string `json:"distributionAlgo"`
	} `json:"xl"`
	Info DiskInfo `json:"-"`
}

// format.json currently has the format:
// {
//   "version": "1",
//   "format": "XXXXX",
//   "XXXXX": {
//
//   }
// }
// Here "XXXXX" depends on the backend, currently we have "fs" and "xl" implementations.
// formatMetaV1 should be inherited by backend format structs. Please look at format-fs.go
// and format-xl.go for details.

// Ideally we will never have a situation where we will have to change the
// fields of this struct and deal with related migration.
type formatMetaV1 struct {
	// Version of the format config.
	Version string `json:"version"`
	// Format indicates the backend format type, supports two values 'xl' and 'fs'.
	Format string `json:"format"`
	// ID is the identifier for the minio deployment
	ID string `json:"id"`
}

// DiskInfo is an extended type which returns current
// disk usage per path.
// The above means that any added/deleted fields are incompatible.
//
// The above means that any added/deleted fields are incompatible.
//
//msgp:tuple DiskInfo
type DiskInfo struct {
	Total      uint64
	Free       uint64
	Used       uint64
	UsedInodes uint64
	FreeInodes uint64
	Major      uint32
	Minor      uint32
	NRRequests uint64
	FSType     string
	RootDisk   bool
	Healing    bool
	Scanning   bool
	Endpoint   string
	MountPath  string
	ID         string
	Rotational bool
	Metrics    DiskMetrics
	Error      string // carries the error over the network
}

```

### multipart
该目录下用来保存分片上传时的中间文件。分片上传的过程中，在该目录下会存在类似如下结构的中间目录：

```
.
└── 6445a143ed2167ea4c1af3771095f1fa56274213dfd738e1c6936dc0a19db464
    └── de6b968f-95a4-4b3e-86e3-0844955463b6x1750142093339803801
        ├── 85fd69e6-aa55-4514-8970-ce6bc3a4c20a
        │   ├── part.1
        │   ├── part.1.meta
        │   ├── part.2
        │   └── part.2.meta
        └── xl.meta
```

分片上传的一般步骤为：

- `NewMultipartUpload`：初始化分片上传，该调用会在`multipart`目录下生成上传的 Object 对应的 xl.meta 文件，路径为：SHA256(bucket/object)/uploadID/xl.meta
- `UploadPart`：上传分片，该调用会在`multipart`目录下生成分片对应的文件，路径为：SHA256(bucket/object)/uploadID/part.N(part.N.meta)
- `CompleteMultipartUpload`：完成分片上传，该调用会将`multipart`目录下的文件rename到对应的用户Bucket下。

按照 MinIO 的设计，在分片上传过程中如果发生中断，导致没有调用`CompleteMultipartUpload`，那么此时产生的中间文件不会立马被删除，也不会一直残留，碎片文件会在24小时后（默认设置）自动删除。

### pool.bin
保存存储池的相关元数据。

```go
type poolMeta struct {
	Version int          `msg:"v"`
	Pools   []PoolStatus `msg:"pls"`

	// Value should not be saved when we have not loaded anything yet.
	dontSave bool `msg:"-"`
}

type PoolStatus struct {
	ID           int                   `json:"id" msg:"id"`
	CmdLine      string                `json:"cmdline" msg:"cl"`
	LastUpdate   time.Time             `json:"lastUpdate" msg:"lu"`
	Decommission *PoolDecommissionInfo `json:"decommissionInfo,omitempty" msg:"dec"`
}

// PoolDecommissionInfo currently decommissioning information
type PoolDecommissionInfo struct {
	StartTime   time.Time `json:"startTime" msg:"st"`
	StartSize   int64     `json:"startSize" msg:"ss"`
	TotalSize   int64     `json:"totalSize" msg:"ts"`
	CurrentSize int64     `json:"currentSize" msg:"cs"`

	Complete bool `json:"complete" msg:"cmp"`
	Failed   bool `json:"failed" msg:"fl"`
	Canceled bool `json:"canceled" msg:"cnl"`

	// Internal information.
	QueuedBuckets         []string `json:"-" msg:"bkts"`
	DecommissionedBuckets []string `json:"-" msg:"dbkts"`

	// Last bucket/object decommissioned.
	Bucket string `json:"-" msg:"bkt"`
	// Captures prefix that is currently being
	// decommissioned inside the 'Bucket'
	Prefix string `json:"-" msg:"pfx"`
	Object string `json:"-" msg:"obj"`

	// Verbose information
	ItemsDecommissioned     int64 `json:"objectsDecommissioned" msg:"id"`
	ItemsDecommissionFailed int64 `json:"objectsDecommissionedFailed" msg:"idf"`
	BytesDone               int64 `json:"bytesDecommissioned" msg:"bd"`
	BytesFailed             int64 `json:"bytesDecommissionedFailed" msg:"bf"`
}
```

### tmp
各种临时文件，例如上述分片上传过程，在上传一个part时，也会先写入该目录，完成后再`rename`到 multipart 目录下。

也包括系统`.trash`目录，临时删除文件，该目录定时被清理（周期为最大 25ms）。

## 用户定义桶

即用户显式创建的存储桶，每个桶内可以上传任意数量的 Object，Object 的名称可以有类似文件的层级结构,对于数据量小于128K的Object，数据会直接内联到 xl.meta 文件中，而不会创建一个数据目录，否则将会创建一个具有 uuid 的数据目录，用 part.N 的文件来存储数据。
一个典型的用户 Bucket 结构如下：
```
.
├── build.sh
│   └── xl.meta
├── go.mod
│   └── xl.meta
├── subdir
│   └── test.txt
│       ├── b265232c-9542-4910-9594-c875c4810f3d
│       │   └── part.1
│       └── xl.meta
└── test.txt
    ├── 85fd69e6-aa55-4514-8970-ce6bc3a4c20a
    │   ├── part.1
    │   ├── part.10
    │   ├── part.11
    │   ├── part.12
    │   ├── part.13
    │   ├── part.14
    │   ├── part.15
    │   ├── part.16
    │   ├── part.2
    │   ├── part.3
    │   ├── part.4
    │   ├── part.5
    │   ├── part.6
    │   ├── part.7
    │   ├── part.8
    │   └── part.9
    └── xl.meta
```