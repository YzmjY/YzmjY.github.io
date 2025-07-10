---
date: 2025-07-03
draft: true
---

# Linux 文件系统

## 本地文件系统

磁盘分区、布局

文件系统分层

VFS

## NFS

[NFS](https://baike.baidu.com/item/%E7%BD%91%E7%BB%9C%E6%96%87%E4%BB%B6%E7%B3%BB%E7%BB%9F/9719420) （Network File System，网络文件系统）最早由 Sun 公司提出。它可以通过网络让不同的主机访问同一个文件系统。

通过 NFS 你可以像访问本地文件系统一样访问 NFS 共享目录。我们通过下面的命令来将一个 NFS 文件系统挂载到本地：
```bash
mount -t nfs <NFS 服务器 IP>:/<共享目录> <挂载点>
```
之后你就可以在挂载点目录下访问 NFS 共享目录了，与访问本地文件系统没有任何差异。



### 协议发展
NFS一共发布了3个版本：NFSv2、NFSv3、NFSv4。其中，NFSv4 包含两个次版本 NFSv4.0 和 NFSv4.1。

### Linux 内核 NFS 实现

![](../assert/nfs-kernel.png)

从上图所示的整体架构图上可以看出，NFS 也是位于 VFS 下的文件系统。因此当 NFS 挂载后，其与本地文件系统并没有任何差异，用户在使用的时候也是透明的。

内核的 NFS 服务主要包括以下几个组件：

- **nfsd**: 
    - **处理 NFS 客户端的文件操作请求**：nfsd 接收来自客户端的各种 NFS 协议调用，比如读取文件、写入文件、打开目录、查找文件属性、创建或删除文件等，并执行对应的文件系统操作。
    - **实现 NFS 协议逻辑**：它根据 NFS 版本协议（如 NFSv3、NFSv4）的规范，解析客户端发来的请求，并将请求转换成内核的文件系统操作，同时将结果封装成 NFS 响应发送给客户端。
    - **维护文件系统状态**：对于支持状态的 NFS 版本（如 NFSv4），nfsd 还负责维护锁、状态打开的文件句柄等信息。
- **mountd**: 
    - **处理挂载请求**：当 NFS 客户端尝试挂载远程文件系统时，会向服务器上的 mountd 发送挂载请求，mountd 负责验证请求是否合法，以及判断客户端是否有权限访问指定的导出（export）目录。
    - **管理导出目录的访问控制**：mountd 负责根据服务器上的导出配置（通常是 /etc/exports 文件）检查客户端 IP 地址或者主机名是否允许访问某个导出目录。
    - **维护挂载表信息**：它会记录客户端已经挂载的文件系统信息，便于服务器监控当前的挂载状态。
    - **提供给客户端导出目录列表**：客户端可以通过 mountd 查询服务器上可以挂载的文件系统列表。
- **idmapd**: 和 NFSv4 协议一起引入并广泛使用的组件，NFSv1、v2、v3 在设计时没有集成 idmap 功能，这些版本主要处理数字 UID/GID。NFSv4 在 [RFC 3530](https://www.rfc-editor.org/rfc/rfc3530.html) 中正式引入了基于字符串的身份标识（如用户名 @域名格式），为此需要一个用户身份映射服务（idmapd），用来在客户端的字符串身份和服务器的数字 UID/GID 之间做转换。
- **portmapper**: rpc server 的端口，并在客户端请求时，负责响应目的 rpc server 端口返回给客户端，工作在tcp与udp的111端口上
NFS 服务其的端口默认为 2049，

### NFS-Ganesha
NFS-Ganesha 是一个用户态的 NFS 服务器实现。对比 Linux 内核 NFS 实现，用户态的 NFS 服务器实现有以下优势：

- 灵活的内存分配
- 更强的移植性
- 对接 FUSE 文件系统
- 支持更多的分布式文件系统，如 CEPHFS、GlusterFS等

NFS-Ganesha 的整体架构图如下：

![](../assert/nfs-ganesha.png)

### 其他
#### NFS 权限控制

#### NFS 常用参数






## Fuse
Fuse(filesystem in userspace),是一个用户空间的文件系统。通过 fuse 内核模块的支持，开发者只需要根据 fuse 提供的接口实现具体的文件操作就可以实现一个文件系统。由于其主要实现代码位于用户空间中，而不需要重新编译内核，这给开发者带来了众多便利。

![](../assert/fuse.png)


## 参考
- https://www.cnblogs.com/cxuanBlog/p/12565601.html
- https://www.cnblogs.com/Linux-tech/p/14110335.html
- https://zhuanlan.zhihu.com/p/34833897