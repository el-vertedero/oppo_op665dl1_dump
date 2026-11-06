#!/system/bin/sh

# ---------------------------------------------------------------------------
# Copyright (C), 2008-2026, OPPO Mobile Comm Corp., Ltd.
# VENDOR_EDIT
# File: UT.sh
# Description: Script for ISP UT Test in Factory
# Version: 1.0
# Date : 2026/04/01
# Author: Wang Jianwei
# ----------------------Revision History-------------------------------------
#   <author>       <data>      <version>     <desc>
# Wang Jianwei   2026/04/01       1.0     implement basic feature
# ---------------------------------------------------------------------------

# Result summary configuration
# Output root: /sdcard/ISP_SLT_TEST/
# Per-run output: /sdcard/ISP_SLT_TEST/runs/<run_id>/
#   ut_test.log       - script execution log
#   p1_ut_result.txt  - P1 test result log
#   p2_MSSV_log.txt   - P2 test result log
#   result.json       - latest test summary (always overwrite)
RESULT_DIR="/sdcard/ISP_SLT_TEST"
RUNS_DIR="${RESULT_DIR}/runs"
RUN_ID=""
RUN_DIR=""
RESULT_FILE="${RESULT_DIR}/result.json"
MAIN_LOG=""
P1_LOG_PATTERN="/data/vendor/camsys_ut/UT*/ut_result.txt"
P1_RESULT_COPY=""
P2_LOG_FILE=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "$0")"

# Check last line of a test log file for "pass" keyword
check_test_result() {
	result_file=$1
	if [ -z "${result_file}" ] || [ ! -f "${result_file}" ]; then
		echo "fail"
		return
	fi
	last_line=$(tail -n 1 "${result_file}" 2>/dev/null)
	if echo "${last_line}" | grep -qi "pass"; then
		echo "pass"
	else
		echo "fail"
	fi
}

# Set a property and verify it takes effect with retries.
# Usage: setprop_with_retry <prop_name> <expected_value> [max_retries] [interval_s]
setprop_with_retry() {
	prop_name=$1
	expected_value=$2
	max_retries=${3:-5}
	interval_s=${4:-1}
	attempt=1

	while [ ${attempt} -le ${max_retries} ]; do
		setprop "${prop_name}" "${expected_value}"
		actual_value=$(getprop "${prop_name}")
		if [ "${actual_value}" = "${expected_value}" ]; then
			echo "setprop success: ${prop_name}=${expected_value} (attempt ${attempt}/${max_retries})"
			return 0
		fi
		echo "setprop retry: ${prop_name}, expect=${expected_value}, actual=${actual_value}, attempt ${attempt}/${max_retries}"
		attempt=$((attempt + 1))
		sleep "${interval_s}"
	done

	echo "setprop failed after ${max_retries} attempts: ${prop_name}, expect=${expected_value}, actual=$(getprop "${prop_name}")"
	return 1
}

# Initialize per-run output paths to avoid overwriting old runs.
# Usage: init_run_paths [run_id]
init_run_paths() {
	run_id_input=$1
	if [ -n "${run_id_input}" ]; then
		RUN_ID="${run_id_input}"
	else
		RUN_ID="$(date +%Y%m%d_%H%M%S)_$$"
	fi
	RUN_DIR="${RUNS_DIR}/${RUN_ID}"
	MAIN_LOG="${RUN_DIR}/ut_test.log"
	P1_RESULT_COPY="${RUN_DIR}/p1_ut_result.txt"
	P2_LOG_FILE="${RUN_DIR}/p2_MSSV_log.txt"

	mkdir -p "${RUN_DIR}" || return 1
	return 0
}

# echo 1 <x>: In mt6995, x=1 vmm=0.7v, x=2 vmm=0.65v, x=3 vmm=0.6v, x=4 vmm=0.575v
check_process() {
	if ! pidof ISP_MSSV_ICdiag_TEST > /dev/null 2>&1; then
		echo "ISP_MSSV_ICdiag_TEST finished, exiting voltage loop"
		return 1
	fi
	return 0
}

wait_and_check() {
	total=$1
	elapsed=0
	while [ $elapsed -lt $total ]; do
		sleep 5
		elapsed=$((elapsed + 5))
		check_process || return 1
	done
	return 0
}

run_isp_ut_test() {
	isp_p1_result="fail"
	isp_p2_result="fail"
	prop_set_ok="1"

	mkdir -p "${RUN_DIR}" || {
		echo "Failed to create ${RUN_DIR}"
		return 1
	}

	echo "=== ISP UT worker started at $(date) ==="
	echo "RUN_ID=${RUN_ID}"
	echo "RUN_DIR=${RUN_DIR}"

	# Clean previous P1 logs to make sure we read the latest result
	rm -rf /data/vendor/camsys_ut/UT*

	# P1 UT Test
	# test result path: /data/vendor/camsys_ut/UT*****/ut_result.txt
	cat /proc/mmdvfs/mmdvfs_opp
	stop camerahalserver
	echo 0x1 > /sys/module/mtk_cam_isp66/parameters/disable_qof
	echo "/sys/module/mtk_cam_isp66/parameters/disable_qof: $(cat /sys/module/mtk_cam_isp66/parameters/disable_qof)"
	/vendor/bin/mt6995/camsys_v4l2_ut STAGGER --sensor 4 5 --exp 2 2 --exp_order1 --stagger_type1 --round 100 --no-stt-start --node 212249 --dc --raw 7
	pkill -9 -f camsys_v4l2_ut
	echo 0x0 > /sys/module/mtk_cam_isp66/parameters/disable_qof
	echo "/sys/module/mtk_cam_isp66/parameters/disable_qof: $(cat /sys/module/mtk_cam_isp66/parameters/disable_qof)"

	# Collect P1 result: pick the latest UT*/ut_result.txt
	p1_log_file=$(ls -t ${P1_LOG_PATTERN} 2>/dev/null | head -n 1)
	echo "P1 source log: ${p1_log_file}"
	if [ -n "${p1_log_file}" ] && [ -f "${p1_log_file}" ]; then
		cp "${p1_log_file}" "${P1_RESULT_COPY}"
		isp_p1_result=$(check_test_result "${P1_RESULT_COPY}")
	else
		rm -f "${P1_RESULT_COPY}"
	fi
	echo "ISP P1 result: ${isp_p1_result} (log: ${P1_RESULT_COPY})"

	# Remove previous P2 log to avoid stale "pass" being picked up
	rm -f "${P2_LOG_FILE}"

	# P2 UT Test
	# test result path: /sdcard/ISP_SLT_TEST/p2_MSSV_log.txt
	cat /proc/mmdvfs/mmdvfs_opp
	echo test > /sys/power/wake_lock
	ps -A | grep cameraserver | grep -v grep | sed 's/ [ ]*/:/g' | cut -d: -f2 | xargs kill -9
	ps -A | grep ISP_MSSV_ICdiag_TEST | grep -v grep | sed 's/ [ ]*/:/g' | cut -d: -f2 | xargs kill -9
	stop camerahalserver
	if ! setprop_with_retry "vendor.camera.imgsys.sltmode" "1" 5 1; then
		echo "WARN: vendor.camera.imgsys.sltmode set failed, continue test flow"
		prop_set_ok="0"
	fi
	if ! setprop_with_retry "persist.vendor.mtk.camera.out.bytealign" "0" 5 1; then
		echo "WARN: persist.vendor.mtk.camera.out.bytealign set failed, continue test flow"
		prop_set_ok="0"
	fi
	touch "${P2_LOG_FILE}"
	/vendor/bin/ISP_MSSV_ICdiag_TEST --gtest_filter=IspMssvTest.IspSLT2 >> "${P2_LOG_FILE}" 2>&1 &

	while check_process; do
		echo 1 1 > /sys/module/mtk_mmdvfs_debug/parameters/force_step
		cat /proc/mmdvfs/mmdvfs_opp
		wait_and_check 60 || break
		echo 1 2 > /sys/module/mtk_mmdvfs_debug/parameters/force_step
		cat /proc/mmdvfs/mmdvfs_opp
		wait_and_check 60 || break
		echo 1 3 > /sys/module/mtk_mmdvfs_debug/parameters/force_step
		cat /proc/mmdvfs/mmdvfs_opp
		wait_and_check 60 || break
		echo 1 4 > /sys/module/mtk_mmdvfs_debug/parameters/force_step
		cat /proc/mmdvfs/mmdvfs_opp
		wait_and_check 60 || break
	done

	if ! setprop_with_retry "vendor.camera.imgsys.sltmode" "0" 5 1; then
		echo "WARN: vendor.camera.imgsys.sltmode set failed, continue test flow"
		prop_set_ok="0"
	fi
	start camerahalserver
	# Quote the pattern so the shell does not glob-expand "camera*" against
	# files in the current working directory before pkill ever sees it.
	pkill -9 "camera.*"

	# Release the wake lock acquired before the P2 test so the device can
	# sleep normally once the test finishes.
	echo test > /sys/power/wake_unlock

	# Collect P2 result and write summary JSON
	isp_p2_result=$(check_test_result "${P2_LOG_FILE}")
	echo "ISP P2 result: ${isp_p2_result} (log: ${P2_LOG_FILE})"
	if [ "${prop_set_ok}" != "1" ]; then
		echo "WARN: one or more setprop operations failed, force final result to fail"
		isp_p2_result="fail"
	fi

	cat > "${RESULT_FILE}" <<EOF
[
    {
        "isp_p1": "${isp_p1_result}",
        "isp_p2": "${isp_p2_result}"
    }
]
EOF

	echo "Summary written to ${RESULT_FILE}:"
	cat "${RESULT_FILE}"
}

# Worker: run P1/P2 tests and write logs to /sdcard/ISP_SLT_TEST/
if [ "$1" = "worker" ]; then
	# Ignore SIGHUP so closing the adb shell session that launched us cannot
	# kill the test (the launcher previously died with exit 129 = SIGHUP).
	# SIG_IGN is preserved across exec, so the test binaries spawned below
	# inherit this and are protected too.
	trap '' HUP
	init_run_paths "$2" || exit 1
	run_isp_ut_test >> "${MAIN_LOG}" 2>&1
	exit $?
fi

# Launcher: start test in background and return immediately
mkdir -p "${RUNS_DIR}" || {
	echo "Failed to create ${RUNS_DIR}"
	exit 1
}

init_run_paths || {
	echo "Failed to initialize run paths"
	exit 1
}

echo "=== ISP UT launcher started at $(date) ===" > "${MAIN_LOG}"
echo "RUN_ID=${RUN_ID}" >> "${MAIN_LOG}"
echo "RUN_DIR=${RUN_DIR}" >> "${MAIN_LOG}"

# Make the worker survive the adb shell session closing. The launching adb
# command returns within seconds; the moment it does, adbd tears down the
# shell and the kernel sends SIGHUP to the session, which previously killed
# the worker (exit 129 = SIGHUP).
#
# The guaranteed protection is "trap '' HUP" here: an ignored signal
# disposition is inherited across fork and preserved across exec, so the
# backgrounded worker AND every test binary it spawns inherit SIG_IGN for
# SIGHUP and cannot be killed by the session hangup. This does not depend on
# setsid actually creating a new session (which proved unreliable on device).
#
# setsid is still used as a best-effort to drop the controlling terminal;
# </dev/null detaches stdin from the pty.
trap '' HUP

if command -v setsid > /dev/null 2>&1; then
	setsid /system/bin/sh "${SCRIPT_PATH}" worker "${RUN_ID}" < /dev/null >> "${MAIN_LOG}" 2>&1 &
else
	/system/bin/sh "${SCRIPT_PATH}" worker "${RUN_ID}" < /dev/null >> "${MAIN_LOG}" 2>&1 &
fi
worker_pid=$!

echo "ISP UT test started in background, pid=${worker_pid}, run_id=${RUN_ID}, log=${MAIN_LOG}"
exit 0
