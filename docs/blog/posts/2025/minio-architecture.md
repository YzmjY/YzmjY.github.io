---
date: 2025-05-23
categories:
  - MinIO
draft: true
---

# MinIO 笔记（1）: 基本架构

![](../assert/minio.png)

<!-- more -->

MinIO 是一个 S3 兼容的对象存储服务，基本架构如下：

![](../assert/minio-arch.svg)

客户端通过标准的 S3 协议与 MinIO 进行交互，MinIO 服务端主要可以分为以下几个模块：

- S3 协议层：提供 S3 兼容的 RESTful API 接口，与客户端进行交互。
- Object Layer：提供对象存储的核心功能，包括对象的上传、下载、删除、元数据管理，EC 编码等。 Object Layer 内部分为以下层次：Pool -> Set -> Obeject。
- Storage Layer：提供对磁盘文件的操作接口。
- 节点通信：提供节点之间的通信，包括 Grid、REST 两种方式。
- 其他组件：包括如数据扫描、数据恢复、日志、监控等功能模块。

## 基本介绍

### 部署

### 可用性

### 扩容



