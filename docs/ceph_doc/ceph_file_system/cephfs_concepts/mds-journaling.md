---
date: 2025-03-27
title: MDS日志记录
---

# MDS日志记录

## CEPHFS元数据池
CephFS使用一个与数据池隔离的存储池来管理文件系统的元数据（inodes和dentries），该元数据池包含
文件系统层级关系在内的所有文件元信息。除此之外，它还保存一些与文件系统中其他部分相关联的元数据，
例如对文件系统操作的日志记录、打开文件句柄表、客户端链接session表等内容。

本文档描述了MDS如何使用和回放元数据的操作日志记录。

## MDS日志记录
MDS在执行文件元数据操作之前，会将对应的元数据事件日志以RADOS对象的形式流式传输到元数据池中。处
于Active状态的MDS进程管理CephFS中的文件和目录的元数据。

CephFS使用Journal日志功能基于以下理由：
1. 一致性： 在MDS故障转移时，可以通过重放Journal日志中的操作事件来是文件系统的状态达到一致。
   另外，记录对元数据存储进行多次更新的复杂操作的操作事件，以保证崩溃一致性（以及其他一致性，例
   如锁等）。
2. 性能：Journal日志的写入是顺序的，因此该操作的速度很快。另外，可以将更新事件合并到一次日志写
   入中，从而节省更新文件不同部分所涉及的磁盘查找事件。Journal日志同样有利于备用MDS进行缓存的
   预热，这在MDS故障转移快速恢复时提供一定的帮助。

每个Active的MDS在元数据池中维护自身的Journal日志。Journal日志被条带化为多个Rados对象。过期
的Journal条目将会在合适的时机被删除。

## Journal志事件类型
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
14. EVENT_UPDATE：对 inode 执行日志文件作。
15. EVENT_SEGMENT：记录新的Journal段边界。
16. EVENT_LID：标记没有逻辑子树映射的日志的开头。

## Journal段


 


 
