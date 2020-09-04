#!/bin/bash

. $AKKADA/etc/akkada.shell

case "$1" in
  t)
        tail -f $AKKADA/var/log/exc_text.log
        ;;
  text)
        tail -f $AKKADA/var/log/exc_text.log
        ;;
  x)
        tail -f $AKKADA/var/log/exc_xml.log
        ;;
  xml)
        tail -f $AKKADA/var/log/exc_xml.log
        ;;
  *)
        tail -f $AKKADA/var/log/exc_text.log $AKKADA/var/log/exc_xml.log
        ;;
esac

