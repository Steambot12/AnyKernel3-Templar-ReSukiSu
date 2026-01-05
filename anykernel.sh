### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# Global properties
properties() { '
kernel.string=Templar Kernel for android12-5.10 devices by WiL (@Steambot12)
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

## Cleanup kernel cache and leftover configs only
cleanup_kernel_cache() {
    ui_print " "
    ui_print "- Cleaning kernel cache and old configs..."
    
    # Clean depmod cache and module database
    if [ -d /data/vendor/modules ]; then
        ui_print "  • Clearing module dependency cache"
        rm -f /data/vendor/modules/modules.dep 2>/dev/null
        rm -f /data/vendor/modules/modules.dep.bin 2>/dev/null
        rm -f /data/vendor/modules/modules.alias 2>/dev/null
        rm -f /data/vendor/modules/modules.alias.bin 2>/dev/null
        rm -f /data/vendor/modules/modules.softdep 2>/dev/null
        rm -f /data/vendor/modules/modules.symbols 2>/dev/null
        rm -f /data/vendor/modules/modules.symbols.bin 2>/dev/null
    fi
    
    # Clean kernel log cache
    if [ -d /data/vendor/kernel ]; then
        ui_print "  • Clearing kernel runtime cache"
        rm -rf /data/vendor/kernel/* 2>/dev/null
    fi
    
    # Clean temporary kernel files in /data
    ui_print "  • Clearing kernel temporary files"
    rm -f /data/local/tmp/kernel* 2>/dev/null
    rm -f /data/local/tmp/*.ko 2>/dev/null
    
    # Sync filesystem to ensure write completion
    sync
    
    ui_print "- Cache cleanup complete!"
    ui_print "  Note: ROM modules preserved"
}

## Kernel version check
check_kernel_version() {
    ui_print " "
    ui_print "- Checking kernel compatibility..."
    
    current_kernel=$(uname -r | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
    new_kernel_string=$(strings "$home"/Image 2>/dev/null | grep -E -m1 'Linux version [0-9]+\.[0-9]+' | sed -E 's/.*Linux version ([0-9]+\.[0-9]+).*/\1/')
    
    ui_print "  • Current kernel: $current_kernel"
    ui_print "  • New kernel: $new_kernel_string"
    
    if [ "$current_kernel" == "5.10" ]; then
        ui_print "  • Version check: Compatible"
    else
        ui_print " "
        ui_print "! INCOMPATIBLE KERNEL VERSION !"
        ui_print "! This kernel requires 5.10 base !"
        ui_print "! Current running: $current_kernel !"
        ui_print " "
        exit 1
    fi
}

## Main installation flow
ui_print "================================================"
ui_print " Templar Kernel Installer"
ui_print " by WiL (@Steambot12)"
ui_print "================================================"

# Run cache cleanup
cleanup_kernel_cache

# Check kernel compatibility
check_kernel_version

ui_print " "
ui_print "- Starting kernel installation..."

## Start boot install
split_boot # Skip ramdisk unpack for GKI devices with init_boot ramdisk

# Display kernel version info
kernel_version=$(strings "$home"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')
ui_print "  • Installing: $kernel_version"

flash_boot # Skip ramdisk repack for GKI devices with init_boot ramdisk
## End boot install

ui_print " "
ui_print "================================================"
ui_print " Installation Complete!"
ui_print "================================================"
ui_print "- Kernel flashed successfully"
ui_print "- ROM modules preserved and will be reused"
ui_print "- Module cache cleared for fresh detection"
ui_print "- Please reboot to apply changes"
ui_print " "
