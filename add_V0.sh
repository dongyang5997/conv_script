#!/bin/bash

# 检查是否提供了正确数量的参数
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_file> <output_file>"
    exit 1
fi

input="$1"
output="$2"

# 处理每一行，在末尾添加 ' -V 0'
while read -r line; do
    echo "$line -V 0" >> "$output"
done < "$input"

# 使输出文件可执行
chmod +x "$output"

echo "已生成新脚本：$output，每行末尾都加上了 '-V 0'。"
