#!/bin/sh

#
# by ciechom@eserwer.pl 
#
# this script provides active and deferred count of mails in postfix mail queue
# to snmpd agent. should be copied to the server with postfix and
# attached to the snmpd daemon by adding e.g. line to the snmpd.conf 
# file: 
#
# exec  "postfix_ad" /usr/local/bin/postfix_mail_queue_ad.sh
#
# after snmpd daemon restart AKK@DA will detect new sevice "postfix_ad"
# and will start to monitor it. If you need to understand output produced
# by this script see UCD_EXT probe documentation at http://akkada.tivi.net.pl/
# (mode STAT)
#


CMD=`which postconf 2>/dev/null`

if [ "$CMD" = "" ]; then
        echo "postconf command not found"
        exit 1;
fi

cd /etc/postfix
sum=0
qdir=`$CMD -h queue_directory`
active=`find $qdir/incoming $qdir/active $qdir/maildrop -type f -print | wc -l | awk '{print $1}'`
deferred=`find $qdir/deferred -type f -print | wc -l | awk '{print $1}'`
echo "AKKADA||STAT||title=Active::output=$active::cfs=GAUGE||title=Deferred::output=$deferred::cfs=GAUGE"

