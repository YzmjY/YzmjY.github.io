#!/bin/bash

# 检查参数数量
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <relative_path> <file_name>"
    exit 1
fi

# 获取参数
relative_path=$1
file_name=$2

# 获取当前日期
current_date=$(date '+%Y-%m-%d')

# 检查路径是否存在，不存在则创建
if [ ! -d "$relative_path" ]; then
    mkdir -p "$relative_path"
fi

# 创建文件并写入内容
cat <<EOL > "${relative_path}/${file_name}"
---
date: $current_date
categories:
  - 刷题
draft: false
---
EOL

echo "文件已在 ${relative_path}/${file_name} 创建，并写入了当前日期：${current_date}"