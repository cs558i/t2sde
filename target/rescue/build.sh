# --- T2-COPYRIGHT-NOTE-BEGIN ---
# This copyright note is auto-generated by ./scripts/Create-CopyPatch.
# 
# T2 SDE: target/desktop/build.sh
# Copyright (C) 2006 The T2 SDE Project
# 
# More information can be found in the files COPYING and README.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License. A copy of the
# GNU General Public License can be found in the file COPYING.
# --- T2-COPYRIGHT-NOTE-END ---

# filter to avoid some non-runtime stuff (static libs, man-pages, ...)
rescue_rootfs_filter ()
{
	sed -i '/\.a$/d
	        /\.la$/d
	        /\/include\//d
	        /\/locale\//d
	        /\/pkgconfig\//d
	        /\/info\//d
	        /\/man\//d
	        /\/doc\//d
	        /\/i18n\//d
		/var\/adm/d
	        /usr\/src\//d' "$1"
	cut -d ' ' -f 2- $build_root/var/adm/flists/gcc |
	grep '/lib\(gcc\|std\).*.so' >> "$1"
}
filter_hook=rescue_rootfs_filter

# do not include some devel packages
var_append pkg_filter ' ' 'dietlibc flex bison make cmake scons python perl autoconf automake libtool m4 ccache distcc texinfo binutils gcc'

. target/generic/build.sh

# now this is a hack - and x86 specific anyway :-(
if [[ $arch = x86* ]]; then
	case "$SDECFG_X86_CD_LOADER" in
	grub)
		sed -i 's/kernel.*/& vga=0x317/' $isofsdir/boot/grub/menu.lst ;;
	isolinux)
		sed -i 's/APPEND.*/& vga=0x317/' $isofsdir/boot/isolinux/isolinux.cfg ;;
	*)
		echo "Adapt target/rescue/build.sh for unknown boot loader: $SDECFG_X86_CD_LOADER" ;;
	esac
fi
