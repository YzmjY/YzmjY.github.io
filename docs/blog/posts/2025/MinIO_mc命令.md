---
date: 2025-07-01
categories:
  - MinIO
draft: false
---

# MinIO: mc 工具常用命令

![](./assert/minio.png)
`mc` 命令行工具为 `ls`、`cat`、`cp`、`mirror` 和 `diff` 等 `UNIX` 命令提供了一种现代替代方案，同时支持本地文件系统和与 Amazon S3 兼容的云存储服务。

<!-- more -->

## 安装

### 创建 S3 服务别名
```bash
mc alias set ALIAS HOSTNAME ACCESS_KEY SECRET_KEY
```

- `ALIAS`: S3 服务别名，通过该名称标识针对哪个 S3 服务执行命令。
- `HOSTNAME`: MinIO 服务器主机名
- `ACCESS_KEY`: 访问密钥
- `SECRET_KEY`: 秘密密钥

### 测试连通性
```bash
mc admin info ALIAS
```

得到类似如下输出：
```bash
●  minio1:9000
   Uptime: 23 minutes
   Version: <development>
   Network: 3/3 OK
   Drives: 1/1 OK
   Pool: 1

●  minio2:9000
   Uptime: 23 minutes
   Version: <development>
   Network: 3/3 OK
   Drives: 1/1 OK
   Pool: 1

●  minio3:9000
   Uptime: 23 minutes
   Version: <development>
   Network: 3/3 OK
   Drives: 1/1 OK
   Pool: 1

┌──────┬────────────────────────┬─────────────────────┬──────────────┐
│ Pool │ Drives Usage           │ Erasure stripe size │ Erasure sets │
│ 1st  │ 23.5% (total: 111 GiB) │ 3                   │ 1            │
└──────┴────────────────────────┴─────────────────────┴──────────────┘
```

## 常用命令

`mc`的命令分为仅适用于 MinIO 和适用于 S3 服务的命令，其中 `mc admin` 簇的命令仅适用于 MinIO，一些 `mc` 命令允许模式匹配，支持 `*`/`?` 通配符。

- `*`: 通配符，匹配任意字符串
- `?`: 通配符，匹配任意一个字符

此外，有一些全局的选项，适用于所有命令：  

- `--config-dir`: 配置目录，默认`~/.mc`
- `--debug`: 开启调试模式
- `--quiet`: 不打印任何信息
- `--json`: 以JSON格式输出

### 普通命令

> 详情：[mc 命令](https://min.io/docs/minio/linux/reference/minio-mc.html)

`mc`提供诸如`cat`, `cp`,`diff`,`du`,`find`,`head`, `ls`, `mv`, `rm`, `stat`,`tree`等类似UNIX的命令，命令语义也类似。

此外，针对 S3 特有的 Bucket，Object 有如下命令：

- `mb`: 创建 Bucket
- `rb`: 删除 Bucket
- `get`: 下载 Object
- `put`: 上传 Object
- `quota`: Bucket 配额相关
- `ready`: 检查集群是否可用
- `ping`: 检查集群是否联通

#### 常用示例

1. 检查集群是否可读写：
    ```bash
    > mc ready minio --json
    ---
    {
    "status": "success",
    "alias": "minio",
    "healthy": true,
    "maintenanceMode": false,
    "writeQuorum": 2,
    "healingDrives": 0,
    "error": null
    }
    ```

2. 查看一个 Bucket 的用量，Object 分布等情况：
    ```bash
    > mc stat minio/data
    ---
    Name      : data
    Date      : 2025-07-01 17:11:57 CST
    Size      : N/A
    Type      : folder

    Properties:
    Versioning: Un-versioned
    Location: us-east-1
    Anonymous: Disabled
    ILM: Disabled

    Usage:
        Total size: 150 MiB
    Objects count: 1
    Versions count: 0

    Object sizes histogram:
    0 object(s) BETWEEN_1024B_AND_1_MB
    0 object(s) BETWEEN_1024_B_AND_64_KB
    0 object(s) BETWEEN_10_MB_AND_64_MB
    1 object(s) BETWEEN_128_MB_AND_512_MB
    0 object(s) BETWEEN_1_MB_AND_10_MB
    0 object(s) BETWEEN_256_KB_AND_512_KB
    0 object(s) BETWEEN_512_KB_AND_1_MB
    0 object(s) BETWEEN_64_KB_AND_256_KB
    0 object(s) BETWEEN_64_MB_AND_128_MB
    0 object(s) GREATER_THAN_512_MB
    0 object(s) LESS_THAN_1024_B
    ```

1. 查看一个 Bucket 的 quota 设置：
    ```bash
    > mc quota info minio/data --json
    ---
    {
    "status": "success",
    "bucket": "data",
    "quota": 5000000000,
    "type": "hard"
    }
    ```

### admin 命令
> 详情：[mc admin命令](https://min.io/docs/minio/linux/reference/minio-mc-admin.html)

#### 检查集群状态

```bash
mc admin info ALIAS
```

#### 配置管理
`mc admin config` 相关命令提供管理员对集群配置的管理。

1. 获取配置
    ```bash
    mc admin config get TARGET
    ```
2. 设置配置
    ```bash
    mc admin config set TARGET
    ```
3. 重置配置
    ```bash
    mc admin config reset TARGET
    ```
4. 导出配置
    ```bash
    mc admin config export TARGET
    ```

#### 数据修复

`mc admin heal` 相关命令用于修复数据的相关能力。

```bash
mc admin heal [FLAGS] TARGET
```

修复一个Bucket：
```bash
mc admin heal <alias/bucket>
```
得到类似如下的结果：
```bash
 ◓  data
    0/0 objects; 0 B in 1s
    ┌────────┬───┬─────────────────────┐
    │ Green  │ 1 │ 100.0% ████████████ │
    │ Yellow │ 0 │   0.0%              │
    │ Red    │ 0 │   0.0%              │
    │ Grey   │ 0 │   0.0%              │
    └────────┴───┴─────────────────────┘
```
该命令有一些Flag是隐藏的，例如：

- `-r`: 递归的修复 Target 下所有 Object。

如果没有指定 bucket 且没有 -r 选项，该命令只会返回后台修复进程（新磁盘修复）的状态，对于没有换盘坏盘等情况，正常输出为：

```bash
>mc admin heal minio
---
No active healing is detected for new disks.
```
#### 数据扫描

`mc admin scanner`相关命令提供了探查数据扫描器相关状态的能力。


#### 请求trace
`mc admin trace`相关命令提供了请求跟踪相关的能力。

```bash
mc admin trace [FLAGS] TARGET
```

`FLAGS`:
- `-a, --all`: 跟踪所有API操作
- `--call`: 某一种类型的请求
- `--errors, e`: 只trace错误的请求
- `--filter-request`: 对request过滤，后面必须跟`--filter-size`来指定过滤的size
- `--filter-response`: 对response过滤，后面必须跟`--filter-size`来指定过滤的size
- `--funcname`: 函数名过滤
- `--method`: HTTP方法过滤
- `--path`: 路径过滤
- `--status-code`: HTTP状态码过滤
- `--request-header`: 请求头过滤
- `--response-duration`: 响应时间过滤
- `--status-code`: 状态码过滤

`--call`的值可以是：

- `batch-keyrotation`
- `batch-replication`
- `bootstrap`
- `decommission`
- `ftp`
- `healing`
- `ilm`
- `internal`
- `os`
- `rebalance`
- `replication-resync`
- `s3`
- `scanner`
- `storage`

常见用例：

- trace所有API操作
    ```bash
    mc admin trace -a ALIAS
    ```
- trace返回503Error的请求
    ```bash
    mc admin trace -v --status-code 503 ALIAS
    ```
- trace某一个路径的请求
    ```bash
    mc admin trace --path my-bucket/my-prefix/* ALIAS
   ```
- trace返回Size大于1MB的请求
    ```bash
    mc admin trace --filter-response --filter-size 1Mb ALIAS
    ```
- trace延迟大于5ms的请求
    ```bash
    mc admin trace --filter-duration 5ms ALIAS
    ```
- trace某一类型的请求
    ```bash
    mc admin trace --call <scanner> TARGET 
    ```

#### 日志
`mc admin logs`相关命令提供了日志相关的能力。






