#!/bin/sh

if [ "$1" = "" ]; then
    echo "usage: cfgfindraw.sh <string>"
    exit 1
fi

. $AKKADA/etc/akkada.shell

DIR=$AKKADA/etc

find $DIR -type f -exec grep -i -H $1 {} \;
