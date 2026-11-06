#!/system/bin/sh
echo "oplus sensor try to insmod oplus_data_record ko" > /dev/kmsg
if lsmod | grep -q "^oplus_data_record "; then
    echo "oplus_data_record ko already loaded" > /dev/kmsg
    exit 0
fi
insmod vendor/lib/modules/oplus_data_record.ko