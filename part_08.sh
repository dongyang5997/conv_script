#!/bin/bash

# 用法提示
if [[ $# -ne 2 ]]; then
    echo "用法: $0 <输入脚本名> <输出前缀名>"
    echo "例如: $0 ConvolutionWorkLoad_MIOpen_1896_v1.sh my_miopen_part_"
    exit 1
fi

input_script="$1"
output_prefix="$2"

# 1. 提取所有以 MIOpen 开头的行
grep '^MIOpen' "$input_script" > all_miopen_lines.tmp

# 2. 统计总行数
total_lines=$(wc -l < all_miopen_lines.tmp)

# 3. 计算每份的行数（向上取整）
lines_per_file=$(( (total_lines + 7) / 8 ))

# 4. 分割成 8 份
split -d -l $lines_per_file all_miopen_lines.tmp "${output_prefix}"

# 5. 生成 8 个脚本文件，并加上环境变量
for i in {0..7}
do
    num=$(printf "%02d" $i)
    out_script="${output_prefix}${num}.sh"
    # 添加 shebang
    echo "#!/bin/bash" > "$out_script"
    # 给每一行加上环境变量
    awk -v dev=$i '{print "HIP_VISIBLE_DEVICES="dev" "$0}' "${output_prefix}${num}" >> "$out_script"
    chmod +x "$out_script"
    rm "${output_prefix}${num}"
done

# 6. 清理临时文件
rm all_miopen_lines.tmp

echo "已生成 8 个脚本：${output_prefix}00.sh 到 ${output_prefix}07.sh，每个脚本的 MIOpen 行前都加了对应的 HIP_VISIBLE_DEVICES 环境变量。"
