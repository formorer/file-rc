#!/bin/sh
# rcfile2link.sh
# Convert the rc-file back into symlinks.
#
# Copyright (c) 1997, Tom Lees <tom@lpsg.demon.co.uk>.
#
# Hacked out of the file-based rc script.
#
# Misc fixes by Roland Rosenfeld <roland@spinnaker.de>
#
# $Id: rcfile2link.sh,v 1.10 2008-05-01 10:16:33 roland Exp $

CFGFILE="/etc/runlevel.conf"
BAKCFG="/etc/runlevel.fallback"
LOCKFILE="/var/lock/runlevel.lock"

i=0
while [ -f "$LOCKFILE" -a "$previous" != "N" ]
do
    read pid < "$LOCKFILE"
    if ! kill -s 0 $pid > /dev/null 2>&1
    then
	echo "$0: found stale lockfile '$LOCKFILE'. Ignoring it." >&2
# restriction on built-in functions ...
#        rm -f "$LOCKFILE"
        break
    fi
    if [ "$i" -gt "10" ]
    then
        echo "Process no. '$pid' is locking the configuration database. Terminating." >&2
        exit 1
    fi
    sleep 2
    i=$(($i + 1))
done

cd /etc
for i in 0 1 2 3 4 5 6 S; do
    [ -d rc${i}.d ] || mkdir rc${i}.d
done

while read  SORT_NO  OFF_LEVELS  ON_LEVELS  CMD  OPTIONS
do
    case "$SORT_NO" in
	\#*|""|\#) continue ;;
	?) SORT_NO=0$SORT_NO ;;
    esac
    [ ! -f $CMD ] && continue

    NAME=`basename $CMD`
    CMD=..${CMD##/etc}

    OLDIFS="$IFS"
    IFS=,
    [ "$OFF_LEVELS" = "-" ] || for i in $OFF_LEVELS; do
	if [ "$i" = "S" ]
	then
	    [ -f rc$i.d/K${SORT_NO}$NAME ] || ln -s $CMD rc$i.d/S${SORT_NO}$NAME 
	else
	    [ $i -ge 0 -a $i -le 6 -a ! -f rc$i.d/K${SORT_NO}$NAME ] && ln -s $CMD rc$i.d/K${SORT_NO}$NAME
	fi
    done
    [ "$ON_LEVELS" = "-" ] || for i in $ON_LEVELS; do
	if [ "$i" = "S" ]
	then
	    [ -f rc$i.d/S${SORT_NO}$NAME ] || ln -s $CMD rc$i.d/S${SORT_NO}$NAME 
	else
	    [ $i -ge 0 -a $i -le 6 -a ! -f rc$i.d/S${SORT_NO}$NAME ] && ln -s $CMD rc$i.d/S${SORT_NO}$NAME 
	fi
    done
    IFS="$OLDIFS"
    unset OLDIFS

done < $CFGFILE

# End of file.
