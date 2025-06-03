---
title: 客户端权限
---


# 客户端权限（Caps）

当客户端想要操作 inode 时，它会以各种方式去查询 MDS，从而获取一组Caps，以保证客户端安全的在 inode 上进行操作。与其他网络文件系统（例如 NFS 或 SMB）相比，CephFS 中的能力非常精细，并且可能有多个客户端在同一 inode 上持有不同的Caps。

## Caps 类型
下面是一些通用的Caps比特位，代表不同Caps对应的能力：

```
/* generic cap bits */
#define CEPH_CAP_GSHARED     1  /* (metadata) client can read (s) */
#define CEPH_CAP_GEXCL       2  /* (metadata) client can read and update (x) */
#define CEPH_CAP_GCACHE      4  /* (file) client can cache reads (c) */
#define CEPH_CAP_GRD         8  /* (file) client can read (r) */
#define CEPH_CAP_GWR        16  /* (file) client can write (w) */
#define CEPH_CAP_GBUFFER    32  /* (file) client can buffer writes (b) */
#define CEPH_CAP_GWREXTEND  64  /* (file) client can extend EOF (a) */
#define CEPH_CAP_GLAZYIO   128  /* (file) client can perform lazy io (l) */
```

而后这些通用的比特位被移动了特定的位数，代表对应的Caps能力是针对inode的数据或元数据的哪些部分。

> 可以理解为前者定义了Caps的权限，后者定义了Caps的权限作用的对象。

```
/* per-lock shift */
#define CEPH_CAP_SAUTH      2 /* A */
#define CEPH_CAP_SLINK      4 /* L */
#define CEPH_CAP_SXATTR     6 /* X */
#define CEPH_CAP_SFILE      8 /* F */
```

注意，对于其中的一些移位数，只有特定的通用Caps类型才会被授予。例如，只有FILE对应的Caps会有超过两个比特来表示。
> 可以理解为将Caps分为多个区域，每个区域的不同bit代表对应一种资源的一类Caps。

```
| PIN | AUTH | LINK | XATTR | FILE
0     2      4      6       8
```

通过以上描述，我们可以得到一个常量，这些常量是通过将每个bit值移动到正确的bit位来生成的：

```
#define CEPH_CAP_AUTH_SHARED  (CEPH_CAP_GSHARED  << CEPH_CAP_SAUTH)
```

可以通过将这些常量通过或运算来生成一个bitmask，以表示一组Caps。

下面是一个例外：

```
#define CEPH_CAP_PIN  1  /* no specific capabilities beyond the pin */
```

"pin" 只是将inode固定到内存中，而不授予任何其他Caps。

图形化表示如下：:

```
+---+---+---+---+---+---+---+---+
| p | _ |As   x |Ls   x |Xs   x |
+---+---+---+---+---+---+---+---+
|Fs   x   c   r   w   b   a   l |
+---+---+---+---+---+---+---+---+
```

第二个bit目前未使用。

## 每个Caps授予的能力

上述描述了如何授予Caps（以及表达），但更为关键的是获取对应Caps的客户端可以做哪些操作：

- PIN: 将inode固定到内存中。这允许客户端获取inode编号，以及其他不可变的东西，如设备inode中的major或minor数字，或符号链接的内容。

- AUTH: 允许客户端获取与身份验证相关的元数据。特别是所有者、组和模式。请注意，执行完整的权限检查可能还需要访问ACL，这些ACL存储在xattrs中。

LINK: The link count of the inode.
- LINK: 允许客户端操作inode的链接计数。

XATTR: Ability to access or manipulate xattrs. Note that since ACLs are stored in xattrs, it’s also sometimes necessary to access them when checking permissions.
- XATTR: 允许客户端访问或操作xattrs。请注意，由于ACL存储在xattrs中，因此在检查权限时可能还需要访问它们。

- FILE: 这个是最重要的。这允许客户端访问和操作文件数据。它还包括与文件数据相关的某些元数据，特别是大小、mtime、atime和ctime。 

## 简写
客户端在日志中可能会呈现Caps的简写表示。例如：

```
pAsLsXsFs
```

`p` 表示PIN。 每个大写字母对应于移位值，每个移位后接的小写字母表示每个移位中授予的实际能力。

## 锁状态与Caps的关系
在MDS中，每个inode都有四个不同的锁，它们是simplelock、scatterlock、filelock和locallock。每个锁有几个不同的锁状态，MDS将根据锁状态向客户端授予Caps。

在 MDS Locker的每个状态下，MDS Locker 总是会尝试向客户端授予所有允许的Caps，即使客户端不需要某些Caps，因为预先授予能力可能会在某些情况下减少延迟。

If there is only one client, usually it will be the loner client for all the inodes. While in multiple clients case, the MDS will try to calculate a loner client out for each inode depending on the capabilities the clients (needed | wanted), but usually it will fail. The loner client will always get all the capabilities.


The filelock will control files’ partial metadatas’ and the file contents’ access permissions. The metadatas include mtime, atime, size, etc.
filelock 控制文件的部分元数据和文件内容的访问权限。元数据包括mtime、atime、size等。

Fs: Once a client has it, all other clients are denied Fw.
- Fs: 

Fx: Only the loner client is allowed this capability. Once the lock state transitions to LOCK_EXCL, the loner client is granted this along with all other file capabilities except the Fl.

Fr: Once a client has it, the Fb capability will be already revoked from all the other clients.

If clients only request to read the file, the lock state will be transferred to LOCK_SYNC stable state directly. All the clients can be granted Fscrl capabilities from the auth MDS and Fscr capabilities from the replica MDSes.

If multiple clients read from and write to the same file, then the lock state will be transferred to LOCK_MIX stable state finally and all the clients could have the Frwl capabilities from the auth MDS, and the Fr from the replica MDSes. The Fcb capabilities won’t be granted to all the clients and the clients will do sync read/write.

Fw: If there is no loner client and once a client have this capability, the Fsxcb capabilities won’t be granted to other clients.

If multiple clients read from and write to the same file, then the lock state will be transferred to LOCK_MIX stable state finally and all the clients could have the Frwl capabilities from the auth MDS, and the Fr from the replica MDSes. The Fcb capabilities won’t be granted to all the clients and the clients will do sync read/write.

Fc: This capability means the clients could cache file read and should be issued together with Fr capability and only in this use case will it make sense.

While actually in some stable or interim transitional states they tend to keep the Fc allowed even the Fr capability isn’t granted as this can avoid forcing clients to drop full caches, for example on a simple file size extension or truncating use case.

Fb: This capability means the clients could buffer file write and should be issued together with Fw capability and only in this use case will it make sense.

While actually in some stable or interim transitional states they tend to keep the Fc allowed even the Fw capability isn’t granted as this can avoid forcing clients to drop dirty buffers, for example on a simple file size extension or truncating use case.

Fl: This capability means the clients could perform lazy io. LazyIO relaxes POSIX semantics. Buffered reads/writes are allowed even when a file is opened by multiple applications on multiple clients. Applications are responsible for managing cache coherency themselves.