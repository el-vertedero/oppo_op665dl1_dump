#! /system/bin/sh


config="$1"

GPS_AUTOMATIC_LOGS_SWITCH=gps_automatic_logs_switch
GPS_DEBUG_LEVEL_ON=5
GPS_DEBUG_LEVEL_OFF=3

MTK_TYPE_GPS=0x10
MTK_TYPE_CONNECT_FW=0x20
MTK_TYPE_GPS_MASK=$((MTK_TYPE_GPS | MTK_TYPE_CONNECT_FW))

MTK_LOG_PATH_TYPE=1

MTK_CMD_PREFIX="am broadcast -a com.debug.loggerui.ADB_CMD"
MTK_CMD_SUFFIX=" -f 0x1000020 -n com.debug.loggerui/.framework.LogReceiver --async"

function logTrace() {
    log -p d -t Debuglog "$1"
}

function isMtkPlatform() {
    local platform hardware
    platform=`getprop ro.soc.manufacturer`
    hardware=`getprop ro.hardware`
    if [[ "${hardware}" == mt* ]] || [[ "${platform}" == "MTK" ]]; then
        return 0
    fi
    return 1
}

function isQcomPlatform() {
    local platform
    platform=`getprop ro.soc.manufacturer`
    if [[ "${platform}" == "QTI" ]]; then
        return 0
    fi
    return 1
}

function mtkSendBroadcast() {
    local cmd_name="$1"
    local cmd_target="$2"
    ${MTK_CMD_PREFIX} -e cmd_name "${cmd_name}" --ei cmd_target ${cmd_target} ${MTK_CMD_SUFFIX}
}

function mtkLogOn() {
    logTrace "mtk gps log on"

    local logtype
    logtype=`getprop persist.sys.mtk.logtype 0`
    logtype=$((logtype | MTK_TYPE_GPS_MASK))
    setprop persist.sys.mtk.logtype ${logtype}

    mtkSendBroadcast "log_save_path_${MTK_LOG_PATH_TYPE}" $((MTK_TYPE_GPS))
    mtkSendBroadcast "start" ${logtype}
}

function mtkLogOff() {
    logTrace "mtk gps log off"

    local logtype
    logtype=`getprop persist.sys.mtk.logtype 0`
    logtype=$((logtype & (~MTK_TYPE_GPS_MASK)))
    setprop persist.sys.mtk.logtype ${logtype}

    if [ ${logtype} -gt 0 ]; then
        mtkSendBroadcast "start" ${logtype}
    else
        mtkSendBroadcast "stop" ${MTK_TYPE_GPS_MASK}
    fi
}

function qcomLogOn() {
    logTrace "qcom gps log on"
}

function qcomLogOff() {
    logTrace "qcom gps log off"
}

function logOn() {
    # set log on command
    echo "gps log on"

    settings put global ${GPS_AUTOMATIC_LOGS_SWITCH} 1
    settings put global gps_debug_level ${GPS_DEBUG_LEVEL_ON}

    if isMtkPlatform; then
        mtkLogOn
    elif isQcomPlatform; then
        qcomLogOn
    else
        logTrace "unsupported platform, skip gps log on"
    fi
}

function logOff() {
    # set log off command
    echo "gps log off"

    settings put global ${GPS_AUTOMATIC_LOGS_SWITCH} 0
    settings put global gps_debug_level ${GPS_DEBUG_LEVEL_OFF}

    if isMtkPlatform; then
        mtkLogOff
    elif isQcomPlatform; then
        qcomLogOff
    else
        logTrace "unsupported platform, skip gps log off"
    fi
}

case "$config" in
    "logon")
        logOn
        ;;
    "logoff")
        logOff
        ;;
    *)
        ;;
esac
