#!/bin/sh

#
# by ciechom@eserwer.pl 
#
# this script provides total count of mails in postfix mail queue
# to snmpd agent. should be copied to the server with postfix and
# attached to the snmpd daemon by adding e.g. line to the snmpd.conf 
# file: 
#
# exec  "postfix_mq" /usr/local/bin/postfix_mail_queue_count.sh
#
# after snmpd daemon restart AKK@DA will detect new sevice "postfix_mq"
# and will start to monitor it. If you need to raise any alarms
# see UCD_EXT probe documentation at http://akkada.tivi.net.pl/
# (mode RAW)
#

CMD=`which postqueue 2>/dev/null`

if [ "$CMD" = "" ]; then
	echo "postqueue command not found"
	exit 1;
fi

COUNT=`$CMD -p |grep Requests. |cut -d "R" -f 1 |cut -d "n" -f 2 |cut -d " " -f 2`
echo $COUNT
