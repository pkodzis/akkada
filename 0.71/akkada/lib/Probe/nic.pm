package Probe::nic;

use vars qw($VERSION);

$VERSION = 0.49;

use base qw(Probe);
use strict;

use Net::SNMP qw(ticks_to_time);
use Number::Format qw(:subs);

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use URLRewriter;

our $DataDir = CFG->{Probe}->{DataDir};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};
our $MaxSNMPSplitRequest = CFG->{MaxSNMPSplitRequest};
our $ICMPMonitorStatusDir = CFG->{ICMPMonitor}->{StatusDir};
our $IANAifType = CFG->{Probes}->{nic}->{IANAifType};

$Number::Format::DECIMAL_FILL = 1;

sub id_probe_type
{
    return 3;
}

sub name
{
    return 'network interface';
}


use constant
{
    IFENTRY => 10,
    PORTENTRY => 11,
    VLANPORTVLAN => 12,
    IFALIAS => 13,
    IPADDRENTRY=> 14,
    NIC_IP => 15,
    RRD_DATA => 16,
};

my $O_IFENTRY = '1.3.6.1.2.1.2.2.1';
my $O_IFALIAS = '1.3.6.1.2.1.31.1.1.1.18';

my $O_VLANPORTVLAN = '1.3.6.1.4.1.9.5.1.9.3.1.3';
my $O_PORTENTRY = '1.3.6.1.4.1.9.5.1.4.1.1';

my $_ifEntry = 
{
    1 => 'ifIndex',
    2 => 'ifDescr',
    3 => 'ifType',
    4 => 'ifMtu',
    5 => 'ifSpeed',
    6 => 'ifPhysAddress',
    7 => 'ifAdminStatus',
    8 => 'ifOperStatus',
    9 => 'ifLastChange',
    10 => 'ifInOctets',
    11 => 'ifInUcastPkts',
    12 => 'ifInNUcastPkts',
    13 => 'ifInDiscards',
    14 => 'ifInErrors',
    15 => 'ifInUnknownProtos',
    16 => 'ifOutOctets',
    17 => 'ifOutUcastPkts',
    18 => 'ifOutNUcastPkts',
    19 => 'ifOutDiscards',
    20 => 'ifOutErrors',
    21 => 'ifOutQLen',
    22 => 'ifSpecific',
};

my $_portEntry = 
{
    1 => 'portModuleIndex',
    2 => 'portIndex',
    3 => 'portCrossIndex',
    4 => 'portName',
    5 => 'portType',
    6 => 'portOperStatus',
    7 => 'portCrossGroupIndex',
    8 => 'portAdditionalStatus',
    9 => 'portAdminSpeed',
    10 => 'portDuplex',
    11 => 'portIfIndex',
    12 => 'portSpantreeFastStart',
    13 => 'portAdminRxFlowControl',
    14 => 'portOperRxFlowControl',
    15 => 'portAdminTxFlowControl',
    16 => 'portOperTxFlowControl',
    17 => 'portMacControlTransmitFrames',
    18 => 'portMacControlReceiveFrames',
    19 => 'portMacControlPauseTransmitFrames',
    20 => 'portMacControlPauseReceiveFrames',
    21 => 'portMacControlUnknownProtocolFrames',
    22 => 'portLinkFaultStatus',
    23 => 'portAdditionalOperStatus',
    24 => 'portInlinePowerDetect',
    25 => 'portEntPhysicalIndex',
};


my $_portLinkFaultStatus = 
{
    1 => 'noFault',
    2 => 'nearEndFault',
    3 => 'nearEndConfigFail',
    4 => 'farEndDisable',
    5 => 'farEndFault',
    6 => 'farEndConfigFail',
    7 => 'notApplicable',
};

my $_portOperStatus = 
{
    1 => 'other',
    2 => 'ok',
    3 => 'minorFault',
    4 => 'majorFault',
};

my $_portAdditionalOperStatus = 
{
    0 => 'other',
    1 => 'connected',
    2 => 'standby',
    3 => 'faulty',
    4 => 'notConnected',
    5 => 'inactive',
    6 => 'shutdown',
    7 => 'dripDis',
    8 => 'disabled',
    9 => 'monitor',
    10 => 'errdisable',
    11 => 'linkFaulty',
    12 => 'onHook',
    13 => 'offHook',
};

my $_ifAdminStatus = 
{
    1 => 'up',
    2 => 'down',
    3 => 'testing',
};

my $_ifOperStatus = 
{
    1 => 'up',
    2 => 'down',
    3 => 'testing',
    4 => 'unknown',
    5 => 'dormant',
    6 => 'notPresent',
    7 => 'lowerLayerDown',
};

my $_ipAddrEntry = 
{
    1 => 'ipAdEntAddr',
    2 => 'ipAdEntIfIndex',
    3 => 'ipAdEntNetMask',
    4 => 'ipAdEntBcastAddr',
    5 => 'ipAdEntReasmMaxSize',
};

my $_portType = 
{
    1 => 'other',
    2 => 'cddi',
    3 => 'fddi',
    4 => 'tppmd',
    5 => 'mlt3',
    6 => 'sddi',
    7 => 'smf',
    8 => 'e10BaseT',
    9 => 'e10BaseF',
    10 => 'scf',
    11 => 'e100BaseTX',
    12 => 'e100BaseT4',
    13 => 'e100BaseF',
    14 => 'atmOc3mmf',
    15 => 'atmOc3smf',
    16 => 'atmOc3utp',
    17 => 'e100BaseFsm',
    18 => 'e10a100BaseTX',
    19 => 'mii',
    20 => 'vlanRouter',
    21 => 'remoteRouter',
    22 => 'tokenring',
    23 => 'atmOc12mmf',
    24 => 'atmOc12smf',
    25 => 'atmDs3',
    26 => 'tokenringMmf',
    27 => 'e1000BaseLX',
    28 => 'e1000BaseSX',
    29 => 'e1000BaseCX',
    30 => 'networkAnalysis',
    31 => 'e1000Empty',
    32 => 'e1000BaseLH',
    33 => 'e1000BaseT',
    34 => 'e1000UnsupportedGbic',
    35 => 'e1000BaseZX',
    36 => 'depi2',
    37 => 't1',
    38 => 'e1',
    39 => 'fxs',
    40 => 'fxo',
    41 => 'transcoding',
    42 => 'conferencing',
    55 => 'intrusionDetect',
};

my $_portAdminSpeed = 
{
    1 => 'autoDetect',
    64000 => 's64000',
    1544000 => 's1544000',
    2000000 => 's2000000',
    2048000 => 's2048000',
    4000000 => 's4000000',
    10000000 => 's10000000',
    16000000 => 's16000000',
    45000000 => 's45000000',
    64000000 => 's64000000',
    100000000 => 's100000000',
    155000000 => 's155000000',
    400000000 => 's400000000',
    622000000 => 's622000000',
    1000000000 => 's1000000000',
};

my $_ifSpeed =
{
    '10000000' => '10M',
    '100000000' => '100M',
    '1000000000' => '1G',
};

my $_portDuplex = 
{
    1 => 'half',
    2 => 'full',
    3 => 'disagree',
    4 => 'auto',
};

sub clear_data
{
    my $self = shift;
    $self->[IFENTRY] = {};
    $self->[PORTENTRY] = {};
    $self->[VLANPORTVLAN] = '';
    $self->[IFALIAS] = '';
    $self->[IPADDRENTRY] = [];
    $self->[NIC_IP] = '';
};

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);

    my $entity = shift;

    if ($entity->has_parent_nosnmp_status)
    {
        $self->clear_data;
        $self->errmsg('');
        $self->status(_ST_UNKNOWN);
        return;
    }

    my $id_entity = $entity->id_entity;

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter(sprintf( qq|ip in entity %s|, $id_entity))
        unless $ip;

    my $index = $entity->params('index');
    throw EEntityMissingParameter(sprintf( qq|index in entity %s|, $id_entity))
        unless $index;

    my $nic_port_slot = $entity->params('nic_port_slot');
    my $nic_port_index = $entity->params('nic_port_index');

    my $oids_disabled = $entity->params_own->{'oids_disabled'};
    #my $oids_disabled = $entity->params('oids_disabled');
    log_debug(sprintf(qq|entity %s oids_disabled: %s|, $id_entity, $oids_disabled), _LOG_DEBUG)
        if $LogEnabled && $oids_disabled;

    my $snmp_split_request = $entity->params_own->{'snmp_split_request'};
    log_debug(sprintf(qq|entity %s snmp_split_request: %s|, $id_entity, $snmp_split_request), _LOG_DEBUG)
        if $LogEnabled && $snmp_split_request;
    $snmp_split_request = 1
        unless $snmp_split_request;

    $self->threshold_high($entity->params('threshold_high'));

    $self->threshold_medium($entity->params('threshold_medium'));

    $self->clear_data;

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error) 
    {
        $session->max_msg_size(2944);

        my $oids = $self->oids_build($oids_disabled, $snmp_split_request, $index, $nic_port_index, $nic_port_slot);

        my $result;

        if ($snmp_split_request == 1)
        {
            $result = $session->get_request( -varbindlist => $oids->[0] );
#use Data::Dumper; print Dumper($oids, $result, $session->error_status, $session->error_index, $session->error) 
#    if $id_entity == 11096;
        }
        else
        {
            my $res;
            for (@$oids)
            {
                $res = $session->get_request( -varbindlist => $_ );

                if ($session->error)
                {
                    $oids->[0] = $_;
                    last;
                }
                
                for (keys %$res)
                {
                    $result->{$_} = $res->{$_};
                }
            }
        }

        $error = $session->error_status;

        if ($error == 1)
        {
#print $ip, ": ", $session->error, ": request too big - need to split\n";
            if ($snmp_split_request <= $MaxSNMPSplitRequest)
            {
                #my $parent = Entity->new($self->dbh, $entity->id_parent);
                ++$snmp_split_request;
                $entity->params('snmp_split_request', $snmp_split_request);
                #$parent->params('snmp_split_request', $snmp_split_request);
            }
            else
            {
                log_debug(sprintf(qq|maximum snmp_split_request value %s already set. cannot fix that!!! check configuration|, 
                    $MaxSNMPSplitRequest), _LOG_ERROR);
            }
#print "new snmp_split_request: ", $snmp_split_request, "\n\n";
        }
        elsif ($error == 2)
        {
            my $bad_oid = $oids->[0]->[$session->error_index - 1];

            if ($bad_oid =~ /^$O_IFENTRY/)
            {
                my @s = split /\./, $bad_oid;
                pop @s;
                $bad_oid = join(".", @s);
            }
            elsif ($bad_oid =~ /^$O_IFALIAS/)
            {
                $bad_oid = $O_IFALIAS;
            }
            elsif ($bad_oid =~ /^$O_VLANPORTVLAN/)
            {
                $bad_oid = $O_VLANPORTVLAN;
            }
            elsif ($bad_oid =~ /^$O_PORTENTRY/)
            {
                my @s = split /\./, $bad_oid;
                pop @s;
                pop @s;
                $bad_oid = join(".", @s);
            }

            $oids_disabled = defined $oids_disabled
                ? join(":", $oids_disabled, $bad_oid)
                : $bad_oid;

            #my $parent = Entity->new($self->dbh, $entity->id_parent);
            #$parent->params('oids_disabled', $oids_disabled);
            $entity->params('oids_disabled', $oids_disabled);

#print $ip, ": ", $session->error, ": disable oid#", $oids_disabled, "#\n";
#print "error oid: ",  $oids->[2]->[$session->error_index - 1], "\n\n";

        }
        $self->result_dispatch($result, $index, $nic_port_index, $nic_port_slot);


        if (! keys %{ $self->ifEntry })
        {
             $self->errmsg('interface not found');
             $self->status(_ST_UNKNOWN);
        }
        else
        {
            if (defined $nic_port_index || defined $nic_port_slot)
            {

                if (defined $self->portEntry->{portIfIndex} 
                    && $self->portEntry->{portIfIndex} ne '' 
                    && $self->portEntry->{portIfIndex} ne $index)
                {
                    $self->errmsg(sprintf(qq|interface entity bad configuration. check entity name, nic_port_index and nic_port_slot parameters or run discovery procedure on the parent entity|,
                        $index, $self->portEntry->{portIfIndex}));
                    $self->status(_ST_UNKNOWN);
                }
            }

            $self->ipAddrEntry_get($session, $index);
            my $ipAddrEntry = $self->ipAddrEntry;
            my $nic_ambiguous_ifDescr = $entity->params('nic_ambiguous_ifDescr');
            my $nic_ifOperStatus_invert = $entity->params('nic_ifOperStatus_invert');

            if (! $self->status)
            {
                if ($nic_ambiguous_ifDescr)
                {
                    $entity->name( sprintf(qq|%s.%s|, $self->ifEntry->{ifDescr}, $index));
                }
                else
                {
                    $entity->name(defined $nic_port_slot && defined $nic_port_index && $nic_ambiguous_ifDescr
                        ? "$nic_port_slot/$nic_port_index"
                        : $self->ifEntry->{ifDescr});
                }

                my $ifAdminStatus = $self->ifEntry->{ifAdminStatus};
                my $ifOperStatus = $self->ifEntry->{ifOperStatus};

                if (defined $ifAdminStatus && $ifAdminStatus ne 'up')
                {
                    $self->errmsg(sprintf(qq|interface ifAdminStatus: %s|, $ifAdminStatus));
                    $self->status(_ST_NOSTATUS);
                }
                elsif ( defined $ifOperStatus 
                    && $ifOperStatus ne 'up' 
                    && $ifOperStatus ne 'dormant' 
                    && $ifOperStatus ne 'notPresent')
                {
                    if (! $nic_ifOperStatus_invert)
                    {
                        $self->errmsg(sprintf(qq|interface ifOperStatus: %s|, $ifOperStatus));
                        $self->status(_ST_DOWN)
                            unless defined $entity->params('nic_ifOperStatus_ignore');
                    }
                    else
                    {
                        $self->errmsg(sprintf(qq|interface ifOperStatus: %s; alarm inverted|, $ifOperStatus));
                    }
                }
                elsif ($nic_ifOperStatus_invert)
                {
                    my $nic_ifOperStatus_invert_msg = $entity->params('nic_ifOperStatus_invert_msg');
                    $self->errmsg(sprintf(qq|interface ifOperStatus: %s; %s|, 
                        $ifOperStatus, $nic_ifOperStatus_invert_msg ? $nic_ifOperStatus_invert_msg : 'alarm inverted'));
                    $self->status(_ST_DOWN)
                        unless defined $entity->params('nic_ifOperStatus_ignore');
                }
                elsif ( defined $self->portEntry->{portDuplex})
                {
                    if ( $self->portEntry->{portDuplex} eq 'disagree' )
                    {
                        $self->errmsg('port duplex in disagree state');
                        $self->status(_ST_MINOR);
                    }
                }
            }
        }
        $session->close
            if $session;
    }
    else
    {
        $self->errmsg($error);
        $self->status(_ST_DOWN);
    }

    if ($self->status < _ST_DOWN)
    {
        my $s = $self->ifAlias;
        if ($s)
        {
            $entity->description_dynamic($s);
        }
        else
        {
            $s = $self->portEntry;
            $entity->description_dynamic($s->{portName})
                if $s->{portName} ;
        }
 
        $entity->params('nic_ip', $self->nic_ip);
        $self->cache_update($id_entity, $self->ifEntry);

        $self->errors_and_utilization_status($entity);
        $self->icmp_monitor
            unless $entity->params('nic_ip_icmp_check_disable')
            || $entity->params('nic_ifOperStatus_invert');

        $self->rrd_save($id_entity, $self->status);
         
    }
        $self->save_data($id_entity);
}

sub errors_and_utilization_status
{
    my $self = shift;
    my $entity = shift;

    my $ch = $self->cache->{$entity->id_entity};

    return
        unless $ch;

    if ($ch->{ifInErrors} && $ch->{ifInErrors}->[1] && $ch->{ifInErrors}->[1] ne 'U')
    {
        $self->errmsg("input errors packets detected");
        $self->status(_ST_WARNING)
            unless defined $entity->params('nic_errors_ignore');
    }
    if ($ch->{ifOutErrors} && $ch->{ifOutErrors}->[1] && $ch->{ifOutErrors}->[1] ne 'U')
    {
        $self->errmsg("output errors packets detected");
        $self->status(_ST_WARNING)
            unless defined $entity->params('nic_errors_ignore');
    }

    if (defined $entity->params('nic_speed_check_disable'))
    {
        return;
    }
    
    my $h;
    my $speed = $entity->params('nic_bandwidth');
    $speed = $self->ifEntry->{ifSpeed}
        unless defined $speed && $speed;

    return
        unless $speed;

    if ($entity->params('nic_bandwidth_aggregate') && $ch->{ifInOctets}->[1] ne 'U' && $ch->{ifOutOctets}->[1] ne 'U')
    {
        $h = ( ($ch->{ifInOctets}->[1] + $ch->{ifOutOctets}->[1])*800 ) / $speed;
        if ($h >= $self->threshold_high)
        {
            $self->errmsg("high aggregated link utilization");
            $self->status(_ST_MINOR);
        }
        elsif ($h >= $self->threshold_medium)
        {
            $self->errmsg("medium aggregated link utilization");
            $self->status(_ST_WARNING);
        }
    }
    else
    {
        if ($ch->{ifInOctets}->[1] ne 'U')
        {
            $h = ( $ch->{ifInOctets}->[1]*800 ) / $speed;
            if ($h >= $self->threshold_high)
            {
                $self->errmsg("high inbound link utilization");
                $self->status(_ST_MINOR);
            }
            elsif ($h >= $self->threshold_medium)
            {
                $self->errmsg("medium inbound link utilization");
                $self->status(_ST_WARNING);
            }
        }

        if ($ch->{ifOutOctets}->[1] ne 'U')
        {
            $h = ( $ch->{ifOutOctets}->[1]*800 ) / $speed;
            if ($h >= $self->threshold_high)
            {
                $self->errmsg("high outbound link utilization");
                $self->status(_ST_MINOR);
            }
            elsif ($h >= $self->threshold_medium)
            {
                $self->errmsg("medium outbound link utilization");
                $self->status(_ST_WARNING);
            }
        }
    }
}

sub icmp_monitor
{
    my $self = shift;

    my $nic_ip = $self->nic_ip;

    if (defined $nic_ip && $nic_ip)
    {
        if (flag_file_check($ICMPMonitorStatusDir, sprintf(qq|%s.lost|,$nic_ip)))
        {
            $self->errmsg("lost ICMP packets");
            $self->status(_ST_MAJOR);
        }
        elsif (flag_file_check($ICMPMonitorStatusDir, sprintf(qq|%s.delay|,$nic_ip)))
        {
            $self->errmsg("ICMP packets delay too high");
            $self->status(_ST_MINOR);
        }
    }
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;


    my $data_dir = $DataDir;

    open F, ">$data_dir/$id_entity";

    my $h = $self->ifEntry;
    my $ch = $self->cache->{$id_entity};
    my $chk = $self->rrd_config;

    for ( map { defined $chk->{$_} && $_ ne 'ifOutQLen' ? ( defined $ch->{$_}->[1] ? "$_\|$ch->{$_}->[1]\n" : "$_\|U\n" ) : "$_\|$h->{$_}\n" } keys %$h )
    {
        print F $_;
    }

    $h = $self->portEntry;
    for ( map { "$_\|$h->{$_}\n" } keys %$h )
    {
        print F $_;
    }

    $h = $self->ifAlias;
    print F sprintf(qq|ifAlias\|%s\n|, $h);
        #if $h;

    $h = $self->vlanPortVlan;
    print F sprintf(qq|vlanPortVlan\|%s\n|, $h);
        #if $h;

    $h = $self->ipAddrEntry;
    print F sprintf(qq|ipAddrEntry\|%s\n|, $h);
        #if $h;

    close F;

}

sub rrd_result
{
    my $self = shift;

    my $h = $self->rrd_data;

    return 
    {
        'ifInOctets' => defined $h->{ifInOctets} ? $h->{ifInOctets} : 'U',
        'ifInUcastPkts' => defined $h->{ifInUcastPkts} ? $h->{ifInUcastPkts} : 'U',
        'ifInNUcastPkts' => defined $h->{ifInNUcastPkts} ? $h->{ifInNUcastPkts} : 'U',
        'ifInDiscards' => defined $h->{ifInDiscards} ? $h->{ifInDiscards} : 'U',
        'ifInErrors' => defined $h->{ifInErrors} ? $h->{ifInErrors} : 'U',
        'ifInUnknownProtos' => defined $h->{ifInUnknownProtos} ? $h->{ifInUnknownProtos} : 'U',
        'ifOutOctets' => defined $h->{ifOutOctets} ? $h->{ifOutOctets} : 'U',
        'ifOutUcastPkts' => defined $h->{ifOutUcastPkts} ? $h->{ifOutUcastPkts} : 'U',
        'ifOutNUcastPkts' => defined $h->{ifOutNUcastPkts} ? $h->{ifOutNUcastPkts} : 'U',
        'ifOutDiscards' => defined $h->{ifOutDiscards} ? $h->{ifOutDiscards} : 'U',
        'ifOutErrors' => defined $h->{ifOutErrors} ? $h->{ifOutErrors} : 'U',
        'ifOutQLen' => defined $h->{ifOutQLen} ? $h->{ifOutQLen} : 'U',
    };
}

sub cache_keys
{
    return 
    [ 
        keys %{ $_[0]->rrd_config } 
    ];
}

sub rrd_config
{
    return 
    {
        'ifInOctets' => 'COUNTER',
        'ifInUcastPkts' => 'COUNTER',
        'ifInNUcastPkts' => 'COUNTER',
        'ifInDiscards' => 'COUNTER',
        'ifInErrors' => 'COUNTER',
        'ifInUnknownProtos' => 'COUNTER',
        'ifOutOctets' => 'COUNTER',
        'ifOutUcastPkts' => 'COUNTER',
        'ifOutNUcastPkts' => 'COUNTER',
        'ifOutDiscards' => 'COUNTER',
        'ifOutErrors' => 'COUNTER',
        'ifOutQLen' => 'GAUGE',
    };
}

sub ipAddrEntry 
{
    my $self = shift;
    my @result;
    for ( @{ $self->[IPADDRENTRY] } )
    { 
        push @result, join(":", values %$_);
    } 
    return join('#', @result);
}

sub nic_ip
{
    my $self = shift;
    if (@_)
    {
        $self->[NIC_IP] = shift
            unless $_[0] =~ /^127\./
                || $_[0] =~ /^0\./
                || $_[0] =~ /^224\./;
    }
    return $self->[NIC_IP];
}

sub result_dispatch
{
    my $self = shift;

    my $result = shift;
    my $index = shift;
    my $nic_port_index = shift;
    my $nic_port_slot = shift;

    return
        unless defined $result;

    my $key;

    for (keys %$result)
    {
        $key = $_; 
       
        if (/^$O_IFENTRY\./)
        {
            s/^$O_IFENTRY\.//g;
            s/\.$index$//g;
            if (defined $_ifEntry->{$_} && $_ifEntry->{$_} eq 'ifPhysAddress')
            {
                $self->[IFENTRY]->{ $_ifEntry->{$_} } = decode_mac($result->{$key}) || '';
            }
            elsif (defined $_ifEntry->{$_} && $_ifEntry->{$_} eq 'ifAdminStatus')
            {
                $self->[IFENTRY]->{ $_ifEntry->{$_} } = $_ifAdminStatus->{ $result->{$key} } || '';
            }
            elsif (defined $_ifEntry->{$_} && $_ifEntry->{$_} eq 'ifOperStatus')
            {
                $self->[IFENTRY]->{ $_ifEntry->{$_} } = $_ifOperStatus->{ $result->{$key} } || '';
            }
            elsif (defined $_ifEntry->{$_} && $_ifEntry->{$_} eq 'ifType')
            {
                $self->[IFENTRY]->{ $_ifEntry->{$_} } = $IANAifType->{ $result->{$key} }
                    ? sprintf(qq|%s; %s|,  $IANAifType->{ $result->{$key} }->{type},  $IANAifType->{ $result->{$key} }->{desc})
                    : $result->{$key};
            }
            elsif (defined $_ifEntry->{$_} && $_ifEntry->{$_} eq 'ifLastChange')
            {
                $self->[IFENTRY]->{ $_ifEntry->{$_} } = ticks_to_time( $result->{$key} ) || '';
            }
            elsif (defined $_ifEntry->{$_} && $_ifEntry->{$_} eq 'ifDescr')
            {
                $self->[IFENTRY]->{ $_ifEntry->{$_} } = $result->{$key} || '';
                $self->[IFENTRY]->{ $_ifEntry->{$_} } =~ s/\'//g;
                $self->[IFENTRY]->{ $_ifEntry->{$_} } =~ s/\000//g;
                $self->[IFENTRY]->{ $_ifEntry->{$_} } =~ s/\s+$//;

            }
            else
            {
                $self->[IFENTRY]->{ $_ifEntry->{$_} } = $result->{$key}
                    if defined $_ifEntry->{$_};
            }
        }
        elsif (/^$O_PORTENTRY\./)
        {
            s/^$O_PORTENTRY\.//g;
            s/\.$nic_port_slot\.$nic_port_index$//g;

            if ($_portEntry->{$_} eq 'portOperStatus')
            {
                $self->[PORTENTRY]->{ $_portEntry->{$_} } = $_portOperStatus->{ $result->{$key} } || '';
            }
            elsif ($_portEntry->{$_} eq 'portLinkFaultStatus')
            {
                $self->[PORTENTRY]->{ $_portEntry->{$_} } = $_portLinkFaultStatus->{ $result->{$key} } || '';
            }
            elsif ($_portEntry->{$_} eq 'portAdditionalOperStatus')
            {
                $self->[PORTENTRY]->{ $_portEntry->{$_} } = $_portAdditionalOperStatus->{ $result->{$key} } || '';
            }
            elsif ($_portEntry->{$_} eq 'portType')
            {
                $self->[PORTENTRY]->{ $_portEntry->{$_} } = $_portType->{ $result->{$key} } || '';
            }
            elsif ($_portEntry->{$_} eq 'portAdminSpeed')
            {
                $self->[PORTENTRY]->{ $_portEntry->{$_} } = $_portAdminSpeed->{ $result->{$key} } || '';
            }
            elsif ($_portEntry->{$_} eq 'portDuplex')
            {
                $self->[PORTENTRY]->{ $_portEntry->{$_} } = $_portDuplex->{ $result->{$key} } || '';
            }
            else
            {
                $self->[PORTENTRY]->{ $_portEntry->{$_} } = $result->{$key};
            }
        }
        elsif (/^$O_VLANPORTVLAN\./)
        {
            $self->[VLANPORTVLAN] = $result->{$_};
        }
        elsif (/^$O_IFALIAS\./)
        {
            $self->[IFALIAS] = $result->{$_};
        }
    }
    my %h = %{ $self->[IFENTRY] };
    $self->[RRD_DATA] = \%h;
}

sub ipAddrEntry_get
{
    my $self = shift;

    my $session = shift;
    my $index = shift;


    my $O_ipAddrEntry = '1.3.6.1.2.1.4.20.1';

    my $result = $session->get_table(-baseoid => $O_ipAddrEntry);

    return 
        unless defined $result;

    my @idx;
    for (keys %$result)
    {
        next
            unless /^1.3.6.1.2.1.4.20.1.2./;
        next
            unless $result->{$_} eq $index;
        s/^1.3.6.1.2.1.4.20.1.2.//g;
        push @idx, $_;
    }

    my $ipAddrEntry = [];
    for my $ip (@idx)
    {
        push @$ipAddrEntry, {};
        $ipAddrEntry->[$#$ipAddrEntry]->{primary} = $#$ipAddrEntry
            ? 0
            : 1;

        $self->nic_ip($ip)
            unless $#$ipAddrEntry;

        $ipAddrEntry->[$#$ipAddrEntry]->{ $_ipAddrEntry->{'1'} } = $result->{ "$O_ipAddrEntry.1.$ip" };
        $ipAddrEntry->[$#$ipAddrEntry]->{ $_ipAddrEntry->{'3'} } = $result->{ "$O_ipAddrEntry.3.$ip" };
    }
    $self->[IPADDRENTRY] = $ipAddrEntry;
}

sub ifAlias
{
    return $_[0]->[IFALIAS];
}

sub vlanPortVlan
{
    return $_[0]->[VLANPORTVLAN];
}

sub portEntry
{
    return $_[0]->[PORTENTRY];
}

sub rrd_data
{
    return $_[0]->[RRD_DATA];
}

sub oids_build
{
    my $self = shift;

    my $oids_disabled = {};

    my $oid_src = shift || '';

    @$oids_disabled{ (split /:/, $oid_src) } = undef;

    my $snmp_split_request = shift;
    my $index = shift;
    my $nic_port_index = shift;
    my $nic_port_slot = shift;

#use Data::Dumper; print "index $index: ", Data::Dumper::Dumper($oids_disabled);

    my (@oids, $s);

    for $s (sort { $a <=> $b} keys %$_ifEntry)
    {
        $s = "$O_IFENTRY.$s";
        next
            if exists $oids_disabled->{$s};
        push @oids, "$s.$index";
    }

    push @oids, "$O_IFALIAS.$index"
        unless exists $oids_disabled->{$O_IFALIAS};

    if (defined $nic_port_index && defined $nic_port_slot)
    {
        for $s (sort { $a <=> $b} keys %$_portEntry)
        {
            $s = "$O_PORTENTRY.$s";
            next
                if exists $oids_disabled->{$s};
            push @oids, "$s.$nic_port_slot.$nic_port_index";
        }
        push @oids, "$O_VLANPORTVLAN.$nic_port_slot.$nic_port_index"
            unless exists $oids_disabled->{$O_VLANPORTVLAN};
    }

#use Data::Dumper; print "index $index: ", Data::Dumper::Dumper(\@oids) if keys %$oids_disabled;
    return [\@oids]
        if $snmp_split_request == 1;

    my $split = 0;
    my $result;

    for (@oids) 
    {
        push @{$result->[$split]}, $_;
        ++$split;
        $split = 0
            if $split == $snmp_split_request;
    }
    return $result;
}

sub ifEntry
{
    return $_[0]->[IFENTRY];
}

sub discover_mandatory_parameters
{       
    my $self = shift;
    my $mp = $self->SUPER::discover_mandatory_parameters();
    
    push @$mp, ['snmp_community_ro', 'snmp_user'];
    
    return $mp;
}   

sub discover
{
    my $self = shift;
    $self->SUPER::discover(@_);
    my $entity = shift;    

    my $ip = $entity->params('ip');
    if (! defined $ip)
    {   
        log_debug('ignored; ip address not configured', _LOG_WARNING)
            if $LogEnabled;
        return;
    }

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error)
    {
        $session->max_msg_size(2944);

        my $result;
        my $new = {};

        my $st; #tmp string
        my @ar; #tmp array

        my $amb = {};

        $result = $session->get_table(-baseoid => '1.3.6.1.2.1.2.2.1.2');

        $error = $session->error();
        if ($error)
        {
            log_debug($error, _LOG_WARNING)
                if $LogEnabled;
            return;
        }

        for (keys %$result)
        {
            $result->{ $_ } =~ s/\'//g;
            $result->{ $_ } =~ s/\000//g;
            $result->{ $_ } =~ s/\s+$//;
            next
                unless $result->{ $_ };
            $amb->{ $result->{ $_ } }->{nic_ambiguous_ifDescr}++;
        }

        my $tmp1;
        $new = {};
        for (keys %$result)
        {
            $st = $result->{$_};
            s/^1.3.6.1.2.1.2.2.1.2.//g;
            $st =~ s/\'//g;
            $st =~ s/\000//g;
            $st =~ s/\s+$//;
            next
                unless $st;
            $tmp1 = $st;       
            $st .= ".$_"
                if $amb->{ $st }->{nic_ambiguous_ifDescr}  > 1;
            $new->{ $st }->{ifIndex} = $_;
            $new->{ $st }->{orgName} = $tmp1;
            $new->{ $st }->{nic_ambiguous_ifDescr} = $amb->{ $tmp1 }->{nic_ambiguous_ifDescr};
            $new->{tmp}->{ $_ }->{ifDescr} = $st;
            $new->{tmp}->{ $_ }->{nic_ambiguous_ifDescr} = $amb->{ $tmp1 }->{nic_ambiguous_ifDescr};
        }  

        if (! keys %$new)
        {
            log_debug(sprintf("no network interfaces available on the entity %s", $entity->id_enity) , _LOG_INFO)
                if $LogEnabled;
            return;
        }

        if  (CFG->{Probes}->{nic}->{DiscoverDisableOperStatusCheckOnDownInterfaces})
        {
            $result = $session->get_table(-baseoid => '1.3.6.1.2.1.2.2.1.7');

            for (keys %$result)
            {       
                $st = $result->{$_};
                s/^1.3.6.1.2.1.2.2.1.7.//g; 
                $new->{tmp}->{ $_ }->{ifAdminStatus} = $st;
            } 

            $result = $session->get_table(-baseoid => '1.3.6.1.2.1.2.2.1.8');

            for (keys %$result)
            {       
                $st = $result->{$_};
                s/^1.3.6.1.2.1.2.2.1.8.//g; 
                $new->{tmp}->{ $_ }->{ifOperStatus} = ($st != 1 && $st != 5 && $st != 6) ? 1 : 0;
            } 
        }

        $result = $session->get_table(-baseoid => '1.3.6.1.2.1.2.2.1.3');

        for (keys %$result)
        {       
            $st = $result->{$_};
            s/^1.3.6.1.2.1.2.2.1.3.//g; 
            $new->{tmp}->{ $_ }->{ifType} = $st;
        } 

        $result = $session->get_table(-baseoid => '1.3.6.1.4.1.9.5.1.4.1.1.11');

        $error = $session->error();

        my $nic_port = 0;
        my @ambs = grep { $_ > 1 } map { $amb->{ $_ }->{nic_ambiguous_ifDescr} } keys %$amb;

use Data::Dumper; log_debug(Dumper(\@ambs), _LOG_ERROR);
#use Data::Dumper; log_debug(Dumper($new), _LOG_ERROR);
        if (! $error)
        {
            for (keys %$result)
            {
                delete $result->{$_}
                    if $result->{$_} eq '';
            }

           
            for (keys %$result)
            {
                $st = $result->{$_};
                s/^1.3.6.1.4.1.9.5.1.4.1.1.11.//g;
                @ar = split (/\./, $_);

                $new->{tmp}->{ $st }->{nic_port_slot} = $ar[0];
                $new->{tmp}->{ $st }->{nic_port_index} = $ar[1];

                if (@ambs)
                {

                $new->{ qq|$ar[0]/$ar[1]| } = $new->{ $new->{tmp}->{ $st }->{ifDescr} };
                $new->{ qq|$ar[0]/$ar[1]| }->{nic_port_slot} = $new->{tmp}->{ $st }->{nic_port_slot};
                $new->{ qq|$ar[0]/$ar[1]| }->{nic_port_index} = $new->{tmp}->{ $st }->{nic_port_index};
                $new->{ qq|$ar[0]/$ar[1]| }->{ifIndex} = $st;
                $new->{ qq|$ar[0]/$ar[1]| }->{ifOperStatus} = $new->{tmp}->{ $st }->{ifOperStatus};
                $new->{ qq|$ar[0]/$ar[1]| }->{ifType} = $new->{tmp}->{ $st }->{ifType};
                $new->{ qq|$ar[0]/$ar[1]| }->{ifAdminStatus} = $new->{tmp}->{ $st }->{ifAdminStatus};
                $new->{ qq|$ar[0]/$ar[1]| }->{orgName} = qq|$ar[0]/$ar[1]|;
                $new->{ qq|$ar[0]/$ar[1]| }->{nic_ambiguous_ifDescr} = 1;

                ++$nic_port;

                delete $new->{ $new->{tmp}->{ $st }->{ifDescr} };

                delete $new->{tmp}->{ $st };

                }
            }  
        }
       
#use Data::Dumper; log_debug(Dumper($new), _LOG_ERROR);

#use Data::Dumper; log_debug(Dumper $nic_port, _LOG_ERROR); exit;

        if ($nic_port)
        {
            for (keys %$new)
            {
                next
                    unless defined $new->{$_}->{orgName};
                next
                    if $new->{$_}->{orgName} eq $_;
                $new->{ $new->{$_}->{orgName} } = $new->{$_};
                $new->{ $new->{$_}->{orgName} }->{nic_ambiguous_ifDescr} = 1;
                delete $new->{$_};
            }
        };
        for (keys %{ $new->{tmp} })
        {
            $new->{ $new->{tmp}->{ $_ }->{ifDescr} }->{ifType} = $new->{tmp}->{ $_ }->{ifType};
            $new->{ $new->{tmp}->{ $_ }->{ifDescr} }->{ifOperStatus} = $new->{tmp}->{ $_ }->{ifOperStatus};
            $new->{ $new->{tmp}->{ $_ }->{ifDescr} }->{ifAdminStatus} = $new->{tmp}->{ $_ }->{ifAdminStatus};
            $new->{ $new->{tmp}->{ $_ }->{ifDescr} }->{nic_ambiguous_ifDescr} = $new->{tmp}->{ $_ }->{nic_ambiguous_ifDescr};
            $new->{ $new->{tmp}->{ $_ }->{ifDescr} }->{nic_port_slot} = $new->{tmp}->{ $_ }->{nic_port_slot}
                if defined $new->{tmp}->{ $_ }->{nic_port_slot};
            $new->{ $new->{tmp}->{ $_ }->{ifDescr} }->{nic_port_index} = $new->{tmp}->{ $_ }->{nic_port_index}
                if defined $new->{tmp}->{ $_ }->{nic_port_index};
        }

        delete $new->{tmp};
        
#use Data::Dumper; log_debug(Dumper($new), _LOG_ERROR);
#exit;
        my $old = $self->_discover_get_existing_entities($entity);

#use Data::Dumper; log_debug(Dumper $new, _LOG_ERROR); log_debug(Dumper $old, _LOG_ERROR); 

        for my $name (keys %$old)
        {
            next
                unless  defined $new->{$name};

            $old->{$name}->{entity}->params('index', $new->{$name}->{ifIndex})
                if $new->{$name}->{ifIndex} ne $old->{$name}->{ifIndex};

            if (defined $new->{$name}->{nic_port_index} && defined $new->{$name}->{nic_port_slot})
            {
                $old->{$name}->{entity}->params('nic_port_index', $new->{$name}->{nic_port_index})
                    if $new->{$name}->{nic_port_index} ne $old->{$name}->{nic_port_index};

                $old->{$name}->{entity}->params('nic_port_slot', $new->{$name}->{nic_port_slot})
                    if $new->{$name}->{nic_port_slot} ne $old->{$name}->{nic_port_slot};
            }
            
            if ($old->{$name}->{entity}->status eq _ST_BAD_CONF)
            {
                $old->{$name}->{entity}->status(_ST_UNKNOWN);
                $old->{$name}->{entity}->db_update_entity;
            }

            delete $new->{$name};
            delete $old->{$name};
        }

        for (keys %$new)
        {
            if (defined $IANAifType->{ $new->{$_}->{ifType} })
            {
                if ($IANAifType->{ $new->{$_}->{ifType} }->{discover} != 1)
                {
                    log_debug(sprintf(qq|interface %s ignored because of akkada configuration (etc/conf.d/Probes/nic.conf)|, $_),
                        _LOG_WARNING)
                         if $LogEnabled;
                    next;
                }
            }

            $self->_discover_add_new_entity($entity, $_, $new->{$_})
                if $_ ne '';

            delete $new->{$_};
        }

#KOMPARE PHASE 3
#czyli to co zostalo w $old = to interfejsy zdefiniowane na akkada, ktore nie 
#znalazly sie przez snmp - CO Z NIMI ROBIMY?
#use Data::Dumper; print Data::Dumper::Dumper($old);
#
# na razie wymyslilem, ze przestawiamy entity w _ST_BAD_CONF, a w Probe.pm entity_init ignoruje takie entity
#
        for (keys %$old)
        {
            #$old->{$_}->{entity}->status(_ST_BAD_CONF);
            #$old->{$_}->{entity}->db_update_entity;
        }

    }
    else
    {
        log_debug($error, _LOG_WARNING)
            if $LogEnabled;
    }

}

sub _discover_add_new_entity
{
    my ($self, $parent, $name, $new) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s/%s|, $parent->id_entity, $name, $new->{ifIndex}), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {
           index => $new->{ifIndex},
           nic_port_slot => $new->{nic_port_slot},
           nic_port_index => $new->{nic_port_index},
       },       
       };      

    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity->{params}->{nic_ifOperStatus_ignore} = 1
        if $new->{ifOperStatus} && $new->{ifAdminStatus} != 2;

    $entity->{params}->{nic_ambiguous_ifDescr} = 1
        if defined $new->{nic_ambiguous_ifDescr} && $new->{nic_ambiguous_ifDescr} > 1;

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {       
        #$self->dbh->exec(sprintf(qq|INSERT INTO links VALUES(%s, %s)|, $parent->id_entity, $entity->id_entity));
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s %s|,
            $parent->id_entity, $entity->id_entity, $name, $new->{ifIndex}), _LOG_INFO)
            if $LogEnabled;
    }                   
}

sub _discover_get_existing_entities
{

    my $self = shift;

    my @list = $self->SUPER::_discover_get_existing_entities(@_);

    my $parent = shift;

    my $result;

    for (@list)
    {

        my $entity = Entity->new($self->dbh, $_);
        if (defined $entity)
        {

            my $name = $entity->name;

            $result->{ $name }->{entity} = $entity;

            my $index = $entity->params('index');
            $result->{ $name }->{ifIndex} = $index
                if defined $index;

            my $nic_port_slot = $entity->params('nic_port_slot');
            $result->{$name}->{nic_port_slot} = $nic_port_slot
                if defined $nic_port_slot;

            my $nic_port_index = $entity->params('nic_port_index');
            $result->{$name}->{nic_port_index} = $nic_port_index
                if defined $nic_port_index;
        };
    };
    return $result;
}

sub desc_brief
{   
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $speed = $entity->params('nic_bandwidth');
    $speed = $data->{ifSpeed}
        unless $speed;

    return $result
        unless defined $data->{ifOperStatus} && $data->{ifOperStatus} ne 'down';

    my ($in, $out);

    if ($speed)
    {
        my $nic_bandwidth_aggregate = $entity->params('nic_bandwidth_aggregate');

        if ($nic_bandwidth_aggregate)
        {
            if ($data->{ifInOctets} ne 'U' && $data->{ifOutOctets} ne 'U')
            {
                $in = (($data->{ifInOctets}+$data->{ifOutOctets})*800)/$speed;
            }
            push @$result, defined $in
                ? sprintf(qq|usage aggregated: <font class="%s">%.2f%%</font> (%s bps)|,
                    percent_bar_style_select($in),$in,format_bytes(($data->{ifInOctets} + $data->{ifOutOctets})*8))
                : 'usage aggregated: n/a';
        }
        else
        {
            if ($data->{ifInOctets} ne 'U' && $data->{ifInOctets} ne '')
            {   
                $in = ($data->{ifInOctets}*800)/$speed;
                push @$result, sprintf(qq|usage in: <font class="%s">%.2f%%</font> %s|,
                    percent_bar_style_select($in),$in, sprintf(qq|(%s bps)|, format_bytes($data->{ifInOctets}*8)));
            }
            else
            {   
                push @$result, qq|usage in: n/a|;
            }

            if ($data->{ifOutOctets} ne 'U' && $data->{ifOutOctets} ne '')
            {   
                $out = ($data->{ifOutOctets}*800)/$speed;
                push @$result, sprintf(qq|usage out: <font class="%s">%.2f%%</font> %s|,
                    percent_bar_style_select($out),$out, sprintf(qq|(%s bps)|, format_bytes($data->{ifOutOctets}*8)));
            }
            else
            {   
                push @$result, qq|usage out: n/a|;
            }
        }
    }

    for (qw/ ifInErrors ifOutErrors /)
    {   
        if ($data->{$_} ne 'U' && $data->{$_} > 0)
        {
             push @$result, sprintf(qq|<font color=red><b>$_: %s pps</b></font>|, format_bytes($data->{$_},2));
        }
    }

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    if ($data->{ipAddrEntry})
    {
        my $tmp = [ split /#/, $data->{ipAddrEntry} ];

        for (@$tmp)
        {
            $_ = [split /:/, $_];
        }
        my $s;
        if (@$tmp == 1)
        {
            $s = sprintf(qq|%s %s|, $tmp->[0]->[0], $tmp->[0]->[1]);
        }
        else
        {
            for (@$tmp)
            {
                $s .= sprintf(qq|%s %s|, $_->[0], $_->[1]);
                $s .= $_->[2]
                    ? ' primary'
                    : ' secondary';
                $s .= '<br>';
            }
        }
        $table->addRow("ip address:", $s );
    }

    $table->addRow("ifType:", $data->{ifType})
        if $data->{ifType};
    $table->addRow("ifPhysAddress:", $data->{ifPhysAddress})
        if $data->{ifPhysAddress};
    $table->addRow("ifOperStatus:", $data->{ifOperStatus})
        if $data->{ifOperStatus};
    $table->addRow("ifAdminStatus:", $data->{ifAdminStatus})
        if $data->{ifAdminStatus};

    my $speed = $entity->params('nic_bandwidth');
    $speed = $data->{ifSpeed}
        unless $speed;

    if ($speed)
    {
        $table->addRow("ifSpeed:", (defined $_ifSpeed->{$speed}
            ? $_ifSpeed->{$speed}
            : $speed) . ' bps');
    }

    $table->addRow("ifIndex:", $data->{ifIndex})
        if $data->{ifIndex};
    $table->addRow("ifLastChange:", $data->{ifLastChange})
        if $data->{ifLastChange};

    if ($data->{portType})
    {
        $table->addRow("portType:", $data->{portType});
        $table->addRow("portAdminSpeed:", $data->{portAdminSpeed})
            if $data->{portAdminSpeed};
        $table->addRow("portDuplex:", $data->{portDuplex})
            if $data->{portDuplex};
        $table->addRow("vlanPortVlan:", $data->{vlanPortVlan})
            if $data->{vlanPortVlan};
        $table->addRow("portOperStatus:", $data->{portOperStatus})
            if $data->{portOperStatus};
        $table->addRow("portAdditionalOperStatus:", $data->{portAdditionalOperStatus})
            if $data->{portAdditionalOperStatus};
        $table->addRow("portLinkFaultStatus:", $data->{portLinkFaultStatus})
            if $data->{portLinkFaultStatus};
    }
    
    return 
        if $data->{ifOperStatus} eq 'down';

    #my $data = $self->rrd_get_data($entity);

    if ($data)
    {
        if ($speed)
        {
            $table->addRow("");
            $table->setCellColSpan($table->getTableRows, 1, 3);

            for (1 .. $table->getTableRows-1)
            {
                 $table->setCellColSpan($_, 2, 2);
            }
            my $percent;
            my $nic_bandwidth_aggregate = $entity->params('nic_bandwidth_aggregate');

            if ($nic_bandwidth_aggregate)
            {
                if ($data->{ifInOctets} ne 'U' && $data->{ifOutOctets} ne 'U')
                {
                    $percent = (($data->{ifInOctets}+$data->{ifOutOctets})*800)/$speed;
                    $table->addRow("ifTotalOctets:", 
                        sprintf(qq|<font class="%s">%.2f%</font>|, percent_bar_style_select($percent),$percent),
                        sprintf(qq|%s bps|, format_bytes(($data->{ifInOctets} +  $data->{ifOutOctets})*8), 2));
                }
                else
                {
                    $table->addRow("ifTotalOctets:", ' unknown ');
                }
            }

            if ($data->{ifInOctets} ne 'U')
            {
                $percent = ($data->{ifInOctets}*800)/$speed;
                $table->addRow("ifInOctets:", 
                    sprintf(qq|<font class="%s">%.2f%</font>|, $nic_bandwidth_aggregate
                        ? $percent
                        : percent_bar_style_select($percent),
                        $percent),
                    sprintf(qq|%s bps|, format_bytes($data->{ifInOctets}*8,2)));
            }
            else
            {
                $table->addRow("ifInOctets:", ' unknown ');
            }

            if ($data->{ifOutOctets} ne 'U')
            {
                $percent = ($data->{ifOutOctets}*800)/$speed;
                $table->addRow("ifOutOctets:", 
                    sprintf(qq|<font class="%s">%.2f%</font>|, $nic_bandwidth_aggregate
                        ? $percent
                        : percent_bar_style_select($percent),
                        $percent),
                    sprintf(qq|%s bps|, format_bytes($data->{ifOutOctets}*8,2)));
            }
            else
            {
                $table->addRow("ifOutOctets:", ' unknown ');
            }
        }

        if ($data->{ifInUcastPkts} ne 'U')
        {
            $table->addRow("ifInUcastPkts:",  sprintf(qq|%s pps|, format_bytes($data->{ifInUcastPkts},2)));
        }
        else
        {
            $table->addRow("ifInUcastPkts:", ' unknown ');
        }
        $table->setCellColSpan($table->getTableRows, 2, 2);

        if ($data->{ifOutUcastPkts} ne 'U')
        {
            $table->addRow("ifOutUcastPkts:",  sprintf(qq|%s pps|, format_bytes($data->{ifOutUcastPkts},2)));
        }
        else
        {
            $table->addRow("ifOutUcastPkts:", ' unknown ');
        }
        $table->setCellColSpan($table->getTableRows, 2, 2);

        my $key = $self->rrd_config; # to jest po to, zeby wczesniej nie kasowac wszystkich kluczy z %$data
        delete $key->{ifInOctets};
        delete $key->{ifOutOctets};
        delete $key->{ifInUcastPkts};
        delete $key->{ifOutUcastPkts};

        $table->addRow("");
        $table->setCellColSpan($table->getTableRows, 1, 3);

        for (sort keys %$key)
        {
            $data->{$_} ne 'U'
                ? $table->addRow("$_:",  
                    ($_ =~ /Errors/ && $data->{$_} > 0
                        ? sprintf(qq|<font color=red><b>%s pps</b></font>|, format_bytes($data->{$_},2))
                        : sprintf(qq|%s pps|, format_bytes($data->{$_},2))))
                : $table->addRow("$_:", ' unknown ');
            $table->setCellColSpan($table->getTableRows, 2, 2);
        }
    }
}

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;

    my @i;
    push @i, '*' if $entity->status_weight == 0;
    push @i, '*' if $entity->params('nic_errors_ignore');
    push @i, '*' if $entity->params('nic_speed_check_disable');
    push @i, '*' if $entity->params('nic_ifOperStatus_ignore');

    return sprintf(qq|%s%s|,
        $entity->name,
        @i
            ? join('', @i)
            : '');
}

sub popup_items
{       
    my $self = shift;

    $self->SUPER::popup_items(@_);

    my $buttons = $_[0]->{buttons};
    my $class = $_[0]->{class};
    my $section = $_[0]->{section};
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "set ignore ifOperStatus", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=nic_ifOperStatus_ignore&add_value=1&id_entity=','current','$class');",});
    $buttons->add({ caption => "set ignore error packets", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=nic_errors_ignore&add_value=1&id_entity=','current','$class');",});
}       

sub menu_stat
{ 
    return 1;
}

sub stat
{           
        
    my $self = shift;
    my $table = shift;
    my $entity = shift;
    my $url_params = shift;
    my $default_only = defined @_ ? shift : 0;
    my $cgi = CGI->new();
            
    my $url;
    $url_params->{probe} = 'nic';
        
    $url_params->{probe_prepare_ds} = 'prepare_ds_traffic';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    if ($entity->params('nic_ip') && ! $entity->params('nic_ip_icmp_check_disable'))
    {
        $url_params->{probe_prepare_ds} = 'prepare_ds_smoke';
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    }

    return 
        if $default_only;

    $url_params->{probe_prepare_ds} = 'prepare_ds_err';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds_discards';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds_unicasts';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds_nonunicasts';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds';

    $url_params->{probe_specific} = 'ifInUnknownProtos';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'ifOutQLen';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}


sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    if ($url_params->{probe_specific} eq 'ifInUnknownProtos')
    {
        $rrd_graph->unit('pps');
        $rrd_graph->title('unknown protocols');
    }
    elsif ($url_params->{probe_specific} eq 'ifOutQLen')
    {
        $rrd_graph->unit('pkts');
        $rrd_graph->title('output queue len');
    }
}

sub prepare_ds_traffic_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    $rrd_graph->unit('bps');
    $rrd_graph->title('traffic');
}

sub prepare_ds_err_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    $rrd_graph->unit('pps');
    $rrd_graph->title('errors');
}

sub prepare_ds_unicasts_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    $rrd_graph->unit('pps');
    $rrd_graph->title('unicasts');
}

sub prepare_ds_discards_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    $rrd_graph->unit('pps');
    $rrd_graph->title('discards');
}

sub prepare_ds_nonunicasts_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    
    $rrd_graph->unit('pps');
    $rrd_graph->title('non unicasts');
}   


sub prepare_ds_traffic
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift; 
    
    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;
    
    my $args = $rrd_graph->args;
    
    my $rrd_file = sprintf(qq|%s/%s.%s|, $RRDDir, $entity->id_entity, $url_params->{probe});
    
    my $up = 1;
    my $down = 0;
        
    push @$args, "DEF:ds0o=$rrd_file:ifOutOctets:$cf";
    push @$args, "CDEF:ds0oo=ds0o,8,*";
    push @$args, "AREA:ds0oo#330099:outbound"; 
    push @$args, "DEF:ds0i=$rrd_file:ifInOctets:$cf";
    push @$args, "CDEF:ds0ii=ds0i,8,*";
    push @$args, "STACK:ds0ii#00CC33:inbound"; 
    
    return ($up, $down, "ds0i");
}

sub prepare_ds_err
{   
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;

    my $rrd_file = sprintf(qq|%s/%s.%s|, $RRDDir, $entity->id_entity, $url_params->{probe});

    my $up = 1;
    my $down = 0;

    push @$args, "DEF:ds0i=$rrd_file:ifInErrors:$cf";
    push @$args, "CDEF:ds0ii=ds0i,1,*";
    push @$args, "LINE:ds0ii#00CC33:inbound errors ";

    push @$args, "DEF:ds0o=$rrd_file:ifOutErrors:$cf";
    push @$args, "CDEF:ds0oo=ds0o,1,*";
    push @$args, "LINE:ds0oo#330099:outbound errors";

    return ($up, $down, "ds0i");
}

sub prepare_ds_discards
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;

    my $rrd_file = sprintf(qq|%s/%s.%s|, $RRDDir, $entity->id_entity, $url_params->{probe});

    my $up = 1;
    my $down = 0;

    push @$args, "DEF:ds1i=$rrd_file:ifInDiscards:$cf";
    push @$args, "CDEF:ds1ii=ds1i,1,*";
    push @$args, "LINE:ds1ii#00CC33:inbound discards";

    push @$args, "DEF:ds1o=$rrd_file:ifOutDiscards:$cf";
    push @$args, "CDEF:ds1oo=ds1o,1,*";
    push @$args, "LINE:ds1oo#330099:outbound discards";

    return ($up, $down, "ds1i");
}


sub prepare_ds_unicasts
{   
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;

    my $rrd_file = sprintf(qq|%s/%s.%s|, $RRDDir, $entity->id_entity, $url_params->{probe});

    my $up = 1;
    my $down = 0;

    push @$args, "DEF:ds0i=$rrd_file:ifInUcastPkts:$cf";
    push @$args, "CDEF:ds0ii=ds0i,1,*";
    push @$args, "AREA:ds0ii#00CC33:inbound unicasts";

    push @$args, "DEF:ds0o=$rrd_file:ifOutUcastPkts:$cf";
    push @$args, "CDEF:ds0oo=ds0o,-1,*";
    push @$args, "AREA:ds0oo#330099:outbound unicasts";

    return ($up, $down, "ds0i");
}

sub prepare_ds_nonunicasts
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;

    my $rrd_file = sprintf(qq|%s/%s.%s|, $RRDDir, $entity->id_entity, $url_params->{probe});

    my $up = 1;
    my $down = 0;

    push @$args, "DEF:ds1i=$rrd_file:ifInNUcastPkts:$cf";
    push @$args, "CDEF:ds1ii=ds1i,1,*";
    push @$args, "AREA:ds1ii#00CC33:inbound nonunicasts";

    push @$args, "DEF:ds1o=$rrd_file:ifOutNUcastPkts:$cf";
    push @$args, "CDEF:ds1oo=ds1o,-1,*";
    push @$args, "AREA:ds1oo#330099:outbound nonunicasts";

    return ($up, $down, "ds1i");
}

sub prepare_ds_smoke_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $entity = $rrd_graph->entity;
    my $nic_ip = $entity->params('nic_ip');
    my $rrd_file = sprintf(qq|%s/%s.icmp_monitor|, $RRDDir, $nic_ip);

    my $pingCount = 20;
    my $url_params = $rrd_graph->url_params;

    my $begin = $rrd_graph->begin;

    my $max = findmax($rrd_file, $pingCount, $begin, $rrd_graph->end);

    my $args = $rrd_graph->args;

    push @$args, ( '--width',$rrd_graph->width, '--height',$rrd_graph->height);
    push @$args, ('COMMENT:Median Ping RTT  (',
      "DEF:median=$rrd_file:median:AVERAGE",
      "DEF:loss=$rrd_file:loss:AVERAGE",
      "LINE2:median#202020");
    push @$args, ( 'GPRINT:median:AVERAGE:loss )  avg\: %.1lf %ss\l');

    $rrd_graph->scale( $max->{ $begin } );
    $rrd_graph->unit('sec');
    $rrd_graph->title($nic_ip . ' ping');
}

sub prepare_ds_smoke
{
    my $self = shift;
    my $rrd_graph = shift;

    my $entity = $rrd_graph->entity;
    my $rrd_file = sprintf(qq|%s/%s.icmp_monitor|, $RRDDir, $entity->params('nic_ip'));

    my $pingCount = 20;
    my $url_params = $rrd_graph->url_params;

    my $scale = $rrd_graph->scale;

    my %lc = 
    (
        0                  => ['0',   '#26ff00'],
        1                  => ["1/$pingCount",  '#00b8ff'],
        2                  => ["2/$pingCount",  '#0059ff'],
        3                  => ["3/$pingCount",  '#5e00ff'],
        4                  => ["4/$pingCount",  '#7e00ff'],
        int($pingCount/2)  => [int($pingCount/2)."/$pingCount", '#dd00ff'],
        $pingCount-1       => [($pingCount-1)."/$pingCount",    '#ff0000'],
    );

    my $args = $rrd_graph->args;

    push @$args, map {"DEF:ping${_}=$rrd_file:ping${_}:AVERAGE"} 1..$pingCount;
    push @$args, map {"CDEF:cp${_}=ping${_},0,$scale,LIMIT"} 1..$pingCount;

    my $smoke = smokecol($pingCount);
    push @$args, @$smoke;

    my $last = -1;
    my $swidth = $scale / $rrd_graph->height;

    foreach my $loss (sort {$a <=> $b} keys %lc)
    {
        push @$args, ("CDEF:me$loss=loss,$last,GT,loss,$loss,LE,*,1,UNKN,IF,median,*",
            "CDEF:meL$loss=me$loss,$swidth,-",
            "CDEF:meH$loss=me$loss,0,*,$swidth,2,*,+",
            "AREA:meL$loss",
            "STACK:meH$loss$lc{$loss}[1]:$lc{$loss}[0]");
        $last = $loss;
    }

    return (1, 0, "median");
}

sub snmp
{
    return 1;
}

1;
