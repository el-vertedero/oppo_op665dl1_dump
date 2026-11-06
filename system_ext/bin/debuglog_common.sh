#! /system/bin/sh

CURTIME=`date +%F_%H-%M-%S`
CURTIME_FORMAT=`date "+%Y-%m-%d %H:%M:%S"`

DEFAULT_LOG_BASE_PATH=/sdcard/Android/data/com.oplus.olc/files/Log
SDCARD_LOG_BASE_PATH=`getprop persist.sys.olc.log.path ${DEFAULT_LOG_BASE_PATH}`
BASE_PATH=$(dirname $(dirname ${SDCARD_LOG_BASE_PATH}))
DATA_DEBUGGING_PATH=/data/debugging
MTK_DATA_DEBUGGING_PATH=/data/debuglogger
DATA_OPLUS_LOG_PATH=/data/persist_log

config="$1"

#------# collect method #--------------------------------------------------------------------------#
function dump_bugreport() {
    traceTransferState "bugreport start..."
    bugreportz
}

function waitForSdcardMounted(){
    local retry=0
    local max_retry=180
    while [ $retry -lt $max_retry ]; do
        if [ -d /sdcard/Android ]; then
            log -p d -t Debuglog "copyAging: /sdcard mounted after ${retry}s"
            return 0
        fi
        sleep 1
        retry=$((retry + 1))
    done
    log -p e -t Debuglog "copyAging: /sdcard not mounted after ${max_retry}s, abort"
    return 1
}

function copyAgingResource(){
    if [ -d /data/media/fbe_0/ ]; then
        if [ ! -f /sdcard/SkipTip.txt ]; then
            waitForSdcardMounted || return
            /system/bin/cp -af /data/media/fbe_0/. /sdcard/
            log -p d -t Debuglog "copyAging: copy done, verifying..."
            local src_size=$(stat -c%s /data/media/fbe_0/sys_screensavers_res.zip 2>/dev/null)
            local dst_size=$(stat -c%s /sdcard/sys_screensavers_res.zip 2>/dev/null)
            if [ "$src_size" = "$dst_size" ] && [ -n "$src_size" ]; then
                log -p d -t Debuglog "copyAging: verify OK, size=${dst_size}"
            else
                log -p e -t Debuglog "copyAging: verify FAIL, src=${src_size} dst=${dst_size}"
            fi
        fi
    fi
    # add for android 17 new service : casefolder remover
    if [ -d /data/media/uncasefolded/fbe_0/ ]; then
        if [ ! -f /sdcard/SkipTip.txt ]; then
            /system/bin/cp -af /data/media/uncasefolded/fbe_0/. /data/media/0/
        fi
    fi
}

#------# utils method #----------------------------------------------------------------------------#
function logObserver() {
    # 1, data free size
    boot_completed=`getprop sys.boot_completed`
    while [ x${boot_completed} != x"1" ];do
        traceTransferState "log observer:device don't boot completed"
        sleep 10
        boot_completed=`getprop sys.boot_completed`
    done

    FreeSize=`df /data | grep -v Mounted | awk '{print $4}'`
    traceTransferState "LOGOBSERVER:free size ${FreeSize}"

    # 2, count log size
    LOG_CONFIG_FILE="${DATA_OPLUS_LOG_PATH}/config/log_config.log"
    LOG_COUNT_SIZE=0
    if [ -f "${LOG_CONFIG_FILE}" ]; then
        while read -r ITEM_CONFIG
        do
            if [ "" != "${ITEM_CONFIG}" ];then
                #echo "${CURTIME_FORMAT} transfer log config: ${ITEM_CONFIG}"
                SOURCE_PATH=`echo ${ITEM_CONFIG} | awk '{print $2}'`
                if [ -d ${SOURCE_PATH} ];then
                    TEMP_SIZE=`du -s ${SOURCE_PATH} | awk '{print $1}'`
                    zipRate=`echo ${ITEM_CONFIG} | awk '{print $3}'`
                    if [ -z  "$zipRate" ]
                    then
                      zipRate=`getDirZipRate ${SOURCE_PATH}`
                    fi
                    TEMP_SIZE=`expr ${TEMP_SIZE} * ${zipRate} / 100`
                    if [ "" != "${TEMP_SIZE}" ]; then
                        LOG_COUNT_SIZE=`expr ${LOG_COUNT_SIZE} + ${TEMP_SIZE}`
                    fi
                    traceTransferState "path: ${SOURCE_PATH}, rate is ${zipRate}, ${TEMP_SIZE}/${LOG_COUNT_SIZE}"
                else
                    echo "${CURTIME_FORMAT} PATH: ${SOURCE_PATH}, No such file or directory"
                fi
            fi
        done < ${LOG_CONFIG_FILE}
    fi

    settings put global logkit_observer_size "${FreeSize}|${LOG_COUNT_SIZE}"
    # settings get global logkit_observer_size
    traceTransferState "LOGOBSERVER:data free and log size: ${FreeSize}|${LOG_COUNT_SIZE}"
}

function getDirZipRate(){
    dir=$1
    rate=85
    if [[ "${dir}" == "/data/debugging/" ]]; then
        rate=40
    elif [[ "${dir}" == */dcs* ]]; then
        rate=100
    elif [[ "${dir}" == *dump* ]]; then
        rate=80
    elif [[ "${dir}" == "/data/debuglogger/mdlog1/" ]]; then
        rate=40
    elif [[ "${dir}" == /data/debuglogger/* ]]; then
        rate=60
    fi
    echo $rate
}

function traceTransferState() {
    content=$1

    if [[ -d ${BASE_PATH} ]]; then
        if [[ ! -d ${SDCARD_LOG_BASE_PATH} ]]; then
            mkdir -p ${SDCARD_LOG_BASE_PATH}
            chmod 2770 ${BASE_PATH} -R
            echo "${CURTIME_FORMAT} TRACETRANSFERSTATE:${SDCARD_LOG_BASE_PATH} " >> ${SDCARD_LOG_BASE_PATH}/logkit_transfer.log
        fi

        currentTime=`date "+%Y-%m-%d %H:%M:%S"`
        echo "${currentTime} ${content} " >> ${SDCARD_LOG_BASE_PATH}/logkit_transfer.log
    fi

    LOG_LEVEL=$2
    if [[ "${LOG_LEVEL}" == "" ]]; then
        LOG_LEVEL=d
    fi
    log -p ${LOG_LEVEL} -t Debuglog ${content}
}

function cleanLog(){
    #MTK
    if [[ -d ${MTK_DATA_DEBUGGING_PATH} ]]; then
        chmod 777 ${MTK_DATA_DEBUGGING_PATH} -R
        rm -rf ${MTK_DATA_DEBUGGING_PATH}/*
    fi

    #QCOM
    if [[ -d ${DATA_DEBUGGING_PATH} ]]; then
        chmod 777 ${DATA_DEBUGGING_PATH} -R
        rm -rf ${DATA_DEBUGGING_PATH}/*
    fi

    chmod 777 ${DATA_OPLUS_LOG_PATH}/TMP -R
    rm -rf ${DATA_OPLUS_LOG_PATH}/TMP/*

    rm -rf /cache/admin/*
    rm -rf /data/core/*
    rm -rf /data/anr/*
    rm -rf /data/tombstones/*
    rm -rf /data/system/dropbox/*
    rm -rf /data/misc/bluetooth/logs/*

    setprop sys.clear.finished 1
}

case "$config" in
    "dump_bugreport")
        dump_bugreport
    ;;
    "copy_aging_resource")
        copyAgingResource
        ;;
    "log_observer")
        logObserver
        ;;
    "clean_log")
        cleanLog
        ;;
    *)
        ;;
esac