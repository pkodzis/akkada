#!/bin/sh

#
# this script checks if file exists
# at server where is running and provide that informationa
# to snmpd agent. should be attached to the snmpd daemon by adding e.g. 
# line to the snmpd.conf file:
#
# exec  "<description>" /usr/local/bin/file_exists.sh <exists|not-exists> <file name> [error message]
#
# after snmpd daemon restart AKK@DA will detect new sevice "file_exists.sh"
# and will start to monitor it. If you need to understand output produced
# by this script see UCD_EXT probe documentation at http://akkada.tivi.net.pl/
# (mode TEXT)
#

if [ "$1" = "" -o "$2" = "" ]; then
    echo "usage: $0 <exists|not-exists> <file name> [error message]"
    exit 1
fi

if [ -e $2 ]; then
    RES="$2 exists"
else
    RES="$2 not exists"
fi

if [ "$3" = "" -a "$1" = "exists" ]; then 
    ERR="file not exists!"
elif [ "$3" = "" -a "$1" = "not-exists" ]; then
    ERR="file exists!"
else
    ERR=$3;
fi

if [ "$1" = "exists" ]; then
    echo "AKKADA||TEXT||bad=not::output=$RES::brief=$RES::errmsg=$ERR"
else
    echo "AKKADA||TEXT||expected=not::output=$RES::brief=$RES::errmsg=$ERR"
fi;


exit 0;

