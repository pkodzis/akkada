#!/bin/sh

. $AKKADA/etc/akkada.shell

TIMESTAMP=`date +%s`

$AKKADA/bin/mysql_db_dump.sh

[ -e $BackupDir ] || mkdir $BackupDir
[ -e $BackupDir ] || exit;

ARCHIVE="bin lib etc htdocs"
cd "${AKKADA}"

for module in $ARCHIVE; do
        echo "${AKKADA}/${module} -> ${BackupDir}/${module}-${TIMESTAMP}.tgz"
        tar -zcf "${BackupDir}/${module}-${TIMESTAMP}.tgz" "${module}"
done

if [ -e $BackupDir/post_backup.sh ]; then
    CDIR=`pwd`
    cd $BackupDir
    ./post_backup.sh  $TIMESTAMP
    cd $CDIR
fi
