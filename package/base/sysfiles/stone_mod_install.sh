# --- ROCK-COPYRIGHT-NOTE-BEGIN ---
# 
# This copyright note is auto-generated by ./scripts/Create-CopyPatch.
# Please add additional copyright information _after_ the line containing
# the ROCK-COPYRIGHT-NOTE-END tag. Otherwise it might get removed by
# the ./scripts/Create-CopyPatch script. Do not edit this copyright text!
# 
# ROCK Linux: rock-src/package/base/sysfiles/stone_mod_install.sh
# ROCK Linux is Copyright (C) 1998 - 2003 Clifford Wolf
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version. A copy of the GNU General Public
# License can be found at Documentation/COPYING.
# 
# Many people helped and are helping developing ROCK Linux. Please
# have a look at http://www.rocklinux.org/ and the Documentation/TEAM
# file for details.
# 
# --- ROCK-COPYRIGHT-NOTE-END ---

part_mounted_action() {
	if gui_yesno "Do you want to un-mount the filesystem on $1/$2?"
	then umount /dev/$1/$2; fi
}

part_swap_action() {
	if gui_yesno "Do you want to de-activate the swap space on $1/$2?"
	then swapoff /dev/$1/$2; fi
}

part_mount() {
	local dir
	gui_input "Mount device $1/$2 on directory
(for example /, /home, /var, ...)" '/' dir
	if [ "$dir" ] ; then
		dir="$( echo $dir | sed 's,^/*,,; s,/*$,,' )"
		if [ -z "$dir" ] || grep -q " /mnt/target " /proc/mounts
		then
			mkdir -p /mnt/target/$dir
			mount /dev/$1/$2 /mnt/target/$dir
		else
			gui_message "Please mount a root filesystem first."
		fi
	fi
}

part_mkfs() {
	cmd="gui_menu part_mkfs 'Create filesystem on $1/$2'"

	cmd="$cmd 'ext3fs   (journaling filesystem)'"
	cmd="$cmd 'mke2fs -j /dev/$1/$2'"

	cmd="$cmd 'ext2fs   (non-journaling fs)'"
	cmd="$cmd 'mke2fs /dev/$1/$2'"

	cmd="$cmd 'reiserfs (journaling filesystem)'"
	cmd="$cmd 'mkreiserfs /dev/$1/$2'"

	cmd="$cmd 'IBM JFS  (journaling filesystem)'"
	cmd="$cmd 'jfs_mkfs /dev/$1/$2'"

	cmd="$cmd 'SGI XFS  (journaling filesystem)'"
	cmd="$cmd 'mkfs.xfs /dev/$1/$2'"

	eval "$cmd" && part_mount $1 $2
}

part_unmounted_action() {
	gui_menu part "$1/$2" \
		"Create a filesystem on the partition" \
				"part_mkfs $1 $2" \
		"Mount an existing filesystem from the partition" \
				"part_mount $1 $2" \
		"Create a swap space on the partition" \
				"mkswap /dev/$1/$2; swapon /dev/$1/$2" \
		"Activate an existing swap space on the partition" \
				"swapon /dev/$1/$2"
}

part_add() {
	local action="unmounted" location="currently not mounted"
	if grep -q "^/dev/$1/$2 " /proc/swaps; then
		action=swap ; location="swap  <no mount point>"
	elif grep -q "^/dev/$1/$2 " /proc/mounts; then
		action=mounted
		location="`grep "^/dev/$1/$2 " /proc/mounts | cut -d ' ' -f 2 | \
			  sed "s,^/mnt/target,," `"
		[ "$location" ] || location="/"
	fi
	type="`disktype /dev/$1/$2 | \
		grep -v -e '^  ' -e '^Block device' -e '^Partition' -e '^---' | \
		sed -e 's/[,(].*//' -e '/^$/d' -e 's/ $//' | tail -1`"
	[ "$type" ] || type="undetected"
	cmd="$cmd '`printf "%-8s %-24s" $2 "$location"` ($type)' 'part_${action}_action $1 $2'"
}

disk_action() {
	if grep -q "^/dev/$1/" /proc/swaps /proc/mounts; then
		gui_message "Partitions from $1 are currently in use, so you
can't modify this disks partition table."
		return
	fi

	cmd="gui_menu disk 'Edit partition table of $1'"
	for x in cfdisk fdisk pdisk mac-fdisk ; do
		fn=""
		[ -f /bin/$x ] && fn="/bin/$x"
		[ -f /sbin/$x ] && fn="/sbin/$x"
		[ -f /usr/bin/$x ] && fn="/usr/bin/$x"
		[ -f /usr/sbin/$x ] && fn="/usr/sbin/$x"
		[ "$fn" ] && \
		  cmd="$cmd \"Edit partition table using '$x'\" \"$x /dev/$1/disc\""
	done

	eval $cmd
}

disk_add() {
	local x y=0
	cmd="$cmd 'Partition table of $1:' 'disk_action $1'"
	for x in $( cd /dev/$1 ; ls part* 2> /dev/null )
	do
		part_add $1 $x ; y=1
	done
	if [ $y = 0 ]; then
		cmd="$cmd 'Partition table is empty.' ''"
	fi
	cmd="$cmd '' ''"
}

main() {
	local cmd install_now=0
	while
		cmd="gui_menu install 'Partitioning your discs

This dialog allows you to modify your discs parition layout and to create filesystems and swap-space - as well as mouting / activating it. Everything you can do using this tool can also be done manually on the command line.'"

		# protect for the case no discs are present ...
		if [ -e /dev/discs ] ; then
		  for x in $( cd /dev/discs
		            ls -l * | grep ' -> ' | cut -f2- -d/ ; )
		  do
			disk_add $x
		  done
		else
		  cmd="$cmd 'No hard-disc found!' ''"
		fi

		cmd="$cmd 'Install the system ...'"
		cmd="$cmd 'install_now=1'"

		eval "$cmd" && [ "$install_now" -eq 0 ]
	do : ; done

	if [ "$install_now" -ne 0 ] ; then
		$STONE packages
		cat > /mnt/target/tmp/stone_postinst.sh << EOT
#!/bin/sh
mount -v /dev
mount -v /proc
. /etc/profile
stone setup
umount -v /dev
umount -v /proc
EOT
		chmod +x /mnt/target/tmp/stone_postinst.sh
		grep ' /mnt/target[/ ]' /proc/mounts | \
			sed 's,/mnt/target/\?,/,' > /mnt/target/etc/mtab
		cd /mnt/target ; chroot . ./tmp/stone_postinst.sh
		rm -fv ./tmp/stone_postinst.sh
		echo
		echo "You might want to umount all filesystems now and reboot"
		echo "the system now using the commands:"
		echo
		echo "	umount -arv"
		echo "	reboot -f"
		echo
		echo "Or by executing 'shutdown -r' which will run the above commands."
		echo
	fi
}

