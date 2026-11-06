#!/system/bin/sh

ntest=3000
delay=0.3	## 300ms
all_on_delay=0.05 ## 50ms

cpu_num=8
cpus=()

array=(1 2 4 8 10 20 40 80 ff)

# 1. 等待 AgingService 通过 ctl.start 拉起 dramagingftmd，禁止本脚本自行启动
PID=""
wait_round=0
while [ -z "$PID" ] && [ $wait_round -lt 120 ]; do
    PID=$(pidof dramagingftmd)
    if [ -z "$PID" ]; then
        sleep 10
        wait_round=$(($wait_round + 1))
    fi
done
if [ -z "$PID" ]; then
    echo "dramagingftmd not started by AgingService, skip cpu hotplug bind"
    exit 0
fi

# 2. 每60秒切换一次CPU（0-7）
for mask in "${array[@]}"; do
    taskset -p $mask $PID  # 绑定到当前 CPU
    sleep 60
done

sleep 1200

for i in $(seq 1 ${ntest})
do
	#FF to flag echo cpu core.
	test=$(($RANDOM%(1<<$cpu_num)))

	if [ $test -gt 0 ]; then
		off_count=0
		for cpu in $(seq 1 ${cpu_num})
		do
			index=$(($cpu-1))
			mask=$((1<<$index))
			value=$(($test&$mask))
			if [ $value -eq 0 -a $off_count -lt 5 ]; then
				echo 0 > /sys/devices/system/cpu/cpu${index}/online
				cpus[$index]=0
				off_count=$(($off_count+1))
			else
				echo 1 > /sys/devices/system/cpu/cpu${index}/online
				cpus[$index]=1
			fi
		done

		echo "off=${off_count} cpu0=${cpus[0]}, cpu1=${cpus[1]}, cpu2=${cpus[2]}, cpu3=${cpus[3]}, cpu4=${cpus[4]}, cpu5=${cpus[5]}, cpu6=${cpus[6]}, cpu7=${cpus[7]}"

		sleep ${delay}

		##let all cpu on.
		##avoid spcecial case: cpu 0 on, cpu 1 on, cpu 2 on and other cpu off; next time cpu 0 off, cpu 1 off, then only one cpu on case.
		for cpu in $(seq 1 ${cpu_num})
		do
			index=$(($cpu-1))
			echo 1 > /sys/devices/system/cpu/cpu${index}/online
		done

		sleep ${all_on_delay}

	fi

done

echo "The test is done and PASS if no exception occurred."
