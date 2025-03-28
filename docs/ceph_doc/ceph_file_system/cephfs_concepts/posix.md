---
date: 2025-03-27
title: POSIX兼容性
---

# 与POSIX的区别
CephFS 旨在尽可能遵守 POSIX 语义。例如，与 NFS 等许多其他常见网络文件系统相比，CephFS 在客
户端之间保持强大的缓存一致性。目标是使通过文件系统通信的进程在不同主机上时的行为与在同一主机上时
的行为相同。

但是，由于各种原因，CephFS 在一些地方与严格的 POSIX 语义存在差异：

- 如果客户端正在写入文件并失败，则其写入不一定是原子的。也就是说，客户端可能会对使用 O_SYNC 和
  8 MB 缓冲区打开的文件调用 write(2)，然后崩溃，并且写入可能只部分应用。(几乎所有文件系统，
  甚至本地文件系统，都有这种行为。)

- 在不同的写入者同时写入情况下，跨越对象边界的写入不一定是原子的。这意味着您可以让写入者 A 写入
  “aa|aa” 的同时，写入者 B 写入 “bb|bb” （其中 | 是对象边界），可能会得到 “aa|bb” ，而不是
  正确的 “aa|aa” 或 “bb|bb”。

- Sparse files propagate incorrectly to the stat(2) st_blocks field. Because 
 CephFS does not explicitly track which parts of a file are allocated/written, 
 the st_blocks field is always populated by the file size divided by the block 
 size. This will cause tools like du(1) to overestimate consumed space. (The 
 recursive size field, maintained by CephFS, also includes file “holes” in its 
 count.)
 稀疏文件错误地传播到 stat（2） st_blocks 字段。由于 CephFS 不会显式跟踪文件的哪些部分被分
 配/写入，因此 st_blocks 字段始终由文件大小除以块大小来填充。这将导致像 du（1） 这样的工具高
 估消耗的空间。（由 CephFS 维护的递归大小字段在其计数中还包括文件 “holes”。

- 当一个文件通过多个主机上的 mmap（2） 映射到内存中时，写入不会一致地传播到其他客户端的缓存中。
  也就是说，如果一个内存页在主机 A 上缓存，然后在主机 B 上更新，则主机 A 的内存页不会一致地失
  效。(共享的可写 mmap 似乎非常罕见 - 我们还没有听到任何关于这种行为的抱怨，并且正确实现缓存一
  致性很复杂。)

- CephFS 客户端提供一个隐藏的 `.snap` 目录，用于访问、创建、删除和重命名快照。虽然 
  readdir（2） 中排除了虚拟目录，但任何尝试创建同名文件或目录的进程都会得到一个错误代码。
  可以在挂载时使用 `-o snapdirname=.somethingelse`（Linux） 或配置选项 
  `client_snapdir` （libcephfs， ceph-fuse） 更改此隐藏目录的名称。

- CephFS 当前不维护 atime 字段。大多数应用程序并不关心，尽管这会影响一些备份和数据分层应用程
  序，这些应用程序可以将未使用的数据移动到辅助存储系统。对于这些场景，您可以以一定的方式解决，因
  为 CephFS 支持通过 `setattr` 作设置 `atime`。

## 权衡
人们经常谈论 “POSIX 兼容性”，但实际上大多数文件系统实现并不严格遵守规范，包括 ext4 和 XFS 等
本地 Linux 文件系统。例如，出于性能原因，读取的原子性要求很宽松：处理来自同样正在写入的文件的
读取可能会看到被损坏的结果。

同样，当多个客户端与相同的文件或目录交互时，NFS 的一致性语义非常弱，而是选择 “close-to-open”。
在网络附加存储的领域中，大多数环境都使用 NFS，服务器的文件系统是否完全的“POSIX 兼容”可能无关紧
要，客户端应用程序是否注意到取决于数据是否在客户端之间共享。NFS 还可能“破坏”并发写入的结果，因
为客户端数据甚至可能不会刷新到服务器，直到文件关闭（更普遍地说，在时延方面，NFS写入会比CEPHFS
多得多，这导致并发写入的结果更难预测）。

## 底线
CephFS 比本地 Linux 内核文件系统更宽松（例如，跨对象边界的写入可能会被撕裂）。在多客户端一致性
方面，它比 NFS 更严格，在写入原子性方面通常严格于 NFS。

换句话说，当涉及到POSIX兼容性时：
```
HDFS < NFS < CephFS < {XFS, ext4}
```

## fsync()和错误
在 fsync 返回错误后，POSIX 对 inode 的状态有些模糊。通常，CephFS 在客户端内核中使用标准错
误返回机制，因此遵循与其他文件系统相同的约定。

在现代 Linux 内核（v4.17 或更高版本）中，将向错误发生时打开的每个文件描述符报告一次写回错误。
此外，在打开文件描述符之前发生的未报告错误也将在 fsync 上返回。











