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

ui_print " "
ui_print "- Cleaning old kernel artifacts..."

# Backup and clean vendor modules
if [ -d /vendor/lib/modules ]; then
    mv /vendor/lib/modules /vendor/lib/modules.old 2>/dev/null
    mkdir -p /vendor/lib/modules
fi

# Backup and clean system modules
if [ -d /system/lib/modules ]; then
    mv /system/lib/modules /system/lib/modules.old 2>/dev/null
    mkdir -p /system/lib/modules
fi

# Clean module configs and cache
rm -f /vendor/etc/modules.load 2>/dev/null
rm -f /vendor/etc/modules.blocklist 2>/dev/null
rm -f /data/vendor/modules/modules.dep 2>/dev/null
rm -f /data/vendor/modules/modules.alias 2>/dev/null

ui_print " "
ui_print "- Checking kernel version..."

current_kernel=$(uname -r | sed -E 's/^([0-9]+\.[0-9]+).*/\1/') 
new_kernel=$(strings "${AKHOME}"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')

if [[ $current_kernel == "5.10" ]]; then
    ui_print "- Compatible: $current_kernel"
else
    ui_print "- Incompatible: $current_kernel"
    exit 1
fi

ui_print " "

## Start boot install

split_boot # Use split_boot to skip ramdisk unpack, e.g., for devices with init_boot ramdisk

ui_print "- $(strings "${home}"/Image 2>/dev/null | grep -E -m1 'Linux version.*#' | awk '{print $3}')"

flash_boot # Use flash_boot to skip ramdisk repack, e.g., for devices with init_boot ramdisk

## End boot install

ui_print " "
ui_print "- Installation complete!"
ui_print "- Old modules backed up to .old folders"
ui_print " "
