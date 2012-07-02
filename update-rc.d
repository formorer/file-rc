#!/bin/sh
# 
# This is the script "update-rc.d" used manipulating the runlevel setup.
# This version handles a configuration file for the SysV-init instead 
# of dealing with links in /etc/rc?.d/*
#
# Author: Winfried Trümper <winni@xpilot.org>
#
# Misc fixes by Tom Lees <tom@lpsg.demon.co.uk>
# Misc fixes by Roland Rosenfeld <roland@spinnaker.de>
#
# Based on version 0.2 of "new-rc".
#
# $Id: update-rc.d,v 1.31 2008-05-01 10:16:33 roland Exp $
#

CFGFILE="/etc/runlevel.conf"
BAKCFG="/etc/runlevel.fallback"
LOCKFILE="/var/lock/runlevel.lock"
TMPFILE="/etc/runlevel.tmp"

valid_runlevels="0 1 2 3 4 5 6 7 8 9 S"
valid_min_seq=0
valid_max_seq=99

true=0
false=1

print_usage() {
    cat <<EOF
usage: update-rc.d [-n] [-f] <basename> remove
       update-rc.d [-n] <basename> defaults [NN | sNN kNN]
       update-rc.d [-n] <basename> start|stop NN runlvl [runlvl] [...] .
                -n: not really
                -f: force
EOF
}

is_valid_runlevel() {
    if [ $# -ne 1 ]
    then
	return $false
    fi

    for lev in $valid_runlevels
    do
	if [ "$1" = "$lev" ]
	then
	    return $true
	fi
    done
    return $false
}

is_valid_sequence() {
    if [ $# -ne 1 ]
    then
	return $false
    fi

    if [ $1 -ge $valid_min_seq -a $1 -le $valid_max_seq ]
    then
	return $true
    fi
    return $false
}

get_runlevels_for_sequence() {
    seq=$1; shift
    i=""
    r=""
    s=""
    list=""
    for i in $*
    do
	r=${i%%:*}
	s=${i##*:}
	if [ $seq -eq $s ]
	then
	    list="$list$r,"
	fi
    done
    list=${list%%,}
    echo $list
}

greater_sequence() {
    s=$1; shift
    for k in $*
    do
	i=${k##*:}
	[ $s -gt $i ] && return $true
    done
    return $false
}

get_shortest_sequence() {
    level=99
    for i in $*
    do
	i=${i##*:}
	[ $i -lt $level ] && level=$i
    done
    echo $level
}

print_config_start_line() {
    linebasename="$1"
    linestartlist="$2"

    NEW_START=""

    if [ -n "$linestartlist" ]; then
	linestartseq=`get_shortest_sequence $linestartlist`
	NEW_START=`get_runlevels_for_sequence $linestartseq $linestartlist`
	NEW_SEQ=$linestartseq

	case "$NEW_SEQ" in
	    ?) NEW_SEQ=0$NEW_SEQ ;;
	esac
	echo "$NEW_SEQ	-	$NEW_START		/etc/init.d/$linebasename" >> "$TMPFILE"
	modified="1"
    fi
}

print_config_stop_line() {
    linebasename="$1"
    linestoplist="$2"

    NEW_STOP=""

    if [ -n "$linestoplist" ]; then
	linestopseq=`get_shortest_sequence $linestoplist`
	NEW_STOP=`get_runlevels_for_sequence $linestopseq $linestoplist`
	NEW_SEQ=$linestopseq

	case "$NEW_SEQ" in
	    ?) NEW_SEQ=0$NEW_SEQ ;;
	esac
	echo "$NEW_SEQ	$NEW_STOP	-		/etc/init.d/$linebasename" >> "$TMPFILE"
	modified="1"
    fi
}

do_while=1
opt_force=0
opt_simulate=0
while [ $# -gt 0 -a $do_while -eq 1 ]
do
    case $1 in
    -h|--help)
	print_usage
	exit 0
	;;
    -f|--force)
	opt_force=1
	shift
	;;
    -n)
	opt_simulate=1
	shift
	;;
    *)
	do_while=0
	;;
    esac
done

if [ $# -lt 2 ]
then
    echo "update-rc.d: too few arguments." >&2
    print_usage >&2
    exit 1
fi

basename="$1"; shift
if [ $opt_force -eq 0 ]; then
    if [ "$1" = "remove" ]; then
	if [ -f "/etc/init.d/$basename" ]
	then
	    echo "update-rc.d: warning /etc/init.d/$basename still exist. Terminating" >&2
	    exit 1
	fi
    else
	if ! [ -f "/etc/init.d/$basename" ]
	then
	    echo "update-rc.d: warning /etc/init.d/$basename doesn't exist. Terminating" >&2
	    exit 1
	fi

	case $basename in
	*.sh)
	    # will be sourced
	    ;;
	*)
	    if ! [ -x "/etc/init.d/$basename" ]
	    then
		echo "update-rc.d: warning /etc/init.d/$basename is not executable. Terminating" >&2
		exit 1
	    fi
	    ;;
	esac
    fi
fi

insserv_find_internal() {
    OLDIFS="$IFS"
    IFS=:

    echo "$1" | while read IN_ACTION IN_SEQUENCE IN_LEVELS IN_BASENAME
    do
	if [ "$IN_BASENAME" = "$2" ]; then
	    if [ "$IN_ACTION" = "S" ]; then
		echo "START_SORT_NO=\"${IN_SEQUENCE}\""
		echo "STARTLEVELS=\"${IN_LEVELS}\""
	    elif [ "$IN_ACTION" = "K" ]; then
		IN_FOUND="true"
		echo "STOP_SORT_NO=\"${IN_SEQUENCE}\""
		echo "STOPLEVELS=\"${IN_LEVELS}\""
	    fi
	fi
    done
    IFS="$OLDIFS"
}

insserv_find() {
    idata=$(insserv_find_internal "$1" "$2")
    if [ -n "$idata" ]; then
	OLDIFS="$IFS"
	IFS="
"
	for line in $(echo $idata); do
	    eval "$line"
	done
	IFS="$OLDIFS"
	return $true
    fi
    return $false;
}

create_lock() {
    # wait for any lock to vanish
    i=0
    while [ -f "$LOCKFILE" ]
    do
	read pid < "$LOCKFILE"
	if ! kill -s 0 $pid > /dev/null 2>&1
	then
            remove_lock
            break
	fi
	if [ "$i" -gt "5" ]
	then
            echo "Process no. '$pid' is locking the configuration database. Terminating." >&2
            exit 1
	fi
	sleep 2
	i=$(($i + 1))
    done

    # lock the configuration file
    echo "$$" > "$LOCKFILE"
}

remove_lock() {
    rm -f "$LOCKFILE"
}

update_config() {
    updateaction="$1"
    updatebasename="$2"
    startlist="$3"
    stoplist="$4"
    rm -f $TMPFILE
    touch $TMPFILE

    SORT_NO=0
    if [ -n "$stoplist" ]; then
	stopseq=`get_shortest_sequence $stoplist`
    fi
    if [ -n "$startlist" ]; then
	startseq=`get_shortest_sequence $startlist`
    fi
    stopseen=0
    startseen=0
    while read LINE
    do
	case $LINE in
	    \#\ THE\ LAST\ LINE\ IS\ NEVER\ READ* )
	    # remove this "last" line and add it at the end of runlevel.conf
		continue
		;;
	    \#* | "" )
		echo "$LINE" >> "$TMPFILE"
		continue
		;;
	esac

	set -- $LINE
	SORT_NO="$1"; STOP="$2"; START="$3"; CMD="$4"

	if [ "$updateaction" = "add" ]; then
	    if [ -n "$stoplist" ]; then
		if [ $stopseen -eq 0 ]; then
		    if [ $SORT_NO -gt $stopseq ]; then
			print_config_stop_line "$updatebasename" "$stoplist"
			stopseen="1"
		    fi
		fi
	    fi
	    if [ -n "$startlist" ]; then
		if [ $startseen -eq 0 ]; then
		    if [ $SORT_NO -gt $startseq ]; then
			print_config_start_line "$updatebasename" "$startlist"
			startseen="1"
		    fi
		fi
	    fi
	fi

	if [ "$CMD" != "/etc/init.d/$updatebasename" ]
	then
	    case "$SORT_NO" in
		?) SORT_NO=0$SORT_NO
		    modified="1"
		    ;;
	    esac
	    echo "$SORT_NO	$STOP	$START		$CMD" >> "$TMPFILE"
	elif [ "$updateaction" = "remove" ]
	then
	    # Remove by not echoing the line.
	    modified="1"
	fi

    done < "$CFGFILE"

    if [ "$updateaction" = "add" ]; then
	if [ -n "$stoplist" ]; then
	    if [ $stopseen -eq 0 ]; then
		print_config_stop_line "$updatebasename" "$stoplist"
		stopseen="1"
	    fi
	fi
	if [ -n "$startlist" ]; then
	    if [ $startseen -eq 0 ]; then
		print_config_start_line "$updatebasename" "$startlist"
		startseen="1"
	    fi
	fi
    fi

    echo '# THE LAST LINE IS NEVER READ' >> "$TMPFILE"

    if [ -z "$modified" ]
    then
	echo "Nothing to do."
	rm -f "$TMPFILE"
    else
	if [ $opt_simulate -eq 0 ]; then
	    umask=022
	    mv "$TMPFILE" "$CFGFILE"
	else
	    echo "$TMPFILE not installed as $CFGFILE"
	fi
    fi
}

list_scripts() {
    while read LINE
    do
	case $LINE in
	    \#\ THE\ LAST\ LINE\ IS\ NEVER\ READ* )
		continue
		;;
	    \#* | "" )
		continue
		;;
	esac
	set -- $LINE
	SORT_NO="$1"; STOP="$2"; START="$3"; CMD="$4"
	if [ -x "$CMD" ]; then
	    echo $(basename "$CMD")
	fi
    done < "$CFGFILE"
}

action="$1"

# Update existing scripts with insserv info
if [ -x /sbin/insserv ]; then
    in_data="$(/sbin/insserv -s 2>/dev/null)"

    case "$action" in
	defaults|add|remove|start|stop)
	    create_lock
	    for script in $(list_scripts | sort | uniq); do
		START_SORT_NO=
		STARTLEVELS=
		STOP_SORT_NO=
		STOPLEVELS=
		if insserv_find "$in_data" "$script"; then
		    STARTLIST=
		    STOPLIST=
		    for lev in $STARTLEVELS; do
			STARTLIST="$STARTLIST$lev:$START_SORT_NO "
		    done
		    for lev in $STOPLEVELS; do
			STOPLIST="$STOPLIST$lev:$STOP_SORT_NO "
		    done
		    update_config add "$script" "$STARTLIST" "$STOPLIST"
		fi
	    done
	    remove_lock
	    ;;
    esac
fi

START_SORT_NO=
STARTLEVELS=
STOP_SORT_NO=
STOPLEVELS=
if [ -x /sbin/insserv ] && insserv_find "$in_data" "$basename"; then
    IN_FOUND="true"
else
    IN_FOUND="false"
fi

if [ "$IN_FOUND" = "true" ]; then
    echo "update-rc.d (file-rc) using dependency based boot sequencing"
else
    echo "update-rc.d (file-rc) using static boot sequencing (WARNING)"
fi

STARTLIST=
STOPLIST=
case "$action" in
    defaults)
	if [ "$IN_FOUND" = "false" ]; then
	    STARTLEVELS="2 3 4 5"
	    STOPLEVELS="0 1 6"
	    case "$#" in
		"1")
		    START_SORT_NO="20"
		    STOP_SORT_NO="20"
		    ;;
		"2")
		    START_SORT_NO="$2"
		    STOP_SORT_NO="$2"
		    ;;
		"3")
		    START_SORT_NO="$2"
		    STOP_SORT_NO="$3"
		    ;;
	    esac
	fi

	if [ -n "$START_SORT_NO" ] && ! is_valid_sequence "$START_SORT_NO"
	then
	    echo "Invalid sequence $START_SORT_NO."
	    exit 1
	fi
	if [ -n "$STOP_SORT_NO" ] && ! is_valid_sequence "$STOP_SORT_NO"
	then
	    echo "Invalid sequence $STOP_SORT_NO."
	    exit 1
	fi
	for lev in $STARTLEVELS; do
	    STARTLIST="$STARTLIST$lev:$START_SORT_NO "
	done
	for lev in $STOPLEVELS; do
	    STOPLIST="$STOPLIST$lev:$STOP_SORT_NO "
	done
	create_lock
	update_config add "$basename" "$STARTLIST" "$STOPLIST"
	remove_lock
	;;
    remove)
	START_SORT_NO="*"
	STOP_SORT_NO="*"
	create_lock
	update_config remove "$basename" "$STARTLIST" "$STOPLIST"
	remove_lock
	;;
    start|stop)
	if [ "$IN_FOUND" = "false" ]; then
	# Loop over the remaining arguments
	    while [ $# -gt 0 ]
	    do
 		if [ $# -gt 2 ]
 		then
 		    type="$1"; shift
 		    seq="$1"; shift
 		    levels=
		    if [ "$type" != "start" -a "$type" != "stop" ]
		    then
			echo "Invalid type $type."
			exit 1
		    fi
 		    if ! is_valid_sequence $seq
 		    then
 			echo "Invalid sequence $seq."
 			exit 1
 		    fi
 		    while [ $# -gt 0 -a "$1" != "." ]
 		    do
			if ! is_valid_runlevel $1
			then
			    echo "Invalid runlevel $1."
			    exit 1
			fi
 			levels="$levels$1 "; shift
 		    done
 		    if [ $# -gt 0 -a "$1" = "." ]
 		    then
 			shift
 		    fi
		    case "$type" in
			"start")
			    for lev in $levels; do
				STARTLIST="$STARTLIST$lev:$seq "
			    done
			    ;;
			"stop")
			    for lev in $levels; do
				STOPLIST="$STOPLIST$lev:$seq "
			    done
			    ;;
		    esac
 		else
 		    echo "Too few arguments."
 		    print_usage
 		    exit 1
 		fi
	    done
	else
	    for lev in $STARTLEVELS; do
		STARTLIST="$STARTLIST$lev:$START_SORT_NO "
	    done
	    for lev in $STOPLEVELS; do
		STOPLIST="$STOPLIST$lev:$STOP_SORT_NO "
	    done
	fi
	create_lock
	update_config add "$basename" "$STARTLIST" "$STOPLIST"
	remove_lock
	;;
    *)
	print_usage
	;;
esac

exit 0
