---
title: 客户端权限
---


# 客户端权限（Caps）

当客户端想要操作 inode 时，它会以各种方式去查询 MDS，从而获取一组Caps，以保证客户端安全的在 inode 上进行操作。与其他网络文件系统（例如 NFS 或 SMB）相比，CephFS 中的能力非常精细，并且可能有多个客户端在同一 inode 上持有不同的Caps。

## Caps 类型
下面是一些通用的Caps比特位，代表可以不同Caps可以进行的操作：

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

而后这些通用的比特位被移动了特定的位数，代表inode的数据或元数据的哪些部分被授予了对应类型的Caps。

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

These bits can then be or’ed together to make a bitmask denoting a set of capabilities.

There is one exception:

#define CEPH_CAP_PIN  1  /* no specific capabilities beyond the pin */
The “pin” just pins the inode into memory, without granting any other caps.

Graphically:

+---+---+---+---+---+---+---+---+
| p | _ |As   x |Ls   x |Xs   x |
+---+---+---+---+---+---+---+---+
|Fs   x   c   r   w   b   a   l |
+---+---+---+---+---+---+---+---+
The second bit is currently unused.

Abilities granted by each cap
While that is how capabilities are granted (and communicated), the important bit is what they actually allow the client to do:

PIN: This just pins the inode into memory. This is sufficient to allow the client to get to the inode number, as well as other immutable things like major or minor numbers in a device inode, or symlink contents.

AUTH: This grants the ability to get to the authentication-related metadata. In particular, the owner, group and mode. Note that doing a full permission check may require getting at ACLs as well, which are stored in xattrs.

LINK: The link count of the inode.

XATTR: Ability to access or manipulate xattrs. Note that since ACLs are stored in xattrs, it’s also sometimes necessary to access them when checking permissions.

FILE: This is the big one. This allows the client to access and manipulate file data. It also covers certain metadata relating to file data -- the size, mtime, atime and ctime, in particular.

Shorthand
Note that the client logging can also present a compact representation of the capabilities. For example:

pAsLsXsFs
The ‘p’ represents the pin. Each capital letter corresponds to the shift values, and the lowercase letters after each shift are for the actual capabilities granted in each shift.

The relation between the lock states and the capabilities
In MDS there are four different locks for each inode, they are simplelock, scatterlock, filelock and locallock. Each lock has several different lock states, and the MDS will issue capabilities to clients based on the lock state.

In each state the MDS Locker will always try to issue all the capabilities to the clients allowed, even some capabilities are not needed or wanted by the clients, as pre-issuing capabilities could reduce latency in some cases.

If there is only one client, usually it will be the loner client for all the inodes. While in multiple clients case, the MDS will try to calculate a loner client out for each inode depending on the capabilities the clients (needed | wanted), but usually it will fail. The loner client will always get all the capabilities.

The filelock will control files’ partial metadatas’ and the file contents’ access permissions. The metadatas include mtime, atime, size, etc.

Fs: Once a client has it, all other clients are denied Fw.

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