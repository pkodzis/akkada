#!/bin/sh

if [ ! "$AKKADA" ]; then
   echo "env variable AKKADA not defined";
   exit 1;
fi

# przeprobic na wywolania z poziomu perla a czesc mysqlowa przeniesc do lib

echo "press ENTER if the database password is empty"

mysqldump -u root akkada -p > $AKKADA/bin/akkada_db_dump.sql
