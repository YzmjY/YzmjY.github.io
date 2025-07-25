---
date: 2025-07-26
categories:
  - MinIO
draft: false
---

# MinIO 笔记（5）：分布式锁

![](../assert/minio.png)

<!-- more -->

## Dsync

「Dsync」是 MinIO 中的用于实现分布式锁的组件。当一个 Node 需要加锁时，向所有 Node 发出请求，在收到 n/2 + 1 个同意后（对于读锁 n/2），才能成功获取锁。

### 实现
Dsync 组件的主要负责协调多个 Node 之间的锁请求，至于对于单个 Node 的锁请求，是通过 NetLocker 接口实现的。
```go
// Dsync represents dsync client object which is initialized with
// authenticated clients, used to initiate lock REST calls.
type Dsync struct {
	// List of rest client objects, one per lock server.
	GetLockers func() ([]NetLocker, string)

	// Timeouts to apply.
	Timeouts Timeouts
}
```
`GetLockers` 方法返回 NetLocker 实例列表，用于与所有 Node 进行通信。

NetLocker 接口定义了分布式锁的基本操作，包括加锁、解锁、刷新锁等。
```go
// NetLocker is dsync compatible locker interface.
type NetLocker interface {
	// Do read lock for given LockArgs.  It should return
	// * a boolean to indicate success/failure of the operation
	// * an error on failure of lock request operation.
	RLock(ctx context.Context, args LockArgs) (bool, error)

	// Do write lock for given LockArgs. It should return
	// * a boolean to indicate success/failure of the operation
	// * an error on failure of lock request operation.
	Lock(ctx context.Context, args LockArgs) (bool, error)

	// Do read unlock for given LockArgs. It should return
	// * a boolean to indicate success/failure of the operation
	// * an error on failure of unlock request operation.
	// Canceling the context will abort the remote call.
	// In that case, the resource may or may not be unlocked.
	RUnlock(ctx context.Context, args LockArgs) (bool, error)

	// Do write unlock for given LockArgs. It should return
	// * a boolean to indicate success/failure of the operation
	// * an error on failure of unlock request operation.
	// Canceling the context will abort the remote call.
	// In that case, the resource may or may not be unlocked.
	Unlock(ctx context.Context, args LockArgs) (bool, error)

	// Refresh the given lock to prevent it from becoming stale
	Refresh(ctx context.Context, args LockArgs) (bool, error)

	// Unlock (read/write) forcefully for given LockArgs. It should return
	// * a boolean to indicate success/failure of the operation
	// * an error on failure of unlock request operation.
	ForceUnlock(ctx context.Context, args LockArgs) (bool, error)

	// Returns underlying endpoint of this lock client instance.
	String() string

	// Close closes any underlying connection to the service endpoint
	Close() error

	// Is the underlying connection online? (is always true for any local lockers)
	IsOnline() bool

	// Is the underlying locker local to this server?
	IsLocal() bool
}
```

Dsync 在 NetLocker 之间传输如下信息，包括加锁的对象、锁的持有者、需要的 quorum 节点数等。
```go
type LockArgs struct {
	// Unique ID of lock/unlock request.
	UID string

	// Resources contains single or multiple entries to be locked/unlocked.
	Resources []string

	// Owner represents unique ID for this instance, an owner who originally requested
	// the locked resource, useful primarily in figuring out stale locks.
	Owner string

	// Source contains the line number, function and file name of the code
	// on the client node that requested the lock.
	Source string `msgp:"omitempty"`

	// Quorum represents the expected quorum for this lock type.
	Quorum *int `msgp:"omitempty"`
}
```

### 加锁
加锁的基本步骤为,阻塞的尝试向所有节点获取锁
- 获取 quorum 节点的响应，则加锁成功，启动一个异步任务去定时刷新锁。刷新锁的基本步骤为：
    * 向所有节点发送 Refresh 请求
    * 获取 quorum 节点的响应，则刷新成功
    * 否则，调用回调函数，强制释放已持有的锁
- 未获取则重试至超时

```mermaid
flowchart TD
    Start([GetLocker])
    Start --> Read{读锁？}
    Read -- 是 --> SetR(isReadLock=true)
    Read -- 否 --> SetW(isReadLock=false)
    SetR --> lockBlocking(lockBlocking)
    SetW --> lockBlocking(lockBlocking)
    lockBlocking --> quorum(确定 quorum)
    quorum --> lock(向所有节点发出加锁请求)
    lock --> quorumResponse{是否获得 quorum 响应？}
    lock -- 是否超时 --> timeout([加锁失败])
    quorumResponse -- 是 --> success(加锁成功)
    quorumResponse -- 否 --> release(释放已持有的锁)
    release -- sleep,retry --> lock
    success --> startContinuousLockRefresh(异步任务刷新)
    startContinuousLockRefresh --> refresh(向所有节点发送 Refresh 请求)
    refresh --> quorumResponse2{是否获得 quorum 响应？}
    quorumResponse2 -- 是 --> success(刷新成功)
    quorumResponse2 -- 否 --> cb(调用回调函数)
    cb --> forceUnlock(强制释放已持有的锁)
    startContinuousLockRefresh --> return([返回加锁成功])
```

### 释放锁
释放锁的基本步骤为：
- 向所有节点发送 Unlock 请求
- 获取 quorum 节点的响应，则释放锁成功
- 失败则退避重试，直至成功或超时

## NetLocker 实现
上述 Dsync 负责在多个 Node 之间协调锁请求，而 NetLocker 则负责在单个 Node 上实现锁的加锁、解锁、刷新等操作。

由于 Node 间锁的协调是通过网络的，则 NetLocker 需要一组服务端和客户端的实现，来满足 Node 之间的调用。NetLocker 的网络通信采用之前的 Grid 框架，将 NetLocker 的服务接口注册到 Grid 的 Handler 中。

其对锁的操作接口由`localLocker`实现，`localLocker` 负责在本地 Node 上维护锁的状态，对外部 Node 的加锁请求进行处理。

## 不同的锁实现

在 MinIO 中，通过上述的 Dsync 分布式锁机制，实现了两种类型的锁：

- Namespace Lock：
- Shard Lock：