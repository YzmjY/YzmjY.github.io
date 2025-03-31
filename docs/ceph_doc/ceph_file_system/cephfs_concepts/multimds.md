---
title: 多活MDS
---

# 配置多个Active MDS进程

*也被称为：多活MDS、active-active MDS*

默认情况下，每个CephFS都配置了一个MDS守护进程。但是，在大规模系统中，您可以配置多个MDS守护进程，以提高系统的元数据性能，这些MDS进程将共同处理元数据工作负载。

## 何时应该使用多个MDS

总的来说，当您的文件系统元数据性能在单个MDS上遇到了瓶颈，此时您应该考虑使用多个MDS。

添加更多的MDS并不是在所有工作负载下都能提高系统性能，通常，在单个客户端上运行的单个应用程序的工作负载下，使用多个MDS并不会带来明显的性能提升，除非该应用程序正在并行执行大量元数据操作。

通过使用多活MDS带来性能提升的场景通常是那些具有许多客户端的工作负载，这些客户端可能在许多独立的目录中工作。

## 增加 MDS Active集群的大小

每个 CephFS 文件系统都有一个 `max_mds` 的参数，用于控制将创建的 Rank 数。只有当备用 MDS 守护进程可用于承担新的 Rank 时，文件系统中的实际 Rank 数才会增加。例如，如果只有一个 MDS 守护程序正在运行，并且 `max_mds` 设置为 2，那么，文件系统不会创建第二个 Rank。（请注意，像这样进行配置是不具备高可用性(HA)的，因为没有备用 MDS 可用于接管失败的Rank。以这种方式配置时，集群会产生健康状态的警告。

将 `max_mds` 设置为所需的 Rank 数。在以下示例中，通过 “ceph status” 的 “fsmap” 行，来说明命令的预期结果。

```
# fsmap e5: 1/1/1 up {0=a=up:active}, 2 up:standby

ceph fs set <fs_name> max_mds 2

# fsmap e8: 2/2/2 up {0=a=up:active,1=c=up:creating}, 1 up:standby
# fsmap e9: 2/2/2 up {0=a=up:active,1=c=up:active}, 1 up:standby
```

新创建的Rank(1) 将通过 'creating' 状态，进入 'active' 状态。

## StandBy 进程

即使有多个Active的 MDS 进程，为了实现系统的高可用性，仍需要配置备用的MDS进程来接管发生故障的活跃MDS进程。

因此，高可用性系统的实际最大 `max_mds` 最多比系统中 MDS 服务器的总数少 1。

要在发生多个服务器故障时保持可用，请增加系统中备用 MDS 的数量，以匹配您希望承受的服务器故障数量。

## 减少Rank的数量
减少等级数就像减少 `max_mds` 一样简单：

```
# fsmap e9: 2/2/2 up {0=a=up:active,1=c=up:active}, 1 up:standby
ceph fs set <fs_name> max_mds 1
# fsmap e10: 2/2/1 up {0=a=up:active,1=c=up:stopping}, 1 up:standby
# fsmap e10: 2/2/1 up {0=a=up:active,1=c=up:stopping}, 1 up:standby
...
# fsmap e10: 1/1/1 up {0=a=up:active}, 2 up:standby
```

集群将自动逐步停止额外的Rank，直到Rank数等于 `max_mds`。

See CephFS Administrative commands for more details which forms <role> can take.

注意：已停止的等级将首先进入stopping状态一段时间，同时将其管理的元数据移交给剩余的Active MDS。此阶段可能需要几秒钟到几分钟。如果 MDS 卡在stopping状态，则应将其作为可能的 bug 进行调查。

If an MDS daemon crashes or is killed while in the up:stopping state, a standby will take over and the cluster monitors will against try to stop the daemon.
如果 MDS 守护程序在 `up：stopping` 状态下崩溃或被终止，则备用MDS将接管它，MON 集群将反对尝试停止守护程序。

当 MDS 结束了stopping状态后，它将恢复为备用MDS。


## 手动将目录树固定到特定Rank 
In multiple active metadata server configurations, a balancer runs which works to spread metadata load evenly across the cluster. This usually works well enough for most users but sometimes it is desirable to override the dynamic balancer with explicit mappings of metadata to particular ranks. This can allow the administrator or users to evenly spread application load or limit impact of users’ metadata requests on the entire cluster.
在多个活动元数据服务器配置中，将运行一个平衡器，该平衡器用于将元数据负载均匀地分布在集群中。对于大多数用户来说，这通常已经足够好了，但有时需要用元数据到特定等级的显式 Map 来覆盖 dynamic balancer。这可以允许管理员或用户均匀分配应用程序负载或限制用户的元数据请求对整个集群的影响。

The mechanism provided for this purpose is called an export pin, an extended attribute of directories. The name of this extended attribute is ceph.dir.pin. Users can set this attribute using standard commands:
为此目的提供的机制称为导出引脚 ，即 目录的 extended 属性。此扩展属性的名称为 用户可以使用标准命令设置此属性：

setfattr -n ceph.dir.pin -v 2 path/to/dir
The value of the extended attribute is the rank to assign the directory subtree to. A default value of -1 indicates the directory is not pinned.
extended 属性的值是要将目录子树分配到的排名。默认值 -1 表示目录未固定。

A directory’s export pin is inherited from its closest parent with a set export pin. In this way, setting the export pin on a directory affects all of its children. However, the parents pin can be overridden by setting the child directory’s export pin. For example:
目录的导出引脚继承自其最近的父级，并设置了导出引脚。这样，在目录上设置 export pin 会影响其所有子项。但是，可以通过设置子目录的 export pin 来覆盖 parents pin。例如：

mkdir -p a/b
# "a" and "a/b" both start without an export pin set
setfattr -n ceph.dir.pin -v 1 a/
# a and b are now pinned to rank 1
setfattr -n ceph.dir.pin -v 0 a/b
# a/b is now pinned to rank 0 and a/ and the rest of its children are still pinned to rank 1
Setting subtree partitioning policies
设置子树分区策略 
It is also possible to setup automatic static partitioning of subtrees via a set of policies. In CephFS, this automatic static partitioning is referred to as ephemeral pinning. Any directory (inode) which is ephemerally pinned will be automatically assigned to a particular rank according to a consistent hash of its inode number. The set of all ephemerally pinned directories should be uniformly distributed across all ranks.
还可以通过一组策略设置子树的自动静态分区。在 CephFS 中，这种自动静态分区称为临时固定 。任何临时固定的目录 （inode） 都将根据其 inode 编号的一致哈希值自动分配给特定排名。所有临时固定目录的集合应均匀分布在所有等级中。

Ephemerally pinned directories are so named because the pin may not persist once the directory inode is dropped from cache. However, an MDS failover does not affect the ephemeral nature of the pinned directory. The MDS records what subtrees are ephemerally pinned in its journal so MDS failovers do not drop this information.
临时固定目录之所以如此命名，是因为一旦从缓存中删除目录 inode，该 pin 可能不会保留。但是，MDS 故障转移不会影响固定目录的短暂性。MDS 会记录哪些子树在其日志中短暂固定，因此 MDS 故障转移不会丢弃此信息。

A directory is either ephemerally pinned or not. Which rank it is pinned to is derived from its inode number and a consistent hash. This means that ephemerally pinned directories are somewhat evenly spread across the MDS cluster. The consistent hash also minimizes redistribution when the MDS cluster grows or shrinks. So, growing an MDS cluster may automatically increase your metadata throughput with no other administrative intervention.
目录要么是临时固定的，要么不是。它固定到哪个排名是从它的 inode 编号和一致的哈希值派生的。这意味着临时固定目录在 MDS 群集中分布得比较均匀。当 MDS 群集增长或收缩时， 一致性哈希还可以最大限度地减少重新分配。因此，扩大 MDS 集群可能会自动增加元数据吞吐量，而无需其他管理干预。

Presently, there are two types of ephemeral pinning:
目前，有两种类型的短暂固定：

Distributed Ephemeral Pins: This policy causes a directory to fragment (even well below the normal fragmentation thresholds) and distribute its fragments as ephemerally pinned subtrees. This has the effect of distributing immediate children across a range of MDS ranks. The canonical example use-case would be the /home directory: we want every user’s home directory to be spread across the entire MDS cluster. This can be set via:
分布式临时 Pin： 此策略会导致目录碎片化（甚至远低于正常的碎片阈值）并将其碎片作为临时固定的子树进行分发。这具有在一系列 MDS 等级之间分配直系子级的效果。规范的示例用例是 /home 目录：我们希望每个用户的主目录分布在整个 MDS 集群中。这可以通过以下方式进行设置：

setfattr -n ceph.dir.pin.distributed -v 1 /cephfs/home
Random Ephemeral Pins: This policy indicates any descendent sub-directory may be ephemerally pinned. This is set through the extended attribute ceph.dir.pin.random with the value set to the percentage of directories that should be pinned. For example:
Random Ephemeral Pins：此策略指示任何派生子目录 可能被短暂固定。这是通过 extended 属性 ceph.dir.pin.random 的目录，该值设置为应固定的目录的百分比。例如：

setfattr -n ceph.dir.pin.random -v 0.5 /cephfs/tmp
Would cause any directory loaded into cache or created under /tmp to be ephemerally pinned 50 percent of the time.
将导致加载到缓存中或在 /tmp 下创建的任何目录在 50% 的时间内短暂固定。

It is recommended to only set this to small values, like .001 or 0.1%. Having too many subtrees may degrade performance. For this reason, the config mds_export_ephemeral_random_max enforces a cap on the maximum of this percentage (default: .01). The MDS returns EINVAL when attempting to set a value beyond this config.
建议仅将其设置为较小的值，例如 .001 或 0.1%。 子树过多可能会降低性能。因此，配置 mds_export_ephemeral_random_max 强制设置此百分比的最大值上限（默认值：.01）。MDS 在尝试设置超出此配置的值时返回 EINVAL。

Both random and distributed ephemeral pin policies are off by default in Octopus. The features may be enabled via the mds_export_ephemeral_random and mds_export_ephemeral_distributed configuration options.
默认情况下，随机和分布式临时 pin 策略在 章鱼。这些功能可以通过 mds_export_ephemeral_random 和 mds_export_ephemeral_distributed 配置选项。

Ephemeral pins may override parent export pins and vice versa. What determines which policy is followed is the rule of the closest parent: if a closer parent directory has a conflicting policy, use that one instead. For example:
临时 pin 可能会覆盖父 export pin，反之亦然。决定遵循哪个策略的是最近的父目录的规则：如果较近的父目录具有冲突的策略，请改用该策略。例如：

mkdir -p foo/bar1/baz foo/bar2
setfattr -n ceph.dir.pin -v 0 foo
setfattr -n ceph.dir.pin.distributed -v 1 foo/bar1
The foo/bar1/baz directory will be ephemerally pinned because the foo/bar1 policy overrides the export pin on foo. The foo/bar2 directory will obey the pin on foo normally.
foo/bar1/baz 目录将被临时固定，因为 foo/bar1 策略覆盖 foo 上的 export pin。foo/bar2 目录将正常服从 foo 上的 pin。

For the reverse situation:
对于相反的情况：

mkdir -p home/{patrick,john}
setfattr -n ceph.dir.pin.distributed -v 1 home
setfattr -n ceph.dir.pin -v 2 home/patrick
The home/patrick directory and its children will be pinned to rank 2 because its export pin overrides the policy on home.
home/patrick 目录及其子目录将被固定到排名 2，因为它的 export pin 覆盖了 home 上的策略。

To remove a partitioning policy, remove the respective extended attribute or set the value to 0.
要删除分区策略，请删除相应的扩展属性或将值设置为 0。

$ setfattr -n ceph.dir.pin.distributed -v 0 home
# or
$ setfattr -x ceph.dir.pin.distributed home
For export pins, remove the extended attribute or set the extended attribute value to -1.
对于导出引脚，请删除 extended 属性或将 extended 属性值设置为 -1。

$ setfattr -n ceph.dir.pin -v -1 home
Dynamic Subtree Partitioning
动态子树分区 
CephFS has long had a dynamic metadata balancer (sometimes called the “default balancer”) which can split or merge subtrees while placing them on “colder” MDS ranks. Moving the metadata in this way improves overall file system throughput and cache size.
CephFS 长期以来一直有一个动态元数据平衡器（有时称为“默认平衡器”），它可以拆分或合并子树，同时将它们放置在“较冷”的 MDS 等级中。以这种方式移动元数据可以提高整体文件系统吞吐量和缓存大小。

However, the balancer is sometimes inefficient or slow, so by default it is turned off. This is to avoid an administrator “turning on multimds” by increasing the max_mds setting only to find that the balancer has made a mess of the cluster performance (reverting from this messy state of affairs is straightforward but can take time).
但是，平衡器有时效率低下或速度较慢，因此默认情况下它是关闭的。这是为了避免管理员通过增加 max_mds 设置来“打开 multimds”，却发现 balancer 器已经把集群性能搞得一团糟（从这种混乱的状态中恢复过来很简单，但可能需要时间）。

To turn on the balancer, run a command of the following form:
要打开平衡器，请运行以下形式的命令：

ceph fs set <fs_name> balance_automate true
Turn on the balancer only with an appropriate configuration, such as a configuration that includes the bal_rank_mask setting (described below).
仅使用适当的配置打开平衡器，例如包含 bal_rank_mask 设置（描述 ）。

Careful monitoring of the file system performance and MDS is advised.
建议仔细监控文件系统性能和 MDS。

Dynamic subtree partitioning with Balancer on specific ranks
在特定等级上使用 Balancer 进行动态子树分区 
The CephFS file system provides the bal_rank_mask option to enable the balancer to dynamically rebalance subtrees within particular active MDS ranks. This allows administrators to employ both the dynamic subtree partitioning and static pining schemes in different active MDS ranks so that metadata loads are optimized based on user demand. For instance, in realistic cloud storage environments, where a lot of subvolumes are allotted to multiple computing nodes (e.g., VMs and containers), some subvolumes that require high performance are managed by static partitioning, whereas most subvolumes that experience a moderate workload are managed by the balancer. As the balancer evenly spreads the metadata workload to all active MDS ranks, performance of static pinned subvolumes inevitably may be affected or degraded. If this option is enabled, subtrees managed by the balancer are not affected by static pinned subtrees.
CephFS 文件系统提供了 bal_rank_mask 选项，使平衡器能够动态地重新平衡特定活动 MDS 等级中的子树。这允许管理员在不同的活动 MDS 等级中同时使用动态子树分区和静态固定方案，以便根据用户需求优化元数据加载。例如，在实际的云存储环境中，大量子卷被分配给多个计算节点（例如，VM 和容器），一些需要高性能的子卷由静态分区管理，而大多数工作负载适中的子卷由 balancer 管理。由于平衡器将元数据工作负载均匀地分散到所有活动的 MDS 排名，因此静态固定子卷的性能可能不可避免地受到影响或降级。如果启用此选项，则 balancer 管理的子树不会受到静态固定子树的影响。

This option can be configured with the ceph fs set command. For example:
可以使用 ceph fs set 命令配置此选项。例如：

ceph fs set <fs_name> bal_rank_mask <hex>
Each bitfield of the <hex> number represents a dedicated rank. If the <hex> is set to 0x3, the balancer runs on active 0 and 1 ranks. For example:
<hex> 数字的每个位域代表一个专用 rank。如果 <hex> 设置为 0x3，则平衡器在活动 0 和 1 等级上运行。例如：

ceph fs set <fs_name> bal_rank_mask 0x3
If the bal_rank_mask is set to -1 or all, all active ranks are masked and utilized by the balancer. As an example:
如果 bal_rank_mask 设置为 -1 或 all，则所有活动排名都将被屏蔽并由 balancer 器使用。例如：

ceph fs set <fs_name> bal_rank_mask -1
On the other hand, if the balancer needs to be disabled, the bal_rank_mask should be set to 0x0. For example:
另一方面，如果需要禁用 balancer，则应将 bal_rank_mask 设置为 0x0。例如：

ceph fs set <fs_name> bal_rank_mask 0x0

