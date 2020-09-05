#!/bin/sh

. $AKKADA/etc/akkada.shell

find  ${AKKADA}/var/* -type f -exec rm -f {} \;
for i in ${AKKADA}/var/* ; do echo "removing files from directory $i" ; rm -rf $i/* ; done

mysql -u root akkada < $AKKADA/bin/clear_all_system.mysql 
mysql -u root akkada < $AKKADA/bin/akkada_db_users_init.sql

$AKKADA/bin/clear_log.sh
