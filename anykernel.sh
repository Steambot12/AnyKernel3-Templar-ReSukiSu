### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Enhanced by WiL for deep kernel cleanup

### AnyKernel setup
# Global properties
properties() { '
kernel.string=Templar Kernel by WiL (@Steambot12)
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### Kernel identification
KERNEL_NAME="Templar"
KERNEL_AUTHOR="WiL"

### AnyKernel install
## Boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto

# Import functions/variables and setup patching
. tools/ak3-core.sh

## Deep cleanup (silent mode)
deep_kernel_cleanup() {
    ui_print "→ Cleaning old kernel configs..."
    
    {
        # Module deps & cache
        [ -d /data/vendor/modules ] && rm -rf /data/vendor/modules/modules.* /data/vendor/modules/*.bin
        
        # Sysctl & scheduler configs
        [ -d /data/vendor/sysctl ] && rm -rf /data/vendor/sysctl/*
        [ -d /data/vendor/scheduler ] && rm -rf /data/vendor/scheduler/*
        rm -f /data/local/kernel.sysctl /data/vendor/etc/sysctl.d/*.conf
        
        # Reset schedtune
        [ -d /dev/stune ] && for d in /dev/stune/*/; do
            echo 0 > "${d}schedtune.boost" 2>/dev/null
            echo 0 > "${d}schedtune.prefer_idle" 2>/dev/null
        done
        
        # I/O scheduler reset
        [ -d /data/vendor/iosched ] && rm -rf /data/vendor/iosched/*
        for q in /sys/block/*/queue/scheduler; do
            [ -f "$q" ] && echo "none" > "$q" 2>/dev/null
        done
        
        # CPUFreq & thermal
        [ -d /data/vendor/cpufreq ] && rm -rf /data/vendor/cpufreq/*
        [ -d /data/system/cpufreq ] && rm -rf /data/system/cpufreq/*
        [ -d /data/vendor/thermal ] && rm -rf /data/vendor/thermal/*
        [ -d /data/vendor/thermal_config ] && rm -f /data/vendor/thermal_config/*.conf
        
        # Kernel cache & logs
        [ -d /data/vendor/kernel ] && rm -rf /data/vendor/kernel/*
        [ -d /data/kernel ] && rm -rf /data/kernel/*
        dmesg -c > /dev/null 2>&1
        
        # BPF/eBPF cleanup
        if [ -d /sys/fs/bpf ]; then
            umount /sys/fs/bpf 2>/dev/null
            mount -t bpf bpf /sys/fs/bpf 2>/dev/null
        fi
        [ -d /data/vendor/bpf ] && rm -f /data/vendor/bpf/*.o /data/vendor/bpf/*.prog
        
        # Network & temp files
        [ -d /data/vendor/netd ] && rm -f /data/vendor/netd/.*.configured
        rm -rf /data/local/tmp/kernel* /data/local/tmp/*.ko /data/local/tmp/kern_*.log
        rm -f /cache/kernel* /data/cache/kernel /data/bootconfig
        
        sync
    } 2>/dev/null
}

## Auto-detect and backup boot partition
backup_boot_image() {
    backup_dir="/sdcard/${KERNEL_NAME}Kernel_Backup"
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir" 2>/dev/null
    
    # Save current kernel info
    uname -a > "$backup_dir/${KERNEL_NAME}-PreviousKernel_${timestamp}.info" 2>/dev/null
    
    ui_print "→ Creating boot backup..."
    
    boot_partition=""
    detection_method=""
    
    # Method 1: Use $bootimg from ak3-core.sh
    if [ -n "$bootimg" ] && [ -b "$bootimg" ]; then
        boot_partition="$bootimg"
        detection_method="ak3"
    fi
    
    # Method 2: Current slot (A/B devices)
    if [ -z "$boot_partition" ]; then
        current_slot=$(getprop ro.boot.slot_suffix 2>/dev/null)
        if [ -n "$current_slot" ]; then
            for base in "/dev/block/bootdevice/by-name" "/dev/block/by-name" "/dev/block/platform/*/by-name" "/dev/block/platform/*/*/by-name"; do
                for path in ${base}/boot${current_slot} ${base}/boot; do
                    if [ -b "$path" ] 2>/dev/null; then
                        boot_partition="$path"
                        detection_method="slot$current_slot"
                        break 2
                    fi
                done
            done
        fi
    fi
    
    # Method 3: MediaTek paths
    if [ -z "$boot_partition" ]; then
        for path in \
            "/dev/block/platform/bootdevice/by-name/boot" \
            "/dev/block/platform/soc/*/by-name/boot" \
            "/dev/block/platform/soc/*/*/by-name/boot" \
            "/dev/block/by-name/boot_para" \
            "/dev/block/mmcblk0boot0" \
            "/dev/block/mmcblk0boot1"; do
            
            for expanded in $path; do
                if [ -b "$expanded" ] 2>/dev/null; then
                    boot_partition="$expanded"
                    detection_method="mtk"
                    break 2
                fi
            done
        done
    fi
    
    # Method 4: Aggressive search
    if [ -z "$boot_partition" ]; then
        boot_partition=$(find /dev/block -type b -name "boot*" 2>/dev/null | grep -E "boot$|boot_[ab]$|boot_para$|mmcblk.*boot" | head -1)
        if [ -n "$boot_partition" ] && [ -b "$boot_partition" ]; then
            detection_method="search"
        else
            boot_partition=""
        fi
    fi
    
    # Method 5: Proc filesystem
    if [ -z "$boot_partition" ]; then
        boot_partition=$(grep -m1 " boot " /proc/mounts 2>/dev/null | awk '{print $1}')
        if [ -n "$boot_partition" ] && [ -b "$boot_partition" ]; then
            detection_method="proc"
        else
            boot_line=$(grep -iE "boot|mmcblk.*boot" /proc/partitions 2>/dev/null | tail -1 | awk '{print $4}')
            if [ -n "$boot_line" ]; then
                boot_partition="/dev/block/$boot_line"
                [ -b "$boot_partition" ] && detection_method="partition" || boot_partition=""
            fi
        fi
    fi
    
    # Execute backup
    if [ -n "$boot_partition" ] && [ -b "$boot_partition" ]; then
        backup_file="$backup_dir/${KERNEL_NAME}-Backup_${timestamp}.img"
        
        dd if="$boot_partition" of="$backup_file" bs=4096 2>&1 | grep -v "records" | grep -v "bytes"
        
        if [ -f "$backup_file" ]; then
            backup_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null || echo 0)
            backup_mb=$((backup_size / 1048576))
            
            if [ "$backup_size" -gt 1048576 ]; then
                ui_print "  ✓ Backup: ${backup_mb}MB ($detection_method)"
                
                # Save metadata
                {
                    echo "Boot partition: $boot_partition"
                    echo "Detection method: $detection_method"
                    echo "Backup file: ${KERNEL_NAME}-Backup_${timestamp}.img"
                    echo "Backup size: ${backup_mb}MB"
                } >> "$backup_dir/${KERNEL_NAME}-PreviousKernel_${timestamp}.info"
            else
                ui_print "  ✗ Backup failed (size: ${backup_mb}MB)"
                rm -f "$backup_file"
            fi
        else
            ui_print "  ✗ Backup creation failed"
        fi
    else
        ui_print "  ! Boot partition not found"
        ui_print "    Kernel info saved, boot backup skipped"
    fi
}

## Version check
check_kernel_version() {
    current_kernel=$(uname -r 2>/dev/null | cut -d'.' -f1-2)
    [ -z "$current_kernel" ] && current_kernel=$(cat /proc/version 2>/dev/null | awk '{print $3}' | cut -d'.' -f1-2)
    
    new_kernel_string=$(strings "$home"/Image 2>/dev/null | grep -m1 'Linux version' | awk '{print $3}' | cut -d'.' -f1-2)
    [ -z "$new_kernel_string" ] && new_kernel_string=$(strings "$home"/Image 2>/dev/null | grep -m1 '5\\.10\\.' | cut -d'.' -f1-2)
    [ -z "$new_kernel_string" ] && new_kernel_string="5.10"
    
    new_major=$(echo "$new_kernel_string" | cut -d'.' -f1)
    new_minor=$(echo "$new_kernel_string" | cut -d'.' -f2)
    
    ui_print "→ Version: $current_kernel → $new_kernel_string"
    
    if [ "$new_major" != "5" ] || [ "$new_minor" != "10" ]; then
        ui_print "  ✗ ERROR: Requires GKI 5.10 kernel"
        exit 1
    fi
}

## Post-install validation
post_install_check() {
    if [ -f "$home/Image" ]; then
        kernel_size=$(stat -c%s "$home/Image" 2>/dev/null || echo 0)
        kernel_mb=$((kernel_size / 1048576))
        
        if [ "$kernel_size" -gt 10485760 ]; then
            ui_print "  ✓ Kernel flashed: ${kernel_mb}MB"
        else
            ui_print "  ! Warning: Kernel size abnormal"
        fi
    fi
}

## Post-boot script setup
set_postflash_configs() {
    mkdir -p /data/adb/service.d 2>/dev/null
    
    cat > /data/adb/service.d/templar_kernel_init.sh << 'EOF'
#!/system/bin/sh
LOGFILE="/data/local/tmp/templar_init.log"
{
    echo "Templar Kernel Post-Boot Init | $(date)"
    sleep 30
    
    echo "System Info:"
    echo "  Kernel: $(uname -r)"
    echo "  Android: $(getprop ro.build.version.release)"
    
    echo ""
    echo "I/O Schedulers:"
    for q in /sys/block/*/queue/scheduler; do
        [ -f "$q" ] && echo "  $(basename $(dirname $(dirname $q))): $(cat $q | grep -o '\[.*\]' | tr -d '[]')"
    done
    
    echo ""
    echo "Clearing cache..."
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    
    echo ""
    echo "✓ Post-boot init complete"
    
    # Self-destruct
    rm -f /data/adb/service.d/templar_kernel_init.sh
} > "$LOGFILE" 2>&1
EOF
    
    chmod 755 /data/adb/service.d/templar_kernel_init.sh 2>/dev/null
}

## ==============================================
## MAIN INSTALLATION FLOW
## ==============================================

ui_print " "
ui_print "============================================"
ui_print "  ${KERNEL_NAME} Kernel Installer"
ui_print "  by ${KERNEL_AUTHOR}"
ui_print "============================================"
ui_print " "

# Version check
check_kernel_version

# Cleanup
deep_kernel_cleanup

# Begin boot install
ui_print "→ Preparing boot partition..."
split_boot

# Backup old boot
backup_boot_image

# Flash new kernel
ui_print "→ Flashing kernel..."
flash_boot
## End boot install

ui_print " "

# Validation
post_install_check

# Setup post-boot script
set_postflash_configs

ui_print " "
ui_print "============================================"
ui_print "  ✓ Installation Complete"
ui_print "============================================"
ui_print " "
ui_print "  Backup: /sdcard/${KERNEL_NAME}Kernel_Backup"
ui_print " "
ui_print "  Next: Reboot and wait ~2 minutes"
ui_print "  Log: /data/local/tmp/templar_init.log"
ui_print " "
ui_print "  If bootloop:"
ui_print "  → Flash ${KERNEL_NAME}-Backup_*.img"
ui_print " "
ui_print "============================================"
ui_print " "

## End of install
