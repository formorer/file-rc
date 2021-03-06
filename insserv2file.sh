#! /bin/sh

# insserv2file - Convert insserv dependencies
# Copyright (C) 1998       Martin Schulze <joey@debian.org>
# Copyright (C) 1999-2004  Roland Rosenfeld <roland@debian.org>
# Copyright (C) 2012       Roger Leigh <rleigh@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111, USA.

# The functions element() and unique() are based on functions
# written by Winfried Tr�mper <winni@xpilot.org>

cat <<EOF
# This file was automatically generated by $0.
# You can use update-rc.d(8) to modify it.  Do not edit by hand
# or else your changes will be lost next time update-rc.d is run.
# Read runlevel.conf(5) man page for more information about this file.
#
# Format:
# <sort> <off-> <on-levels>     <command>
EOF

OLDIFS="$IFS"
IFS=":"
/sbin/insserv -s | sort  -t: -k2 -k1 | while read IN_ACTION IN_SEQUENCE IN_LEVELS IN_BASENAME
do
    IN_LEVELS="$(echo "$IN_LEVELS" | sed -e 's; ;,;g')"
    if [ "$IN_ACTION" = "S" ]; then
	echo "$IN_SEQUENCE	-	$IN_LEVELS		/etc/init.d/$IN_BASENAME"
    elif [ "$IN_ACTION" = "K" ]; then
	echo "$IN_SEQUENCE	$IN_LEVELS	-		/etc/init.d/$IN_BASENAME"
    fi
done
IFS="$OLDIFS"

echo "# THE LAST LINE IS NEVER READ"
