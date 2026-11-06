#! /system/bin/sh

config="$1"
CONFIG_FILE="/system_ext/etc/perfetto-configs/labmode_sys_ostats_trace_trigger.pbtxt"
OUTPUT_DIR="/data/misc/perfetto-traces/oplus/"
DEST_DIR="/data/persist_log/operfetto"

function deleteExtraTracesIfNeeded() {
    trace_dir=$1
    file_limit=5
    curBakCount=`ls ${trace_dir} | wc -l`
    #can only save 5 trace files at most
    while [ ${curBakCount} -gt $file_limit ]
    do
        rm ${trace_dir}/$(ls -t ${trace_dir} | tail -1)
        curBakCount=`ls ${trace_dir} | wc -l`
    done
}

function triggerTrace() {
	perfetto -c ${CONFIG_FILE} --txt
	sleep 5
    if [ ! -d ${DEST_DIR} ]; then
        mkdir -p ${DEST_DIR}
        chmod -R 777 ${DEST_DIR}
    fi
    for file in "${OUTPUT_DIR}"sys_trigger_ostats_ext.trace.operfetto.*; do
        if [ -e "$file" ]; then
            deleteExtraTracesIfNeeded ${DEST_DIR}
            #mv "$file" ${DEST_DIR}/otrace-$(date +%F-%H-%M-%S).operfetto
            cp "$file" ${DEST_DIR}/otrace-$(date +%F-%H-%M-%S).operfetto
            chmod 660 ${DEST_DIR}/otrace-$(date +%F-%H-%M-%S).operfetto
            rm -f "$file"
        fi
    done
}


case "$config" in
    "triggerTrace")
        triggerTrace
        ;;
    *)
        ;;
esac
