#!/bin/bash
#
# --- T2-COPYRIGHT-NOTE-BEGIN ---
# This copyright note is auto-generated by ./scripts/Create-CopyPatch.
# 
# T2 SDE: package/.../oprofile/pulpstoned.sh
# Copyright (C) 2004 - 2005 The T2 SDE Project
# Copyright (C) 1998 - 2003 ROCK Linux Project
# 
# More information can be found in the files COPYING and README.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License. A copy of the
# GNU General Public License can be found in the file COPYING.
# --- T2-COPYRIGHT-NOTE-END ---

period=600
report_script=pulpstoner
report_dir=/var/log/pulpstone
pidfile=/var/run/pulpstoned.pid

cd /; mkdir -p $report_dir
echo "pulpstone daemon: writing logs to $report_dir ..."

(

psd_end() {
	opcontrol -h
	echo "Shutting down on signal."
	rm -f $pidfile
	date +"=== <%Y/%m/%d %H:%M:%S> ==="
	exit 0
}

trap psd_end INT TERM
echo $$ > $pidfile

while true; do
	now=`date +"%Y%m%d%H"`
	exec >> $report_dir/$now.log 2>&1
	for x in $report_dir/*.log; do
		[ "$x" = "$report_dir/$now.log" ] && continue
		echo; echo "Uploading $report_dir/$now.log ..."
		res="$( curl -s -F data=@$x http://www.rocklinux.net/pulpstone/upload.cgi )"
		if [ "$res" = "ok" ]; then
			echo "File upload succesfull."
			mv $x ${x%.log}.old
		else
			echo "Error while uploading."
		fi
	done
	date +"%n=== <%Y/%m/%d %H:%M:%S> ==="
	opcontrol -s
	opcontrol --reset
	opcontrol --event="CPU_CLK_UNHALTED:100000:0:1:1"
	for ((c=0; c<period; c++)); do sleep 1; done
	opcontrol -h
	date +"=== <%Y/%m/%d %H:%M:%S> ==="
	nice -n 99 $report_script | unexpand -a
	date +"=== <%Y/%m/%d %H:%M:%S> ==="
done

) &

