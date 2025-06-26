---
date: 2025-06-26
categories:
  - Minio
draft: true
---

# 【MinIO】Scanner
---

Scanner是MinIO中一个重要的子系统，MinIO使用Scanner程序来实现诸多功能，包括：

- 计算磁盘的使用量、Object/bucket的统计数据。
- 在Object上应用生命周期、保留规则（如果存在）。
- 应用Bucket或Site级别的负责策略。
- 检查对象是否损坏并修复。

<!--more-->