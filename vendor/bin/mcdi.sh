#!/system/bin/sh

TAG="mcdi.sh"

log_msg() {
	ts="$(date)"
	msg="[$TAG][$ts][pid=$$] $*"
	echo "$msg"
	if [ -w /dev/kmsg ] 2>/dev/null; then
		echo "$msg" > /dev/kmsg 2>/dev/null || true
	fi
}

write_proc() {
	path="$1"
	val="$2"
	if [ ! -w "$path" ] 2>/dev/null; then
		log_msg "ERROR: not writable or missing: $path"
		return 1
	fi
	# Use printf to avoid trailing newline surprises on some nodes.
	if printf '%s' "$val" >"$path" 2>/dev/null; then
		log_msg "OK: echo $val > $path"
		return 0
	fi
	log_msg "ERROR: write failed: $path (errno $?)"
	return 1
}

log_msg "start: $0"

# NOTE:
# - This script is intended to run ON-DEVICE (init/service context), not from PC adb.
# - Do NOT wrap with adb shell here.

write_proc /proc/mtk_lpm/cpuidle/state/stress_latency 100 || exit 1
write_proc /proc/mtk_lpm/cpuidle/state/stress_residency 100 || exit 1
write_proc /proc/mtk_lpm/cpuidle/control/stress_time 1000 || exit 1
write_proc /proc/mtk_lpm/cpuidle/control/stress 1 || exit 1
write_proc /proc/mtk_lpm/cpuidle/info 1 || exit 1

log_msg "done"
exit 0
