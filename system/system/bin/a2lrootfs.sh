#!/system/bin/sh
#set -euo pipefail

rootfs="/data/a2lrootfs"
init="oslg"
a2lrootfs_dns_file="$rootfs/etc/resolv.conf"
log_file="$rootfs/mnt/oslg/log/a2lrootfs.log"

bind_img()
{
    local try_time=50
    local do_time=0
    local img_path=null
    local old_devices=$(losetup -a | grep $1 | awk -F: '{print $1}')
    if [ ! -z $old_devices ]; then
        losetup -d $old_devices
    fi

    while [ $(getprop vendor.oplus.pcengine.mount.start) -eq 1 ]
    do
        sleep 0.05
    done

    # 根据镜像名匹配镜像路径
    if [ "$1" = "usr" ]; then
        img_path=/data/a2lrootfs/usrimg
    elif [ "$1" = "kingsoft" ]; then
        img_path=$rootfs/kingsoftimg
    fi
    if [ ! -f $img_path ]; then
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): error: $img_path is not exist" >> $log_file
        return
    fi
    # 尝试固定次数，直到成功或者结束
    while [ $do_time -le $try_time ]
    do
        get_devices=$(losetup -f)
        losetup -r $get_devices $img_path
        if [ $? -eq 0 ]; then
            setprop vendor.oplus.pcengine.img.loopdevice $get_devices
            echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): losetup -r $get_devices $img_path success" >> $log_file
            return
        fi
        ((do_time++))
        sleep 0.02
    done
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): error: bind $1 failed" >> $log_file
    #exit
}

umount_img()
{
    local try_time=50
    local do_time=0
    local img_umount_path=null
    # 根据镜像名匹配镜像路径
    if [ "$1" = "usr" ]; then
        img_umount_path=$rootfs/usr
    elif [ "$1" = "kingsoft" ]; then
        img_umount_path=$rootfs/opt/kingsoft
    fi
    # 尝试固定次数，直到成功或者结束
    while [ $do_time -le $try_time ]
    do
        umount $img_umount_path
        if [ $? -eq 0 ]; then
            echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): umount $img_umount_path success" >> $log_file
            return
        fi
        ((do_time++))
        sleep 0.02
    done
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): error: umount $1 failed" >> $log_file
    #exit
}

mount_img()
{
    local img_mount_path=null
    # 根据镜像名匹配镜像路径
    if [ "$1" = "usr" ]; then
        img_mount_path=$rootfs/usr
        img_path=/data/a2lrootfs/usrimg
    elif [ "$1" = "kingsoft" ]; then
        img_mount_path=$rootfs/opt/kingsoft
        img_path=$rootfs/kingsoftimg
    fi
    if [ ! -f $img_path ]; then
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): error: $img_path is not exist" >> $log_file
        return
    fi
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start mount $img_mount_path" >> $log_file
    setprop vendor.oplus.pcengine.img.mountpath $img_mount_path
    setprop vendor.oplus.pcengine.mount.start 1

    # 循环10次, 每次等待100ms, 总时长1s, 最长1s后检测还未有挂载节点视为挂载失败, 进行wps镜像所有信息回滚到最初状态
    mount_success=0
    for i in $(seq 1 10); do
        if mount | grep -q ${img_mount_path}; then
            mount_success=1
            echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): mount $img_mount_path sucees." >> $log_file
            # 设置挂载成功状态
            setprop vendor.oplus.pcengine.$1.mount 0
            break
        fi
        # 等待100ms
        sleep 0.1
    done

    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): mount mount_success:$mount_success." >> $log_file
    if [ "$mount_success" = "0" ]; then
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): mount $img_mount_path failed, md5sum $img_path = $(md5sum $img_path)." >> $log_file
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): mount $img_mount_path failed, du -sh $img_path = $(du -sh $img_path)." >> $log_file
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): mount $img_mount_path failed, Check if the image is damaged: file $img_path = $(file $img_path)" >> $log_file
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): mount $img_mount_path failed, reset it." >> $log_file
        rm -f $img_path $img_path.md5 $img_path.version
        touch $img_path $img_path.md5 $img_path.version
        chmod 666 $img_path $img_path.md5 $img_path.version
        # 设置挂载失败状态
        setprop vendor.oplus.pcengine.$1.mount 1
    fi
}

set_a2lrootfs_version()
{
    local a2lrootfs_version=$(cat $rootfs/etc/version.txt | sed 's/a2lrootfs-\([0-9]*\)\.tgz/\1/')
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): setup env_version: $a2lrootfs_version" >> $log_file
    setprop ro.vendor.oplus.pcengine.a2lrootfs.version $a2lrootfs_version
}

set_a2lrootfs_dns()
{
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start setup dns" >> $log_file
    local a2lrootfs_dns=$(getprop persist.vendor.oplus.pcengine.a2lrootfs.dns)
    echo "nameserver 114.114.114.114" > $a2lrootfs_dns_file
    for dns in $a2lrootfs_dns; do
        echo "nameserver $dns" >> $a2lrootfs_dns_file
    done
}

check_if_oppo_dir_set_uid()
{
    # for wps fonts
    mkdir -p $rootfs/home/oppo/.local/share/Kingsoft/office6/docerFonts
    chown 7102:7102 -R $rootfs/home/oppo
    [ ! -f $log_file ] && touch $log_file
    chown 7102:7102 -R $rootfs/mnt/oslg
    chmod 666 $log_file
    chown 7102:7102 -R $rootfs/run/user
    chmod 777 -R $rootfs/home/
}

release_wps_files()
{
    if [[ ! -e "/data/a2lrootfs/kingsoftimg"
          || ! -e "/data/a2lrootfs/kingsoftimg.md5"
          || ! -e "/data/a2lrootfs/kingsoftimg.version" ]]; then
        rm -f /data/a2lrootfs/kingsoftimg /data/a2lrootfs/kingsoftimg.md5 /data/a2lrootfs/kingsoftimg.version
        touch /data/a2lrootfs/kingsoftimg /data/a2lrootfs/kingsoftimg.md5 /data/a2lrootfs/kingsoftimg.version
        chmod 666 /data/a2lrootfs/kingsoftimg /data/a2lrootfs/kingsoftimg.md5 /data/a2lrootfs/kingsoftimg.version
    fi
    if [[ ! -e "/data/a2lrootfs/usrimg"
          || ! -e "/data/a2lrootfs/usrimg.md5"
          || ! -e "/data/a2lrootfs/usrimg.version" ]]; then
        rm -f /data/a2lrootfs/usrimg /data/a2lrootfs/usrimg.md5 /data/a2lrootfs/usrimg.version
        touch /data/a2lrootfs/usrimg /data/a2lrootfs/usrimg.md5 /data/a2lrootfs/usrimg.version
        chmod 666 /data/a2lrootfs/usrimg /data/a2lrootfs/usrimg.md5 /data/a2lrootfs/usrimg.version
    fi
    if [[ ! -e "/data/a2lrootfs/a2lrootfs.tgz" ]]; then
        rm -f /data/a2lrootfs/a2lrootfs.tgz
        touch /data/a2lrootfs/a2lrootfs.tgz
        chmod 666 /data/a2lrootfs/a2lrootfs.tgz
    fi
}

release_root_dir()
{
    local appconfig_filepath="$rootfs/home/oppo/.config/"
    local apps_filename="Kingsoft user-dirs.dirs"
    # app配置备份
    for app in $apps_filename
    do
        if [ -d "$appconfig_filepath/$app" ]; then
            rm -rf $appconfig_filepath/$app-bak
            mv $appconfig_filepath/$app $appconfig_filepath/$app-bak
        fi
    done
    # 配置容器根目录环境
    tar -xf  $rootfs/$1 -C $rootfs
    if [ $? -eq 0 ]; then
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): root_file_system tar success" >> $log_file
    else
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): root_file_system tar failed" >> $log_file
    fi

    # app配置文件恢复
    for app in $apps_filename
    do
        if [ -d "$appconfig_filepath/$app-bak" ]; then
            rm -rf $appconfig_filepath/$app
            mv $appconfig_filepath/$app-bak $appconfig_filepath/$app
        fi
    done

    # 默认设置
    # hosts
    if [ -e "$rootfs/etc/hosts" ]; then
        echo "127.0.0.1 localhost" > $rootfs/etc/hosts
    fi

    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): release_root_dir end" >> $log_file

    # dns
    set_a2lrootfs_dns
}

check_if_release_root_dir()
{
    local version_file="$rootfs/etc/version.txt"
    local old_env_version=$(cat $rootfs/etc/version.txt | sed 's/a2lrootfs-\([0-9]*\)\.tgz/\1/')
    local latest_env_version=$(cat $rootfs/usrimg.version)
    if [ -f $version_file ]; then
        if [[ "$old_env_version" < "$latest_env_version" ]]; then
            echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start update the root file system" >> $log_file
            release_root_dir "a2lrootfs.tgz"
        fi
    else
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start setting up the root file system" >> $log_file
        release_root_dir "a2lrootfs.tgz"
    fi
    release_wps_files
}

release_base_env()
{
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start mount imgs" >> $log_file
    rm -rf $rootfs/tmp/*
    mkdir -p $rootfs/tmp/osl/rdp
    chmod -R 0755 $rootfs/tmp/osl

    # 设置容器根目录tar包版本号
    set_a2lrootfs_version
}

start_container()
{
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start oslg" >> $log_file

    rm $rootfs/tmp/android17/osl/rdp/server_ctl
    rm $rootfs/tmp/android17/osl/rdp/client_ctl

    # 启动容器守护进程
    rm -rf $rootfs/home/oppo/core
    export TMPDIR=/tmp/android17/osl/rdp
    debug_switch=$(getprop persist.sys.assert.panic)
    if [ "$debug_switch" == "true" ]; then
        debug_switch="1"
    else
        debug_switch="0"
    fi
    weston_logex=$(getprop vendor.oplus.pcengine.container.weston.logex)
    screen_dpi=$(getprop vendor.oplus.pcengine.screen_config)
    window_cfg=$(getprop vendor.oplus.pcengine.wps_container_config)
    chroot $rootfs /bin/su - root -c "/bin/oslg --dbglog.switch='$debug_switch' --weston.logex='$weston_logex' --screen.dpi='$screen_dpi' --window.cfg='$window_cfg'"
}

start_healthcheck()
{
    local pcengine_health=$(getprop vendor.oplus.pcengine.health)
    local check_count=$(getprop vendor.oplus.pcengine.heartbeat)
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): Start healthcheck: $check_count with health: $pcengine_health" >> $log_file
    while [ $pcengine_health -gt 0 ]
    do
        ((pcengine_health--))
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): Set health-- : $pcengine_health and sleep 60s" >> $log_file
        setprop vendor.oplus.pcengine.health $pcengine_health
        sleep 60
        ((check_count++))
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): Set check++ : $check_count and Start next healthcheck" >> $log_file
        setprop vendor.oplus.pcengine.heartbeat $check_count
        pcengine_health=$(getprop vendor.oplus.pcengine.health)
    done
    if [ $pcengine_health -eq 0 ]; then
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): Stop container for health : $pcengine_health and End healthcheck" >> $log_file
        setprop vendor.oplus.pcengine.container.start 0
    fi
}

update_app_version()
{
    # 要更新的镜像完整镜像名
    local update_app_name=$(getprop vendor.oplus.pcengine.app.update)
    local if_update_running=$(getprop vendor.oplus.pcengine.update.state)
    local img_mount_path=null
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): Start update img: $update_app_name." >> $log_file
    setprop vendor.oplus.pcengine.container.start 0
    # 根据镜像名匹配镜像路径
    if [ "$update_app_name" = "usr" ]; then
        img_mount_path=$rootfs/usr
    elif [ "$update_app_name" = "kingsoft" ]; then
        img_mount_path=$rootfs/opt/kingsoft
    fi
    while [ "$if_update_running" = "running" ]
    do
        sleep 0.5
        if_update_running=$(getprop vendor.oplus.pcengine.update.state)
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): Wait for update end." >> $log_file
    done
    setprop vendor.oplus.pcengine.update.state running
    # 解挂载对应镜像
    if mount | grep -q $img_mount_path; then
        umount_img $update_app_name
    fi
    # 重新绑定loop设备
    bind_img $update_app_name
    # 重新挂载镜像
    mount_img $update_app_name

    # 更新结束
    setprop vendor.oplus.pcengine.update.state end
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): Update $update_app_name end." >> $log_file
}

clean_appdata()
{
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start cleanup app data" >> $log_file
    if [ "$(getprop vendor.oplus.pcengine.app.clean)" = "kingsoft" ]; then
        clean_dir="Kingsoft"
    else
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): error: please check which app need be clean" >> $log_file
        return
    fi
    rm -rf $rootfs/home/oppo/.config/$clean_dir
#    rm -rf $rootfs/home/oppo/.local/share/$clean_dir
    cp -raf $rootfs/root/.config/$clean_dir $rootfs/home/oppo/.config/
    chmod 777 -R $rootfs/home/oppo/.config/$clean_dir
    chown 7102:7102 -R $rootfs/home/oppo/.config/$clean_dir

    setprop vendor.oplus.pcengine.container.start 0
    setprop vendor.oplus.pcengine.app.cleandone kingsoft
}

unistall_app()
{
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start uninstall app" >> $log_file
    local uninstall_app_name=$(getprop vendor.oplus.pcengine.app.uninstall)
    # 清理wps数据
    setprop vendor.oplus.pcengine.app.clean $uninstall_app_name

    # umount APP镜像挂载目录
    umount_img $uninstall_app_name
}

set_timezone()
{
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start setup container timezone" >> $log_file

    # ensure usrimg mounted
    local usrimg_mount_path=$rootfs/usr
    for i in `seq 1 100`; do
        echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): set_timezone usrimg round: $i." >> $log_file
        ls $rootfs/usr/share/zoneinfo
        if [ "$?" = "0" ]; then
            echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): set_timezone usrimg mounted." >> $log_file
            break
        fi

        # 等待 500ms
        sleep 0.5
    done

    local timezone=$(getprop persist.sys.timezone)
    rm $rootfs/etc/localtime
    chroot $rootfs/ /usr/bin/ln -s /usr/share/zoneinfo/$timezone /etc/localtime
}

inspect_a2lrootfs()
{
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): check imgs mount_state" >> $log_file
    local imgs_mount_path="$rootfs/usr $rootfs/opt/kingsoft"
    for path in $imgs_mount_path
    do
        if ! mount | grep -q $path; then
            imgname=$(basename "$path")
            bind_img $imgname
            mount_img $imgname
        fi
    done
}

reset_a2lrootfs()
{
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start reset container env" >> $log_file
    setprop vendor.oplus.pcengine.container.start 0
    rm -rf $rootfs/{boot,etc,media,mnt,root,run,src,srv,tmp,var,bin,lib,sbin}
    check_if_release_root_dir
    release_base_env
    setprop vendor.oplus.pcengine.container.reset.state 1
}

reset_window_size()
{
    #重置窗口尺寸
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): start reset window size" >> $log_file
    sed -i '\|Application%20Settings\\WindowWidth|d
        \|Application%20Settings\\WindowHeight|d' $rootfs/home/oppo/.config/Kingsoft/Office.conf
}

enable_channel()
{
    #使能通道
    mkfifo $rootfs/tmp/android17/osl/ads
    chmod 777 $rootfs/tmp/android17/osl/ads
    chown root:7102 $rootfs/tmp/android17/osl/ads
    echo start > $rootfs/tmp/android17/osl/ads
}

save_network_logs()
{
    chroot $rootfs /bin/su - root -c '/bin/save_network_logs.sh'
}

if [ "$1" = "check_if_release_root_dir" ]; then
    check_if_release_root_dir
    check_if_oppo_dir_set_uid
    start_time=$(getprop vendor.oplus.pcengine.container.state)
    if [ -z "$start_time" ]; then
        release_base_env
        setprop vendor.oplus.pcengine.container.state 1
    else
        setprop vendor.oplus.pcengine.container.state 2
    fi
elif [ "$1" = "start_container" ]; then
    inspect_a2lrootfs
    set_timezone
    start_container
elif [ "$1" = "start_healthcheck" ]; then
    start_healthcheck
elif [ "$1" = "update_app_version" ]; then
    update_app_version
elif [ "$1" = "clean_appdata" ]; then
    clean_appdata
elif [ "$1" = "unistall_app" ]; then
    unistall_app
elif [ "$1" = "set_a2lrootfs_dns" ]; then
    set_a2lrootfs_dns
elif [ "$1" = "set_timezone" ]; then
    set_timezone
elif [ "$1" = "reset_a2lrootfs" ]; then
    reset_a2lrootfs
elif [ "$1" = "release_wps_files" ]; then
    release_wps_files
elif [ "$1" = "reset_window_size" ]; then
    reset_window_size
elif [ "$1" = "enable_channel" ]; then
    enable_channel
elif [ "$1" = "save_network_logs" ]; then
    save_network_logs
else
    echo "$(date +%Y-%m-%d_%H:%M:%S.%3N): Please use the correct parameters: $1." >> $log_file
fi
