---
date: 2025-07-27
categories:
  - MinIO
slug: minio-read-write
draft: true
---

# MinIO 笔记（6）: 读写流程

![](../assert/minio.png)

<!-- more -->

## EC 编码

```go
// newFileInfo - initializes new FileInfo, allocates a fresh erasure info.
func newFileInfo(object string, dataBlocks, parityBlocks int) (fi FileInfo) {
	fi.Erasure = ErasureInfo{
		Algorithm:    erasureAlgorithm,
		DataBlocks:   dataBlocks,
		ParityBlocks: parityBlocks,
		BlockSize:    blockSizeV2,
		Distribution: hashOrder(object, dataBlocks+parityBlocks),
	}
	return fi
}
```
常量：
```go
const erasureAlgorithm = "rs-vandermonde"

	// Block size used in erasure coding version 2.
	blockSizeV2 = 1 * humanize.MiByte
```

encoder
```go
// Erasure - erasure encoding details.
type Erasure struct {
	encoder                  func() reedsolomon.Encoder
	dataBlocks, parityBlocks int
	blockSize                int64
}
```

一个数据 Block 会被切分为 `dataBlocks` 个 shard，切分规则：等分，不能等分的最后一个 shard 会补 0。

每个 shard 的 size ：
```go
blockSize = ceilFrac(e.blockSize, int64(e.dataBlocks)) 
```

encode 过程：

decode 过程：

