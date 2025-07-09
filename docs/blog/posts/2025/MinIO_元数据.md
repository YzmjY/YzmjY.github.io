---
date: 2025-06-23
categories:
  - MinIO
draft: false
---

# MinIO: 元数据组织
---
![](./assert/minio.png)

## Object元数据
MinIO的元数据对应xl.meta文件，该文件记录了一个Object的所有元数据条目，包括多版本、删除标记等。

xl.meta文件对应的数据结构如下：

```go
type xlMetaV2 struct {
	versions []xlMetaV2ShallowVersion

	// data will contain raw data if any.
	// data will be one or more versions indexed by versionID.
	// To remove all data set to nil.
	data xlMetaInlineData

	// metadata version.
	metaV uint8
}
```

<!-- more -->

- `versions`: 多版本元数据条目。 
- `data`: inline数据，当Object数据小于128K时不会创建数据目录，直接内联到元数据中。
- `metaV`: 元数据版本，目前为3。

`versions`中每一个元素对应一个版本的元数据条目，对应的数据结构如下：
```go
type xlMetaV2ShallowVersion struct {
	header xlMetaV2VersionHeader
	meta   []byte // meta数据buf
}
```
其中`header`包括完整的元数据的概要信息，包括如下字段：
```go
type xlMetaV2VersionHeader struct {
	VersionID [16]byte
	ModTime   int64
	Signature [4]byte
	Type      VersionType
	Flags     xlFlags
	EcN, EcM  uint8 // Note that these will be 0/0 for non-v2 objects and older xl.meta
}
``` 

- `VersionID`: 多版本中的版本ID，每个Version不同。
- `ModTime`: 修改时间。
- `Signature`: 根据`xlMetaV1Object`计算出的一个签名，一个Object的某一Version的签名在所有磁盘上一致。
- `Type`: 标识元数据类型，包括：`ObjectType`/`DeleteType`/`LegacyType`,分别标识Object类型、删除标记、历史版本（需要向后兼容）。
- `Flags`: 一些标志位的或，包括是否使用了数据目录（非内联或者完成了restore的分层对象）、是否内联数据、是否为FreeVersion（用来处理分层对象，创建一个FreeVersion等待异步删除远端的数据）
- `EcN`, `EcM`:EC配置 

根据`meta`字段反序列化得到：
```go
type xlMetaV2Version struct {
	Type             VersionType           `json:"Type" msg:"Type"`
	ObjectV1         *xlMetaV1Object       `json:"V1Obj,omitempty" msg:"V1Obj,omitempty"`
	ObjectV2         *xlMetaV2Object       `json:"V2Obj,omitempty" msg:"V2Obj,omitempty"`
	DeleteMarker     *xlMetaV2DeleteMarker `json:"DelObj,omitempty" msg:"DelObj,omitempty"`
	WrittenByVersion uint64                `msg:"v"` // Tracks written by MinIO version
}
```
字段含义：

- `Type`: 根据`Type`字段的不同，部分字段可能为`nil`。
- `ObjectV1`: 历史版本，现在不再使用，只做向后兼容性的处理。
- `ObjectV2`: 当前版本，包含了Object的元数据信息。
- `DeleteMarker`: 删除标记，当Object被删除时，会设置该字段。
- `WrittenByVersion`: 写入该元数据的MinIO版本，对应Release时间戳。

### `xlMetaV2Object`字段解析
完整的`xlMetaV2Object`数据结构定义如下：
```go
type xlMetaV2Object struct {
	VersionID          [16]byte          `json:"ID" msg:"ID"`                                    // Version ID
	DataDir            [16]byte          `json:"DDir" msg:"DDir"`                                // Data dir ID
	ErasureAlgorithm   ErasureAlgo       `json:"EcAlgo" msg:"EcAlgo"`                            // Erasure coding algorithm
	ErasureM           int               `json:"EcM" msg:"EcM"`                                  // Erasure data blocks
	ErasureN           int               `json:"EcN" msg:"EcN"`                                  // Erasure parity blocks
	ErasureBlockSize   int64             `json:"EcBSize" msg:"EcBSize"`                          // Erasure block size
	ErasureIndex       int               `json:"EcIndex" msg:"EcIndex"`                          // Erasure disk index
	ErasureDist        []uint8           `json:"EcDist" msg:"EcDist"`                            // Erasure distribution
	BitrotChecksumAlgo ChecksumAlgo      `json:"CSumAlgo" msg:"CSumAlgo"`                        // Bitrot checksum algo
	PartNumbers        []int             `json:"PartNums" msg:"PartNums"`                        // Part Numbers
	PartETags          []string          `json:"PartETags" msg:"PartETags,allownil"`             // Part ETags
	PartSizes          []int64           `json:"PartSizes" msg:"PartSizes"`                      // Part Sizes
	PartActualSizes    []int64           `json:"PartASizes,omitempty" msg:"PartASizes,allownil"` // Part ActualSizes (compression)
	PartIndices        [][]byte          `json:"PartIndices,omitempty" msg:"PartIdx,omitempty"`  // Part Indexes (compression)
	Size               int64             `json:"Size" msg:"Size"`                                // Object version size
	ModTime            int64             `json:"MTime" msg:"MTime"`                              // Object version modified time
	MetaSys            map[string][]byte `json:"MetaSys,omitempty" msg:"MetaSys,allownil"`       // Object version internal metadata
	MetaUser           map[string]string `json:"MetaUsr,omitempty" msg:"MetaUsr,allownil"`       // Object version metadata set by user
}
```
各字段含义：

- `VersionID`: 版本ID，每个Object的不同版本的VersionID不同。
- `DataDir`: 数据目录ID，标识该版本数据存储在哪个数据目录。
- `ErasureAlgorithm`: 纠删码算法，目前只支持`ReedSolomon`。
- `ErasureM`: 纠删码数据块数。
- `ErasureN`: 纠删码校验块数。
- `ErasureBlockSize`: 纠删码块大小。
- `ErasureIndex`: 纠删码磁盘索引，标识当前磁盘上的数据块在纠删码中的索引。
- `ErasureDist`: 纠删码分布，标识磁盘与纠删码索引的对应关系，第ErasureDist[i]个纠删码编码数据位于第i个磁盘上。
- `BitrotChecksumAlgo`: 位旋转校验和算法，目前只支持`HighwayHash`。
- `PartNumbers`: Part编号集合，标识该版本数据的所有Part分片编号。
- `PartETags`: Part的ETag集合。
- `PartSizes`: Part大小集合，标识该版本数据的每个Part大小。
- `PartActualSizes`: Part实际大小集合，标识该版本数据的每个Part实际大小（压缩后）。
- `PartIndices`: Part索引集合，标识该版本数据的每个Part索引（压缩后）。
- `Size`: 该版本Object大小。
- `ModTime`: 该版本Object修改时间。
- `MetaSys`: 该版本Object内部元数据KV。
- `MetaUser`: 该版本Object用户自定义元数据KV。

系统内部使用的元数据KV对的Key以`x-minio-internal-`开头，常见的系统内部的元数据KV有：

- "tier-free-versionID": FreeVersion对应的Version ID。
- "tier-free-marker"： 标识该Version是否为FreeVersion。
- "tier-skip-fvid"：标识是否跳过该FreeVersion，在删除分层存储的对象时远端对象已经被删除（可能由于过期等机制）时使用。
- "transition-status": 分层对象的转换状态，包括`pending`（转换中）、`completed`（转换完成）。
- "transitioned-object": 分层对象在远端对应的ObjectName。
- "transitioned-versionID"：该版本的分层对象在远端对象对应的VersionID。
- "transition-tier"：分层存储的远端存储类。
- "crc": 上传时计算的CRC32C校验和。
- "metacache-part-%d": List过程中产生的metacache数据块。
- "inline-data": 标识是否内联数据。

// TODO: 
- "replication-reset" 
- "replication-status"
- "replication-timestamp"
- "replica-status"
- "replica-timestamp"
- "tagging-timestamp"
- "objectlock-retention-timestamp"
- "objectlock-legalhold-timestamp"
- 

### xl.meta 落盘流程

对应`xlStorage`的`WriteMetadata`方法。函数签名为：

```go
func (s *xlStorage) WriteMetadata(ctx context.Context, origvolume, volume, path string, fi FileInfo) (err error)
```
入参：

- `volume`/`path`: 标识磁盘位置。
- `fi`: 待写入的元数据。

根据上文对于元数据数据结构的分析，可见多个版本对应同一个xl.meta文件，xl.meta内部通过一个数据区分不同的version。xl.meta文件的完整写入流程如下：

#### 构造xlMetaV2
完成`FileInfo`到`xlMetaV2Version`的数据转换，判断是对已有version的修改还是新增version，新增version插入`xlMetaV2.versions`的前端。

#### 编码
编码xlMetaV2，具体编码格式如下：

```
+--------------------------------------------------------------------+
|                     xlHeader (magic,"XL2  ")                       |
+--------------------------------------------------------------------+
|                  xlVersionCurrent(xl version)                      |
+--------------------------------------------------------------------+
|          Metadata Block Size (4字节, 后续元数据块的总长度)             |
+--------------------------------------------------------------------+
|                                                                    |
|                            Metadata Block                          |
|                                                                    |
| +----------------------------------------------------------------+ |
| |                        xlHeaderVersion (3)                     | |
| +----------------------------------------------------------------+ |
| |                         xlMetaVersion (3)                      | |
| +----------------------------------------------------------------+ |
| |                        Number of Versions                      | |
| +----------------------------------------------------------------+ |
| |                 Version 1 Header (MessagePack)                 | |
| +----------------------------------------------------------------+ |
| |                 Version 1 Meta (MessagePack)                   | |
| +----------------------------------------------------------------+ |
| |                           ...                                  | |
| +----------------------------------------------------------------+ |
| |                         Version N Header                       | |
| +----------------------------------------------------------------+ |
| |                          Version N Meta                        | |
| +----------------------------------------------------------------+ |
|                                                                    |
+--------------------------------------------------------------------+
|                          CRC Checksum (5Byte)                      |
+--------------------------------------------------------------------+
|                             Inline Data                            |
+--------------------------------------------------------------------+
```
#### 落盘
写磁盘，对于临时创建的对象（例如在 `listObjects()` 调用期间创建的对象），可以不用使用sync落盘，其余的写入都是sync的。

## Bucket元数据
每个Bucket的元数据对应一个在系统保留Bucket(`.minio.sys`)下的一个Object，具体名称为：`buckets/<bucketname>/.metadata.bin`。该文件记录了一个Bucket所有的元数据信息（不包括使用量等统计信息），对应的数据结构为：

```go
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
  ...
}
```
由上述字段描述，Bucket元数据包含一个Bucket的访问策略、生命周期配置、多版本配置、多副本配置等等。

### Bucket元数据管理
Bucket元数据的管理对应`BucketMetadataSys`子模块，该模块在内存中缓存了一个MinIO集群所有Bucket的元数据，提供了BucketMeta的读写接口。











