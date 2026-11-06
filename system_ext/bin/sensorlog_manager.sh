#! /system/bin/sh

config="$1"

function logOn() {
    # set log on command
    echo "sensor log on"
    local platform
    platform=`getprop ro.soc.manufacturer`
    if [ x"${platform}" = x"QTI" ]; then
        local diag_charge_log_status
        diag_charge_log_status=`getprop init.svc.oplus_diag_charge_log_start`
        if [ x"${diag_charge_log_status}" != x"running" ]; then
            setprop ctl.stop sensor_logger_qxdm_start
            setprop ctl.start sensor_logger_qxdm_start
        fi
        return
    fi
}

function logOff() {
    # set log off command
    echo "sensor log off"
    local platform
    platform=`getprop ro.soc.manufacturer`
    if [ x"${platform}" = x"QTI" ]; then
        setprop ctl.stop sensor_logger_qxdm_stop
        setprop ctl.start sensor_logger_qxdm_stop
        return
    fi
}

function checkProp() {
    local prop
    prop=$1
    # waiting for 5 seconds
    local i
    i=1
    while [ $i -le 5 ]; do
        sleep 1
        value=$(getprop ${prop})
        echo "prop ${prop} = ${value}"
        if [ x"${value}" != x"running" ]; then
            echo "Property ${prop} has changed to ${value}. Exiting."
            return
        fi
        ((i++))
    done
    echo "Waited for 5 seconds, property still running. Exiting."
    return
}

function logDump() {
    local platform
    # set log dump command
    echo "sensor log dump"

    platform=`getprop ro.soc.manufacturer`
    if [ x"${platform}" = x"QTI" ]; then
        setprop ctl.start sensor_logger_qxdm_drain
        checkProp "init.svc.sensor_logger_qxdm_drain"
        sleep 2
        setprop ctl.start sensor_logger_qxdm_stop
        checkProp "init.svc.sensor_logger_qxdm_stop"
        sleep 5
        setprop ctl.start sensor_logger_qxdm_start
        checkProp "init.svc.sensor_logger_qxdm_start"
    fi
}

function dataRecordStart() {
    echo "sensor data record start"
    setprop ctl.start sensor_logger_data_start
    checkProp "init.svc.sensor_logger_data_start"
    setprop ctl.stop sensor_logger_data_start
    checkProp "init.svc.sensor_logger_data_start"
}

function dataRecordStop() {
    echo "sensor data record stop"
    setprop ctl.start sensor_logger_data_stop
    checkProp "init.svc.sensor_logger_data_stop"
    setprop ctl.stop sensor_logger_data_stop
    checkProp "init.svc.sensor_logger_data_stop"
}

case "$config" in
    "logon")
        ;;
    "logoff")
        ;;
    "logdump")
        ;;
    "logon_always")
        dataRecordStart
        log -t "sensor_log" -p i "Log Always On begin"
        logOn
        log -t "sensor_log" -p i "Log Always On end"
        ;;
    "logoff_always")
        log -t "sensor_log" -p i "Log Always Off begin"
        logOff
        log -t "sensor_log" -p i "Log Always Off end"
        ;;
    "logdump_always")
        dataRecordStop
        log -t "sensor_log" -p i "Log Always dump begin"
        logDump
        log -t "sensor_log" -p i "Log Always dump end"
        ;;
    *)
        ;;
esac
