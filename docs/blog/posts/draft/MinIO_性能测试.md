---
date: 2025-06-27
categories:
  - Minio
draft: true
---

![](./assert/minio.png)


└─open--local--lvm--xfs-local--4dcc0718--3f56--4d6b--9bea--6166a6859bb5 253:0    0  2.5T  0 lvm  /var/lib/kubelet/pods/c36f9d6f-5e17-4f62-9485-0ef8e7f2ef05/volumes/kubernetes.io~csi/local-4dcc0718-3f56-4d6b-9bea-6166a6859bb5/mount





磁盘写
dd if=/dev/zero of=./test1 bs=16M count=128 oflag=direct
128+0 records in
128+0 records out
2147483648 bytes (2.1 GB, 2.0 GiB) copied, 0.634047 s, 3.4 GB/s

磁盘读
dd of=/dev/null if=./test1 bs=16M count=128 iflag=direct
128+0 records in
128+0 records out
2147483648 bytes (2.1 GB, 2.0 GiB) copied, 0.354278 s, 6.1 GB/s

小文件

./warp put --host=minio-pool-0-{0...2}.minio.cadp-system.svc.cluster.local:9000 --access-key=vestack  --secret-key=RWJTZZjODw --concurrent=32  --obj.size=1M --duration=3m

Report: PUT (487171 reqs). Ran Duration: 2m57s, starting 11:23:24 CST
 * Objects per request: 1. Size: 1000000 bytes. Concurrency: 32. Hosts: 3.
 * Average: 2579.23 MiB/s, 2704.51 obj/s (177s)
 * Reqs: Avg: 12.4ms, 50%: 10.8ms, 90%: 17.1ms, 99%: 24.9ms, Fastest: 6.6ms, Slowest: 129.7ms, StdDev: 4.1ms

Throughput by host:
 * http://minio-pool-0-0.minio.cadp-system.svc.cluster.local:9000: Avg: 888.43 MiB/s, 931.59 obj/s (180s)
 * http://minio-pool-0-1.minio.cadp-system.svc.cluster.local:9000: Avg: 858.48 MiB/s, 900.18 obj/s (180s)
 * http://minio-pool-0-2.minio.cadp-system.svc.cluster.local:9000: Avg: 834.09 MiB/s, 874.61 obj/s (180s)

Throughput, split into 177 x 1s:
 * Fastest: 2869.2MiB/s, 3008.60 obj/s (1s, starting 11:23:32 CST)
 * 50% Median: 2719.7MiB/s, 2851.79 obj/s (1s, starting 11:23:44 CST)
 * Slowest: 625.0MiB/s, 655.39 obj/s (1s, starting 11:25:53 CST)


