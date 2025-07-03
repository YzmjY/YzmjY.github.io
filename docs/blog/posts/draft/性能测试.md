---
date: 2025-06-27
categories:
  - Minio
draft: true
---


/dev/nvme0n1p3 999511208 207677692 791833516  21% /var/lib/docker

磁盘写
dd if=/dev/zero of=./test bs=16M count=128 oflag=direct
128+0 records in
128+0 records out
2147483648 bytes (2.1 GB, 2.0 GiB) copied, 1.16756 s, 1.8 GB/s

磁盘读
dd of=/dev/null if=./test bs=16M count=128 iflag=direct
128+0 records in
128+0 records out
2147483648 bytes (2.1 GB, 2.0 GiB) copied, 0.713841 s, 3.0 GB/s

