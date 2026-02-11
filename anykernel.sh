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

### AnyKernel install

## Boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto

# Import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

## Simplified deep cleanup (silent mode with progress)
deep_kernel_cleanup() {
    ui_print "- Deep cleaning old kernel configs..."
    
    # Clean all in one pass (silent)
    {
        # Module deps & cache
        [ -d /data/vendor/modules ] && rm -rf /data/vendor/modules/modules.* /data/vendor/modules/*.bin
        
        # Sysctl & scheduler configs
        [ -d /data/vendor/sysctl ] && rm -rf /data/vendor/sysctl/*
        [ -d /data/vendor/scheduler ] && rm -rf /data/vendor/scheduler/*
        rm -f /data/local/kernel.sysctl /data/vendor/etc/sysctl.d/*.conf
        
        # Reset schedtune if exists
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
    
    ui_print "  ✓ Cleanup complete"
}

## Auto-detect boot partition (MediaTek & Qualcomm compatible)
backup_boot_image() {
    backup_dir="/sdcard/TemplarKernel_Backup"
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir" 2>/dev/null
    
    # Save current kernel info
    uname -a > "$backup_dir/OLD_kernel_${timestamp}.info" 2>/dev/null
    
    ui_print "- Creating boot backup..."
    
    boot_partition=""
    detection_method=""
    
    # Method 1: Use $bootimg from ak3-core.sh (set by split_boot)
    if [ -n "$bootimg" ] && [ -b "$bootimg" ]; then
        boot_partition="$bootimg"
        detection_method="ak3-core"
    fi
    
    # Method 2: Check current slot (A/B devices)
    if [ -z "$boot_partition" ]; then
        current_slot=$(getprop ro.boot.slot_suffix 2>/dev/null)
        if [ -n "$current_slot" ]; then
            # Try boot with slot suffix (boot_a or boot_b)
            for base in "/dev/block/bootdevice/by-name" "/dev/block/by-name" "/dev/block/platform/*/by-name" "/dev/block/platform/*/*/by-name"; do
                for path in ${base}/boot${current_slot} ${base}/boot; do
                    if [ -b "$path" ] 2>/dev/null; then
                        boot_partition="$path"
                        detection_method="slot-aware ($current_slot)"
                        break 2
                    fi
                done
            done
        fi
    fi
    
    # Method 3: MediaTek specific paths
    if [ -z "$boot_partition" ]; then
        # Check MediaTek common paths
        for path in \
            "/dev/block/platform/bootdevice/by-name/boot" \
            "/dev/block/platform/soc/*/by-name/boot" \
            "/dev/block/platform/soc/*/*/by-name/boot" \
            "/dev/block/by-name/boot_para" \
            "/dev/block/mmcblk0boot0" \
            "/dev/block/mmcblk0boot1"; do
            
            # Expand wildcards
            for expanded in $path; do
                if [ -b "$expanded" ] 2>/dev/null; then
                    boot_partition="$expanded"
                    detection_method="mediatek-path"
                    break 2
                fi
            done
        done
    fi
    
    # Method 4: Aggressive search via find (last resort)
    if [ -z "$boot_partition" ]; then
        # Search for any partition named "boot*"
        boot_partition=$(find /dev/block -type b -name "boot*" 2>/dev/null | grep -E "boot$|boot_[ab]$|boot_para$|mmcblk.*boot" | head -1)
        if [ -n "$boot_partition" ] && [ -b "$boot_partition" ]; then
            detection_method="aggressive-search"
        else
            boot_partition=""
        fi
    fi
    
    # Method 5: Parse /proc/mounts or /proc/partitions
    if [ -z "$boot_partition" ]; then
        # Check if boot is mounted (shouldn't be, but check anyway)
        boot_partition=$(grep -m1 " boot " /proc/mounts 2>/dev/null | awk '{print $1}')
        if [ -n "$boot_partition" ] && [ -b "$boot_partition" ]; then
            detection_method="proc-mounts"
        else
            # Try /proc/partitions
            boot_line=$(grep -iE "boot|mmcblk.*boot" /proc/partitions 2>/dev/null | tail -1 | awk '{print $4}')
            if [ -n "$boot_line" ]; then
                boot_partition="/dev/block/$boot_line"
                if [ -b "$boot_partition" ]; then
                    detection_method="proc-partitions"
                else
                    boot_partition=""
                fi
            fi
        fi
    fi
    
    # Perform backup if boot partition found
    if [ -n "$boot_partition" ] && [ -b "$boot_partition" ]; then
        ui_print "  • Boot found: $boot_partition"
        ui_print "    Method: $detection_method"
        
        backup_file="$backup_dir/OLD_boot_${timestamp}.img"
        
        # Execute dd with progress (suppress records output)
        dd if="$boot_partition" of="$backup_file" bs=4096 2>&1 | grep -v "records"
        
        # Verify backup
        if [ -f "$backup_file" ]; then
            backup_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null || echo 0)
            backup_mb=$((backup_size / 1048576))
            
            if [ "$backup_size" -gt 1048576 ]; then
                ui_print "  ✓ Backup saved: ${backup_mb}MB"
                
                # Save boot partition path for recovery instructions
                echo "Boot partition: $boot_partition" >> "$backup_dir/OLD_kernel_${timestamp}.info"
                echo "Detection method: $detection_method" >> "$backup_dir/OLD_kernel_${timestamp}.info"
            else
                ui_print "  ✗ Backup too small (${backup_mb}MB), removing"
                rm -f "$backup_file"
            fi
        else
            ui_print "  ✗ Backup failed (file not created)"
        fi
    else
        ui_print "  ! Boot partition not detected"
        ui_print "    Device: $(getprop ro.product.board 2>/dev/null || echo 'Unknown')"
        ui_print "    Searching common MediaTek paths failed"
        ui_print "    Kernel info saved, boot backup skipped"
        
        # Debug info
        ui_print " "
        ui_print "  Debug Info (for developer):"
        ui_print "    • Current slot: $(getprop ro.boot.slot_suffix 2>/dev/null || echo 'none')"
        ui_print "    • Board: $(getprop ro.product.board 2>/dev/null)"
        ui_print "    • Available boot* partitions:"
        find /dev/block -name "boot*" 2>/dev/null | head -5 | while read p; do
            ui_print "      $p"
        done
    fi
    
    ui_print " "
}


## Simplified version check
check_kernel_version() {
    current_kernel=$(uname -r 2>/dev/null | cut -d'.' -f1-2)
    [ -z "$current_kernel" ] && current_kernel=$(cat /proc/version 2>/dev/null | awk '{print $3}' | cut -d'.' -f1-2)
    
    new_kernel_string=$(strings "$home"/Image 2>/dev/null | grep -m1 'Linux version' | awk '{print $3}' | cut -d'.' -f1-2)
    [ -z "$new_kernel_string" ] && new_kernel_string=$(strings "$home"/Image 2>/dev/null | grep -m1 '5\.10\.' | cut -d'.' -f1-2)
    [ -z "$new_kernel_string" ] && new_kernel_string="5.10"
    
    current_major=$(echo "$current_kernel" | cut -d'.' -f1)
    current_minor=$(echo "$current_kernel" | cut -d'.' -f2)
    new_major=$(echo "$new_kernel_string" | cut -d'.' -f1)
    new_minor=$(echo "$new_kernel_string" | cut -d'.' -f2)
    
    ui_print "- Version: $current_kernel → $new_kernel_string"
    
    if [ "$current_major" = "5" ] && [ "$current_minor" = "10" ] && [ "$new_major" = "5" ] && [ "$new_minor" = "10" ]; then
        strings "$home"/Image 2>/dev/null | grep -q "SCHED_BORE" && ui_print "  ✓ SchedBORE enabled"
        strings "$home"/Image 2>/dev/null | grep -iq "ssg" && ui_print "  ✓ SSG I/O scheduler enabled"
        return 0
    elif [ "$new_major" = "5" ] && [ "$new_minor" = "10" ]; then
        ui_print "  ! Warning: Base mismatch, proceeding anyway"
        sleep 1
        return 0
    else
        ui_print " "
        ui_print "✗ INCOMPATIBLE: Requires GKI 5.10 kernel base"
        ui_print "  Current: $current_major.$current_minor | Target: $new_major.$new_minor"
        exit 1
    fi
}

## Minimal post-install validation
post_install_check() {
    # Verify boot partition after flash
    if [ -n "$bootimg" ] && [ -b "$bootimg" ]; then
        boot_size=$(stat -c%s "$bootimg" 2>/dev/null || echo 0)
        if [ "$boot_size" -gt 0 ]; then
            ui_print "  ✓ Boot partition verified"
        else
            ui_print "  ! Warning: Boot partition check failed"
        fi
    fi
    
    # Verify new kernel Image integrity
    if [ -f "$home/Image" ]; then
        kernel_size=$(stat -c%s "$home/Image" 2>/dev/null || echo 0)
        kernel_mb=$((kernel_size / 1048576))
        
        if [ "$kernel_size" -gt 10485760 ]; then
            ui_print "  ✓ Kernel Image: ${kernel_mb}MB"
        else
            ui_print "  ! Warning: Kernel Image too small"
        fi
    fi
}

## Silent post-boot script setup
set_postflash_configs() {
    mkdir -p /data/adb/service.d 2>/dev/null
    
    cat > /data/adb/service.d/templar_kernel_init.sh << 'EOF'
#!/system/bin/sh
LOGFILE="/data/local/tmp/templar_init.log"
{
    echo "==================================="
    echo "Templar Kernel Post-Boot Init"
    echo "Timestamp: $(date)"
    echo "==================================="
    echo ""
    
    # Wait for system boot completion
    sleep 30
    
    echo "Checking kernel features..."
    
    # Verify SchedBORE
    if [ -f /proc/sys/kernel/sched_bore ]; then
        echo "✓ SchedBORE: Active"
        echo "  Value: $(cat /proc/sys/kernel/sched_bore 2>/dev/null)"
    else
        echo "✗ SchedBORE: Not found"
    fi
    
    echo ""
    echo "Checking I/O schedulers..."
    
    # Verify I/O schedulers
    for queue in /sys/block/*/queue/scheduler; do
        if [ -f "$queue" ]; then
            device=$(dirname $(dirname $queue) | xargs basename)
            current=$(cat "$queue" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
            echo "  $device: $current"
        fi
    done
    
    echo ""
    echo "Clearing lingering cache..."
    
    # Clear any lingering kernel cache
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    
    echo ""
    echo "✓ Post-boot initialization complete"
    echo "==================================="
    
    # Self-destruct (run only once after flash)
    rm -f /data/adb/service.d/templar_kernel_init.sh
    
} > "$LOGFILE" 2>&1

# Create notification (if supported)
if [ -f /system/bin/cmd ]; then
    /system/bin/cmd notification post -S bigtext -t "Templar Kernel" "Tag" "Kernel initialized successfully. Check log: $LOGFILE" 2>/dev/null
fi
EOF
    
    chmod 755 /data/adb/service.d/templar_kernel_init.sh 2>/dev/null
}

## ==============================================
## MAIN INSTALLATION FLOW
## ==============================================

ui_print " "
ui_print "================================================"
ui_print " Templar Kernel Installer"
ui_print "================================================"

# Step 1: Version check (before any modifications)
check_kernel_version

# Step 2: Deep cleanup (before flashing)
deep_kernel_cleanup

ui_print " "
ui_print "- Preparing boot partition..."

## Begin boot install
split_boot  # This detects and extracts boot partition

# Step 3: Backup OLD boot (AFTER split_boot when $bootimg is available)
backup_boot_image

ui_print "- Flashing new kernel..."

# Extract and display kernel info
kernel_version=$(strings "$home"/Image 2>/dev/null | grep -m1 'Linux version' | awk '{print $3}')
ui_print "  Installing: $kernel_version"

flash_boot  # Flash new kernel
## End boot install

ui_print " "

# Step 4: Post-install validation
post_install_check

# Step 5: Setup post-boot script
set_postflash_configs

ui_print " "
ui_print "================================================"
ui_print " ✓ Installation Complete"
ui_print "================================================"
ui_print "  • Kernel flashed & configs cleaned"
ui_print "  • Backup: /sdcard/TemplarKernel_Backup"
ui_print "  • Post-boot script configured"
ui_print " "
ui_print "Next Steps:"
ui_print "  1. Reboot device now"
ui_print "  2. Wait 1-2 minutes for initialization"
ui_print "  3. Check: /data/local/tmp/templar_init.log"
ui_print " "
ui_print "If bootloop occurs:"
ui_print "  • Boot to recovery"
ui_print "  • Flash: OLD_boot_XXXXXX.img from backup folder"
ui_print "================================================"
ui_print " "

## End of install
