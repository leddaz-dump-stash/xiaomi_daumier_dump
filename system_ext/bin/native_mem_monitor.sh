#!/system/bin/sh

# process_name,monitor_threshold,dumpheap_threshold
# This is base config for less than 4GB device.
# unit: GB
MEM_BASE=4

# These are set according to normal memory usage of each process.
# unit: MB
PROCESS_CONFIGS_BASE=(
    "system_server,400,400"
    "surfaceflinger,500,500"
    "netd,100,100"
    "audioserver,200,200"
    "cameraserver,200,200"
    "mediaserver,200,200"
    "mediaserverwrapper,100,100"
    "drmserver,100,100"
    "vold,100,100"
    "storaged,100,100"
    "installd,100,100"
)
process_configs=()

function init_config {
    local mem=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')
    ((mem=($mem + 500000)/1000000))
    echo "Real RAM: $mem GB"

    # Actually we don't have Android S device with less than 4GB ram.
    # The low bound is just for special case. We can't make it lower.
    # On the other hand, we can't make it too large in case that process
    # crashes before we could dump heap. In all, we always treat device
    # as 4GB, 6GB and 8GB ram.
    if [ $mem -lt 4 ]; then
        mem=4
    elif [ $mem -gt 8 ]; then
        mem=8
    fi
    echo "Clamped RAM: $mem GB"

    let seq_max=${#PROCESS_CONFIGS_BASE[*]}-1
    for i in $(seq 0 $seq_max); do
        local config=${PROCESS_CONFIGS_BASE[$i]}
        process_name=$(echo $config | awk -F ',' '{print $1}')
        ((monitor_threshold=$(echo $config | awk -F ',' '{print $2}') * $mem / $MEM_BASE * 1000))
        ((dumpheap_threshold=$(echo $config | awk -F ',' '{print $3}') * 1000 + $monitor_threshold))
        process_configs[$i]="$process_name,$monitor_threshold,$dumpheap_threshold"
    done

    echo "Process configs:"
    for config in ${process_configs[*]}; do
        echo $config
    done
}

init_config

dump_dir=/data/mqsas/nativeheap
if [ -d $dump_dir ]; then
    chmod 777 $dump_dir
else
    mkdir -p -m 777 $dump_dir
fi

monitoring_pids=""
dumped_pids=""
while true; do
    echo "Start loop"
    for config in ${process_configs[*]}; do
        local pname=$(echo $config | awk -F ',' '{print $1}')
        monitor_threshold=$(echo $config | awk -F ',' '{print $2}')
        dumpheap_threshold=$(echo $config | awk -F ',' '{print $3}')
        pid=$(pidof $pname)
        echo "Check process $pname, pid: $pid, ($monitor_threshold, $dumpheap_threshold)"
        if [ "$pid" = "" ]; then
            continue
        fi
        local native_pss=$(dumpsys meminfo $pid | grep "Native Heap" | head -1 | awk '{print $3}')
        echo "native pss: $native_pss"
        if [ $native_pss -gt $dumpheap_threshold ]; then
            local dumped=$(echo $dumped_pids | grep $pid)
            if [ "$dumped" = "" ]; then
                kill -47 $pid
                echo "dump heap of process $pname, pid: $pid. native pss: $native_pss"
                dumped_pids+="$pid "
            fi
        elif [ $native_pss -gt $monitor_threshold ]; then
            local monitoring=$(echo $monitoring_pids | grep $pid)
            if [ "$monitoring" = "" ]; then
                kill -45 $pid
                monitoring_pids+="$pid "
                echo "start monitoring process $pname, pid: $pid. native pss: $native_pss"
            fi
        fi
    done

    if [ "$monitoring_pids" = "" ]; then
        echo "Going to sleep 300s..."
        sleep 300s
    else
        echo "Going to sleep 60s..."
        sleep 60s
    fi
    echo
done

