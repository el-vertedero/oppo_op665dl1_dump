#!system/bin/sh

readonly HYB_ERR_UNSUPPORTED=1004
readonly HYB_ERR_UNSET=1009
readonly LOG_TAG="init_oplus_mm-sys"

MEM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)

logi() {
  /system/bin/log -p i -t ${LOG_TAG} "$1"
  echo "${LOG_TAG}: $1"
}

write_kthread_to_cpuset() {
  local path_kthread=$1
  local path_cpuset=$2

  if [[ ! -f "${path_kthread}" ]] || [[ ! -f "${path_cpuset}" ]]; then
    return
  fi

  for pid in $(cat "${path_kthread}" | awk 'NR>1 {print $2}'); do
    echo ${pid} > ${path_cpuset}
  done
}

configure_sys_params() {
  local direct_swappiness=60
  local vm_swappiness=160

  logi "config sys params"
  echo 1 > "/proc/oplus_mem/mask_kswapd_reclaim"
  echo "direct_swappiness=${direct_swappiness}" > "/proc/oplus_mem/swappiness_para"
  echo "vm_swappiness=${vm_swappiness}" > "/proc/oplus_mem/swappiness_para"
  write_kthread_to_cpuset "/proc/osvelte/bg_kthread" "/dev/cpuset/background/tasks"
  write_kthread_to_cpuset "/proc/osvelte/kswapd_like_kthread" "/dev/cpuset/kswapd-like/tasks"
}

write_hybridswap_errcode() {
  setprop persist.sys.oplus.nandswap.err "$1"
  setprop persist.sys.oplus.nandswap.condition false
}

init_zram() {
  local zram_increase_limit=0
  local magic=32758
  local comp_algorithm="lz4"
  # if user disable hybridswap or some err condtion, force enable hybridswap
  local force_enable="false"
  local hybridswap_enable=$(getprop persist.sys.oplus.nandswap)

  if [[ $(getprop sys.oplus.nandswap.init) == "true" ]]; then
    logi "zram already init, just return"
    return
  fi

  setprop sys.oplus.nandswap.init true

  local nandswap_sz=0

  if [[ ${hybridswap_enable} == "true" ]]; then
    # calc nandswap_sz & set hybridswap prop
    /product/bin/nandswap_tool -r "/odm/etc/hybridswap.cfg"
    # os 15.x use partition, one possible error is storage is full. ignore this.
    local condition=$(getprop persist.sys.oplus.nandswap.condition)
    if [[ ${condition} == "true" ]]; then
      nandswap_sz=$(( $(getprop persist.sys.oplus.nandswap.swapsize.curr) * 1024 ))

      if [[ ${nandswap_sz} -gt ${zram_increase_limit} ]]; then
        nandswap_sz=${zram_increase_limit}
      fi
    else
      # setting app use this value.
      write_hybridswap_errcode "${HYB_ERR_UNSET}"
      setprop persist.sys.oplus.nandswap.swapsize.curr 0
      hybridswap_enable="false"
    fi
  else
    write_hybridswap_errcode "${HYB_ERR_UNSET}"
    setprop persist.sys.oplus.nandswap.swapsize.curr 0
    hybridswap_enable="false"
  fi

  logi "setup zram"
  #1 stage1: setup zram
  if [[ $MEM_TOTAL -le 524288 ]]; then
    #config 384MB zramsize with ramsize 512MB
    swap_size_mb=384
  elif [[ $MEM_TOTAL -le 1048576 ]]; then
    #config 768MB zramsize with ramsize 1GB
    swap_size_mb=768
  elif [[ $MEM_TOTAL -le 2097152 ]]; then
    #config 1GB+256MB zramsize with ramsize 2GB
    swap_size_mb=1280
  elif [[ $MEM_TOTAL -le 3145728 ]]; then
    #config 1GB+512MB zramsize with ramsize 3GB
    swap_size_mb=1536
  elif [[ $MEM_TOTAL -le 4194304 ]]; then
    #config 2GB+512MB zramsize with ramsize 4GB
    swap_size_mb=2560
  elif [[ $MEM_TOTAL -le 6291456 ]]; then
    #config 3GB zramsize with ramsize 6GB
    swap_size_mb=3072
  elif [[ $MEM_TOTAL -le 8388608 ]]; then
    #config 5GB zramsize with ramsize 8GB
    swap_size_mb=5632
  elif [[ $MEM_TOTAL -le 12582912 ]]; then
    #config 5GB zramsize with ramsize 12GB
    swap_size_mb=12288
  else
    #config 7GB zramsize with ramsize 16GB or larger devices
    swap_size_mb=12288
  fi

  local disksize=${swap_size_mb}

  if [[ ${hybridswap_enable} == "false" ]] && [[ ${force_enable} == "true" ]]; then
    logi "hybridswap force enable"
    nandswap_sz=${zram_increase_limit}
  fi
  disksize=$(( ${swap_size_mb} + ${nandswap_sz} ))

  logi "swapon zram disk_size: ${disksize} algo: ${comp_algorithm}"
  echo "${comp_algorithm}" > /sys/block/zram0/comp_algorithm
  echo "${disksize}M" > /sys/block/zram0/disksize
  mkswap /dev/block/zram0
  swapon /dev/block/zram0 -p $magic

  if [[ ! -f "/sys/block/zram0/hybridswap_core_enable" ]]; then
    write_hybridswap_errcode "${HYB_ERR_UNSUPPORTED}"
    return
  fi
  if [[ ${hybridswap_enable} == "false" ]] && [[ ${force_enable} == "false" ]]; then
    logi "hybridswap is in inavlid state"
    return
  fi

  logi "init hybridswapd"
  local memcg_root_path="/sys/fs/cgroup/"
  local threshold_wakeup_hybridswapd="0 0 0 0"
  local zram_root_path="/sys/block/zram0/"
  local hybridswap_partition="/dev/block/by-name/hybridswap"
  local hybridswap_crypto_partition="/dev/block/mapper/hybridswap_crypto"

  if [[ ! -L "${hybridswap_partition}" ]]; then
    return
  fi
  if [[ -L ${hybridswap_crypto_partition} ]]; then
    hybridswap_partition="${hybridswap_crypto_partition}"
  fi

  # disable memcg before hybridswap setup
  setprop persist.sys.oplus.hybridswap_app_memcg false
  setprop persist.sys.oplus.hybridswap_app_uid_memcg false
  chmod o+w $(ls -l ${zram_root_path}/hybridswap_* | grep ^'\-rw\-' | awk '{print $NF}')
  echo "apps" > "${memcg_root_path}/apps/memory.name"
  echo "300" > "${memcg_root_path}/apps/memory.app_score"
  echo "3 0 99 0 0 0 100 399 80 0 0 400 499 70 0 0 " > "${memcg_root_path}/memory.swapd_memcgs_param"
  echo "400" > "${memcg_root_path}/memory.app_score"
  echo "root" > "${memcg_root_path}/memory.name"
  echo "${threshold_wakeup_hybridswapd}" > "${memcg_root_path}/memory.avail_buffers"
  echo "${zram_critical_threshold}" > "${memcg_root_path}/memory.zram_critical_threshold"
  echo "50" > "${memcg_root_path}/memory.swapd_max_reclaim_size"
  echo "1000 50" > "${memcg_root_path}/memory.swapd_shrink_parameter"
  echo "5000" > "${memcg_root_path}/memory.max_skip_interval"
  echo "50" > "${memcg_root_path}/memory.reclaim_exceed_sleep_ms"
  echo "60" > "${memcg_root_path}/memory.cpuload_threshold"
  echo "30" > "${memcg_root_path}/memory.max_reclaimin_size_mb"
  echo "80" > "${memcg_root_path}/memory.zram_wm_ratio"
  echo "512" > "${memcg_root_path}/memory.empty_round_skip_interval"
  echo "20" > "${memcg_root_path}/memory.empty_round_check_threshold"
  echo -n "${hybridswap_partition}" > "${zram_root_path}/hybridswap_loop_device"
  echo "1" > "${zram_root_path}/hybridswap_enable"
  echo "1" > "${zram_root_path}/hybridswap_reclaim_in_enable"
  echo "${nandswap_sz}" > "${zram_root_path}/hybridswap_zram_increase"
  echo "1" > "${zram_root_path}/hybridswap_loglevel"

  logi "init memcg"
  # if osense memcg already set, do nothing
  if [[ $(getprop ro.oplus.osense_app_memcg) == "true" ]]; then
    return
  fi
  # memcg enable
  setprop persist.sys.oplus.hybridswap_app_memcg true
  # enable app uid memcg if ram_size greater than 6Gib
  if [[ ${MEM_TOTAL} -gt 6291456 ]]; then
    setprop persist.sys.oplus.hybridswap_app_uid_memcg true
  fi
}

configure_aizerofs_parameters() {
  local aizerofs_supported=0
  local aizerofs_rus_disable=`cat /sys/module/oplus_bsp_aizerofs/parameters/rus_disable`
  local my_engineering_type=$(getprop ro.oplus.image.my_engineering.type)

  if [ -e "/sys/module/oplus_bsp_aizerofs/parameters/enabled" ]; then
    aizerofs_supported=1
  fi

  logi "config aizerofs params"
  if [ "$aizerofs_supported" -eq "1" ]; then
    local val=0
    if [ "$my_engineering_type" != "release" ]; then
      val=1
    fi
    echo $val > /sys/kernel/aizerofs/bug_on

    if [ "$aizerofs_rus_disable" -ne "1" ]; then
      logi "aizerofs enabled"
      echo 1 > /sys/module/oplus_bsp_aizerofs/parameters/enabled

      if [ "$aizerofs_rus_disable" -ne "2" ]; then
        logi "aizerofs write_enabled"
        echo 1 > /sys/module/oplus_bsp_aizerofs/parameters/write_enabled
      fi
    fi
  fi
}

configure_hwzram_params() {
  local hwzram_disable=$(getprop persist.sys.oplus.hwzram.disable)

  if [ $hwzram_disable -eq 1 ]; then
  logi "mvpu disabled"
    echo "swonly" > /sys/block/zram0/comp_mode
  else
    echo "mvpu" > /sys/block/zram0/comp_mode
    echo "100" > /sys/block/zram0/mvpu_hard_limit
  fi
}

main() {
  configure_sys_params
  configure_hwzram_params
  init_zram
  configure_aizerofs_parameters
}
main "$@"
