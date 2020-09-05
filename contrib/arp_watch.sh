#!/bin/sh

#
# this script checks availablility of the host on the same LAN
# as server where is running and provide that informationa
# to snmpd agent. should be attached to the snmpd daemon by adding e.g. 
# line to the snmpd.conf file:
#
# exec  "arp_watch" /usr/local/bin/arp_watch.sh 192.168.1.1
#
# after snmpd daemon restart AKK@DA will detect new sevice "arp_watch"
# and will start to monitor it. If you need to understand output produced
# by this script see UCD_EXT probe documentation at http://akkada.tivi.net.pl/
# (mode TEXT)
#
# this is useful if you need to monitor host's availability and this host's 
# firewall block all ip traffic
#

if [ "$1" = "" ] ; then
    echo "usage: arp_watch.sh <ip address>"
    exit 1
fi

ARP=`/sbin/arp -d $1 2>/dev/null; /bin/ping -c 1 -W 1 $1 >/dev/null; arp -a | /bin/grep $1 | /bin/awk '{print $4}'`

echo "AKKADA||TEXT||bad=<incomplete>::output=$ARP::brief=ip address $1, MAC address $ARP::errmsg=ip address unreachable"

