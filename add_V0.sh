#!/bin/bash

input="$1"
output="$2"

if [ -z "$input" ] || [ -z "$output" ]; then
    echo "Usage: $0 <input_file> <output_file>"
    exit 1
fi

# 保留原始 shebang（如果有）
head -n 1 "$input" | grep -q "^#!" && head -n 1 "$input" > "$output"

# 处理每一行，末尾加上 ' -V 0'
tail -n +2 "$input" | awk '{print $0 " -V 0"}' >> "$output"

chmod +x "$output"

echo "已生成新脚本：$output，每行末尾都加上了 -V 0"
