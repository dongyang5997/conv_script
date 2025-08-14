#!/bin/bash

# 判断是否为第二遍
if [[ "$1" == "second_run" ]]; then
    log_suffix="_second"
else
    log_suffix=""
fi

SECONDS=0
start_time=$(TZ='Asia/Shanghai' date +'%F %T %Z')

container_name=dongyang_test
log_dir="/workspace/dongyang/1896"
bench_script=ConvolutionWorkLoad_cuDNN_1896_v1


# 1. 收集主机环境信息到临时文件
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
    nvidia-smi
}


# ======= 启动前清理遗留文件 =======
rm -f /tmp/eenv.log
container_id=$(docker ps -f "name=$container_name" -q)
if [ -n "$container_id" ]; then
    # 清理容器内可能残留的临时文件
    docker exec $container_name rm -f \
        /tmp/container_env.log \
        /tmp/conv.log \
        /tmp/host_env.log \
        $log_dir/conv_with_env.log
else
    echo "错误：容器 '$container_name' 未运行!"
    exit 1
fi

# 2. 在主机上收集主机环境信息
gather_host_env_info > /tmp/eenv.log

# 3. 进入容器，收集容器环境信息和运行 workload
docker exec -i $container_name bash <<EOF
log_dir="$log_dir"

# ======= 确保工作目录存在 =======
mkdir -p \$log_dir

# ======= 容器内启动时清理残留 =======
rm -f /tmp/container_env.log /tmp/conv.log

gather_container_env_info() {
    echo "==========Docker Container System Environment =========="
    echo "[Time]           $(TZ='Asia/Shanghai' date +'%F %T %Z')"
    echo "[Hostname]       $(hostname)"
    echo "[OS Version]     $(source /etc/os-release; echo "$NAME $VERSION")"
    echo "[Kernel]         $(uname -r)"

    # ECC状态检测
    echo -n "[ECC Status]     "
    nvidia-smi --query-gpu=ecc.errors.corrected.volatile.device --format=csv,noheader | \
    awk '{sum+=\$1} END{print (sum>0)?"Enabled":"Disabled"}'

    # 版本信息
    echo "[CUDA Version]   \$(nvcc --version | grep "release" | awk '{print \$6}')"
    echo "[Driver Version] \$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | uniq)"
    echo "[Python Version] \$(python3 --version 2>&1 | cut -d' ' -f2)"
    echo "[Which python3]  \$(which python3)"
}
gather_container_env_info > /tmp/container_env.log

cd \$log_dir
bash $bench_script.sh 2>&1 | tee /tmp/conv.log

# 安全合并：确保文件存在再操作
if [ -f /tmp/container_env.log ] && [ -f /tmp/conv.log ]; then
    cat /tmp/container_env.log /tmp/conv.log > \$log_dir/conv_with_env.log
    rm -f /tmp/container_env.log /tmp/conv.log
else
    echo "错误：容器环境或日志文件缺失!" > \$log_dir/conv_with_env.log
    [ -f /tmp/container_env.log ] && cat /tmp/container_env.log >> \$log_dir/conv_with_env.log
    [ -f /tmp/conv.log ] && cat /tmp/conv.log >> \$log_dir/conv_with_env.log
fi
EOF

# 4. 合并主机和容器环境信息到最终 log
docker cp /tmp/eenv.log $container_name:/tmp/host_env.log
docker exec -i $container_name bash -c \
    "if [ -f $log_dir/conv_with_env.log ]; then
        cat /tmp/host_env.log $log_dir/conv_with_env.log > $log_dir/$bench_script${log_suffix}.log
    else
        echo '警告：conv_with_env.log 缺失，仅保存主机环境信息' > $log_dir/$bench_script${log_suffix}.log
        cat /tmp/host_env.log >> $log_dir/$bench_script${log_suffix}.log
    fi
    rm -f /tmp/host_env.log $log_dir/conv_with_env.log"

# 5. 清理主机临时文件
rm -f /tmp/eenv.log

echo "日志已生成在容器内 $log_dir/$bench_script${log_suffix}.log"

end_time=$(TZ='Asia/Shanghai' date +'%F %T %Z')
duration=$SECONDS
hours=$((duration/3600))
minutes=$(( (duration%3600)/60 ))
seconds=$((duration%60))

docker exec -i $container_name bash -c \
    "echo '========== Test Completed ==========' >> $log_dir/$bench_script${log_suffix}.log
     echo '[End time]   $end_time' >> $log_dir/$bench_script${log_suffix}.log
     echo '[Total Time]     ${hours}hours${minutes}minutes${seconds}seconds' >> $log_dir/$bench_script${log_suffix}.log"


# 如果是第一次运行，则等待3分钟后自动再次运行本脚本
if [[ "$1" != "second_run" ]]; then
    echo "Waiting 3 minutes before running the script again..."
    sleep 180
    bash "$0" second_run
fi
