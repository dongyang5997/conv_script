#!/bin/bash

input="ConvolutionWorkLoad_MIOpen_1896_v1.sh"
output="ConvolutionWorkLoad_MIOpen_1896_v1_withV.sh"

# 保留原始 shebang（如果有）
head -n 1 "$input" | grep -q "^#!" && head -n 1 "$input" > "$output"

# 处理每一行，末尾加上 ' -V 0'
tail -n +2 "$input" | awk '{print $0 " -V 0"}' >> "$output"

chmod +x "$output"

echo "已生成新脚本：$output，每行末尾都加上了 -V 0"
