# --- T2-COPYRIGHT-NOTE-BEGIN ---
# T2 SDE: package/*/stone/stone_mod_install.sh
# Copyright (C) 2004 - 2023 The T2 SDE Project
# Copyright (C) 1998 - 2003 ROCK Linux Project
# 
# This Copyright note is generated by scripts/Create-CopyPatch,
# more information can be found in the files COPYING and README.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2.
# --- T2-COPYRIGHT-NOTE-END ---

# TODO: check error, esp. of lvm commands and display red alert on error

mapper2lvm() {
	local x="${1//--/
}"
	x="${x//-//}"
	echo "${x//
/-}"
}

part_mounted_action() {
	if gui_yesno "Do you want to unmount the filesystem on $1?"
	then umount /dev/$1; fi
}

part_activepv_action() {
	if gui_yesno "Do you want to remove physical LVM $1 from volume group $2?"
	then vgreduce $2 /dev/$1; fi
}

part_swap_action() {
	if gui_yesno "Do you want to deactivate the swap space on $1?"
	then swapoff /dev/$1; fi
}

part_mount() {
	local dev=$1
	local dir="/ /boot /home /srv /var"
	[ -d /sys/firmware/efi ] && dir="${dir/boot/boot/efi}"
	local d
	for d in $dir; do
		grep -q " /mnt${d%/} " /proc/mounts || break
	done
	gui_input "Mount device $dev on directory
(for example ${dir// /, }, ...)" "${d:-/}" dir
	if [ "$dir" ]; then
		dir="$(echo $dir | sed 's,^/*,,; s,/*$,,')"
		# check if at least a rootfs / is already mounted
		if [ -z "$dir" ] || grep -q " /mnt " /proc/mounts
		then
			mkdir -p /mnt/$dir
			[ "$2" ] && mount -o "$2" /dev/$dev /mnt/$dir 2>/dev/null ||
				mount /dev/$dev /mnt/$dir
		else
			gui_message "Please mount a root filesystem first."
		fi
	fi
}

part_mkfs() {
	local dev=$1
	cmd="gui_menu part_mkfs 'Create filesystem on $dev'"

	maybe_add () {
	  if #grep -q $1 /proc/filesystems &&
	     type -p $3 > /dev/null; then
		cmd="$cmd '$1 ($2 filesystem)' \
		'type wipefs 2>/dev/null && wipefs -a /dev/$dev; $3 $4 /dev/$dev'"
	  fi
	}

	maybe_add btrfs	'Better, b-tree, CoW journaling' 'mkfs.btrfs' '-f'
	maybe_add ext4	'journaling, extents'	'mkfs.ext4'
	maybe_add ext3	'journaling'		'mkfs.ext3'
	maybe_add ext2	'non-journaling'	'mkfs.ext2'
	maybe_add jfs	'IBM journaling'	'mkfs.jfs'
	maybe_add reiserfs 'journaling'		'mkfs.reiserfs'
	maybe_add xfs	'Sgi journaling'	'mkfs.xfs' '-f'
	maybe_add fat	'File Allocation Table'	'mkfs.fat'

	eval "$cmd" && part_mount $dev "compress=zstd"
}

part_decrypt() {
	local dev=$1

	local dir="root home swap"
	local d
	for d in $dir; do
		[ -e /dev/mapper/$dir ] || break
	done
	gui_input "Mount device $dev on directory
(for example ${dir// /, }, ...)" "${d:-/}" dir
	if [ "$dir" ]; then
		dir="$(echo $dir | sed 's,^/*,,; s,/*$,,')"
		cryptsetup luksOpen --disable-locks /dev/$dev $dir
	fi
}

part_crypt() {
	local dev=$1
	cryptsetup luksFormat --disable-locks --pbkdf=pbkdf2 /dev/$dev || return

	part_decrypt $dev
}

part_pvcreate() {
	local dev=$1
	pvcreate /dev/$dev
}

vg_add_pv() {
	pvs -o vgname $2 --noheadings
	gui_input "Add physical volume $1 to logical volume group:" "vg0" vg
	if [ "$vg" ]; then
	    if vgs $vg 2>/dev/null; then
		vgextend $vg $1
	    else
		vgcreate $vg $1
	    fi
	fi
}

part_unmounted_action() {
	local dev=$1 stype=$2

	type=$(blkid --match-tag TYPE /dev/$dev)
	type=${type#*\"}; type=${type%\"*}
	[ "$type" = swsuspend ] && type="swap"

	local cmd="gui_menu part $dev"

	[ "$type" -a "$type" != "swap" -a "$type" != "crypto_LUKS" ] &&
		cmd="$cmd \"Mount filesystem from the partition\" \"part_mount $dev\""
	[ "$type" = "crypto_LUKS" ] &&
		cmd="$cmd \"Activate LUKS encrypted partition\"  \"part_decrypt $dev\""
	[ "$type" = "swap" ] &&
		cmd="$cmd \"Activate existing swap space on the partition\" \"swapon /dev/$dev\""
	
	cmd="$cmd \"Create filesystem on the partition\" \"part_mkfs $dev\""
	cmd="$cmd \"Create swap space on the partition\" \"mkswap /dev/$dev; swapon /dev/$dev\""
	cmd="$cmd \"Encrypt partition using LUKS cryptsetup\" \"part_crypt $dev\""

	[ "$stype" != "lv" ] &&
		cmd="$cmd \"Create physical LVM volume\" \"part_pvcreate $dev\""

	if [ "$stype" = "lv" ]; then
		[[ "$(lvs -o active --noheadings /dev/$dev)" = *active ]] &&
		cmd="$cmd 'Deactivate logical LVM volume' 'lvchange -an /dev/$dev'" ||
		cmd="$cmd 'Activate logical LVM volume' 'lvchange -ay /dev/$dev'"
		cmd="$cmd \"Rename logical LVM volume\" \"lvm_rename ${dev#mapper/} lv\""
		cmd="$cmd \"Remove logical LVM volume\" \"lvremove /dev/$dev\""
	fi
	[ "$type" = "LVM2_member" ] &&
		cmd="$cmd 'Add physical LVM volume to volume group' 'vg_add_pv /dev/$dev'" &&
		cmd="$cmd 'Remove physical LVM volume' 'pvremove /dev/$dev'"

	eval $cmd
}

part_add() {
	local dev=$1
	local action="unmounted" location="currently not mounted"
	if grep -q "^/dev/$dev " /proc/swaps; then
		action=swap location="swap  <no mount point>"
	elif grep -q "^/dev/$dev " /proc/mounts; then
		action=mounted
		location="`grep "^/dev/$dev " /proc/mounts | cut -d ' ' -f 2 |
			  sed "s,^/mnt,," `"
		[ "$location" ] || location="/"
	fi

	# save partition information
	disktype /dev/$dev > /tmp/stone-install 2>/dev/null
	type="`grep /tmp/stone-install -v -e '^  ' -e '^Block device' \
	       -e '^Partition' -e '^---' |
	       sed -e 's/[,(].*//' -e '/^$/d' -e 's/ $//' | tail -n 1`"
	size="`grep 'Block device, size' /tmp/stone-install |
	       sed 's/.* size \(.*\) (.*/\1/'`"
	if [ -z "$type" ]; then
		type=$(blkid --match-tag TYPE /dev/$dev)
		type=${type#*\"}; type=${type%\"*}
	fi

	# active LVM pv?
	if [[ "$type" = *LVM2*volume* ]]; then
		local vg=`pvs --noheadings -o vgname /dev/$dev`
		vg="${vg##* }"
		[ "$vg" ] && action=activepv && location="$vg" && set "$1" "$vg"
	fi

	dev=${1#*/}; dev=${dev#mapper/}
	cmd="$cmd '`printf "%-6s %-24s %-10s" $dev "$location" "$size"` ${type//_/ }' 'part_${action}_action $1 $2'"
}

disk_action() {
	if grep -q "^/dev/$1 " /proc/swaps /proc/mounts; then
		gui_message "Partitions from $1 are currently in use, so you
can't modify this disks partition table."
		return
	fi

	local cmd="gui_menu disk 'Edit partition table of $1'"
	for x in cfdisk fdisk pdisk mac-fdisk parted; do
		type -p $x > /dev/null &&
		  cmd="$cmd \"Edit partition table using '$x'\" \"$x /dev/$1\""
	done

	eval $cmd
}

lvm_rename() {
	local dev=$1
	echo $dev $type
	[ "$2" = lv ] && dev=$(mapper2lvm $dev)
	gui_input "Rename $dev:" "${dev#*/}" name

	if [ "$2" = vg ]; then
		vgrename $dev $name
	else
		lvrename $dev $name
	fi
}


lv_create() {
	local dev=$1 type=$2
	# TODO: name, stripes
	local size=$(vgdisplay $dev | grep Free | sed 's,.*/,,; s, <,,; s/ //g ')
	gui_input "Logical volume size:" "$size" size
	[ "$size" ] &&
		lvcreate -L "$size" --type $type $dev # -n name
}

vg_action() {
	local cmd="gui_menu vg 'Volume Group $1'"

	cmd="$cmd 'Create Linear logical volume' 'lv_create $1 linear'"
	cmd="$cmd 'Create Striped logical volume' 'lv_create $1 striped'"
	cmd="$cmd 'Create RAID 1 logical volume' 'lv_create $1 raid1'"
	cmd="$cmd 'Create RAID 5 logical olume' 'lv_create $1 raid5'"
	cmd="$cmd 'Create RAID 6 logical volume' 'lv_create $1 raid6'"
	cmd="$cmd 'Create RAID 10 logical volume' 'lv_create $1 raid10'"
	cmd="$cmd '' ''"
	cmd="$cmd 'Activate all volumes in group' 'vgchange -ay $1'"
	cmd="$cmd 'Deactivate all volumes in group' 'vgchange -an $1'"
	cmd="$cmd 'Rename volume group' 'lvm_rename $1 vg'"
	cmd="$cmd 'Remove volume group' 'vgremove $1'"
	cmd="$cmd 'Display low-level information' 'gui_cmd \"display $1\" vgdisplay $1'"

	eval $cmd
}

disk_add() {
	local x found=0
	cmd="$cmd 'Edit partition table of $1:' 'disk_action $1'"
	# TODO: maybe better /sys/block/$1/$1* ?
	for x in $(cd /dev; ls $1[0-9p]* 2> /dev/null)
	do
		part_add $x
		found=1
	done
	[ $found = 0 ] && cmd="$cmd 'Partition table is empty.' ''"
	cmd="$cmd '' ''"
}

vg_add() {
	local x= found=0

	cmd="$cmd 'Logical volumes of $1:' 'vg_action $1'"

	[ -x /sbin/lvs ] && for x in $(lvs --noheadings -o dm_path $1 2> /dev/null); do
		x=${x#/dev/}
		part_add $x lv
		volumes="${volumes/ $x /}"
		found=1
	done
	if [ $found = 0 ]; then
		cmd="$cmd 'No logical volumes.' ''"
	fi

	cmd="$cmd '' ''"
}

main() {
	$STONE general set_keymap

	local install_now=0
	while
		cmd="gui_menu install 'Storage setup: partitions and mount-points

Modify your storage layout: create file-systems, swap-space, encrypt and mount them. You can also use advanced low-level tools on the command line.'"

		local found=0
		volumes=""
		for x in /sys/block/*; do
			[ ! -e $x/device -a ! -e $x/dm ] && continue
			x=${x#/sys/block/}
			[[ "$x" = fd[0-9]* ]] && continue
			# TODO: media? udevadm info -q property --name=/dev/sr0

			# LVM Device Mapper?
			if [ -e /sys/block/$x/dm ]; then
				if [ -e /sys/block/$x/dm/name ]; then
					x=$(< /sys/block/$x/dm/name)
					[[ $x = *_rimage* || $x = *_rmeta* ]] && continue
				fi
				volumes="${volumes} mapper/$x "
			else
				disk_add $x
			fi
			found=1
		done

		[ -x /sbin/vgs ] && for x in $(vgs --noheadings -o name 2> /dev/null); do
			vg_add "$x"
			found=1
		done

		# any other remaining device-mapper, e.g. LUKS cryptosetup
		if [ "$volumes" ]; then
			for x in $volumes; do part_add $x; done
			cmd="$cmd '' ''"
		fi

		if [ $found = 0 ]; then
			cmd="$cmd 'No storage found!' ''"
		fi

		cmd="$cmd 'Install the system ...' 'install_now=1'"

		eval "$cmd" && [ "$install_now" -eq 0 ]
	do : ; done

	if [ "$install_now" -ne 0 ]; then
		$STONE packages

		mount -v --bind /dev /mnt/dev
		cat > /mnt/tmp/stone_postinst.sh << EOT
#!/bin/bash
mount -v /proc
mount -v /sys
. /etc/profile
stone setup
umount -v /dev
umount -v /proc
umount -v /sys
EOT
		chmod +x /mnt/tmp/stone_postinst.sh
		sed -n 's, /mnt/\?, /,p' /etc/mtab > /mnt/etc/mtab
		chroot /mnt /tmp/stone_postinst.sh
		rm -f /mnt/tmp/stone_postinst.sh

		if gui_yesno "Do you want to un-mount the filesystems and reboot now?"
		then
			# try to re-boot via kexec, if available
			if type -p kexec > /dev/null; then
			    root=$(sed -n '/.*\(root=.*\)/{ s//\1/p; q}' /mnt/boot/grub/grub.cfg)
			    kernel="$(echo /mnt/boot/vmlinu[xz]-*)"
			    kernel="${kernel##* }"
			    kexec -l $kernel --initrd="${kernel/vmlinu?/initrd}" \
				  --reuse-cmdline --append "$root"
			fi
			shutdown -r now
		else
			echo
			echo "You might want to umount all filesystems now and reboot"
			echo "the system now using the commands:"
			echo
			echo "	shutdown -r now"
			echo
			echo "Or by executing 'shutdown -r now' which will run the above commands."
			echo
		fi
	fi
}
