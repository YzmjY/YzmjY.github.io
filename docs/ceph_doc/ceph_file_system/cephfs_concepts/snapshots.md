---
title: 快照
---

# CephFS 快照
CephFS 快照是 CephFS 文件系统在特定时间点的不可变视图。CephFS 快照在名为 `.snap` 的特殊隐藏子目录中管理。要创建 CephFS 快照，请在.snap 目录中使用 `mkdir` 命令。

快照可以通过更改以下客户端配置来暴露不同的名称：

- `snapdirname`: 内核客户端的挂载选项。
- `client_snapdir`: ceph-fuse 的挂载选项。

## 创建快照
CephFS 快照功能默认启用在新文件系统上。要在现有文件系统上启用 CephFS 快照功能，请使用以下命令。

```
$ ceph fs set <fs_name> allow_new_snaps true
```

当启用快照时，CephFS中的所有目录都将具有一个特殊的`.snap`目录(您可以使用客户端的`snapdir`参数配置为其他名称。)。要在目录`/file1/`上创建CephFS快照,请在.snap目录下创建一个名为`snapshot-name`的子目录。例如,要在`/file1/`上创建快照,请运行以下命令:

```
$ touch file1
$ cd .snap
$ mkdir my_snapshot
```

## 使用快照恢复数据
快照也可以用于恢复删除的文件:

创建一个文件file1，而后创建一个快照snap1

```
$ touch /mnt/cephfs/file1
$ cd .snap
$ mkdir snap1
```

创建一个文件file2，而后创建一个快照snap2

```
$ touch /mnt/cephfs/file2
$ cd .snap
$ mkdir snap2
```
删除文件file1，而后创建一个快照snap3

```
$ rm /mnt/cephfs/file1
$ cd .snap
$ mkdir snap3
```
使用cp命令恢复文件file1

```
$ cd .snap
$ cd snap2
$ cp file1 /mnt/cephfs/
```

## 删除快照
快照可以通过在它们的.snap目录中运行rmdir来删除。（尝试删除快照的根目录将失败。您必须首先删除快照。）

```
$ cd .snap
$ rmdir my_snapshot
```

