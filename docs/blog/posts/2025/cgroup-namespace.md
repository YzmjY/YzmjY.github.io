---
date: 2025-07-14
categories:
  - Linux
slug: cgroup-namespace
draft: false
---

# Linux: Cgroup 和 Namespace

![](../assert/linux-logo.png)
/// caption
///

<!-- more -->

## Cgroup：资源限制
[Cgroup](https://man7.org/linux/man-pages/man7/cgroups.7.html) 用于限制，记录，隔离进程组的资源使用情况。通过 cgroup 可以实现：

- 资源限制：cgroup 可以对进程组使用的资源总额进行限制，例如对特定进程进行内存上限限制，超过限制触发 OOM。
- 优先级分配：
- 资源统计：对进程组使用的资源进行统计，例如统计内存使用量，CPU 占用时间等。
- 进程控制：cgroup 可以对进程组进行控制，例如暂停，重启，终止进程组。

### 概念

- *cgroup*： cgroup 将一组 task 与一个或多个 subsystem 的一组参数相关联。
- *subsystem*：subsystem 是一个利用 cgroups 提供的任务分组工具以特定方式处理任务组的模块。subsystem 通常是调度资源或应用于每个 cgroup 限制的 “资源控制器”，但它也可以是想要作用于一组 tasks 的任何东西，例如虚拟化子系统。
- *hierarchy*：某个控制器的各个 cgroup 以层次结构的形式组织。这个层次结构是通过在 cgroup 文件系统中创建、删除和重命名子目录来定义的。在层次结构的每一级，都可以定义属性（例如限制）。cgroup 提供的限制、控制和统计功能通常会影响定义这些属性的 cgroup 下的整个子层次结构。例如，层次结构中较高级别的 cgroup 所设置的限制不能被其子 cgroup 突破。

在 Linux 实现中，cgroup 通过一个虚拟文件系统来提供对 cgroup 资源的访问。这个虚拟文件系统的根目录是 `/sys/fs/cgroup`，每个 cgroup 都有一个对应的目录，目录名就是 cgroup 的名称。Hierarchy 层级结构通过文件夹结构实现，而每个 cgroup 的 Subsystem 配置和 Tasks 则通过文件来配置。

```
/sys/fs/cgroup/
|-- blkio
|-- cpu -> cpu,cpuacct
|-- cpuacct -> cpu,cpuacct
|-- cpu,cpuacct
|-- cpuset
|-- devices
|-- freezer
|-- hugetlb
|-- memory
|-- net_cls -> net_cls,net_prio
|-- net_cls,net_prio
|-- net_prio -> net_cls,net_prio
|-- perf_event
|-- pids
```

上述每一个子目录就对应一个 Subsystem。

- cpu：使用调度程序控制任务对cpu的使用
- cpuacct：自动生成cgroup中任务对cpu资源使用情况的报告
- cpuset：可以为cgroup中的任务分配独立的cpu和内存
- blkio：可以为块设备设定输入 输出限制，比如物理驱动设备
- devices：可以开启或关闭cgroup中任务对设备的访问
- freezer： 可以挂起或恢复cgroup中的任务
- pids：限制任务数量
- memory：可以设定cgroup中任务对内存使用量的限定，并且自动生成这些任务对内存资源使用情况的报告
- perf_event：使用后使cgroup中的任务可以进行统一的性能测试
- net_cls：docker没有直接使用它，它通过使用等级识别符标记网络数据包，从而允许linux流量控制程序识别从具体cgroup中生成的数据包

### 使用

组织 cgroup 的层次结构（hierarchy）是通过在 cgroup 文件系统（通常是 `/sys/fs/cgroup`）中创建目录和子目录来完成的，这种方式直观地将 cgroup 组织成树状结构。

以下是组织 cgroup 层次结构的基本原则和步骤：

1.  **根层次结构**：
    在 cgroup v2 中，所有资源控制器（CPU, memory, I/O 等）都位于一个统一的层次结构下，根目录就是`/sys/fs/cgroup`。这个根 cgroup 包含了系统上所有的进程。

2.  **创建子 cgroup**：
    您可以通过创建子目录来创建新的 cgroup。每个目录都代表一个 cgroup，它可以有自己的资源限制，并且可以包含进程。

    例如，假设您想为系统上的 Web 服务器和数据库服务分别创建资源组，可以这样组织：

    ```bash
    # 在根 cgroup 下创建一个用于“services”的 cgroup
    sudo mkdir /sys/fs/cgroup/services

    # 在 services/cgroup 下，分别为 web 和 db 创建子 cgroup
    sudo mkdir /sys/fs/cgroup/services/web
    sudo mkdir /sys/fs/cgroup/services/db
    ```

    这样，您就创建了如下的层次结构：
    ```
    /sys/fs/cgroup/
    └── services/
        ├── web/
        └── db/
    ```

3.  **资源继承和限制**：
    层次结构的一个关键特性是资源的继承和限制。
    *   **限制传递**：父 cgroup 的资源限制会传递给其子 cgroup。子 cgroup 可用的资源不能超过其父 cgroup 的限制。
    *   **分布资源**：您可以将父 cgroup 的资源分配给其子 cgroup。

    例如，您可以为 `services` cgroup 设置一个总的内存限制：
    ```bash
    # 限制所有 services 最多使用 10GB 内存
    echo "10G" | sudo tee /sys/fs/cgroup/services/memory.max
    ```
    然后，您可以将这10GB的内存在`web`和`db`子cgroup之间进行分配：
    ```bash
    # 限制 web 服务最多使用 6GB 内存
    echo "6G" | sudo tee /sys/fs/cgroup/services/web/memory.max

    # 限制 db 服务最多使用 4GB 内存
    echo "4G" | sudo tee /sys/fs/cgroup/services/db/memory.max
    ```
    `web`和`db`的内存限制之和（6G + 4G = 10G）不能超过其父 cgroup `services`的限制。

4.  **移动进程**：
    将进程的 PID 写入目标 cgroup 的 `cgroup.procs` 文件，即可将进程移动到该 cgroup 中，从而受其资源限制。

    ```bash
    # 将 PID 为 1234 的 web 服务器进程移动到 web cgroup
    echo 1234 | sudo tee /sys/fs/cgroup/services/web/cgroup.procs

    # 将 PID 为 5678 的数据库进程移动到 db cgroup
    echo 5678 | sudo tee /sys/fs/cgroup/services/db/cgroup.procs
    ```

通过这种方式，您可以根据应用程序、用户或系统服务的类别来构建精细化的资源控制层次结构，从而实现对系统资源的有效管理和隔离。

## Namespace：资源隔离

[Namespace](https://man7.org/linux/man-pages/man7/namespaces.7.html) 是 Linux 内核提供的一种机制，用于隔离不同进程的资源视图。每个 Namespace 都有自己的一套资源，包括进程 ID、文件系统、网络等，每个进程只能看到自己命名空间内的对应资源。

Namespace 主要有以下几种类型：

| 类型    | Flag            | 隔离资源                 |
| ------- | --------------- | ------------------------ |
| Cgroup  | CLONE_NEWCGROUP | Cgroup                   |
| IPC     | CLONE_NEWIPC    | IPC,POSIX msg queue      |
| Network | CLONE_NEWNET    | 网络设备，协议栈，端口等 |
| Mount   | CLONE_NEWNS     | 挂载点                   |
| PID     | CLONE_NEWPID    | PID                      |
| Time    | CLONE_NEWTIME   |                          |
| User    | CLONE_NEWUSER   | 用户和用户组 ID          |
| UTS     | CLONE_NEWUTS    | 主机名和域名             |

### API

Namespace 可以通过一下系统调用来操作：

- `clone(2)`：创建一个新进程，如果指定了 `CLONE_NEW*` 标志，会创建新的 Namespace，并将子进程加入到新的 Namespace 中。
- `setns(2)`：将调用进程加入到指定的 Namespace 中。
- `unshare(2)`：将调用进程加入到新的 Namespace 中。

关于 `/proc/[pid]/ns` 目录：

每个进程的 `/proc/[pid]/ns` 目录包含了一组文件，这些文件对应该进程所参与的各种命名空间，这些文件实际上是符号链接，链接到内核中对应命名空间的标识符，通常表现为类似 `ns:[4026531840]` 的格式，数字是该命名空间的内核对象标识符（inode）。

## 参考
- [cgroup](https://www.kernel.org/doc/html/v5.7/admin-guide/cgroup-v1/cgroups.html)
- [Linux: Cgroup 和 Namespace](https://xigang.github.io/2018/10/14/namespace-md/)


