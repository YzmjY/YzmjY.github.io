---
date: 2025-06-04
categories:
  - MinIO
draft: false
---

# MinIO: 通信框架-Grid

![](../assert/minio.png)

<!-- more -->

## 简介
「Grid」 是 MinIO 中的一个内部通信框架，用于在分布式部署环境中实现节点间的高效通信。它提供了一个基于 WebSocket 的双向通信系统，支持单次请求-响应模式和流式通信模式，使得 MinIO 集群中的不同节点能够可靠地交换数据和执行远程操作。

Grid 通信框架适用于：

- 高频次、小数据、低延迟的请求。
- 长周期运行的中小型数据交换。

不适用于：

- 大数据量的传输。

Grid 中的两个节点只会创建一个连接，这意味着单连接无法使带宽达到饱和。因此，使用 Grid 框架传输大数据量的请求会比使用另一个独立的连接慢，且该连接上的其他请求会被该请求阻塞。

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
Grid 中负责管理连接的模块是 `Manager`，`Manager` 定义如下:

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
- ID：`Manager` 的实例 ID，每次服务器重启时都会改变。
- targets：存储所有连接到 Grid 的连接,key 为连接的目标地址，在 `Manager` 创建时传入，不可更改。

Grid 中每个节点都会与其他节点建立 WebSocket 连接，每个连接的双端区分为 client 端和 server 端，连接初始化时，由 client 端发起建连，server 端响应建连。

client 和 server 端依据两节点的 Host 地址确定。
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

每一对节点之间建立的连接对应一个 `Connection` 实例，`Connection` 用来收发连接上的消息，管理连接上的多路复用.

#### 连接建立
待建连的两个节点之间首先依据上述的hash算法确定建连的方向，由 client 端发起建连，server 端响应建连。

##### Client侧
Client 侧会不断地尝试重新建立连接，直至服务关闭即 `Connection` 实例的状态被设置为 Shutdown（正常情况下不会有这个状态）。

Client 侧首先会建立 WebSocket 连接，建连 handler 如下：		
```go
// Pass Dialer for websocket grid, make sure we do not
// provide any DriveOPTimeout() function, as that is not
// useful over persistent connections.
Dialer: grid.ConnectWS(
	grid.ContextDialer(xhttp.DialContextWithLookupHost(lookupHost, xhttp.NewInternodeDialContext(rest.DefaultTimeout, globalTCPOptions.ForWebsocket()))),
	newCachedAuthToken(),
	&tls.Config{
		RootCAs:          globalRootCAs,
		CipherSuites:     fips.TLSCiphers(),
		CurvePreferences: fips.TLSCurveIDs(),
	}),
```
WebSocket 连接建立的具体过程为：
- 从 `globalDNSCache` 模块中获取目标地址的 IP 地址列表。
- 遍历 IP 地址列表，使用 net 标准库依次尝试建立 tcp 连接，直至成功连接。
- TCP 连接建连过程之后，按照 WebSocket 协议进行连接、握手、协议升级等操作，完成 WebSocket 连接的建立。

上述过程中，`globalDNSCache` 模块用于缓存 DNS 解析结果，避免每次都进行 DNS 解析。

WebSocket 连接建立完成之后，Client 侧会通过该连接发送一个 `OpConnect` 请求，请求中包含了 Client 的 ID、本地地址、远程地址等信息。Server 端接收到该请求后，会响应一个 `OpConnectResponse` 响应，包含了 Server 的 UUID，以及是否接受该连接、拒绝连接的原因等信息。

连接建立后，Client 侧会启动两个协程，分别用于接收和发送消息。并一直阻塞直至连接上有错误发生或者连接被关闭。如果连接上有错误发生，Client 侧会尝试重新建立连接。

##### Server侧
Server 侧则开放一个 HTTP API 端点，用于接收 Client 端的连接请求。 在对应的 Handler 内处理协议升级等 WebSocket 建连操作。同样的，WebSocket 连接建立之后，Server 侧等待 Client 端发送 `OpConnect` 请求，接收到该请求后，会响应一个 `OpConnectResponse` 响应，包含了Server的UUID，以及是否接受该连接、拒绝连接的原因等信息。
连接建立后，Server 侧会启动两个协程，分别用于接收和发送消息。并一直阻塞直至连接上有错误发生或者连接被关闭。Server 侧不会尝试重新建立连接，重连的操作由 Client 端发起。	

#### 消息收发
Server 侧通过接收 Client 端的连接请求，创建 `Connection` 实例;Client 端主动发起连接请求，创建 `Connection` 实例。`Connection` 建立完成后，会启动两个协程，分别用于接收和发送消息。
- `readStream`：负责从 websocket 连接中读取消息，然后将消息解码为 `message` 私有协议格式，而后根据 `OpCode` 进行路由，区分出不同的操作类型。
- `writeStream`：负责将 buf 合并写入 websocket 连接中，并发送探活消息。

### 多路复用
一个 `Connection` 实例上可以同时存在多个 `Mux` 实例，每个 `Mux` 实例对应一个连接上的一个多路复用通道，每个 `Mux` 实例负责接收和发送消息。同样的，一对 `Mux` 实例被区分为 CS 两端，请求发起方会创建一个 `muxClient` 实例，接受方会创建一个 `muxServer` 实例。保存在 `Connection` 实例中的全局 Map 中，key 为对应的 mux id。

`Mux` 的消息收发共用 `Connection` 的连接，通过 `MuxId` 进行区分不同的 `Mux` 实例。

对于单次请求的场景，`muxClient` 提供 `roundtrip` 方法，负责组装 `Msg` 并通过 `Connection` 进行发送，消息类型为 `OpRequest`，而后阻塞等待响应。

对于流式请求的场景，`muxClient` 提供 `RequestStream` 方法，Client 和 Server 端进行双向的流式请求。


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
简单将请求分为控制请求、探活请求和 RPC 请求。

- 控制请求：包含建连、流控、Batch 等请求。
- 探活请求：包含 Ping、Pong 请求。
- RPC请求：实现一次远程调用，根据 msg 中的 HandlerID 和 SubRouter 路由到对应的提前注册的 Handler 上进行处理。有单次请求和流式请求两种类型。

#### Handler
通过 Grid 框架，用户可以实现自己的 Handler，用于处理 RPC 请求。

对于单次请求的 Handler，使用流程如下：
- 实现一个 HandlerFunction：`func(payload []byte) ([]byte, *grid.RemoteErr)`
- 注册该 Handler，关联一个 HandlerID。
- 通过 Handler 的 `Call` 方法，实现 RPC 调用。

流式请求类似，流程如下：
- 实现 Handler：`StreamHandlerFn func(ctx context.Context, payload []byte, in <-chan []byte, out chan<- []byte) *RemoteErr`
- 注册该 Handler，关联一个 HandlerID。 
- 通过 Handler 的 `Call` 方法，实现 RPC 调用，返回一个 `Stream` 实例。
  - 通过 `Stream` 的 `Result` 方法，注册一个回调函数，用于处理响应。
  - 通过 `Stream` 的 `Send` 方法，发送请求。

### 健康检查
每个 Connection 都会定期的进行 Ping\Pong 的请求来进行探活，对于超时未收到 Pong 响应的连接，会由 Client 侧不断地发起 `reconnect` 请求。	

## MinIO 中的使用
MinIO中一个Server会有两个全局的 `Manager` 实例，分别用于处理分布式锁场景和其他交互场景。

### 元数据读写

MinIO中元数据读写由 Grid 进行处理，数据 Part 读写由 restClient 处理。	

Grid 通信框架适用于对于元数据读写、Bucket、Object 等删除这类数据量较小的请求，而对于数据 Part 的读写这类操作，通常数据量较大，不适用于 Grid。因此在 MinIO 中，对于数据 Part 的读写，使用的是 restClient，restClient 即为一个简单的 HTTP 服务，通过 REST 接口使用 HTTP 协议进行数据的读写。

### 锁

