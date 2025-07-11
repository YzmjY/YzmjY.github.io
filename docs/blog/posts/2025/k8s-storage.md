---
date: 2025-06-23
categories:
  - Kubernetes
draft: false
---

# Kubernetes 存储

![](../assert/k8s-logo.png){ width="1000" }
/// caption
///

Kubernetes 卷为 Pod 中的容器提供了一种通过文件系统访问和共享数据的方式。通过卷可以实现：

<!-- more -->

- 数据持久性： 容器中的文件在磁盘上是临时存放的，这给在容器中运行较重要的应用带来一些问题。 当容器崩溃或被停止时，容器的状态不会被保存，因此在容器生命期内创建或修改的所有文件都将丢失。 在崩溃之后，kubelet 会以干净的状态重启容器。
- 共享存储： 当多个容器在一个 Pod 中运行并需要共享文件时，会出现另一个问题。 那就是在所有容器之间设置和访问共享文件系统可能会很有难度。


## 基础概念
### 临时卷
- **EmptyDir** ： 是最简单的卷类型，它在 Pod 中创建一个临时目录，用于存储数据。 当 Pod 被删除时，EmptyDir 中的数据也会被删除。
- **ConfigMap** ： 是一种特殊的卷类型，它将 ConfigMap 中的数据作为文件挂载到容器中。 这意味着容器可以直接访问 ConfigMap 中的配置数据，而无需在容器中配置文件系统。
- **Secret** ： 是一种特殊的卷类型，它将 Secret 中的数据作为文件挂载到容器中。 这意味着容器可以直接访问 Secret 中的配置数据，而无需在容器中配置文件系统。

### 持久化卷
- **PersistentVolume (PV)** ：集群管理员预先配置或动态创建的存储资源，是集群基础设施的一部分。PV 具有独立于 Pod 的生命周期，封装了底层存储实现的具体细节（如 NFS、iSCSI、云存储等）。
- **PersistentVolumeClaim (PVC)** ：用户请求和绑定 PV 的资源对象。PVC 定义了用户对存储的需求，包括存储大小、访问模式、存储类等。PVC 可以动态创建或绑定到现有的 PV。
- **StorageClass** ：定义了如何动态制备 PV 的模板。 管理员可以根据需要创建多个 StorageClass，每个 StorageClass 都有自己的制备策略和参数。

## 存储架构
下面介绍一下 Kubernetes 中存储架构：  

![](../assert/k8s_存储架构.png) 
图中各组件作用如下：

- **PV Controller**: 负责 PV/PVC 的绑定、生命周期管理，并根据需求进行数据卷的 Provision/Delete 操作；

- **AD Controller**：负责存储设备的 Attach/Detach 操作，将设备挂载到目标节点；

- **Volume Manager**：管理卷的 Mount/Unmount 操作、卷设备的格式化以及挂载到一些公用目录上的操作；

- **Volume Plugins**：它主要是对上面所有挂载功能的实现；

- **Scheduler**：实现对 Pod 的调度能力，会根据一些存储相关的的定义去做一些存储相关的调度；

PV Controller、AD Controller、Volume Manager 主要是进行操作的调用，而具体操作则是由 Volume Plugins 实现的。

当我们在一个 Pod 中使用 PVC 并挂载到容器的指定目录时，K8s 对该 Pod 的创建流程大致如下：

![](../assert/k8s_持久化卷创建过程.png)



## CSI

### 什么是 CSI

### CSI 工作原理

## 实践














## 参考
- [K8S官方文档：存储概念](https://kubernetes.io/docs/concepts/storage/)
- [从零开始入门 K8s：Kubernetes 存储架构及插件使用](https://www.infoq.cn/article/afju539zmbpp45yy9txj)
- https://jimmysong.io/book/kubernetes-handbook/storage/