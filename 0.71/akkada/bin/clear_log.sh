#!/bin/sh

. $AKKADA/etc/akkada.shell

rm -f $AKKADA/var/log/*.log

touch $AKKADA/var/log/exc_text.log
touch $AKKADA/var/log/exc_xml.log
chgrp $ApacheGroup $AKKADA/var/log/*
chown $OSLogin $AKKADA/var/log/*
chmod 664 $AKKADA/var/log/*
