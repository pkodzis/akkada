#!/bin/sh

. $AKKADA/etc/akkada.shell || exit;

chown $OSLogin $AKKADA
chgrp $OSGroup $AKKADA
chmod 755 $AKKADA

[ -d $AKKADA/var ] || mkdir $AKKADA/var
[ -d $AKKADA/var/control ] || mkdir $AKKADA/var/control
[ -d $AKKADA/var/data ] || mkdir $AKKADA/var/data
[ -d $AKKADA/var/icmp_status ] || mkdir $AKKADA/var/icmp_status
[ -d $AKKADA/var/last_check ] || mkdir $AKKADA/var/last_check
[ -d $AKKADA/var/last_discover ] || mkdir $AKKADA/var/last_discover
[ -d $AKKADA/var/log ] || mkdir $AKKADA/var/log
[ -d $AKKADA/var/nosnmp ] || mkdir $AKKADA/var/nosnmp
[ -d $AKKADA/var/pid ] || mkdir $AKKADA/var/pid
[ -d $AKKADA/var/probe_status ] || mkdir $AKKADA/var/probe_status
[ -d $AKKADA/var/rrd ] || mkdir $AKKADA/var/rrd
[ -d $AKKADA/var/rrd_graph_tmp ] || mkdir $AKKADA/var/rrd_graph_tmp
[ -d $AKKADA/var/sessions ] || mkdir $AKKADA/var/sessions
[ -d $AKKADA/var/status_calc ] || mkdir $AKKADA/var/status_calc
[ -d $AKKADA/var/tree_cache ] || mkdir $AKKADA/var/tree_cache
[ -d $AKKADA/var/unreachable ] || mkdir $AKKADA/var/unreachable
[ -d $AKKADA/var/actions ] || mkdir $AKKADA/var/actions
[ -d $AKKADA/var/top ] || mkdir $AKKADA/var/top
[ -d $AKKADA/var/correl ] || mkdir $AKKADA/var/correl
[ -d $AKKADA/var/av2 ] || mkdir $AKKADA/var/av2

cd $AKKADA
chown $OSLogin *
chgrp $OSGroup *
chgrp $ApacheGroup var;
chmod 755 *

rm -f bin/perl

find var/* -type f -exec chown $OSLogin {} \;
find var/* -type f -exec chgrp $ApacheGroup {} \;
find var/* -type f -exec chmod 660 {} \;
find var/* -type d -exec chown $OSLogin {} \;
find var/* -type d -exec chgrp $ApacheGroup {} \;
find var/* -type d -exec chmod 770 {} \;

find htdocs/* -type f -exec chown $OSLogin {} \;
find htdocs/* -type f -exec chgrp $OSGroup {} \;
find htdocs/* -type f -exec chmod 644 {} \;
find htdocs/* -type d -exec chown $OSLogin {} \;
find htdocs/* -type d -exec chgrp $OSGroup {} \;
find htdocs/* -type d -exec chmod 755 {} \;

find lib/* -type f -exec chown $OSLogin {} \;
find lib/* -type f -exec chgrp $ApacheGroup {} \;
find lib/* -type f -exec chmod 640 {} \;
find lib/* -type d -exec chown $OSLogin {} \;
find lib/* -type d -exec chgrp $ApacheGroup {} \;
find lib/* -type d -exec chmod 750 {} \;

chown $OSLogin bin/*
chgrp $OSGroup bin/*
chmod a-x bin/*
chmod u+rw,g-rw,o-rw bin/*
chmod u+x bin/*.pl
chmod u+x bin/*.sh
chmod u+x bin/akkada

chgrp $ApacheGroup bin/startup.pl
chmod 640 bin/startup.pl

chown $OSLogin etc/*
chgrp $OSGroup etc/*
chgrp $ApacheGroup etc/akkada.conf
chmod 640 etc/akkada.conf
chmod 640 etc/akkada.shell
chown $OSLogin etc/init.d/akkada
chgrp $OSGroup etc/init.d/akkada
chmod 700 etc/init.d/akkada
[ -e  etc/init.d/akkada_pre ] && chmod 700 etc/init.d/akkada_pre

chgrp $ApacheGroup etc/conf.d
chgrp $ApacheGroup etc/snmp_generic
chgrp $ApacheGroup etc/Tools

find etc/conf.d/* -type f -exec chown $OSLogin {} \;
find etc/conf.d/* -type f -exec chgrp $ApacheGroup {} \;
find etc/conf.d/* -type f -exec chmod 640 {} \;
find etc/conf.d/* -type d -exec chown $OSLogin {} \;
find etc/conf.d/* -type d -exec chgrp $ApacheGroup {} \;
find etc/conf.d/* -type d -exec chmod 750 {} \;

find etc/snmp_generic/* -type f -exec chown $OSLogin {} \;
find etc/snmp_generic/* -type f -exec chgrp $ApacheGroup {} \;
find etc/snmp_generic/* -type f -exec chmod 640 {} \;
find etc/snmp_generic/* -type d -exec chown $OSLogin {} \;
find etc/snmp_generic/* -type d -exec chgrp $ApacheGroup {} \;
find etc/snmp_generic/* -type d -exec chmod 750 {} \;

find etc/Tools/* -type f -exec chown $OSLogin {} \;
find etc/Tools/* -type f -exec chgrp $ApacheGroup {} \;
find etc/Tools/* -type f -exec chmod 640 {} \;
find etc/Tools/* -type d -exec chown $OSLogin {} \;
find etc/Tools/* -type d -exec chgrp $ApacheGroup {} \;
find etc/Tools/* -type d -exec chmod 750 {} \;

cd bin
[ -e perl ] || ln -s `which perl` perl
[ -e akkada ] || ln -s ../etc/init.d/akkada akkada

