#!/vendor/bin/sh

MemTotalStr=`cat /proc/meminfo | grep MemTotal`
MemTotal=${MemTotalStr:16:8}
ERM_PATH=/sys/kernel/oplus_mm/erm

function configure_read_ahead_kb_values() {
  erofs_ra_kb=128
  dmpts=$(ls /sys/block/*/queue/read_ahead_kb | grep -e dm -e mmc)

  # Set 128 for <= 3GB &
  # set 512 for >= 4GB targets.
  if [ $MemTotal -le 3145728 ]; then
    ra_kb=128
  else
    ra_kb=512
  fi

  for dm in $dmpts; do
    # mtk configure dm-[0-5], so we don't need rewrite here.
    ignore=`echo $dm | grep 'dm-[0-5]/'`
    if [ ! -z "$ignore" ]; then
      continue
    fi

    dm_dev=`echo $dm |cut -d/ -f4`
    if [ "$dm_dev" = "" ]; then
      is_erofs=""
    else
      is_erofs=`mount |grep erofs |grep "${dm_dev} "`
    fi
    if [ "$is_erofs" = "" ]; then
      echo $ra_kb > $dm
    else
      echo $erofs_ra_kb > $dm
    fi
  done
}

function oplus_configure_tuning_swappiness() {
  local para_path=/proc/sys/vm
  local kernel_version=`uname -r`

  if [[ "$kernel_version" == "5.1"* || "$kernel_version" == "6."* ]]; then
    echo 160 > /sys/module/oplus_bsp_zram_opt/parameters/vm_swappiness
  else
    echo 160 > /sys/module/zram_opt/parameters/vm_swappiness
  fi

  echo 100 > /proc/sys/vm/swappiness

  if [[ "$kernel_version" == "5.1"* || "$kernel_version" == "6."* ]]; then
    para_path=/sys/module/oplus_bsp_zram_opt/parameters
  fi

  if [ $MemTotal -le 6291456 ]; then
    echo 0 > $para_path/vm_swappiness_threshold1
    echo 0 > $para_path/swappiness_threshold1_size
    echo 0 > $para_path/vm_swappiness_threshold2
    echo 0 > $para_path/swappiness_threshold2_size
  elif [ $MemTotal -le 8388608 ]; then
    echo 100  > $para_path/vm_swappiness_threshold1
    echo 2000 > $para_path/swappiness_threshold1_size
    echo 120  > $para_path/vm_swappiness_threshold2
    echo 1500 > $para_path/swappiness_threshold2_size
  else
    echo 100  > $para_path/vm_swappiness_threshold1
    echo 4096 > $para_path/swappiness_threshold1_size
    echo 120  > $para_path/vm_swappiness_threshold2
    echo 2048 > $para_path/swappiness_threshold2_size
  fi
}

function configure_thp()
{
  # With THP enabled, the kernel greatly increases min_free_kbytes over its
  # default value. Disable THP to prevent resetting of min_free_kbytes
  # value during online/offline pages.
  # 11584kb is the standard kernel value of min_free_kbytes for 8Gb of lowmem
  if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
      echo never > /sys/kernel/mm/transparent_hugepage/enabled
  fi
  # oplus_kernel_mm, increase min_free_kbytes from 11584 to 23168
  echo 23168 > /proc/sys/vm/min_free_kbytes
}

function configure_erm() {
  if [ ! -d "$ERM_PATH" ]; then
    return
  fi

  echo "4096 100" > $ERM_PATH/kswapd_swappiness1
  echo "2048 120" > $ERM_PATH/kswapd_swappiness2

  # camera
  echo 2000 > $ERM_PATH/cam_preopen_prefill_mb
  echo 500 > $ERM_PATH/cam_open_release_ms
  echo 120 > $ERM_PATH/camera_swappiness
}

function setup_mm() {
  configure_read_ahead_kb_values
  oplus_configure_tuning_swappiness

  echo 0 > /proc/sys/vm/page-cluster
  echo 0 > /proc/sys/vm/compaction_proactiveness
  echo 500 > /dev/memcg/system/memory.app_score
  echo systemserver > /dev/memcg/system/memory.name

  # tune boostpool min watermark
  if [ $MemTotal -gt 8388608 ]; then
    echo 64 > /proc/boost_pool/mtk_mm-uncached/min
    echo 500 > /proc/boost_pool/mtk_mm/min
  elif [ $MemTotal -gt 6291456 ]; then
    echo 64 > /proc/boost_pool/mtk_mm-uncached/min
    echo 128 > /proc/boost_pool/mtk_mm/min
  fi

  # disable boost_watermark
  echo 0 > /proc/sys/vm/watermark_boost_factor

  # For transparent_hugepage
  configure_thp

  # For erm
  configure_erm

   # For vts test which has replace system.img
  if [ -L "/product" ]; then
    sh "/odm/etc/init.oplus.mm-sys.sh"
  fi
}

setup_mm
