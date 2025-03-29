---
title: 文件布局(Layout)
---

# 文件布局(Layout)

一个文件的 Layout 是指文件的内容与Ceph Rados对象之间的映射关系。您可以通过虚拟扩展属性或者xattrs
来查看文件的 Layout。

客户端在写入文件Layout时，必须使用 `p` 选项。 请参阅 [Layout和Quota限制](https://docs.ceph.com/en/latest/cephfs/client-auth/#cephfs-layout-and-quota-restriction)

Layout的xattr属性名根据文件的类型而不同：

- 普通文件：`ceph.file.layout`
- 目录：`ceph.dir.layout`

下文中的例子都是基于普通文件的，当您在目录上执行示例中的操作时，您需要将 `ceph.dir.layout` 替
换为`ceph.file.layout`。

!!! tip

    默认情况下，您的Linux发行版可能没有附带用来操作 `xattr` 的命令，您可以通过安装 `attr` 
    包来解决。

## Layout字段
Layout包含以下字段：

- pool：
    包含ID或者名称的字符串，只能包含 `[a-zA-Z0-9\_-.]` 中的字符。该字段标识用于存储文件数据
    对象的Rados存储池。
- pool_id：
    由数字组成的字符串，表示Ceph在创建Rados存储池时分配的ID。
- pool_name:
    字符串，表示用户在创建Rados存储池时指定的名称。
- pool_namespace:
    字符串，只能包含 `[a-zA-Z0-9\_-.]` 中的字符。该字段决定了文件数据的Rados对象写入数据池
    的那个命名空间。默认为空（即默认的命名空间）。
- stripe_unit:
    整数。用于分发文件的数据块的大小 （以字节为单位）。文件的所有条带单位大小相同。最后一个条带
    单元通常只有部分数据：它会保留文件数据直至文件结束符（EOF），同时还会保留用于填充固定条带单
    元大小剩余部分的填充数据。
- stripe_count:
    整数。表示文件 RAID 0条带化的条带数量。
- object_size:
    整数。表示文件数据对象的大小（以字节为单位）。文件数据被分割为多个此大小的Rados对象中。

!!! tip

    RADOS 对象大小可配置，但存在限制：如果将 CephFS 对象大小增加到超过该限制，则写入可能不会
    成功。OSD 对应的选项为 `osd_max_object_size`，默认为 128MB。非常大的 RADOS 对象可能
    会影响集群的正常运行，因此不建议将对象大小限制设置超过默认值。

## 使用GETFATTR读取Layout

将Layout信息作为一个字符串返回。

```bash
$ touch file
$ getfattr -n ceph.file.layout file
# file: file
ceph.file.layout="stripe_unit=4194304 stripe_count=1 object_size=4194304 pool=cephfs_data"
```

读取Layout中的单个字段：


```bash
$ getfattr -n ceph.file.layout.pool_name file
# file: file
ceph.file.layout.pool_name="cephfs_data"
$ getfattr -n ceph.file.layout.pool_id file
# file: file
ceph.file.layout.pool_id="5"
$ getfattr -n ceph.file.layout.pool file
# file: file
ceph.file.layout.pool="cephfs_data"
$ getfattr -n ceph.file.layout.stripe_unit file
# file: file
ceph.file.layout.stripe_unit="4194304"
$ getfattr -n ceph.file.layout.stripe_count file
# file: file
ceph.file.layout.stripe_count="1"
$ getfattr -n ceph.file.layout.object_size file
# file: file
ceph.file.layout.object_size="4194304"
```

!!! note

    读取Layout时，`pool` 字段通常输出为 name 。但是，在极少数情况下，当刚刚创建存储池时，
    可能会改为输出 ID。

目录默认没有Layout，只有在自定义设置之后才会产生Layout。如果从未修改过目录的Layout，则尝试读
取目录的Layout会返回错误：这意味着将会使用下一个具有显式Layout的祖先目录的Layout。

```bash
$ mkdir dir
$ getfattr -n ceph.dir.layout dir
dir: ceph.dir.layout: No such attribute
$ setfattr -n ceph.dir.layout.stripe_count -v 2 dir
$ getfattr -n ceph.dir.layout dir
# file: dir
ceph.dir.layout="stripe_unit=4194304 stripe_count=2 object_size=4194304 pool=cephfs_data"
```

使用如下命令可以以JSON格式输出Layout信息：

```bash
$ getfattr -n ceph.dir.layout.json --only-values /mnt/mycephs/accounts
{"stripe_unit": 4194304, "stripe_count": 1, "object_size": 4194304, "pool_name": "cephfs.a.data", "pool_id": 3, "pool_namespace": "", "inheritance": "@default"}
```

如果没有为指定的 inode 设置Layout，系统会向后遍历目录路径，使用最近的祖先目录的 Layout 以 
json 格式返回。文件的Layout可以通过名为 `ceph.file.layout.json` 的 xattr 查询 json 格式
的文件Layout。

## 使用SETFATTR设置Layout

使用`setfattr`命令设置Layout字段：

```bash
$ ceph osd lspools
0 rbd
1 cephfs_data
2 cephfs_metadata

$ setfattr -n ceph.file.layout.stripe_unit -v 1048576 file2
$ setfattr -n ceph.file.layout.stripe_count -v 8 file2
$ setfattr -n ceph.file.layout.object_size -v 10485760 file2
$ setfattr -n ceph.file.layout.pool -v 1 file2  # Setting pool by ID
$ setfattr -n ceph.file.layout.pool -v cephfs_data file2  # Setting pool by name
$ setfattr -n ceph.file.layout.pool_id -v 1 file2  # Setting pool by ID
$ setfattr -n ceph.file.layout.pool_name -v cephfs_data file2  # Setting pool by name
```

!!! note

    使用`setfattr`命令修改文件Layout时，此文件必须为空，否则会报错。 

```bash
# touch an empty file
$ touch file1
# modify layout field successfully
$ setfattr -n ceph.file.layout.stripe_count -v 3 file1

# write something to file1
$ echo "hello world" > file1
$ setfattr -n ceph.file.layout.stripe_count -v 4 file1
setfattr: file1: Directory not empty
```

同样可以通过JSON格式设置文件和目录的 Layout。设置Layout时，将忽略 `inheritance`字段。此外，
如果同时指定了 `pool_name` 和 `pool_id`，则 `pool_name` 具有较高的优先级。

```bash
$ setfattr -n ceph.file.layout.json -v '{"stripe_unit": 4194304, "stripe_count": 1, "object_size": 4194304, "pool_name": "cephfs.a.data", "pool_id": 3, "pool_namespace": "", "inheritance": "@default"}' file1
```

## 清除Layout

如果您希望删除一个目录的显式Layout，恢复为继承自其祖先目录的Layout，您可以这样做：

```bash
setfattr -x ceph.dir.layout mydir
```

同样，如果你已经设置了 `pool_namespace` 属性，并希望修改Layout以改用 `default` 命名空间：

```bash
# Create a dir and set a namespace on it
mkdir mydir
setfattr -n ceph.dir.layout.pool_namespace -v foons mydir
getfattr -n ceph.dir.layout mydir
ceph.dir.layout="stripe_unit=4194304 stripe_count=1 object_size=4194304 pool=cephfs_data_a pool_namespace=foons"

# Clear the namespace from the directory's layout
setfattr -x ceph.dir.layout.pool_namespace mydir
getfattr -n ceph.dir.layout mydir
ceph.dir.layout="stripe_unit=4194304 stripe_count=1 object_size=4194304 pool=cephfs_data_a"
```

## Layout的继承
文件在创建时继承其父目录的布局。但是，对父目录布局的后续更改不会影响目录中已存在的后代。
```bash
$ getfattr -n ceph.dir.layout dir
# file: dir
ceph.dir.layout="stripe_unit=4194304 stripe_count=2 object_size=4194304 pool=cephfs_data"

# Demonstrate file1 inheriting its parent's layout
$ touch dir/file1
$ getfattr -n ceph.file.layout dir/file1
# file: dir/file1
ceph.file.layout="stripe_unit=4194304 stripe_count=2 object_size=4194304 pool=cephfs_data"

# Now update the layout of the directory before creating a second file
$ setfattr -n ceph.dir.layout.stripe_count -v 4 dir
$ touch dir/file2

# Demonstrate that file1's layout is unchanged
$ getfattr -n ceph.file.layout dir/file1
# file: dir/file1
ceph.file.layout="stripe_unit=4194304 stripe_count=2 object_size=4194304 pool=cephfs_data"

# ...while file2 has the parent directory's new layout
$ getfattr -n ceph.file.layout dir/file2
# file: dir/file2
ceph.file.layout="stripe_unit=4194304 stripe_count=4 object_size=4194304 pool=cephfs_data"
```

对于多级目录结构，创建文件时，如果中间目录没有设置布局，则会向上找到最近的祖先目录，并继承其布局。

```bash
$ getfattr -n ceph.dir.layout dir
# file: dir
ceph.dir.layout="stripe_unit=4194304 stripe_count=4 object_size=4194304 pool=cephfs_data"
$ mkdir dir/childdir
$ getfattr -n ceph.dir.layout dir/childdir
dir/childdir: ceph.dir.layout: No such attribute
$ touch dir/childdir/grandchild
$ getfattr -n ceph.file.layout dir/childdir/grandchild
# file: dir/childdir/grandchild
ceph.file.layout="stripe_unit=4194304 stripe_count=4 object_size=4194304 pool=cephfs_data"
```

## 向文件系统添加数据池

在将存储池与 CephFS 一起使用之前，必须将其添加到元数据服务器。

```bash
$ ceph fs add_data_pool cephfs cephfs_data_ssd
$ ceph fs ls  # Pool should now show up
.... data pools: [cephfs_data cephfs_data_ssd ]
```
确保您的 cephx 密钥允许客户端访问此新池。

然后，您可以更新 CephFS 中目录上的布局，以使用您添加的存储池：

```bash
$ mkdir /mnt/cephfs/myssddir
$ setfattr -n ceph.dir.layout.pool -v cephfs_data_ssd /mnt/cephfs/myssddir
```

在该目录中创建的所有新文件现在都将继承其布局并将其数据放入新添加的池中。

您可能会注意到，主数据池（传递给 fs new 的数据池）中的对象计数继续增加，即使您添加的池中正在创
建文件也是如此。这是正常的：文件数据存储在布局指定的池中，但所有文件都在主数据池中都保留了少量元
数据。