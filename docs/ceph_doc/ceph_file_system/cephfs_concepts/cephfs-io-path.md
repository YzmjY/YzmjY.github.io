---
title: CEPHFS IO路径
---

# CEPHFS IO 路径

CephFS 中的所有文件数据都存储为 RADOS 对象。CephFS 客户端可以直接访问 RADOS 以操作文件数据。MDS 仅处理元数据操作。

![IO 路径](../../image/cephfs-io-path.png)

要读/写 CephFS 文件，客户端需要具有相应 inode 的文件读写权限。如果客户端没有所需的权限(1)，它会向 MDS 发送“权限消息”，告诉 MDS 它想要什么。MDS 会根据情况判断是否可以赋予客户端对应的权限。一旦客户端具有文件读写权限，它就可以直接访问 RADOS 以读/写文件数据。文件数据以 `<inode number>.<object index>` 的形式存储为 RADOS 对象。有关更多信息，请参阅[架构](../../architecture/architecture.md)的“数据条带化”部分。如果文件仅由一个客户端打开，则 MDS 还会授予唯一的客户端文件的缓存读写（`file cache/buffer`）权限。`file cache` 的权限意味着客户端缓存可以满足文件读取。`file buffer` 权限意味着文件写入可以在客户端缓存中缓冲。
{.annotate}

1. 对应CephFS中的Caps。
