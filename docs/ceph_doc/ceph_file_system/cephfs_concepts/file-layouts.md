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