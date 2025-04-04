---
date: 2025-03-27
title: CEPH 文件系统
---
# CEPH 文件系统
Ceph 文件系统 （CephFS） 是构建在 Ceph 的分布式对象存储 RADOS 之上的 POSIX 兼容文件系统。CephFS 致力于为各种应用程序提供最先进的、多用途的、高可用的高性能文件存储，包括共享主目录、HPC 暂存空间和分布式工作流共享存储等传统使用案例。

CephFS 通过其创新的架构来实现这些目标。值得注意的是，CephFS 文件元数据与文件数据分开存储在RADOS 池中，并通过可横向扩展的元数据服务器（MDS）集群对外提供服务，该集群可扩展以支持更高吞吐量的工作负载。

文件系统的客户端可以直接访问 RADOS 以读取和写入文件数据块。这使得工作负载能够根据底层 RADOS对象存储的大小进行线性扩展。不存在网关或代理来协调客户端的数据 I/O。

对文件元数据的访问是通过 MDS 集群来协调的，MDS 集群充当由客户端和 MDS 共同维护的分布式元数据缓存状态的权威机构。元数据的更改由每个 MDS 聚合并顺序写入到一系列对基于RADOS对象的日志中;MDS自身不会在本地存储任何元数据状态。此模型允许在 POSIX 文件系统的上下文中实现客户端之间的一致和快速协作。

![Ceph 文件系统](../image/cephfs-architecture.svg)

CephFS 因其新颖的设计和对文件系统研究的贡献而成为众多学术论文的主题。它是 Ceph 中最古老的存储接口，曾经是 RADOS 的主要用例。现在，它和另外两个存储接口，共同形成一个现代统一存储系统：RBD(Ceph 块设备)和 RGW(Ceph 对象存储网关)。