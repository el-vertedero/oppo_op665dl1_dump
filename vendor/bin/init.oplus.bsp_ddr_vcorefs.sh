#!/system/bin/sh

#=============================================================================
#persist.debug.ddr.vcorefs.config
#testing_phase=`getprop persist.debug.ddr.vcorefs.config`
#=============================================================================
#### ORDER or RANDOM
RANDOM_STRESS=1
#### wait latency for each DVFS finish (0.1=100ms, 0.001=1ms) 600 = 60s
T_DVFS_INTERVAL=0.1
T_DVFS_TEMP_INTERVAL=1
ntest=600
nrtest=1800
echo " ***** STARTING DVFS STRESS ***** "
echo "=== modem shutdown ==="
echo "This is ftmd code"
muxreport 3

# ============ initialize risk level (DVFSRC OPP) by platform begin ====================
# G4: full tier list; G5: same as G4 with OPPs that only exist at vcore <= 0.65V removed
platform=`getprop ro.board.platform`
oplus_ddr_pl_l=$(echo "$platform" | tr 'A-Z' 'a-z')
case "$oplus_ddr_pl_l" in
	mt6995*)
		G4_risk_dvfsrc_opp=(87 66 45 30 20 14 8 5 2 1)
		G5_risk_dvfsrc_opp=(20 14 8 5 2 1)
		;;
	mt6993*)
		G4_risk_dvfsrc_opp=(92 71 50 35 25 19 13 7 4 1 0)
		G5_risk_dvfsrc_opp=(25 19 13 7 4 1 0)
		;;
	*)
		# legacy / unknown: keep MT6993 tables for backward compatibility
		G4_risk_dvfsrc_opp=(92 71 50 35 25 19 13 7 4 1 0)
		G5_risk_dvfsrc_opp=(25 19 13 7 4 1 0)
		;;
esac
# ============ initialize risk level (DVFSRC OPP) by platform end ======================

# ============ initialize max temp for mt6993 platform begin ======================
aging_max_temp=-273000
HIGH_TEMP_LIMIT=95
LOW_TEMP_LIMIT=85
flag_hightemp=0
touch /cache/factory/dram_aging_temp.log
chmod 666 /cache/factory/dram_aging_temp.log
# ============ initialize max temp for mt6993 platform end ======================

# ============ initialize dram_aging_dconfig.log for DDR LV/NV + UFS G4/G5 test begin============
initialize_dram_aging_dconfig_log() {
    touch /cache/factory/dram_aging_dconfig.log
    chmod 666 /cache/factory/dram_aging_dconfig.log
    FILEPATH="/vendor/bin/dconfig"
    TIMEOUT=60
    until [ -f "$FILEPATH" ]; do
        echo wait for /vendor/bin/dconfig >> /cache/factory/dram_aging_dconfig.log
        sleep 1
        TIMEOUT=$((TIMEOUT-1))
        if [ "$TIMEOUT" -eq 0 ]; then
            echo timeout
            exit 1
        fi
    done
    echo wait end >> /cache/factory/dram_aging_dconfig.log
}
initialize_dram_aging_dconfig_log
# ============ initialize dram_aging_dconfig.log for DDR LV/NV + UFS G4/G5 test end============

# ============ dconfig set for DDR LV/NV + UFS G4/G5 test begin============
dconfig_set_nv_lv() {
    setprop persist.debug.ddr.ufs.mode normal
    if [ -f /mnt/vendor/oplusreserve/factory/mode.txt ]; then
        chmod 666 /mnt/vendor/oplusreserve/factory/mode.txt
        DDR_UFS_TEST_MODE=$(cat "/mnt/vendor/oplusreserve/factory/mode.txt")
        if [ $DDR_UFS_TEST_MODE = "G4=TRUE" ]; then
            echo G4=TRUE match > /cache/factory/dram_aging_dconfig.log
            # set DDR LV, then reboot sblmemtest
            dconfig set 36 44 47 50 53 56 59 >> /cache/factory/dram_aging_dconfig.log
            dd if=/dev/zero of=/dev/block/by-name/dram_para bs=64 count=1 conv=notrunc >> /cache/factory/dram_aging_dconfig.log
            echo G4_Aging > /mnt/vendor/oplusreserve/factory/mode.txt
            /system/bin/reboot sblmemtest
        elif [ $DDR_UFS_TEST_MODE = "G4_Aging" ]; then
            echo G4_Aging match >> /cache/factory/dram_aging_dconfig.log
            dconfig status >> /cache/factory/dram_aging_dconfig.log
            setprop persist.debug.ddr.ufs.mode LV_G4
        elif [ $DDR_UFS_TEST_MODE = "G4=FASLE" ]; then
            echo G4=FASLE match > /cache/factory/dram_aging_dconfig.log
            # set DDR NV, then reboot sblmemtest
            dconfig set 35 43 46 49 52 55 58 >> /cache/factory/dram_aging_dconfig.log
            dd if=/dev/zero of=/dev/block/by-name/dram_para bs=64 count=1 conv=notrunc >> /cache/factory/dram_aging_dconfig.log
            echo Not_G4_Aging > /mnt/vendor/oplusreserve/factory/mode.txt
            /system/bin/reboot sblmemtest
        elif [ $DDR_UFS_TEST_MODE = "Not_G4_Aging" ]; then
            echo Not_G4_Aging match >> /cache/factory/dram_aging_dconfig.log
            dconfig status >> /cache/factory/dram_aging_dconfig.log
            # set DDR LV, take effect when next reboot
            dconfig set 36 44 47 50 53 56 59 >> /cache/factory/dram_aging_dconfig.log
            dd if=/dev/zero of=/dev/block/by-name/dram_para bs=64 count=1 conv=notrunc >> /cache/factory/dram_aging_dconfig.log
            setprop persist.debug.ddr.ufs.mode NV_G5
        else
            echo mode not match >> /cache/factory/dram_aging_dconfig.log
            setprop persist.debug.ddr.ufs.mode unexpected
        fi
    else
        echo mode.txt not exist >> /cache/factory/dram_aging_dconfig.log
        setprop persist.debug.ddr.ufs.mode mode_not_exist
    fi
}
dconfig_set_nv_lv
ddr_ufs_test_mode=`getprop persist.debug.ddr.ufs.mode`
echo persist.debug.ddr.ufs.mode is $ddr_ufs_test_mode >> /cache/factory/dram_aging_dconfig.log
# ============ dconfig set for DDR LV/NV + UFS G4/G5 test end============

if [ x"$platform" = x"mt6877" ] || [ x"$platform" = x"mt6833" ]; then
    DVFSRC_PATH="/sys/devices/platform/10012000.dvfsrc/helio-dvfsrc/"
else
    DVFSRC_PATH="/sys/kernel/helio-dvfsrc/"
fi

NUM_DVFSRC_OPP=$(($(cat ${DVFSRC_PATH}dvfsrc_num_opps)-1))

# ============ find and check the first line of OPP information based on ]: begin============
opp_line_number=$(grep -n ']:' ${DVFSRC_PATH}dvfsrc_opp_table | head -n 1 | cut -d: -f1)
if [ "$opp_line_number" = "" ]; then
    echo "opp_line_number is none"
    touch /cache/factory/dram_aging_dvfsrc_opp_table_format_warning.log
    chmod 666 /cache/factory/dram_aging_dvfsrc_opp_table_format_warning.log
    echo "dvfsrc_opp_table format has changed, can't find ]:" > /cache/factory/dram_aging_dvfsrc_opp_table_format_warning.log
    /system/bin/reboot reboot_eng_at_fail
fi
echo "opp_line_number is $opp_line_number"

check_dvfsrc_opp_table_node() {
    line_content=$(sed -n "${opp_line_number}p" ${DVFSRC_PATH}dvfsrc_opp_table)
    if [[ "$line_content" != *"bps"* && "$line_content" != *"khz"* ]]; then
        touch /cache/factory/dram_aging_dvfsrc_opp_table_format_warning.log
        chmod 666 /cache/factory/dram_aging_dvfsrc_opp_table_format_warning.log
        echo "dvfsrc_opp_table format has changed, can't find bps or khz" > /cache/factory/dram_aging_dvfsrc_opp_table_format_warning.log
        echo "line $opp_line_number content is $line_content" >> /cache/factory/dram_aging_dvfsrc_opp_table_format_warning.log
        /system/bin/reboot reboot_eng_at_fail
    fi
}
check_dvfsrc_opp_table_node
# ============ find and check the first line of OPP information based on ]: begin ============

# ============ initialize DDR_OPP_MASK_LIST, mask some DDR opp that Vcore <= 0.65V for UFS G5 test begin ============
DDR_OPP_MASK_LIST=()
initialize_ddr_mask_list() {
    mask_index=0
    for i in  $(seq 0 $(($NUM_DVFSRC_OPP))); do
        opp=$(($i+$opp_line_number))
        p=p
        line=$opp$p
        # find OPP_VCORE and DDR_OPP based on ]:
        # for example:
        # mt6895 dvfsrc_opp_table format : [OPP26]: 575000   uv 800000   khz
        # mt6991 dvfsrc_opp_table format : [86 ]:545000, 1532  Mbps [0]
        OPP_VCORE=$(sed -n $line ${DVFSRC_PATH}dvfsrc_opp_table | grep -o ']:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
        DDR_OPP=$(sed -n $line ${DVFSRC_PATH}dvfsrc_opp_table | grep -o '\[[^]]*\]:' | grep -o '[0-9]*' | head -n 1)
        if [ $OPP_VCORE -le 650000 ]; then
            DDR_OPP_MASK_LIST[mask_index]=$DDR_OPP
                echo "DDR_OPP is $DDR_OPP, Vcore is $OPP_VCORE, mask"
            mask_index=$mask_index+1
        fi
    done
}
initialize_ddr_mask_list
echo "DDR_OPP_MASK_LIST Length: ${#DDR_OPP_MASK_LIST[*]}"
echo "DDR_OPP_MASK_LIST: ${DDR_OPP_MASK_LIST[@]}"
# ============ initialize DDR_OPP_MASK_LIST, mask some DDR opp that Vcore <= 0.65V for UFS G5 test end ============

# ============ initialize DDR_Freq_List for ddr random frequency test begin ============
initialize_ddr_freq_list() {
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
}
initialize_ddr_freq_list
NUM_DVFSRC_OPP=$((${#DDR_Freq_List[*]}-1))
# ============ initialize DDR_Freq_List for ddr random frequency test end ============

# ============ find UFSG5_DDR_MIN_OPP and UFSG5_DDR_MAX_OPP in DDR_Freq_List for UFS G5 test begin ============
DDR_Freq_List_Min_Index=$((${#DDR_Freq_List[*]}-1))
DDR_Freq_List_Max_Index=1
UFSG5_DDR_MIN_OPP=${DDR_Freq_List[$DDR_Freq_List_Min_Index]}
UFSG5_DDR_MAX_OPP=${DDR_Freq_List[$DDR_Freq_List_Max_Index]}
find_ufsG5_ddr_min_opp() {
    p=p
    min_line=$((UFSG5_DDR_MIN_OPP+opp_line_number))
    # find OPP_VCORE based on ]:
    OPP_VCORE=$(sed -n $min_line$p ${DVFSRC_PATH}dvfsrc_opp_table | grep -o ']:[[:space:]]*[0-9]*' | grep -o '[0-9]*')

    while [ OPP_VCORE -le 650000 ]
    do
        DDR_Freq_List_Min_Index=$((DDR_Freq_List_Min_Index-1))
        if [[ $DDR_Freq_List_Min_Index == 0 && "$ddr_ufs_test_mode" == "NV_G5" ]]; then
            touch /cache/factory/dram_aging_ddr_opp_warning.log
            chmod 666 /cache/factory/dram_aging_ddr_opp_warning.log
            echo "DDR_Freq_List: ${DDR_Freq_List[@]}" > /cache/factory/dram_aging_ddr_opp_warning.log
            echo "UFSG5_DDR_MIN_OPP is $UFSG5_DDR_MIN_OPP, vcore <= 0.65v, can't do UFS G5 test" >> /cache/factory/dram_aging_ddr_opp_warning.log
            /system/bin/reboot reboot_eng_at_fail
        fi
        UFSG5_DDR_MIN_OPP=${DDR_Freq_List[$DDR_Freq_List_Min_Index]}
        min_line=$((UFSG5_DDR_MIN_OPP+opp_line_number))
        OPP_VCORE=$(sed -n $min_line$p ${DVFSRC_PATH}dvfsrc_opp_table | grep -o ']:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
        echo "OPP VCORE is $OPP_VCORE"
    done
}
find_ufsG5_ddr_min_opp
echo "UFSG5_DDR_MIN_OPP is $UFSG5_DDR_MIN_OPP"

find_ufsG5_ddr_max_opp() {
    p=p
    max_line=$((UFSG5_DDR_MAX_OPP+opp_line_number))
    # find OPP_VCORE based on ]:
    OPP_VCORE=$(sed -n $max_line$p ${DVFSRC_PATH}dvfsrc_opp_table | grep -o ']:[[:space:]]*[0-9]*' | grep -o '[0-9]*')

    while [ OPP_VCORE -le 650000 ]
    do
        DDR_Freq_List_Max_Index=$((DDR_Freq_List_Max_Index+1))
        if [[ $DDR_Freq_List_Max_Index -gt $NUM_DVFSRC_OPP && "$ddr_ufs_test_mode" == "NV_G5" ]]; then
            touch /cache/factory/dram_aging_ddr_opp_warning.log
            chmod 666 /cache/factory/dram_aging_ddr_opp_warning.log
            echo "DDR_Freq_List: ${DDR_Freq_List[@]}" > /cache/factory/dram_aging_ddr_opp_warning.log
            echo "UFSG5_DDR_MAX_OPP is $UFSG5_DDR_MAX_OPP, vcore <= 0.65v, can't do UFS G5 test" >> /cache/factory/dram_aging_ddr_opp_warning.log
            /system/bin/reboot reboot_eng_at_fail
        fi
        UFSG5_DDR_MAX_OPP=${DDR_Freq_List[$DDR_Freq_List_Max_Index]}
        max_line=$((UFSG5_DDR_MAX_OPP+opp_line_number))
        OPP_VCORE=$(sed -n $max_line$p ${DVFSRC_PATH}dvfsrc_opp_table | grep -o ']:[[:space:]]*[0-9]*' | grep -o '[0-9]*')
        echo "OPP VCORE is $OPP_VCORE"
    done
}
find_ufsG5_ddr_max_opp
echo "UFSG5_DDR_MAX_OPP is $UFSG5_DDR_MAX_OPP"
# ============ find UFSG5_DDR_MIN_OPP and UFSG5_DDR_MAX_OPP in DDR_Freq_List for UFS G5 test end ============


SOC_PATH="/sys/devices/platform/soc"
UFS_PATH=(`ls $SOC_PATH | grep ufshci`)
echo $UFS_PATH
UFS_CLKSCALE_CONTROL_PATH=$SOC_PATH/$UFS_PATH/clkscale/clkscale_control
echo $UFS_CLKSCALE_CONTROL_PATH

# ============ vcore low prerequisites before force opp begin ============
setup_mmdvfs_vcore_low() {
    # Fixed MMDVFS vcore low requirement
    echo 1 > /sys/module/mmdvfs_pmqos/parameters/mmdvfs_enable
    if [ x"$platform" = x"mt6877" ]; then
        echo 2 > /sys/module/mmdvfs_pmqos/parameters/force_step
    elif [ x"$platform" = x"mt6991" ] || [ x"$platform" = x"mt6899" ] || [ x"$platform" = x"mt6993" ] || [ x"$platform" = x"mt6995" ]; then
        echo 0 5 > /sys/module/mtk_mmdvfs_debug/parameters/force_step
    else
        echo 3 > /sys/module/mmdvfs_pmqos/parameters/force_step
    fi
}

setup_ufs_vcore_low() {
    ddr_ufs_test_mode=`getprop persist.debug.ddr.ufs.mode`
    if [ "$ddr_ufs_test_mode" != "NV_G5" ]; then
        # Fixed UFS vcore low requirement (release first, then limit)
        # echo 5 > $UFS_CLKSCALE_CONTROL_PATH
        echo 3 > $UFS_CLKSCALE_CONTROL_PATH
    fi
}

setup_gps_vcore_low() {
    # Fixed GPS vcore low requirement
    settings put secure location_mode 0
}
# ============ vcore low prerequisites before force opp end ============

do_ddr_vcorefs_switch(){
    if [ $1 -gt 10 ]
    then
        setprop persist.debug.ddr.vcorefs.low.freq true
    else
        setprop persist.debug.ddr.vcorefs.low.freq false
    fi
    echo $1 > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
}

do_ddr_vcorefs_random(){

    echo " ***** STARTING DVFS STRESS ***** "
    echo 1 > ${DVFSRC_PATH}dvfsrc_enable

    #Disable MMDVFS and keep lowest freq
    setup_mmdvfs_vcore_low

    muxreport 3
    #Disable hold vcore whenever UFS access storage
    echo 0 > /proc/ufs_perf

    #Let SCP in low freq
    echo opp 0 > /proc/scp_dvfs/scp_dvfs_ctrl

    #Let APU in low freq
    if [ -f /d/apusys/power ]; then
        echo dvfs_debug 4 > /d/apusys/power
    fi

    setup_ufs_vcore_low

    if [ x"$platform" = x"mt6993" ] || [ x"$platform" = x"mt6995" ]; then
        echo 3 > /sys/module/mtk_hwz/parameters/kick_hwe_gear
    fi

    for i in $(seq 1 ${ntest})
    do
        high_temp_check
        sleep $T_DVFS_INTERVAL
        #fix_opp=$(($RANDOM%$NUM_DVFSRC_OPP))
        DDR_Freq_List_Index=$(($RANDOM%(($NUM_DVFSRC_OPP))+1))
        fix_opp=${DDR_Freq_List[$DDR_Freq_List_Index]}
        if [ x"$platform" = x"mt6877" ]; then
            #Disable vcore 0.55v
            if [[ $fix_opp -ne 14 && $fix_opp -ne 19 && $fix_opp -ne 24 && $fix_opp -ne 29 ]]; then
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        elif [ x"$platform" = x"mt6789" ]; then
            #Disable vcore 0.55v in mt6789
            if [[ $fix_opp -ne 12 && $fix_opp -ne 16 && $fix_opp -ne 20 ]]; then
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        else
            if [[ "$ddr_ufs_test_mode" == "NV_G5" && " ${DDR_OPP_MASK_LIST[@]} " == *" $fix_opp "* ]]; then
                continue
            else
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        fi
        cat ${DVFSRC_PATH}dvfsrc_dump | grep -e uv -e "DDR       :"
    done
}

do_ddr_vcorefs_max(){
    echo 1 > ${DVFSRC_PATH}dvfsrc_enable

    setup_mmdvfs_vcore_low
    setup_ufs_vcore_low

    if [ x"$platform" = x"mt6993" ] || [ x"$platform" = x"mt6995" ]; then
        echo 3 > /sys/module/mtk_hwz/parameters/kick_hwe_gear
    fi
    for i in $(seq 1 ${ntest})
    do
        high_temp_check
        DDR_Freq_List_Index=1
        fix_opp=${DDR_Freq_List[$DDR_Freq_List_Index]}
        if [ "$ddr_ufs_test_mode" == "NV_G5" ]; then
            fix_opp=$UFSG5_DDR_MAX_OPP
        fi
        echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
        echo 0 > ${DVFSRC_PATH}dvfsrc_enable
        sleep $T_DVFS_INTERVAL
        cat ${DVFSRC_PATH}dvfsrc_dump | grep -e uv -e "DDR       :"
    done
}

do_ddr_vcorefs_min(){
    echo 1 > ${DVFSRC_PATH}dvfsrc_enable
    echo "Disable MMDVFS and keep lowest freq"
    setup_mmdvfs_vcore_low

    if [ x"$platform" = x"mt6993" ] || [ x"$platform" = x"mt6995" ]; then
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

    setup_ufs_vcore_low
    #echo "fix vcore 0.55v and dram 1866M"
    #echo "fix vcore 0.58v and dram 800M"
    if [ x"$platform" = x"mt6877" ]; then
        echo "fix vcore 0.6v and dram 800M"
        echo 28 > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
    elif [ x"$platform" = x"mt6789" ]; then
        echo "fix vcore 0.6v and dram 800M in mt6789"
        echo 19 > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
    else
        DDR_Freq_List_Index=$((${#DDR_Freq_List[*]}-1))
        fix_opp=${DDR_Freq_List[$DDR_Freq_List_Index]}
        if [ "$ddr_ufs_test_mode" == "NV_G5" ]; then
            fix_opp=$UFSG5_DDR_MIN_OPP
        fi
        echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
    fi

    echo 0 > ${DVFSRC_PATH}dvfsrc_enable
    for i in $(seq 1 ${ntest})
    do
        sleep $T_DVFS_INTERVAL
        cat ${DVFSRC_PATH}dvfsrc_dump | grep -e uv -e "DDR       :"
    done
}

do_ddr_vcorefs_longstep_random(){
    echo 1 > ${DVFSRC_PATH}dvfsrc_enable
    echo "do_ddr_vcorefs_longstep_random"
    echo "Disable MMDVFS and keep lowest freq"
    setup_mmdvfs_vcore_low

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

    setup_ufs_vcore_low

    if [ x"$platform" = x"mt6993" ] || [ x"$platform" = x"mt6995" ]; then
        echo 3 > /sys/module/mtk_hwz/parameters/kick_hwe_gear
    fi

    #fix_opp=$(($RANDOM%$NUM_DVFSRC_OPP))
    DDR_Freq_List_Index=$(($RANDOM%(($NUM_DVFSRC_OPP))+1))
    for i in $(seq 1 ${ntest})
    do
        high_temp_check
        sleep $T_DVFS_INTERVAL
        L_step=$(($RANDOM%5))
        DDR_Freq_List_Index=$(($DDR_Freq_List_Index+10+$L_step))
        DDR_Freq_List_Index=$(($DDR_Freq_List_Index%$NUM_DVFSRC_OPP))
        fix_opp=${DDR_Freq_List[$DDR_Freq_List_Index]}
        if [ x"$platform" = x"mt6877" ]; then
            #Disable vcore 0.55v
            if [[ $fix_opp -ne 14 && $fix_opp -ne 19 && $fix_opp -ne 24 && $fix_opp -ne 29 ]]; then
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        elif [ x"$platform" = x"mt6789" ]; then
            #Disable vcore 0.55v in mt6789
            if [[ $fix_opp -ne 12 && $fix_opp -ne 16 && $fix_opp -ne 20 ]]; then
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        else
            if [[ "$ddr_ufs_test_mode" == "NV_G5" && " ${DDR_OPP_MASK_LIST[@]} " == *" $fix_opp "* ]]; then
                continue
            else
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        fi
        cat ${DVFSRC_PATH}dvfsrc_dump | grep -e uv -e "DDR       :"
    done
}

do_ddr_vcorefs_risk(){
    echo 1 > ${DVFSRC_PATH}dvfsrc_enable
    echo "Disable MMDVFS and keep lowest freq"
    setup_mmdvfs_vcore_low

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

    setup_ufs_vcore_low
    #slect one risk level
    for i in $(seq 1 ${nrtest})
    do
        high_temp_check
        sleep $T_DVFS_INTERVAL
        # ramdon slect one level
        fix_opp=${G4_risk_dvfsrc_opp[$RANDOM % ${#G4_risk_dvfsrc_opp[@]}]}
        if [ "$ddr_ufs_test_mode" == "NV_G5" ]; then
            fix_opp=${G5_risk_dvfsrc_opp[$RANDOM % ${#G5_risk_dvfsrc_opp[@]}]}
        fi
        if [ x"$platform" = x"mt6877" ]; then
            #Disable vcore 0.55v
            if [[ $fix_opp -ne 14 && $fix_opp -ne 19 && $fix_opp -ne 24 && $fix_opp -ne 29 ]]; then
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        elif [ x"$platform" = x"mt6789" ]; then
            #Disable vcore 0.55v in mt6789
            if [[ $fix_opp -ne 12 && $fix_opp -ne 16 && $fix_opp -ne 20 ]]; then
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        else
            if [[ "$ddr_ufs_test_mode" == "NV_G5" && " ${DDR_OPP_MASK_LIST[@]} " == *" $fix_opp "* ]]; then
                continue
            else
                echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
            fi
        fi
        cat ${DVFSRC_PATH}dvfsrc_dump | grep -e uv -e "DDR       :"
    done
}

high_temp_check() {
    while [ 1 ]
    do
        read aging_max_temp < /cache/factory/dram_aging_temp.log
        if [ $aging_max_temp -ge $HIGH_TEMP_LIMIT ]; then
            flag_hightemp=1
	    DDR_Freq_List_Index=$((${#DDR_Freq_List[*]}-1))
            fix_opp=${DDR_Freq_List[$DDR_Freq_List_Index]}
            if [ "$ddr_ufs_test_mode" == "NV_G5" ]; then
                fix_opp=$UFSG5_DDR_MIN_OPP
            fi
        elif [ $aging_max_temp -ge $LOW_TEMP_LIMIT ]; then
            if [ $flag_hightemp -eq 1 ]; then
                DDR_Freq_List_Index=$((${#DDR_Freq_List[*]}-1))
                fix_opp=${DDR_Freq_List[$DDR_Freq_List_Index]}
                if [ "$ddr_ufs_test_mode" == "NV_G5" ]; then
                    fix_opp=$UFSG5_DDR_MIN_OPP
                fi
            else
                break
            fi
        else
            flag_hightemp=0
            break
        fi

        echo $fix_opp > ${DVFSRC_PATH}dvfsrc_force_vcore_dvfs_opp
        cat ${DVFSRC_PATH}dvfsrc_dump | grep -e uv -e "DDR       :"
        # 1s钟进行一次循环检查
        sleep $T_DVFS_TEMP_INTERVAL
    done
}

update_high_temp() {
    max_temp=-273000
    # scan all thermal_zone
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        # read the zone sensor data, and check return if error or not.
        current_temp=$(cat $zone 2>/dev/null)
		if [ $? -eq 0 ]; then
			current_temp=$(($current_temp))
			# compare the result.
			if [ $current_temp -gt $max_temp -a $current_temp -ne 125000 ]; then
				max_temp=$current_temp
			fi
		fi
    done
    # show the result.
    aging_max_temp=$(($max_temp/1000))
    echo "$aging_max_temp" > /cache/factory/dram_aging_temp.log
}

start_get_max_temp_fn(){
    {
        while [ 1 ]
        do
            update_high_temp
            sleep $T_DVFS_TEMP_INTERVAL
        done
    }&
}

enable_ddr_vcorefs_test(){
    while [ 1 ]
    do
        ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
        if [ "$ddr_testphase" = "done" ]; then
            break
        fi
        setprop persist.debug.ddr.vcorefs.config random
        ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
        echo "ddr_testphase:$ddr_testphase."
        if [ "$ddr_testphase" = "random" ]; then
            do_ddr_vcorefs_random
        fi

        ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
        if [ "$ddr_testphase" = "done" ]; then
            break
        fi
        setprop persist.debug.ddr.vcorefs.config max
        ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
        echo "ddr_testphase:$ddr_testphase."
        if [ "$ddr_testphase" = "max" ]; then
            do_ddr_vcorefs_max
        fi

        ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
        if [ "$ddr_testphase" = "done" ]; then
            break
        fi
        setprop persist.debug.ddr.vcorefs.config min
        ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
        echo "ddr_testphase:$ddr_testphase."
        if [ "$ddr_testphase" = "min" ]; then
            do_ddr_vcorefs_min
        fi

        ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
        if [ "$ddr_testphase" = "done" ]; then
            break
        fi
        setprop persist.debug.ddr.vcorefs.config longstep
        ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
        echo "ddr_testphase:$ddr_testphase."
        if [ "$ddr_testphase" = "longstep" ]; then
            do_ddr_vcorefs_longstep_random
        fi

        ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
        if [ "$ddr_testphase" = "done" ]; then
            break
        fi
        setprop persist.debug.ddr.vcorefs.config risk
        ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
        echo "ddr_testphase:$ddr_testphase."
        if [ "$ddr_testphase" = "risk" ] && [ x"$platform" = x"mt6993" -o x"$platform" = x"mt6995" ]; then
            do_ddr_vcorefs_risk
        fi
    done
    echo "The ddr_vcorefs_test is done and PASS if no exception occurred."
}

enable_ddr_vcorefs_manual(){
    ddr_testphase=`getprop persist.debug.ddr.vcorefs.config`
    while [ 1 ]
    do
        if [ "$ddr_testphase" != "done" ]; then
            break
        fi
        ddr_manualphase=`getprop persist.debug.ddr.vcorefs.manual`
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

# Fixed GPS vcore low requirement before force opp test
setup_gps_vcore_low

start_get_max_temp_fn
enable_ddr_vcorefs_test
enable_ddr_vcorefs_manual

