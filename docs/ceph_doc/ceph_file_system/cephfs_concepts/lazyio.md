---
title: 惰性IO
---

# 惰性 IO

LazyIO 放宽了 POSIX 语义。即使文件由多个客户端上的多个应用程序打开，也允许缓冲读/写。应用程序
负责管理缓存一致性本身。

Libcephfs 从 nautilus 版本开始支持 LazyIO。

## 启用 LazyIO

LazyIO 可以通过以下方式启用：

- `client_force_lazyio` 选项为 libcephfs 和 ceph-fuse 挂载启用全局 LAZY_IO。

- `ceph_lazyio(...)` 以及 `ceph_ll_lazyio(...)` 为 libcephfs 中的文件句柄启用 LAZY_IO。

## 使用

LazyIO 包括两个方法 `lazyio_propagate()` 和 `lazyio_synchronize()`。 启用 LazyIO 后，
其他客户端可能无法看到写入操作，直到调用 `lazyio_propagate()` 。读操作可能来自本地缓存（无论
其他客户端如何更改文件），直到调用 `lazyio_synchronize()`。

- `lazyio_propagate(int fd, loff_t offset, size_t count)`

  确保特定区域（偏移量到 offset+count）中客户端的任何缓冲写入都已传播到共享文件。如果
  offset 和 count 均为 0，则对整个文件执行该操作。目前仅支持此功能。

- `lazyio_synchronize(int fd, loff_t offset, size_t count)`

  确保客户端在后续读取调用中能够读取更新的文件以及其他客户端的所有传播写入。在 CephFS 中，
  这是通过使与 inode 相关的文件缓存无效来实现的，因此会强制客户端从更新的文件中重新获取/重新
  缓存数据。此外，如果调用客户端的写缓存是脏的（未传播），`lazyio_synchronize()` 也会刷新
  它。

下面给出了一个示例用法（使用 `libcephfs`）。这是并行应用程序中特定客户端/文件描述符的示例 I/O 循环：

```cpp
/* Client a (ca) opens the shared file file.txt */
int fda = ceph_open(ca, "shared_file.txt", O_CREAT|O_RDWR, 0644);

/* Enable LazyIO for fda */
ceph_lazyio(ca, fda, 1));

for(i = 0; i < num_iters; i++) {
    char out_buf[] = "fooooooooo";

    ceph_write(ca, fda, out_buf, sizeof(out_buf), i);
    /* Propagate the writes associated with fda to the backing storage*/
    ceph_propagate(ca, fda, 0, 0);

    /* The barrier makes sure changes associated with all file descriptors
    are propagated so that there is certainty that the backing file
    is up to date */
    application_specific_barrier();

    char in_buf[40];
    /* Calling ceph_lazyio_synchronize here will ascertain that ca will
    read the updated file with the propagated changes and not read
    stale cached data */
    ceph_lazyio_synchronize(ca, fda, 0, 0);
    ceph_read(ca, fda, in_buf, sizeof(in_buf), 0);

    /* A barrier is required here before returning to the next write
    phase so as to avoid overwriting the portion of the shared file still
    being read by another file descriptor */
    application_specific_barrier();
}
```
