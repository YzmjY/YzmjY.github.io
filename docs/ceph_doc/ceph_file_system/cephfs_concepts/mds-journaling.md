---
date: 2025-03-27
title: MDS日志记录
---

# MDS Journal

## CEPHFS元数据池
CephFS使用一个与数据池隔离的存储池来管理文件系统的元数据（inodes和dentries），该元数据池包含
文件系统层级关系在内的所有文件元信息。除此之外，它还保存一些与文件系统中其他部分相关联的元数据，
例如对文件系统操作的日志记录、打开文件句柄表、客户端链接session表等内容。

本文档描述了MDS如何使用和回放元数据的操作日志记录。

## Journal记录
MDS在执行文件元数据操作之前，会将对应的元数据事件日志以RADOS对象的形式流式传输到元数据池中。处
于Active状态的MDS进程管理CephFS中的文件和目录的元数据。

CephFS使用Journal功能基于以下理由：

1. 一致性： 在MDS故障转移时，可以通过重放Journal中的操作事件来是文件系统的状态达到一致。另外，
   记录对元数据存储进行多次更新的复杂操作的操作事件，以保证崩溃一致性（以及其他一致性，例如锁等）。

2. 性能：Journal的写入是顺序的，因此该操作的速度很快。另外，可以将更新事件合并到一次日志写入中,
   从而节省更新文件不同部分所涉及的磁盘查找事件。Journal同样有利于备用MDS进行缓存的预热，
   这在MDS故障转移快速恢复时提供一定的帮助。

每个Active的MDS在元数据池中维护自身的Journal日志。Journal日志被条带化为多个Rados对象。过期
的Journal条目将会在合适的时机被删除。

## Journal 事件
除了记录文件系统元数据更新，CephFS Journal 还记录了其它各种事件，例如客户端会话信息和目录导入、
导出状态等。这些事件被 MDS 用来根据需要重新建立正确的状态，例如，通过重放Journal事件，如果存在
特定事件类型指定了一个客户端在MDS 重启之前与其建立了会话，则 MDS 在重启时会尝试重新连接该客户端,

为了检查日志中记录的此类事件的列表，CephFS 提供了一个命令行实用程序 cephfs-journal-tool，
其使用方式如下：

```
cephfs-journal-tool --rank=<fs>:<rank> event get list
```
cephfs-journal-tool 还用于发现和修复损坏的 Ceph 文件系统。（有关更多详细信息，请参阅 
cephfs-journal-tool）
## Journal 事件类型
以下是MDS记录的各类操作事件类型：

1. EVENT_COMMITTED: 将请求(id)标记为已提交。
2. EVENT_EXPORT：将目录映射到 MDS Rank。
3. EVENT_FRAGMENT：跟踪目录分片（拆分/合并）的各个阶段
4. EVENT_IMPORTSTART：当 MDS Rank开始导入目录分片时记录。
5. EVENT_IMPORTFINISH：当 MDS Rank完成导入目录分片时记录。
6. EVENT_NOOP：用于跳过日志区域的空操作事件类型。
7. EVENT_OPEN：跟踪哪些 inode 具有打开的文件句柄。
8. EVENT_RESETJOURNAL：Used to mark a journal as reset post truncation.
9. EVENT_SESSION: 跟踪打开的客户端Session。
10. EVENT_SLAVEUPDATE: 记录已转发到（从属）mds 的操作的各个阶段。
11. EVENT_SUBTREEMAP：目录 inode 到目录内容（子树分区）的映射。
12. EVENT_TABLECLIENT: Log transition states of MDSs view of client tables (snap/anchor).
13. EVENT_TABLESERVER: Log transition states of MDSs view of server tables (snap/anchor).
14. EVENT_UPDATE：对 inode 执行操作日志文件。
15. EVENT_SEGMENT：记录新的Journal段边界。
16. EVENT_LID：标记没有逻辑子树映射的日志的开头。

## Journal段
MDS的Journal有多个逻辑段组成，在代码中被称为LogSegment。这些段用于将元数据更新的多个事件组合
成一个逻辑单元，Journal修剪以这样的一个逻辑单元进行。每当MDS尝试提交元数据操作（例如将文件创建
作为omap更新到dirfrag对象）时，它会在一系列更新元数据对象的过程中以可回放的批量更新方式执行这
些更新。更新必须是可回放的，以防MDS在对不同的元数据对象的一系列更新过程中崩溃。通过批量更新的方
式，可以将对同一个元数据对象的多个更新合并到一个更新中（dirfrag），其中多个omap条目可能在同一
时间段内被更新。

当一个Journal逻辑段被trim后，它被标记为"过期的"。过期的Journal段可以被journaler安全的删除，
因为其所有元数据更新操作都已经被持久化到对应的RADOS对象中。通过更新journaler的"expire position"
来将对应的过期Journal段标记为过期。一些过期的Journal段可能会被保留，以提高MDS在重启时的缓存局部
性。

在 CephFS 的大部分历史中（直到 2023 年），Journal Segment由子树映射（ESubtreeMap 事件）
为分界点。这样做的主要原因是，在重播任何其他事件之前，Journal恢复必须从子树 map 的副本开始。

现在，Journal Segment可以以 `SegmentBoundary` 类的事件作为边界点。包括 `ESubtreeMap`、
`EResetJournal`、`ESegment` （2023） 或 `ELid` （2023 年）。对于 `ESegment`，这种轻量
级的 segment 边界允许 MDS 降低记录子树映射的频率，同时保持日志 segment 较小以保持修剪事件简
短。为了保证 journal 重放看到的第一个事件是 `ESubtreeMap`，那些以该事件开头的 segment 被认
为是 “major segments”，并且为删除过期的 segment 增加了一个限制：Journal的第一个 segment 
必须始终是 major segment。

`ELid` 事件的存在是为了将 MDS 日志标记为 “new”，其他操作需要 LogSegment 和日志序列号才能继
续，尤其是 MDSTable 操作。MDS 在创建排名或关闭Rank时使用此事件。从此初始状态重放Rank时，不需
要子树映射。

## 配置
日志分段的目标大小（以事件数量而言）由以下参数控制：

```
mds_log_events_per_segment 
```
    MDS 日志段中的最大事件数

    类型 : uint

    默认值 : 1024

    最小值 : 1

自上一个Major Segment 以来的 Minor mds 日志 Segment 的数量由以下参数控制：

```
mds_log_minor_segments_per_major_segment
```
    The number of minor mds log segments since last major segment after which a major segment is started/logged.
    自上一个主要分段以来的次要 mds 日志分段数，在此之后启动/记录主要分段。

    类型 : uint

    默认值 : 16

    最小值 : 4

这控制 MDS 修剪过期日志段的频率（值越高，MDS 更新日志过期位置以进行修剪的频率越低）。

最大Segment数由以下参数控制：

```
mds_log_max_segments
```
    开始修剪之前，日志中的最大段 （对象） 数。设置为 -1 可禁用限制。

    类型 : uint

    默认值 : 128

    最小值 : 8

The MDS will often sit a little above this number due to non-major segments 
awaiting trimming up to the next major segment.



 
