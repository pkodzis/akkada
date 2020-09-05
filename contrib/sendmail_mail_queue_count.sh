#!/bin/sh

#
# this script provides count of mails in sendmail mail queue
# to snmpd agent. should be copied to the server with postfix and
# attached to the snmpd daemon by adding e.g. line to the snmpd.conf 
# file: 
#
# exec  "sendmail_mc" /usr/local/bin/sendmail_mail_queue_count.pl
#
# after snmpd daemon restart AKK@DA will detect new sevice "sendmail_mc"
# and will start to monitor it.  If you need to raise any alarms
# see UCD_EXT probe documentation at http://akkada.tivi.net.pl/
# (mode RAW)
#


CMD=`which mailq 2>/dev/null`

if [ "$CMD" = "" ]; then
        echo "mailq command not found"
        exit 1;
fi


$CMD | /bin/grep Total | /bin/awk '{ print $3 }'
