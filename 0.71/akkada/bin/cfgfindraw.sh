#!/bin/sh

. $AKKADA/etc/akkada.shell

DIR=$AKKADA/etc

find $DIR -type f -exec grep -H $1 {} \;
