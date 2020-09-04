#!/bin/sh

if [ ! "$AKKADA" ]; then
   echo "env variable AKKADA not defined";
   exit 1;
fi

# przeprobic na wywolania z poziomu perla a czesc mysqlowa przeniesc do lib

mysqldump -u root akkada > $AKKADA/bin/akkada_db_dump.sql
