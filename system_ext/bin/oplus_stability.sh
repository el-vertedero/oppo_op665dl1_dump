#! /system/bin/sh

cmd="$1"

function binder_proc_state_capture() {
    THRESHOLD=60
    ANR_DIR=/data/anr
    TARGET_PID=`getprop sys.oplus.binder.query_pid`
    CURRENT_TIME=`date +%s`
    PROC_STATE_FILE=/dev/binderfs/binder_logs/proc/${TARGET_PID}
    ANR_STATE_FILE=${ANR_DIR}/proc_binder_state_${TARGET_PID}

    if [ ! -f "${PROC_STATE_FILE}" ]; then
        exit 1
    fi
    cat "${PROC_STATE_FILE}" > "${ANR_STATE_FILE}"
    if [ ! -f "${ANR_STATE_FILE}" ]; then
        exit 1
    fi
    chown system:system "${ANR_STATE_FILE}"
    chmod 600 "${ANR_STATE_FILE}"

    for file in "${ANR_DIR}"/proc_binder_state_*; do
        if [ ! -f "$file" ]; then
            continue
        fi
        file_time=`stat -c %Y "${file}" 2>/dev/null`
        if [ -z "${file_time}" ]; then
            continue
        fi
        age=$((CURRENT_TIME - file_time))
        if [ "${age}" -gt "${THRESHOLD}" ]; then
            rm -f "${file}"
        fi
    done
}

case "$cmd" in
    "binder_proc_state_capture")
        binder_proc_state_capture
        ;;
    *)
        ;;
esac
