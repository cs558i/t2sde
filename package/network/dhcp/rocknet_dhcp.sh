# --- T2-COPYRIGHT-NOTE-BEGIN ---
# This copyright note is auto-generated by ./scripts/Create-CopyPatch.
# 
# T2 SDE: package/.../dhcp/rocknet_dhcp.sh
# Copyright (C) 2004 - 2019 The T2 SDE Project
# 
# More information can be found in the files COPYING and README.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License. A copy of the
# GNU General Public License can be found in the file COPYING.
# --- T2-COPYRIGHT-NOTE-END ---

public_dhcp() {
	addcode up   5 1 "ip link set $if up"
	addcode up   5 5 "dhclient -q -pf /var/run/dhclient-$if.pid $@ $if"
	addcode down 5 5 "/sbin/dhclient -pf /var/run/dhclient-$if.pid -x"
}
