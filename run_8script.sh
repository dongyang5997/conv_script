#!/bin/bash

if [[ "$1" == "second_run" ]]; then
    log_suffix="_second"
else
    log_suffix=""
fi

SECONDS=0
start_time=$(TZ='Asia/Shanghai' date +'%F %T %Z')

container_name=dongyang_test
log_dir="/mnt/raid0/users/dongyang/1896"
# 用空格拼接脚本名
scripts="miopen_no_validation_part_00.sh miopen_no_validation_part_01.sh miopen_no_validation_part_02.sh miopen_no_validation_part_03.sh miopen_no_validation_part_04.sh miopen_no_validation_part_05.sh miopen_no_validation_part_06.sh miopen_no_validation_part_07.sh"

gather_host_env_info() {
    echo "==========Host Environment =========="
    echo "[Hostname]       $(hostname)"
    echo "[Container Name] $(echo $container_name)"
    echo "[Start Time]     $(TZ='Asia/Shanghai' date +'%F %T %Z')"
    echo "[OS Version]     $(source /etc/os-release; echo "$NAME $VERSION")"
    echo "[Memory Size]    $(free -h | awk '/Mem:/{print $2}')"
    echo "[NUMA Balance]   $(cat /proc/sys/kernel/numa_balancing 2>/dev/null || echo 'N/A')"
    echo "[Kernel cmdline] $(cat /proc/cmdline)"
    echo "[Kernel]         $(uname -r)"
    cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    cpu_sockets=$(lscpu | grep "Socket(s)" | awk '{print $2}')
    echo "[CPU Model]      ${cpu_model} * ${cpu_sockets}"
    container_id=$(docker ps -f "name=$container_name" -q)
    if [ -n "$container_id" ]; then
        container_image=$(docker inspect --format='{{.Config.Image}}' $container_id)
        echo "[Docker Image]   $container_image"
    else
        echo "[Docker Image]   No container found with name $container_name"
    fi
    uname_r=$(uname -r)
    dkms_version=$(dkms status | grep $uname_r)
    echo "[DKMS Version]   $dkms_version"
    gec_status=$(dmesg | grep -i vram)
    echo "[GECC Status]    $gec_status"
    rocm-smi --showhw
}

rm -f /tmp/eenv.log
container_id=$(docker ps -f "name=$container_name" -q)
if [ -n "$container_id" ]; then
    docker exec $container_name rm -f \
        /tmp/container_env.log \
        /tmp/script*.log \
        /tmp/host_env.log \
        $log_dir/parallel_with_env.log
else
    echo "错误：容器 '$container_name' 未运行!"
    exit 1
fi

gather_host_env_info > /tmp/eenv.log

# 通过 -e 传递 log_dir 和 scripts 两个变量
docker exec -e log_dir="$log_dir" -e scripts="$scripts" -i $container_name bash <<'EOF'
# 还原 scripts 为数组
IFS=' ' read -r -a scripts_array <<< "$scripts"

mkdir -p "$log_dir"
rm -f /tmp/container_env.log /tmp/script*.log

gather_container_env_info() {
    echo "==========Docker Container System Environment =========="
    echo "[Time]           $(TZ='Asia/Shanghai' date +'%F %T %Z')"
    echo "[Hostname]       $(hostname)"
    echo "[OS Version]     $(source /etc/os-release; echo \"$NAME $VERSION\")"
    echo "[Kernel]         $(uname -r)"
    echo "[ROCm Version]   $(apt-cache show rocm-core | grep Version | head -1 | cut -d: -f2 | xargs)"
    echo "[Python Version] $(python3 --version 2>&1 | cut -d' ' -f2)"
    echo "[Which python3]  $(which python3)"
}
gather_container_env_info > /tmp/container_env.log

cd "$log_dir"

# 并行运行所有脚本，每个脚本日志单独保存
for i in "${!scripts_array[@]}"; do
    bash "${scripts_array[$i]}" > /tmp/script${i}.log 2>&1 &
done

wait

cat /tmp/container_env.log /tmp/script*.log > "$log_dir/parallel_with_env.log"
rm -f /tmp/container_env.log /tmp/script*.log
EOF

docker cp /tmp/eenv.log $container_name:/tmp/host_env.log
docker exec -i $container_name bash -c \
    "if [ -f $log_dir/parallel_with_env.log ]; then
        cat /tmp/host_env.log $log_dir/parallel_with_env.log > $log_dir/parallel${log_suffix}.log
    else
        echo '警告：parallel_with_env.log 缺失，仅保存主机环境信息' > $log_dir/parallel${log_suffix}.log
        cat /tmp/host_env.log >> $log_dir/parallel${log_suffix}.log
    fi
    rm -f /tmp/host_env.log $log_dir/parallel_with_env.log"

rm -f /tmp/eenv.log

echo "日志已生成在容器内 $log_dir/parallel${log_suffix}.log"

end_time=$(TZ='Asia/Shanghai' date +'%F %T %Z')
duration=$SECONDS
hours=$((duration/3600))
minutes=$(( (duration%3600)/60 ))
seconds=$((duration%60))

docker exec -i $container_name bash -c \
    "echo '========== Test Completed ==========' >> $log_dir/parallel${log_suffix}.log
     echo '[End time]   $end_time' >> $log_dir/parallel${log_suffix}.log
     echo '[Total Time]     ${hours}hours${minutes}minutes${seconds}seconds' >> $log_dir/parallel${log_suffix}.log"

if [[ "$1" != "second_run" ]]; then
    echo "Waiting 3 minutes before running the script again..."
    sleep 180
    bash "$0" second_run
fi
