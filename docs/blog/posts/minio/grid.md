---
date: 2025-06-04
categories:
  - Minio
draft: false
---

# 【MinIO】通信框架-Grid
---

## 简介
Grid 是 MinIO 中的一个内部通信框架，用于在分布式部署环境中实现节点间的高效通信。它提供了一个基于 WebSocket 的双向通信系统，支持单次请求-响应模式和流式通信模式，使得 MinIO 集群中的不同节点能够可靠地交换数据和执行远程操作。

Grid 通信框架适用于：

- 高频次、小数据、低延迟的请求。
- 长周期运行的中小型数据交换。

不适用于：

- 大数据量的传输。

Grid中的两个节点只会创建一个连接，这意味着单连接无法使带宽达到饱和。因此，使用Grid框架传输大数据量的请求会比使用另一个独立的连接慢，且该连接上的其他请求会被该请求阻塞。

<!-- more -->


## 实现

### 私有协议

```
+--------+--------+----------+------------+---------+-------+---------+----------+--------+
| mux id | seq id | deadline | handler id | op code | flags | payload | subroute | crc    |
+--------+--------+----------+------------+---------+-------+---------+----------+--------+
| uint64 | uint32 |  uint32  |    uint8   |  uint8  | uint8 |  bytes  | []byte   | uint32 |
+--------+--------+----------+------------+---------+-------+---------+----------+--------+
\------------------------------msgpack-------------------------------/\---append binary---/
```
其中：

- mux id：单连接多路复用标识符。
- seq id：请求序列号，请求响应保序。
- deadline：请求超时时间。
- handler id：请求处理函数标识符,用于分发请求。
- op code：请求操作码。
- flags：请求标志位。
- payload：请求负载数据。
- subroute：请求子路由。
- crc：请求校验码。


### 连接管理
Grid中负责管理连接的模块是`Manager`，`Manager`定义如下:

```go
// Manager will contain all the connections to the grid.
// It also handles incoming requests and routes them to the appropriate connection.
type Manager struct {
	// ID is an instance ID, that will change whenever the server restarts.
	// This allows remotes to keep track of whether state is preserved.
	ID uuid.UUID

	// Immutable after creation, so no locks.
	targets map[string]*Connection

	// serverside handlers.
	handlers handlers

	// local host name.
	local string

	// authToken is a function that will validate a token.
	authToken ValidateTokenFn

	// routePath indicates the dial route path
	routePath string
}
```
其中：
- ID：`Manager`的实例ID，每次服务器重启时都会改变。
- targets：存储所有连接到Grid的连接,key为连接的目标地址，在`Manager`创建时传入，不可更改。

Grid中每个节点都会与其他节点建立WebSocket连接，每个连接的双端区分为client端和server端，连接初始化时，由client端发起建连，server端响应建连。

client和server端依据两节点的Host地址确定。
```go
func (c *Connection) shouldConnect() bool {
	// The remote should have the opposite result.
	h0 := xxh3.HashString(c.Local + c.Remote)
	h1 := xxh3.HashString(c.Remote + c.Local)
	if h0 == h1 {
		return c.Local < c.Remote
	}
	return h0 < h1
}
```

每一对节点之间建立的连接对应一个`Connection`实例，`Connectioin`用来收发连接上的消息，管理连接上的多路复用.

#### 连接建立
TODO:时序图：

c 


#### 消息收发


### 多路复用
一个`Connection`实例上可以同时存在多个`Mux`实例，每个`Mux`实例对应一个连接上的一个多路复用通道，每个`Mux`实例负责接收和发送消息。

请求发起方会创建一个`muxClient`实例，接受方会创建一个`muxServer`实例。保存在`Connection`实例中的全局Map中，key为对应的mux id。

对于单次请求的场景

对于流式请求的场景，`muxClient`和`muxServer`都会进行消息的收发。


### 请求处理
`Connection`接受到请求之后，首先依据`OpCode`进行路由，区分出不同的操作类型，`OpCode`及其含义如下：
```go
const (
	// OpConnect is a connect request.
	OpConnect Op = iota + 1
	// OpConnectResponse is a response to a connect request.
	OpConnectResponse
	// OpPing is a ping request.
	// If a mux id is specified that mux is pinged.
	// Clients send ping requests.
	OpPing
	// OpPong is a OpPing response returned by the server.
	OpPong
	// OpConnectMux will connect a new mux with optional payload.
	OpConnectMux
	// OpMuxConnectError is an  error while connecting a mux.
	OpMuxConnectError
	// OpDisconnectClientMux instructs a client to disconnect a mux
	OpDisconnectClientMux
	// OpDisconnectServerMux instructs a server to disconnect (cancel) a server mux
	OpDisconnectServerMux
	// OpMuxClientMsg contains a message to a client Mux
	OpMuxClientMsg
	// OpMuxServerMsg contains a message to a server Mux
	OpMuxServerMsg
	// OpUnblockSrvMux contains a message that a server mux is unblocked with one.
	// Only Stateful streams has flow control.
	OpUnblockSrvMux
	// OpUnblockClMux contains a message that a client mux is unblocked with one.
	// Only Stateful streams has flow control.
	OpUnblockClMux
	// OpAckMux acknowledges a mux was created.
	OpAckMux
	// OpRequest is a single request + response.
	// MuxID is returned in response.
	OpRequest
	// OpResponse is a response to a single request.
	// FlagPayloadIsErr is used to signify that the payload is a string error converted to byte slice.
	// When a response is received, the mux is already removed from the remote.
	OpResponse
	// OpDisconnect instructs that remote wants to disconnect
	OpDisconnect
	// OpMerged is several operations merged into one.
	OpMerged
)
```
简单将请求分为控制请求、探活请求和消息处理请求。

消息处理请求类似于一次RPC调用，根据msg中的handlerid和subrouter路由到对应的提前注册的handler上进行处理。有单次请求和流式请求两种类型。


#### Single Request


#### Stream Request



## MinIO 中的使用
