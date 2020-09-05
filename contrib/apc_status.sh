#!/bin/bash

# Date: 	2007.12.30 
# Version: 	0.1
# Author: 	ciechom@eserwer.pl 
# Info: 
#
#  This script provides collecting information about APC UPS device 
#  from apcupsd daemon (see: http://www.apcupsd.com).
#  Script can by attached to the snmpd daemon by adding e.g. lines to 
#  the snmpd.conf file: 
#
#  exec UPS01_InputStatus	/etc/_scripts/apc_status 01 status	
#  exec UPS01_OutputVoltage	/etc/_scripts/apc_status 01 outputv
#  exec UPS01_LineVoltage 	/etc/_scripts/apc_status 01 linev
#  exec UPS01_LineFrequency 	/etc/_scripts/apc_status 01 linefreq
#  exec UPS01_UpsLoad 		/etc/_scripts/apc_status 01 loadpct
#  exec UPS01_BatteryCharge 	/etc/_scripts/apc_status 01 bcharge
#  exec UPS01_BatteryVoltage 	/etc/_scripts/apc_status 01 battv
#  exec UPS01_BatteryLeft 	/etc/_scripts/apc_status 01 timeleft
#  exec UPS01_InternalTemp	/etc/_scripts/apc_status 01 itemp

SERVER=$1
PARAM=$2

case $SERVER in

01)
 SERVERIP="192.168.2.100:3551"
;;

*)
 echo "Using localhost"
 SERVERIP="" 
;;

esac


COMMAND="/sbin/apcaccess status $SERVERIP"


case $PARAM in

status)
  STAT=`$COMMAND |grep "^STATUS" | /bin/awk '{print $3}'`
  echo "AKKADA||TEXT||expected=ONLINE::output=$STAT::brief=Input power status: $STAT::errmsg=Input Power ERROR: $STAT"
;;

outputv)
  OUTPUTV=`$COMMAND |grep "^OUTPUTV" | /bin/awk '{print $3}'`
  LOTRANS=`$COMMAND |grep "^LOTRANS" | /bin/awk '{print $3}'`
  HITRANS=`$COMMAND |grep "^HITRANS" | /bin/awk '{print $3}'`

  if [ -n "$VALUE" ]; then
    OUTPUTV=0
    LOTRANS=200
    HITRANS=250
  fi
  
  echo "AKKADA||STAT||title=Output_Voltage::output=$OUTPUTV::cfs=GAUGE::min=$LOTRANS::max=$HITRANS||title=Min::output=$LOTRANS::cfs=GAUGE||title=Max::output=$HITRANS::cfs=GAUGE"
;;


linev)
  LINEV=`$COMMAND |grep "^LINEV" | /bin/awk '{print $3}'`
  LOTRANS=`$COMMAND |grep "^LOTRANS" | /bin/awk '{print $3}'`
  HITRANS=`$COMMAND |grep "^HITRANS" | /bin/awk '{print $3}'`

  if [ -n "$VALUE" ]; then
    LINEV=0
    LOTRANS=200
    HITRANS=250
  fi
  
  echo "AKKADA||STAT||title=Line_Voltage::output=$LINEV::cfs=GAUGE::min=$LOTRANS::max=$HITRANS||title=Min::output=$LOTRANS::cfs=GAUGE||title=Max::output=$HITRANS::cfs=GAUGE"
;;


linefreq)
  LINEFREQ=`$COMMAND |grep "^LINEFREQ" | /bin/awk '{print $3}'`
  if [ -n "$VALUE" ];then LINEFREQ=0; fi 
  echo "AKKADA||STAT||title=Line_Frequency::output=$LINEFREQ::cfs=GAUGE::min=40::max=60"
;;


loadpct)
  LOADPCT=`$COMMAND |grep "^LOADPCT" | /bin/awk '{print $3}'`
  if [ -n "$VALUE" ]; then LOADPCT=0; fi
  echo "AKKADA||STAT||title=Load_Capacity::output=$LOADPCT::cfs=GAUGE::max=90"
;;

bcharge)
  BCHARGE=`$COMMAND |grep "^BCHARGE" | /bin/awk '{print $3}'`
  if [ -n "$VALUE" ]; then BCHARGE=0; fi
  echo "AKKADA||STAT||title=Battery_Cherge::output=$BCHARGE::cfs=GAUGE::min=10::max=100"
;;


battv)
  BATTV=`$COMMAND |grep "^BATTV" | /bin/awk '{print $3}'`
  if [ -n "$VALUE" ]; then BATTV=0; fi
  echo "AKKADA||STAT||title=Battery_Volts::output=$BATTV::cfs=GAUGE::min=20::max=30"
;;


timeleft)
  TIMELEFT=`$COMMAND |grep "^TIMELEFT" | /bin/awk '{print $3}'`
  if [ -n "$VALUE" ]; then TIMELEFT=0; fi
  echo "AKKADA||STAT||title=TimeLeft_on_Batt::output=$TIMELEFT::cfs=GAUGE::min=5"
;;

itemp)
  ITEMP=`$COMMAND |grep "^ITEMP" | /bin/awk '{print $3}'`
  if [ -n "$VALUE" ]; then ITEMP=0; fi
  echo "AKKADA||STAT||title=Internal_Temp::output=$ITEMP::cfs=GAUGE::min=10::max=60"
;;

*)
  echo "usage: apc_status SERVERNUM [ status|outputv|linev|linefreq|loadpct|bcharge|battv|timeleft|itemp ]"
;;

esac
