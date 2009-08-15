#! /bin/sh
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
    local seq s i list
    seq=$1; shift
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

remove_sequence() {
    local outline
    seq=$1; shift
    outline=""
    for i in $*
    do
	s=${i##*:}
        if [ "$s" != "$seq" ]
	then
	    outline="$outline$i "
	fi
    done
    echo "$outline"
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

print_config_line() {
    if [ $startseq -eq $stopseq ]
    then
	NEW_START=`get_runlevels_for_sequence $startseq $STARTLIST`
	NEW_STOP=`get_runlevels_for_sequence $stopseq $STOPLIST`
	NEW_SEQ=$startseq
	STARTLIST=`remove_sequence $startseq $STARTLIST`
	STOPLIST=`remove_sequence $stopseq $STOPLIST`
	startseq=`get_shortest_sequence $STARTLIST`
	stopseq=`get_shortest_sequence $STOPLIST`
    else
	if [ $startseq -lt $stopseq ]
	then
	    NEW_START=`get_runlevels_for_sequence $startseq $STARTLIST`
	    NEW_STOP="-"
	    NEW_SEQ=$startseq
	    STARTLIST=`remove_sequence $startseq $STARTLIST`
	    startseq=`get_shortest_sequence $STARTLIST`
	else
	    NEW_START="-"
	    NEW_STOP=`get_runlevels_for_sequence $stopseq $STOPLIST`
	    NEW_SEQ=$stopseq
	    STOPLIST=`remove_sequence $stopseq $STOPLIST`
	    stopseq=`get_shortest_sequence $STOPLIST`
	fi
    fi
    [ -z "$NEW_START" ] && NEW_START="-"
    [ -z "$NEW_STOP" ] && NEW_STOP="-"
    case "$NEW_SEQ" in
	?) NEW_SEQ=0$NEW_SEQ ;;
    esac
    echo "$NEW_SEQ	$NEW_STOP	$NEW_START		/etc/init.d/$basename" >> "$TMPFILE"
    modified="1"
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


cmd_already_there() {
    local CMD
    while read LINE
    do
	case $LINE in
	    \#* | "" ) continue
	esac
	set -- $LINE
	CMD="$4"
	[ "$CMD" = "/etc/init.d/$basename" ] && return 0
    done < "$CFGFILE"
    return 1
}


START_SORT_NO=""
STOP_SORT_NO=""
STARTLEVELS=""
STOPLEVELS=""

STARTLIST=
STOPLIST=
action="$1"
case "$action" in
    defaults)
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

	if ! is_valid_sequence $START_SORT_NO || ! is_valid_sequence $STOP_SORT_NO
	then
	    echo "Invalid sequence $START_SORT_NO or $STOP_SORT_NO."
	    exit 1
	fi
	for lev in $STARTLEVELS; do
	    STARTLIST="$STARTLIST$lev:$START_SORT_NO "
	done
	for lev in $STOPLEVELS; do
	    STOPLIST="$STOPLIST$lev:$STOP_SORT_NO "
	done
	action=add
	;;
    remove)
	START_SORT_NO="*"
	STOP_SORT_NO="*"
	;;
    start|stop)
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
	action=add
	;;
    *)
	print_usage
	;;
esac

remove_lock() {
    rm -f "$LOCKFILE"
}

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

if [ $opt_force -eq 0 -a "$action" != "remove" ] && cmd_already_there 
then
    echo "$basename already in $CFGFILE: No change."
    remove_lock
    exit 0
fi

skip=""
rm -f $TMPFILE
touch $TMPFILE

stopseq=`get_shortest_sequence $STOPLIST`
startseq=`get_shortest_sequence $STARTLIST`
SORT_NO=0
seen=0
while read LINE
do
    remove=0

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

    if [ "$CMD" = "/etc/init.d/$basename" ] 
    then
	[ "$action" = "remove" ] && remove=1
	[ "$action" = "add" -a $opt_force -eq 1 ] && remove=1
	[ $opt_force -eq 0 ] && seen=1
    fi

    if [ $seen -eq 0 ]
    then
	if [ $SORT_NO -gt $stopseq -o $SORT_NO -gt $startseq ]
	then
	    print_config_line
	fi
    fi

    if [ $remove -ne 1 ]
    then
	case "$SORT_NO" in
	    ?) SORT_NO=0$SORT_NO
	       modified="1"
	       ;;
	esac
	echo "$SORT_NO	$STOP	$START		$CMD" >> "$TMPFILE"
    else
	modified="1"
    fi

done < "$CFGFILE"

if [ $seen -eq 0 ]
then
    while [ -n "$STARTLIST" -o  -n "$STOPLIST" ]
    do
	print_config_line
    done
fi
echo '# THE LAST LINE IS NEVER READ' >> "$TMPFILE"

remove_lock

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
exit 0
