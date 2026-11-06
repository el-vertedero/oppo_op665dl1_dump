#! /system/bin/sh
# F2FS userdata tuning (min_ssr / min_fsync / ipu_policy). Invoked from init on boot + persist.sys.oplus.f2fstune.
#
# persist.sys.oplus.f2fstune:
#   1 — tuned set (12288 / 32 / 186), ignore UFS whitelist
#   2 — default set (722 / 20 / 184), ignore UFS whitelist
#   unset/other — UFS whitelist match -> tuned; else -> default (original if/else)
#
# Usage: /system_ext/bin/oplus_f2fs_ufs_tune.sh [apply]

apply_tuned() {
	echo 12288 > "${BASE}/min_ssr_sections" 2>/dev/null || return 1
	echo 32 > "${BASE}/min_fsync_blocks" 2>/dev/null || return 1
	echo 186 > "${BASE}/ipu_policy" 2>/dev/null || true
	return 0
}

apply_default() {
	echo 722 > "${BASE}/min_ssr_sections" 2>/dev/null || return 1
	echo 20 > "${BASE}/min_fsync_blocks" 2>/dev/null || return 1
	echo 184 > "${BASE}/ipu_policy" 2>/dev/null || true
	return 0
}

apply_ufs_auto() {
	UFS_INFO="/proc/devinfo/ufs"
	# for eMMC, no /proc/devinfo/ufs, apply default
	if [ ! -r "$UFS_INFO" ]; then
		apply_default
		return 0
	fi

	#WL='KLUFG4LHGC-B0E1|KLUFG4LHKD-F0H1|KLUGG8LHKD-F0H1|XBUSC1B1AAAQK2|XBUSC1B1BAAQK3'
	WL='KLUFG4LHKD-F0H1'
	if grep -qE "$WL" "$UFS_INFO" 2>/dev/null; then
		apply_tuned
	else
		apply_default
	fi
}

apply_tune() {
	BLK=$(getprop dev.mnt.blk.userdata)
	[ -z "$BLK" ] && return 0

	BASE="/sys/fs/f2fs/${BLK}"
	[ -d "$BASE" ] || return 0

	MODE=$(getprop persist.sys.oplus.f2fstune)
	case "$MODE" in
		1) apply_tuned ;;
		2) apply_default ;;
		*) apply_ufs_auto ;;
	esac
	return 0
}

case "$1" in
	apply | "") apply_tune ;;
	*) apply_tune ;;
esac

exit 0
