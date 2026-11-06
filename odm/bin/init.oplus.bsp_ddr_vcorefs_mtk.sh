#!/system/bin/sh

config="$1"
#=============================================================================
#persist.debug.ddr.vcorefs.config
#testing_phase=`getprop persist.debug.ddr.vcorefs.config`
#=============================================================================
#### ORDER or RANDOM
RANDOM_STRESS=1
#### wait latency for each DVFS finish (0.1=100ms, 0.001=1ms) 600 = 60s
T_DVFS_INTERVAL=0.1
ntest=600
echo " ***** STARTING DVFS STRESS ***** "
echo "=== modem shutdown ==="
muxreport 3

platform=`getprop ro.board.platform`

if [ x"$platform" = x"mt6877" ] || [ x"$platform" = x"mt6833" ]; then
    DVFSRC_PATH="/sys/devices/platform/10012000.dvfsrc/helio-dvfsrc/"
else
    DVFSRC_PATH="/sys/kernel/helio-dvfsrc/"
fi

NUM_DVFSRC_OPP=$(($(cat ${DVFSRC_PATH}dvfsrc_num_opps)-1))

mcdi_ntest=3000000
mcdi_delay=30

script_name="multi-media quick on/off stress script"
script_version=1.0.1
script_owner=yanghui.li@mediatek.com

#### test times
mm_ntest=5

#### step internal sleep unit s
step_internal=1

##### test mode setting
test_serial_mode=0
test_random_mode=1

##### test pattern setting
test_camera_review_flag=1
test_video_play_flag=1
test_system_suspend_flag=0
test_cpu_idle_flag=1
test_display_onoff_flag=1
test_video_record_flag=1

test_all_case_count=6


if [ ${#DDR_Freq_List[*]} == 0 ]; then
    if [ -f /cache/factory/DDR_Freq_Config.csv ]; then
        echo "/cache/factory/DDR_Freq_Config.csv exist"
        DDR_Freq_Config="/cache/factory/DDR_Freq_Config.csv"
        while read line; do
            echo "${line[@]}"
        done < "$DDR_Freq_Config"
        echo $line
        BAK_IFS=$IFS
        IFS=','
        DDR_Freq_List=($line)
        echo "DDR_Freq_List Length: ${#DDR_Freq_List[*]}"
        echo "DDR_Freq_List: ${DDR_Freq_List[@]}"
        IFS=$BAK_IFS
    else
        echo "/cache/factory/DDR_Freq_Config.csv not exist"
        DDR_Freq_List=()
        for i in  $(seq 0 $(($NUM_DVFSRC_OPP+1))); do
            if [ $i == 0 ]; then
                DDR_Freq_List[i]="MTK"
            else
                DDR_Freq_List[i]=$(($i-1))
            fi
        done
        echo "DDR_Freq_List Length: ${#DDR_Freq_List[*]}"
        echo "DDR_Freq_List: ${DDR_Freq_List[@]}"
    fi
fi

NUM_DVFSRC_OPP=$((${#DDR_Freq_List[*]}-1))

function do_ddr_vcorefs_switch(){
    if [ $1 -gt 10 ]
    then
        setprop persist.debug.ddr.vcorefs.low.freq true
    else
        setprop persist.debug.ddr.vcorefs.low.freq false
    fi
    echo $1 > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
}

function do_ddr_vcorefs_random(){

    echo " ***** STARTING DVFS STRESS ***** "
    echo 1 > ${DVFSRC_PATH}dvfsrc_enable

    #Disable MMDVFS and keep lowest freq (for mt6877)
    echo 1 > /sys/module/mmdvfs_pmqos/parameters/mmdvfs_enable
    if [ x"$platform" = x"mt6877" ]; then
        echo 2 > /sys/module/mmdvfs_pmqos/parameters/force_step
    else
        echo 3 > /sys/module/mmdvfs_pmqos/parameters/force_step
    fi
    muxreport 3
    #Disable hold vcore whenever UFS access storage
    echo 0 > /proc/ufs_perf

    #Let SCP in low freq
    echo opp 0 > /proc/scp_dvfs/scp_dvfs_ctrl

    #Let APU in low freq
    if [ -f /d/apusys/power ]; then
        echo dvfs_debug 4 > /d/apusys/power
    fi

    for i in $(seq 1 ${ntest})
    do
        sleep $T_DVFS_INTERVAL
        #fix_opp=$(($RANDOM%$NUM_DVFSRC_OPP))
        DDR_Freq_List_Index=$(($RANDOM%(($NUM_DVFSRC_OPP))+1))
        fix_opp=${DDR_Freq_List[$DDR_Freq_List_Index]}
        echo 0 5 > /sys/module/mtk_mmdvfs_debug/parameters/force_step
        echo 3 > /sys/devices/platform/soc/16810000.ufshci/clkscale/clkscale_control
        if [ x"$platform" = x"mt6993" ]; then
            echo 3 > /sys/module/mtk_hwz/parameters/kick_hwe_gear
        fi
        if [ x"$platform" = x"mt6877" ]; then
            #Disable vcore 0.55v
            if [[ $fix_opp -ne 14 && $fix_opp -ne 19 && $fix_opp -ne 24 && $fix_opp -ne 29 ]]; then
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        else
            echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
        fi
        cat ${DVFSRC_PATH}dvfsrc_dump | grep -e uv -e "DDR       :"
    done
}

function do_ddr_vcorefs_max(){
    echo 0 5 > /sys/module/mtk_mmdvfs_debug/parameters/force_step
    echo 3 > /sys/devices/platform/soc/16810000.ufshci/clkscale/clkscale_control
    if [ x"$platform" = x"mt6993" ]; then
        echo 3 > /sys/module/mtk_hwz/parameters/kick_hwe_gear
    fi
    echo 1 > ${DVFSRC_PATH}dvfsrc_enable
    DDR_Freq_List_Index=1
    fix_opp=${DDR_Freq_List[$DDR_Freq_List_Index]}
    echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
    echo 0 > ${DVFSRC_PATH}dvfsrc_enable
    for i in $(seq 1 ${ntest})
    do
        sleep $T_DVFS_INTERVAL
        cat ${DVFSRC_PATH}dvfsrc_dump | grep -e uv -e "DDR       :"
    done
}

function do_ddr_vcorefs_min(){
    echo 1 > ${DVFSRC_PATH}dvfsrc_enable
    echo "Disable MMDVFS and keep lowest freq (for mt6877)"
    echo 1 > /sys/module/mmdvfs_pmqos/parameters/mmdvfs_enable
    if [ x"$platform" = x"mt6877" ]; then
        echo 2 > /sys/module/mmdvfs_pmqos/parameters/force_step
    else
        echo 3 > /sys/module/mmdvfs_pmqos/parameters/force_step
    fi
    echo 0 5 > /sys/module/mtk_mmdvfs_debug/parameters/force_step
    echo 3 > /sys/devices/platform/soc/16810000.ufshci/clkscale/clkscale_control
    if [ x"$platform" = x"mt6993" ]; then
        echo 3 > /sys/module/mtk_hwz/parameters/kick_hwe_gear
    fi

    echo "=== modem shutdon ==="
    shell muxreport 3

    echo "Disable hold vcore whenever UFS access storage"
    echo 0 > /proc/ufs_perf

    echo "Let SCP in low freq"
    echo opp 0 > /proc/scp_dvfs/scp_dvfs_ctrl

    #Let APU in low freq
    if [ -f /d/apusys/power ]; then
        echo "Let APU in low freq"
        echo dvfs_debug 4 > /d/apusys/power
    fi

    #echo "fix vcore 0.55v and dram 1866M"
    #echo "fix vcore 0.58v and dram 800M"
    if [ x"$platform" = x"mt6877" ]; then
        echo "fix vcore 0.6v and dram 800M"
        echo 28 > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
    else
        DDR_Freq_List_Index=$((${#DDR_Freq_List[*]}-1))
        fix_opp=${DDR_Freq_List[$DDR_Freq_List_Index]}
        echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
    fi

    echo 0 > ${DVFSRC_PATH}dvfsrc_enable
    for i in $(seq 1 ${ntest})
    do
        sleep $T_DVFS_INTERVAL
        cat ${DVFSRC_PATH}dvfsrc_dump | grep -e uv -e "DDR       :"
    done
}

function do_ddr_vcorefs_longstep_random(){
    echo 1 > ${DVFSRC_PATH}dvfsrc_enable
    echo "do_ddr_vcorefs_longstep_random"
    echo "Disable MMDVFS and keep lowest freq (for mt6877)"
    echo 1 > /sys/module/mmdvfs_pmqos/parameters/mmdvfs_enable
    if [ x"$platform" = x"mt6877" ]; then
        echo 2 > /sys/module/mmdvfs_pmqos/parameters/force_step
    else
        echo 3 > /sys/module/mmdvfs_pmqos/parameters/force_step
    fi

    echo "=== modem shutdon ==="
    shell muxreport 3

    echo "Disable hold vcore whenever UFS access storage"
    echo 0 > /proc/ufs_perf

    echo "Let SCP in low freq"
    echo opp 0 > /proc/scp_dvfs/scp_dvfs_ctrl

    #Let APU in low freq
    if [ -f /d/apusys/power ]; then
        echo "Let APU in low freq"
        echo dvfs_debug 4 > /d/apusys/power
    fi

    #fix_opp=$(($RANDOM%$NUM_DVFSRC_OPP))
    DDR_Freq_List_Index=$(($RANDOM%(($NUM_DVFSRC_OPP))+1))
    fix_opp=${DDR_Freq_List[$DDR_Freq_List_Index]}
    for i in $(seq 1 ${ntest})
    do
        sleep $T_DVFS_INTERVAL
        L_step=$(($RANDOM%5))
        fix_opp=$(($fix_opp+10+$L_step))
        fix_opp=$(($fix_opp%$NUM_DVFSRC_OPP))
        echo 0 5 > /sys/module/mtk_mmdvfs_debug/parameters/force_step
        echo 3 > /sys/devices/platform/soc/16810000.ufshci/clkscale/clkscale_control
        if [ x"$platform" = x"mt6993" ]; then
            echo 3 > /sys/module/mtk_hwz/parameters/kick_hwe_gear
        fi
        if [ x"$platform" = x"mt6877" ]; then
            #Disable vcore 0.55v
            if [[ $fix_opp -ne 14 && $fix_opp -ne 19 && $fix_opp -ne 24 && $fix_opp -ne 29 ]]; then
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        else
            echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
        fi
        cat ${DVFSRC_PATH}dvfsrc_dump | grep -e uv -e "DDR       :"
    done
}

### show basic script information
function show_basic_infor(){
    echo $script_name, version=$script_version, script creater=$script_owner
}


### test camera review
function test_camera_review(){
    if [ $test_camera_review_flag -eq 0 ]; then
        return
    fi

    ## start camera review
    am start -S -a android.media.action.IMAGE_CAPTURE

    sleep 2

    ## back to home screen
    am start -a android.intent.action.MAIN -c android.intent.category.HOME
}

### test video play
function test_video_play(){
    if [ $test_video_play_flag -eq 0 ]; then
        return
    fi

    ## start idle test app
    am start -n com.mediatek.screenflash/.MainActivity

    ## record 5s screen
    screenrecord --time-limit 5 /sdcard/DCIM/Camera/test_mm.mp4

    ## wait a little
    sleep 0.1

    ## video play
    am start -a android.intent.action.VIEW  -t video/mp4 -d file:/sdcard/DCIM/Camera/test_mm.mp4
    sleep 5

    ## back to home screen
    am start -a android.intent.action.MAIN -c android.intent.category.HOME
    rm /sdcard/DCIM/Camera/test_mm.mp4
}

### test suspend
function test_system_suspend(){
    if [ $test_system_suspend_flag -eq 0 ]; then
        return
    fi

    #sleep duration, default 5s
    duration=5
    #try sleep with 5s, each 0.1s, 10times
    try_time=5
    try_count=$(($try_time*10))

    #set wake alarm
    echo +$duration > /sys/class/rtc/rtc0/wakealarm

    #set wake alarm fail, may have old alarm.
    if [ $? -ne 0 ]; then
        echo +=$duration > /sys/class/rtc/rtc0/wakealarm
    fi

    # press powerkey to sleep
    input keyevent 26

    # record before sustem wall time.
    before_time=$(cat /sys/class/rtc/rtc0/since_epoch)

    # usb set to off, system will goto suspend.
    setprop vendor.usb.charging yes

    # sleep $try_times s to wait system goto suspend, need using very small pace to try.
    index=0
    interval=0
    while [ $index -lt $try_count ]
    do
        after_time=$(cat /sys/class/rtc/rtc0/since_epoch)
        interval=$(($after_time - $before_time))
        # echo interval=$interval, index=$index
        # if wall interval is bigger than real time, may have sleep.
        if [ interval -gt 4 ]; then
            break
        fi

        index=$(($index+1))
        sleep 0.1

    done

    # press powerkey when system resume
    input keyevent 26

    # usb set to on
    setprop vendor.usb.charging no

    sleep 0.2

    # unlock screen
    input keyevent 82

    # wait usb on
    sleep 2
}

### test cpu idle
function test_cpu_idle(){
    if [ $test_cpu_idle_flag -eq 0 ]; then
        return
    fi

    ## start idle test app
    am start -n com.mediatek.screenflash/.MainActivity

    ## sleep 5s
    sleep 5

    ## back to home screen
    am start -a android.intent.action.MAIN -c android.intent.category.HOME
}

### test display on/off
function test_display_onoff(){

    if [ $test_display_onoff_flag -eq 0 ]; then
        return
    fi

    ## first eat a wakelock
    echo test_display_onoff > /sys/power/wake_lock

    ## call power key to off screen
    input keyevent 26

    ## sleep 1s
    sleep 1

    ## call power key to on screen
    input keyevent 26

    sleep 0.2

    # unlock screen
    input keyevent 82

    ## release the wakelock
    echo test_display_onoff > /sys/power/wake_unlock
}

### test video record
function test_video_record(){
    if [ $test_video_record_flag -eq 0 ]; then
        return
    fi

    ## start camera video review
    am start -S -a android.media.action.VIDEO_CAPTURE

    sleep 2

    ## back to home screen
    am start -a android.intent.action.MAIN -c android.intent.category.HOME

}

function do_random_test_flow(){

    echo "mm quick on/off random test"

    for rotate in $(seq 1 ${test_all_case_count})
    do
        select_test=$(($RANDOM%$test_all_case_count))

        if [ $select_test -eq 0 ]; then
            test_camera_review
        elif [ $select_test -eq 1 ]; then
            test_video_play
        elif [ $select_test -eq 2 ]; then
            test_system_suspend
        elif [ $select_test -eq 3 ]; then
            test_cpu_idle
        elif [ $select_test -eq 4 ]; then
            test_display_onoff
        elif [ $select_test -eq 5 ]; then
            test_video_record
        else
            echo test_all_case_count=$test_all_case_count, is not match setting, exit.
            exit 1
        fi

        sleep $step_internal

        done
}

function do_serial_test_flow(){

    echo "mm quick on/off serial test"

    test_camera_review
    sleep $step_internal

    test_video_play
    sleep $step_internal

    test_system_suspend
    sleep $step_internal

    test_video_record
    sleep $step_internal

    test_cpu_idle
    sleep $step_internal

    test_display_onoff
    sleep $step_internal

}

function enable_ddr_vcorefs_test(){
    while [ 1 ]
    do
        ddr_testphase=`getprop persist.vendor.ddr.vcorefs.config`
        if [ "$ddr_testphase" = "done" ]; then
            break
        fi
        setprop persist.vendor.ddr.vcorefs.config random
        ddr_testphase=`getprop persist.vendor.ddr.vcorefs.config`
        echo "ddr_testphase:$ddr_testphase."
        if [ "$ddr_testphase" = "random" ]; then
            do_ddr_vcorefs_random
        fi

        ddr_testphase=`getprop persist.vendor.ddr.vcorefs.config`
        if [ "$ddr_testphase" = "done" ]; then
            break
        fi
        setprop persist.vendor.ddr.vcorefs.config max
        ddr_testphase=`getprop persist.vendor.ddr.vcorefs.config`
        echo "ddr_testphase:$ddr_testphase."
        if [ "$ddr_testphase" = "max" ]; then
            do_ddr_vcorefs_max
        fi

        ddr_testphase=`getprop persist.vendor.ddr.vcorefs.config`
        if [ "$ddr_testphase" = "done" ]; then
            break
        fi
        setprop persist.vendor.ddr.vcorefs.config min
        ddr_testphase=`getprop persist.vendor.ddr.vcorefs.config`
        echo "ddr_testphase:$ddr_testphase."
        if [ "$ddr_testphase" = "min" ]; then
            do_ddr_vcorefs_min
        fi

        ddr_testphase=`getprop persist.vendor.ddr.vcorefs.config`
        if [ "$ddr_testphase" = "done" ]; then
            break
        fi
        setprop persist.vendor.ddr.vcorefs.config longstep
        ddr_testphase=`getprop persist.vendor.ddr.vcorefs.config`
        echo "ddr_testphase:$ddr_testphase."
        if [ "$ddr_testphase" = "longstep" ]; then
            do_ddr_vcorefs_longstep_random
        fi
    done
    echo "The ddr_vcorefs_test is done and PASS if no exception occurred."
}

function enable_ddr_vcorefs_manual(){
    ddr_testphase=`getprop persist.vendor.ddr.vcorefs.config`
    while [ 1 ]
    do
        if [ "$ddr_testphase" != "done" ]; then
            break
        fi
        ddr_manualphase=`getprop persist.vendor.ddr.vcorefs.manual`
        echo "ddr_manualphase:$ddr_manualphase."
        if [ "$ddr_manualphase" = "random" ]; then
            do_ddr_vcorefs_random
        elif [ "$ddr_manualphase" = "max" ]; then
            do_ddr_vcorefs_max
        elif [ "$ddr_manualphase" = "min" ]; then
            do_ddr_vcorefs_min
        elif [ "$ddr_manualphase" = "longstep" ]; then
            do_ddr_vcorefs_longstep_random
        elif [ "$ddr_manualphase" = "done" ]; then
            break
        else
            sleep 10
        fi
    done
    echo "The enable_ddr_vcorefs_manual is done and PASS if no exception occurred."
}

function enable_mcdi_stress(){
    for i in $(seq 1 ${mcdi_ntest})
    do
        # MCDI Stress for CPU Idle state test
        echo 1 > /proc/mtk_lpm/cpuidle/enable
        echo 1 > /proc/mtk_lpm/cpuidle/info
        echo 1 > /proc/mtk_lpm/cpuidle/control/stress
        echo 5000 > /proc/mtk_lpm/cpuidle/control/stress_time
        echo 100 > /proc/mtk_lpm/cpuidle/state/residency
        echo 100 > /proc/mtk_lpm/cpuidle/state/latency

        sleep ${mcdi_delay}

        # MCDI disable for WFI test
        echo 0 > /proc/mtk_lpm/cpuidle/enable
        echo 1 > /proc/mtk_lpm/cpuidle/info
        echo 1 > /proc/mtk_lpm/cpuidle/control/stress

        sleep ${mcdi_delay}

    done
}

function enable_mm_quick_test(){
    show_basic_infor
    ## first start to cpu idle test scenes, to disable keyguard.
    am start -n com.mediatek.screenflash/.MainActivity

    for i in $(seq 1 ${mm_ntest})
    do

        echo test-loop:$i

        if [ $test_serial_mode -eq 1 ]; then
            do_serial_test_flow
        else
            do_random_test_flow
        fi
    done
    echo "exit mm quick onoff stress test"
}

case "$config" in
    "enable_ddr_vcorefs_test")
    enable_ddr_vcorefs_test
    ;;
    "enable_mcdi_stress")
    enable_mcdi_stress
    ;;
    "enable_mm_quick_test")
    enable_mm_quick_test
    ;;
esac

