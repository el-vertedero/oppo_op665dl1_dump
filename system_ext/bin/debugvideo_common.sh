#! /system/bin/sh

config="$1"

#================================== COMMON LOG =========================

function videologmtkc2on() {
    echo -codec_log 7 -vpud_log 3 -job_log 3 > /sys/module/mtk_vcodec_dec_v2/parameters/mtk_vdec_vcp_log
    echo 2 > /proc/mtprintk
    echo 7 > /sys/module/mtk_vcodec_dec_v2/parameters/mtk_v4l2_dbg_level
    echo 1 > /sys/module/mtk_vcodec_dec_v2/parameters/mtk_vcodec_dbg
}

function videologmtkc2off() {
    chown -R media:system /data/vendor/videodump
    echo -codec_log 0 -vpud_log 0 -job_log 0 > /sys/module/mtk_vcodec_dec_v2/parameters/mtk_vdec_vcp_log
    echo 0 > /proc/mtprintk
    echo 0 > /sys/module/mtk_vcodec_dec_v2/parameters/mtk_v4l2_dbg_level
    echo 0 > /sys/module/mtk_vcodec_dec_v2/parameters/mtk_vcodec_dbg
}

function videologqcomc2on() {
}

function videologqcomc2off() {
    chown -R media:system /data/vendor/videodump
}

function videologunisocc2on() {
}

function unisocvideodumpinput() {
    setprop vendor.video.dump.vdec.input.filesize "104857600"
    setprop vendor.video.dump.vdec.input.dirsize "209715200"
    setprop vendor.video.dump.vdec.output.framenum "1"
    setprop vendor.video.dump.vdec "0x01"
#   setprop vendor.video.dynamicdump.enable true
}

function unisocvideodumpoutput() {
    setprop vendor.video.dump.vdec "0x11"
    setprop vendor.oplus.video.dump.output "0"
}

function videologunisocc2off() {
#   setprop vendor.video.dynamicdump.enable false
    setprop vendor.video.dump.vdec "0x00"
    setprop vendor.oplus.video.dump.output "0"
    setprop vendor.video.dump.vdec.output.framenum "0"
    setprop vendor.video.dump.vdec.input.dirsize "0"
    setprop vendor.video.dump.vdec.input.filesize "0"

    chown -R media:system /data/vendor/mediacodec
}

case "$config" in
    "videologmtkc2on")
        videologmtkc2on
        ;;
    "videologmtkc2off")
        videologmtkc2off
        ;;
    "videologqcomc2on")
        videologqcomc2on
        ;;
    "videologqcomc2off")
        videologqcomc2off
        ;;
    "videologunisocc2on")
        videologunisocc2on
        ;;
    "videologunisocc2off")
        videologunisocc2off
        ;;
    "unisocvideodumpinput")
        unisocvideodumpinput
        ;;
    "unisocvideodumpoutput")
        unisocvideodumpoutput
        ;;
       *)

      ;;
esac
