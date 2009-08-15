#! /bin/sh
#
# $Id: start-rc.d,v 1.4 2000-07-08 15:41:05 roland Exp $
#
# Usage: start-rc.d <daemon>
#
# Starts <daemon> if this daemon is active in the current runlevel
# or started in "rcS" according to runlevel.conf.
#
# This script was written by Roland Rosenfeld <roland@spinnaker.de>,
# it is based on an idea of Ingo Saitz <ingo@stud.uni-hannover.de> and
# some code from the other file-rc scripts (update-rc.d, rc, rcS).
#
##########################################################################
#
#   Copyright (C) 1999-2000  Roland Rosenfeld <roland@spinnaker.de>
#
#   This program is free software; you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation; either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
#   General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
##########################################################################

basename=$1

# Get the actual runlevel using runlevel(8). This command outputs the
# previous runlevel and the actual runlevel. We only use the latter.
runlevel=`runlevel`
runlevel=${runlevel##* }

CFGFILE=/etc/runlevel.conf

element() {
    local element list IFS

    element="$1"
        
    [ "$2" = "in" ] && shift
    list="$2"
    [ "$list" = "-" ] && return 1
    [ "$list" = "*" ] && return 0

    IFS=","
    set -- $list
    case $element in
        "$1" | "$2" | "$3" | "$4" | "$5" | "$6" | "$7" | "$8" | "$9")
            return 0
    esac
    return 1
}


while read LINE
do
    case $LINE in
	\#*|"") continue
    esac

    set -- $LINE
    SORT_NO="$1"; STOP="$2"; START="$3"; CMD="$4"

    [ "$CMD" = "/etc/init.d/$basename" ] || continue

    if element "$runlevel" in "$START" || element "S" in "$START"
    then
	/etc/init.d/$basename start
	exit 0
    fi
done < $CFGFILE
