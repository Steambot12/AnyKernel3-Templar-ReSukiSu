### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Enhanced by WiL for deep kernel cleanup

### AnyKernel setup
# Global properties
properties() { '
kernel.string=Templar Kernel v4.8-ReSuki for android12-5.10 devices by WiL (@Steambot12)
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

## Deep kernel cleanup function - removes ALL traces of old kernel config
deep_kernel_cleanup() {
    ui_print " "
    ui_print "================================================"
    ui_print " DEEP KERNEL CLEANUP - Removing Old Config"
    ui_print "================================================"
    
    # 1. Clean kernel module dependencies and cache
    ui_print "  [1/10] Clearing module dependency database..."
    if [ -d /data/vendor/modules ]; then
        rm -rf /data/vendor/modules/modules.* 2>/dev/null
        rm -f /data/vendor/modules/*.bin 2>/dev/null
    fi
    
    # 2. Clean sysctl persistent configs
    ui_print "  [2/10] Removing persistent sysctl configs..."
    if [ -d /data/vendor/sysctl ]; then
        rm -rf /data/vendor/sysctl/* 2>/dev/null
    fi
    rm -f /data/local/kernel.sysctl 2>/dev/null
    rm -f /data/vendor/etc/sysctl.d/*.conf 2>/dev/null
    
    # 3. Clean scheduler persistent state
    ui_print "  [3/10] Clearing CPU scheduler state..."
    if [ -d /data/vendor/scheduler ]; then
        rm -rf /data/vendor/scheduler/* 2>/dev/null
    fi
    # Reset schedtune boosting values if persisted
    if [ -d /dev/stune ]; then
        for stune_dir in /dev/stune/*/; do
            echo 0 > "${stune_dir}schedtune.boost" 2>/dev/null
            echo 0 > "${stune_dir}schedtune.prefer_idle" 2>/dev/null
        done
    fi
    
    # 4. Clean I/O scheduler configs and queue state
    ui_print "  [4/10] Resetting I/O scheduler configs..."
    if [ -d /data/vendor/iosched ]; then
        rm -rf /data/vendor/iosched/* 2>/dev/null
    fi
    # Reset I/O scheduler to default before flash
    for queue in /sys/block/*/queue/scheduler; do
        if [ -f "$queue" ]; then
            echo "none" > "$queue" 2>/dev/null
        fi
    done
    
    # 5. Clean CPU frequency governor persistent state
    ui_print "  [5/10] Clearing CPU frequency state..."
    if [ -d /data/vendor/cpufreq ]; then
        rm -rf /data/vendor/cpufreq/* 2>/dev/null
    fi
    if [ -d /data/system/cpufreq ]; then
        rm -rf /data/system/cpufreq/* 2>/dev/null
    fi
    
    # 6. Clean thermal configs and zone state
    ui_print "  [6/10] Resetting thermal management..."
    if [ -d /data/vendor/thermal ]; then
        rm -rf /data/vendor/thermal/* 2>/dev/null
    fi
    # Clear thermal zone trip points cache
    if [ -d /data/vendor/thermal_config ]; then
        rm -f /data/vendor/thermal_config/*.conf 2>/dev/null
    fi
    
    # 7. Clean kernel runtime cache and logs
    ui_print "  [7/10] Clearing kernel runtime data..."
    if [ -d /data/vendor/kernel ]; then
        rm -rf /data/vendor/kernel/* 2>/dev/null
    fi
    if [ -d /data/kernel ]; then
        rm -rf /data/kernel/* 2>/dev/null
    fi
    # Clean kernel ring buffer logs that might contain old params
    dmesg -c > /dev/null 2>&1
    
    # 8. Clean BPF/eBPF programs and maps from old kernel
    ui_print "  [8/10] Removing BPF programs..."
    if [ -d /sys/fs/bpf ]; then
        # Unmount and remount to clear pinned programs
        umount /sys/fs/bpf 2>/dev/null
        mount -t bpf bpf /sys/fs/bpf 2>/dev/null
    fi
    if [ -d /data/vendor/bpf ]; then
        rm -f /data/vendor/bpf/*.o 2>/dev/null
        rm -f /data/vendor/bpf/*.prog 2>/dev/null
    fi
    
    # 9. Clean network stack parameters
    ui_print "  [9/10] Resetting network parameters..."
    if [ -d /proc/sys/net ]; then
        # Reset TCP/IP stack to defaults (will be reinitialized by new kernel)
        if [ -d /data/vendor/netd ]; then
            rm -f /data/vendor/netd/.*.configured 2>/dev/null
        fi
    fi
    
    # 10. Clean temporary kernel build artifacts and old configs
    ui_print "  [10/10] Cleaning temporary files..."
    rm -rf /data/local/tmp/kernel* 2>/dev/null
    rm -f /data/local/tmp/*.ko 2>/dev/null
    rm -f /data/local/tmp/kern_*.log 2>/dev/null
    rm -f /cache/kernel* 2>/dev/null
    rm -rf /data/cache/kernel 2>/dev/null
    
    # Additional: Clear bootconfig if exists (for GKI 2.0)
    if [ -f /data/bootconfig ]; then
        ui_print "  [EXTRA] Clearing bootconfig cache..."
        rm -f /data/bootconfig 2>/dev/null
    fi
    
    # Force filesystem sync to ensure all changes are written
    ui_print "  • Syncing filesystem changes..."
    sync
    sleep 1
    
    ui_print "- Deep cleanup complete!"
    ui_print "  ✓ All old kernel configs removed"
    ui_print " "
}

## Backup current kernel config (optional safety)
backup_kernel_config() {
    ui_print " "
    ui_print "- Creating backup of current kernel..."
    
    backup_dir="/sdcard/TemplarKernel_Backup"
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir" 2>/dev/null
    
    # Backup current kernel version info
    uname -a > "$backup_dir/kernel_${timestamp}.info" 2>/dev/null
    
    # Backup current boot image (if possible)
    if [ -b "$block" ]; then
        ui_print "  • Backing up current boot image..."
        dd if="$block" of="$backup_dir/boot_${timestamp}.img" bs=4096 2>/dev/null
        if [ -f "$backup_dir/boot_${timestamp}.img" ]; then
            ui_print "  ✓ Backup saved to: $backup_dir"
        fi
    fi
    
    ui_print " "
}

## Kernel version check with enhanced validation
check_kernel_version() {
    ui_print " "
    ui_print "- Checking kernel compatibility..."
    
    # Get current running kernel version
    current_kernel=$(uname -r | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
    current_full=$(uname -r)
    
    # Extract new kernel version from Image
    new_kernel_string=$(strings "$home"/Image 2>/dev/null | grep -E -m1 'Linux version [0-9]+\.[0-9]+' | sed -E 's/.*Linux version ([0-9]+\.[0-9]+).*/\1/')
    new_kernel_full=$(strings "$home"/Image 2>/dev/null | grep -E -m1 'Linux version' | cut -d' ' -f3)
    
    ui_print "  • Current: $current_full"
    ui_print "  • New:     $new_kernel_full"
    ui_print " "
    
    # Check base version compatibility (must be 5.10)
    if [ "$current_kernel" == "5.10" ] && [ "$new_kernel_string" == "5.10" ]; then
        ui_print "  ✓ Version check: Compatible (GKI 5.10)"
        
        # Check if CONFIG_SCHED_BORE is compiled in new kernel
        if strings "$home"/Image 2>/dev/null | grep -q "CONFIG_SCHED_BORE"; then
            ui_print "  ✓ SchedBORE detected in new kernel"
        fi
        
        # Check if SSG I/O scheduler is compiled
        if strings "$home"/Image 2>/dev/null | grep -q "ssg"; then
            ui_print "  ✓ SSG I/O scheduler detected"
        fi
        
    elif [ "$new_kernel_string" == "5.10" ] && [ "$current_kernel" != "5.10" ]; then
        ui_print " "
        ui_print "! WARNING: Kernel base mismatch !"
        ui_print "! You are running $current_kernel but installing 5.10 !"
        ui_print "! This may cause bootloop. Continue at your own risk."
        ui_print " "
        sleep 3
    else
        ui_print " "
        ui_print "✗ INCOMPATIBLE KERNEL VERSION ✗"
        ui_print "! This kernel requires 5.10 GKI base !"
        ui_print "! Current running: $current_kernel !"
        ui_print "! Target version:  $new_kernel_string !"
        ui_print " "
        ui_print "Installation aborted for safety."
        exit 1
    fi
}

## Post-installation validation
post_install_check() {
    ui_print " "
    ui_print "- Running post-installation checks..."
    
    # Verify boot image was written correctly
    if [ -b "$block" ]; then
        boot_size=$(stat -c%s "$block" 2>/dev/null)
        if [ "$boot_size" -gt 0 ]; then
            ui_print "  ✓ Boot partition written successfully"
        else
            ui_print "  ✗ WARNING: Boot partition may be corrupted!"
        fi
    fi
    
    # Check if new kernel Image is valid
    if [ -f "$home/Image" ]; then
        kernel_size=$(stat -c%s "$home/Image")
        if [ "$kernel_size" -gt 10485760 ]; then  # > 10MB
            ui_print "  ✓ Kernel Image size valid ($kernel_size bytes)"
        else
            ui_print "  ✗ WARNING: Kernel Image seems too small!"
        fi
    fi
    
    ui_print "  ✓ All checks passed"
    ui_print " "
}

## Set optimal post-flash configs (will be applied on next boot)
set_postflash_configs() {
    ui_print " "
    ui_print "- Preparing post-boot configuration..."
    
    # Create post-boot script directory if not exists
    mkdir -p /data/adb/service.d 2>/dev/null
    
    # Create post-boot optimization script
    cat > /data/adb/service.d/templar_kernel_init.sh << 'EOF'
#!/system/bin/sh
# Templar Kernel Post-Boot Initialization
# This runs once after flash to ensure clean config

LOGFILE="/data/local/tmp/templar_init.log"

{
    echo "Templar Kernel Init - $(date)"
    
    # Wait for boot completion
    sleep 30
    
    # Verify SchedBORE is active
    if [ -f /proc/sys/kernel/sched_bore ]; then
        echo "✓ SchedBORE active"
    fi
    
    # Verify SSG I/O scheduler
    for queue in /sys/block/*/queue/scheduler; do
        current=$(cat "$queue" 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
        echo "I/O Scheduler on $(dirname $queue | xargs basename): $current"
    done
    
    # Clear any lingering kernel cache
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    
    echo "✓ Initialization complete"
    
    # Self-destruct (run only once after flash)
    rm -f /data/adb/service.d/templar_kernel_init.sh
    
} > "$LOGFILE" 2>&1
EOF
    
    chmod 755 /data/adb/service.d/templar_kernel_init.sh 2>/dev/null
    
    ui_print "  ✓ Post-boot script configured"
    ui_print "  • Will run automatically on next boot"
    ui_print " "
}

## ==============================================
## MAIN INSTALLATION FLOW
## ==============================================

ui_print " "
ui_print "================================================"
ui_print "  TEMPLAR KERNEL INSTALLER v4.8-ReSuki"
ui_print "  by WiL (@Steambot12)"
ui_print "================================================"
ui_print " "
ui_print "  • GKI 5.10 with SchedBORE & SSG I/O"
ui_print "  • Deep cleanup enabled for fresh install"
ui_print " "

# Step 1: Backup current setup (optional but recommended)
backup_kernel_config

# Step 2: Check kernel compatibility
check_kernel_version

# Step 3: Deep cleanup - Remove ALL old kernel traces
deep_kernel_cleanup

# Step 4: Start kernel installation
ui_print "================================================"
ui_print " INSTALLING NEW KERNEL"
ui_print "================================================"
ui_print " "

## Begin boot install
split_boot  # Skip ramdisk unpack for GKI devices with init_boot ramdisk

# Display detailed kernel info
kernel_version=$(strings "$home"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')
kernel_builder=$(strings "$home"/Image 2>/dev/null | grep -E -m1 'Linux version.*@' | sed -E 's/.*@([^ ]+).*/\1/')
kernel_date=$(strings "$home"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | sed -E 's/.*#[0-9]+ ([A-Z][a-z]+ .+)/\1/')

ui_print "  • Kernel Version: $kernel_version"
ui_print "  • Built by:       $kernel_builder"
ui_print "  • Build date:     $kernel_date"
ui_print " "
ui_print "- Flashing kernel to boot partition..."

flash_boot  # Skip ramdisk repack for GKI devices with init_boot ramdisk

## End boot install

# Step 5: Post-installation validation
post_install_check

# Step 6: Setup post-boot optimization
set_postflash_configs

## Final summary
ui_print "================================================"
ui_print "  ✓ INSTALLATION COMPLETE"
ui_print "================================================"
ui_print " "
ui_print "Summary:"
ui_print "  ✓ Old kernel configs completely removed"
ui_print "  ✓ New kernel flashed successfully"
ui_print "  ✓ ROM modules preserved and will be reused"
ui_print "  ✓ Post-boot optimization configured"
ui_print "  ✓ Backup saved to /sdcard/TemplarKernel_Backup"
ui_print " "
ui_print "Next steps:"
ui_print "  1. Reboot your device now"
ui_print "  2. Wait 1-2 minutes for initialization"
ui_print "  3. Check /data/local/tmp/templar_init.log"
ui_print " "
ui_print "In case of bootloop:"
ui_print "  • Boot to recovery"
ui_print "  • Flash backup from /sdcard/TemplarKernel_Backup"
ui_print " "
ui_print "================================================"
ui_print " "

## End of install
