package Probe::tcpip;

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

$Number::Format::DECIMAL_FILL = 1;

sub id_probe_type
{
    return 24;
}

sub name
{
    return 'TCP/IP statistics';
}


use constant
{
    DATA => 13,
};

my $O_IPSTAT = '1.3.6.1.2.1.4';
my $O_ICMP = '1.3.6.1.2.1.5';
my $O_TCP = '1.3.6.1.2.1.6';
my $O_UDP = '1.3.6.1.2.1.7';

my $NO_CACHE =
{
     'tcpRtoAlgorithm' => 1,
     'tcpRtoMin' => 1,
     'tcpRtoMax' => 1,
     'tcpMaxConn' => 1,
     'ipDefaultTTL' => 1,
     'ipReasmTimeout' => 1,
};

my $ALARMS =
{
     'icmpInErrors' => 'icmpInMsgs',
     'icmpOutErrors' => 'icmpOutMsgs', 
     'tcpInErrs' => 'tcpInSegs',
     'udpInErrors' => 'udpInDatagrams',
     'ipInHdrErrors' => 'ipInReceives',
     'ipInAddrErrors' => 'ipInReceives ',
     'ipReasmFails' => 0,
     'ipFragFails' => 0,
};

my $_icmp =
{
     1 => 'icmpInMsgs', #.0 = Counter32: 14781484
     2 => 'icmpInErrors', #.0 = Counter32: 0
     3 => 'icmpInDestUnreachs', #.0 = Counter32: 1149
     4 => 'icmpInTimeExcds', #.0 = Counter32: 0
     5 => 'icmpInParmProbs', #.0 = Counter32: 0
     6 => 'icmpInSrcQuenchs', #.0 = Counter32: 0
     7 => 'icmpInRedirects', #.0 = Counter32: 9
     8 => 'icmpInEchos', #.0 = Counter32: 14780253
     9 => 'icmpInEchoReps', #.0 = Counter32: 66
     10 => 'icmpInTimestamps', #.0 = Counter32: 2
     11 => 'icmpInTimestampR', #.0 = Counter32: 0
     12 => 'icmpInAddrMasks', #.0 = Counter32: 4
     13 => 'icmpInAddrMaskReps', #.0 = Counter32: 0
     14 => 'icmpOutMsgs', #.0 = Counter32: 14952244
     15 => 'icmpOutErrors', #.0 = Counter32: 0
     16 => 'icmpOutDestUnr', #.0 = Counter32: 55751
     17 => 'icmpOutTimeExcds', #.0 = Counter32: 92
     18 => 'icmpOutParmProbs', #.0 = Counter32: 0
     19 => 'icmpOutSrcQuenchs', #.0 = Counter32: 0
     20 => 'icmpOutRedirects', #.0 = Counter32: 116077
     21 => 'icmpOutEchos', #.0 = Counter32: 4673
     22 => 'icmpOutEchoReps', #.0 = Counter32: 14780256
     23 => 'icmpOutTimestamps', #.0 = Counter32: 0
     24 => 'icmpOutTimestampR', #.0 = Counter32: 2
     25 => 'icmpOutAddrMasks', #.0 = Counter32: 0
     26 => 'icmpOutAddrMaskR', #.0 = Counter32: 0
};

my $_tcp =
{
     1 => 'tcpRtoAlgorithm', #.0 = INTEGER: vanj(4)    ##############NOCACHE
     2 => 'tcpRtoMin', #.0 = INTEGER: 300 milliseconds
     3 => 'tcpRtoMax', #.0 = INTEGER: 60000 milliseconds
     4 => 'tcpMaxConn', #.0 = INTEGER: -1
     5 => 'tcpActiveOpens', #.0 = Counter32: 2
     6 => 'tcpPassiveOpens', #.0 = Counter32: 108910
     7 => 'tcpAttemptFails', #.0 = Counter32: 391
     8 => 'tcpEstabResets', #.0 = Counter32: 108471
     9 => 'tcpCurrEstab', #.0 = Gauge32: 0
     10 => 'tcpInSegs', #.0 = Counter32: 1195823
     11 => 'tcpOutSegs', #.0 = Counter32: 1043567
     12 => 'tcpRetransSegs', #.0 = Counter32: 81
     14 => 'tcpInErrs', #.0 = Counter32: 0
     15 => 'tcpOutRsts', #.0 = Counter32: 437033
};

my $_tcpRtoAlgorithm =
{
    1 => 'other',
    2 => 'constant',
    3 => 'rsre',
    4 => 'vanj',
    5 => 'rfc2988',
};

my $_udp =
{
     1 => 'udpInDatagrams', #.0 = Counter32: 36441542
     2 => 'udpNoPorts', #.0 = Counter32: 14419773
     3 => 'udpInErrors', #.0 = Counter32: 0
     4 => 'udpOutDatagrams', #.0 = Counter32: 22208034
};

my $_ipstat =
{
     2 => 'ipDefaultTTL', #.0 = INTEGER: 64   #################NOCACHE
     3 => 'ipInReceives', #.0 = Counter32: 9759554
     4 => 'ipInHdrErrors', #.0 = Counter32: 0
     5 => 'ipInAddrErrors', #.0 = Counter32: 0
     6 => 'ipForwDatagrams', #.0 = Counter32: 0
     7 => 'ipInUnknownProtos', #.0 = Counter32: 0
     8 => 'ipInDiscards', #.0 = Counter32: 0
     9 => 'ipInDelivers', #.0 = Counter32: 9751120
     10 => 'ipOutRequests', #.0 = Counter32: 9724101
     11 => 'ipOutDiscards', #.0 = Counter32: 0
     12 => 'ipOutNoRoutes', #.0 = Counter32: 0
     13 => 'ipReasmTimeout', #.0 = INTEGER: 0
     14 => 'ipReasmReqds', #.0 = Counter32: 0
     15 => 'ipReasmOKs', #.0 = Counter32: 0
     16 => 'ipReasmFails', #.0 = Counter32: 0
     17 => 'ipFragOKs', #.0 = Counter32: 264
     18 => 'ipFragFails', #.0 = Counter32: 0
     19 => 'ipFragCreates', #.0 = Counter32: 0
};

my $_descr =
{
    icmpInAddrMaskReps => 'ICMP input address mask replies',
    icmpInAddrMasks => 'ICMP input address masks',
    icmpInDestUnreachs => 'ICMP input destination unreachable',
    icmpInEchoReps => 'ICMP input echo replies',
    icmpInEchos => 'ICMP input echos',
    icmpInErrors => 'ICMP input errors',
    icmpInMsgs => 'ICMP input messages',
    icmpInParmProbs => 'ICMP input parameter problems',
    icmpInRedirects => 'ICMP input redirects',
    icmpInSrcQuenchs => 'ICMP input source quenchs',
    icmpInTimeExcds => 'ICMP input time exceeded',
    icmpInTimestampR => 'ICMP input timestamp replies',
    icmpInTimestamps => 'ICMP input timestamps',
    icmpOutAddrMaskR => 'ICMP output address mask replies',
    icmpOutAddrMasks => 'ICMP output address masks',
    icmpOutDestUnr => 'ICMP output destination unreachable',
    icmpOutEchoReps => 'ICMP output echo replies',
    icmpOutEchos => 'ICMP output echos',
    icmpOutErrors => 'ICMP output errors',
    icmpOutMsgs => 'ICMP output messages',
    icmpOutParmProbs => 'ICMP output parameter problems',
    icmpOutRedirects => 'ICMP output redirects',
    icmpOutSrcQuenchs => 'ICMP output source quenchs',
    icmpOutTimeExcds => 'ICMP output time exceeded',
    icmpOutTimestampR => 'ICMP output timestamp replies',
    icmpOutTimestamps => 'ICMP output timestamps',
    ipDefaultTTL => 'IP default TTL',
    ipForwDatagrams => 'IP forward datagrams',
    ipFragCreates => 'IP fragment creates',
    ipFragFails => 'IP fragment fails',
    ipFragOKs => 'IP fragment OKs',
    ipInAddrErrors => 'IP input address errors',
    ipInDelivers => 'IP input delivers',
    ipInDiscards => 'IP input discards',
    ipInHdrErrors => 'IP input hardware errors',
    ipInReceives => 'IP input receives',
    ipInUnknownProtos => 'IP input unknown protocols',
    ipOutDiscards => 'IP output discards',
    ipOutNoRoutes => 'IP output no routes',
    ipOutRequests => 'IP output requests',
    ipReasmFails => 'IP re-assembled fails',
    ipReasmOKs => 'IP re-assembled OKs',
    ipReasmReqds => 'IP re-assembled Reqds',
    ipReasmTimeout => 'IP re-assembled timeout',
    tcpActiveOpens => 'TCP active opens',
    tcpAttemptFails => 'TCP attempt fails',
    tcpCurrEstab => 'TCP current established',
    tcpEstabResets => 'TCP established resets',
    tcpInErrs => 'TCP input errors',
    tcpInSegs => 'TCP input segments',
    tcpMaxConn => 'TCP maximum connections',
    tcpOutRsts => 'TCP output resets',
    tcpOutSegs => 'TCP output segments',
    tcpPassiveOpens => 'TCP passive opens',
    tcpRetransSegs => 'TCP retransmited segments',
    tcpRtoAlgorithm => 'TCP RTO algorithm',
    tcpRtoMax => 'TCP RTO max',
    tcpRtoMin => 'TCP RTO min',
    udpInDatagrams => 'UDP input datagrams',
    udpInErrors => 'UDP input errors',
    udpNoPorts => 'UDP no ports',
    udpOutDatagrams => 'UDP output datagrams',
};

sub clear_data
{
    my $self = shift;
    $self->[DATA] = {};
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

    my $oids_disabled = $entity->params_own->{'oids_disabled'};
    log_debug(sprintf(qq|entity %s oids_disabled: %s|, $id_entity, $oids_disabled), _LOG_DEBUG)
        if $LogEnabled && $oids_disabled;

    my $snmp_split_request = $entity->params_own->{'snmp_split_request'};
    log_debug(sprintf(qq|entity %s snmp_split_request: %s|, $id_entity, $snmp_split_request), _LOG_DEBUG)
        if $LogEnabled && $snmp_split_request;
    $snmp_split_request = 1
        unless $snmp_split_request;

    $self->clear_data;

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error) 
    {
        $session->max_msg_size(2944);

        my $oids = $self->oids_build($oids_disabled, $snmp_split_request);

        my $result;

        if ($snmp_split_request == 1)
        {
            $result = $session->get_request( -varbindlist => $oids->[0] );
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
            if ($snmp_split_request <= $MaxSNMPSplitRequest)
            {
                ++$snmp_split_request;
                $entity->params('snmp_split_request', $snmp_split_request);
            }
            else
            {
                log_debug(sprintf(qq|maximum snmp_split_request value %s already set. cannot fix that!!! check configuration|, 
                    $MaxSNMPSplitRequest), _LOG_ERROR);
            }
        }
        elsif ($error == 2)
        {
            my $bad_oid = $oids->[0]->[$session->error_index - 1];

            $oids_disabled = defined $oids_disabled
                ? join(":", $oids_disabled, $bad_oid)
                : $bad_oid;

            $entity->params('oids_disabled', $oids_disabled);
        }

        $self->result_dispatch($result);

        if (! keys %{ $self->data })
        {
             $self->errmsg('data collecting problem');
             $self->status(_ST_UNKNOWN);
        }

        $session->close
            if $session;
    }
    else
    {
        $self->errmsg($error);
        $self->status(_ST_UNKNOWN);
    }

    if ($self->status == _ST_OK)
    {
        $self->cache_update($id_entity, $self->data);
        $self->errors_and_utilization_status($entity);
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

    my $threshold_gp = $entity->params('tcpip_threshold_percent');
    my $threshold_gu = $entity->params('tcpip_threshold_units');

    my $thres;
    my $per;

    for my $tr (keys %$ALARMS)
    {
        next
            unless $ch->{$tr}->[1] && $ch->{$tr}->[1] ne 'U';

        $thres = $entity->params(sprintf(qq|tcpip_%s_threshold_units|, $tr));
        $thres = $threshold_gu
             unless defined $thres;

        if (defined $thres && $ch->{$tr}->[1] > $thres)
        {
             $self->errmsg("$_descr->{$tr} units threshold exceeded");
             $self->status(_ST_WARNING);
             next;
        }

        if ($ALARMS->{$tr} && defined $ch->{ $ALARMS->{$tr} } 
            && $ch->{ $ALARMS->{$tr} }->[1] > 0 && $ch->{ $ALARMS->{$tr} }->[1] ne 'U')
        {
            $thres = $entity->params(sprintf(qq|tcpip_%s_threshold_percent|, $tr));
            $thres = $threshold_gp
                unless defined $thres;
            $per = $ch->{$tr}->[1] * 100 / $ch->{ $ALARMS->{$tr} }->[1]; 
            if (defined $thres && $per > $thres)
            {
                $self->errmsg("$_descr->{$tr} percent threshold exceeded");
                $self->status(_ST_WARNING);
                next;
            }
        }
    }
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;


    my $data_dir = $DataDir;

    open F, ">$data_dir/$id_entity";

    my $h = $self->data;
    my $ch = $self->cache->{$id_entity};

    for ( map { defined $NO_CACHE->{$_}
        ? "$_\|$h->{$_}\n"
        : ( defined $ch->{$_} && defined $ch->{$_}->[1] 
            ? "$_\|$ch->{$_}->[1]\n${_}Counter\|$h->{$_}\n" 
            : "$_\|U\n${_}Counter\|$h->{$_}\n" ) } keys %$h )
    {   
        print F $_;
    }

    close F;
}

sub rrd_result
{
    my $self = shift;

    my $h = $self->data;
    my @k = keys %{$self->rrd_config};

    my $res = {};

    $res->{ $_ } = defined $h->{$_} ? $h->{$_} : 'U'
        for @k;

    return $res;
}

sub tracks
{
    my $self = shift;
    my @res;
    push @res, values %$_ipstat;
    push @res, values %$_icmp;
    push @res, values %$_tcp;
    push @res, values %$_udp;
    return \@res;
}

sub cache_keys
{
    return [ grep { ! defined $NO_CACHE->{$_} } @{$_[0]->tracks} ];
}

sub rrd_config
{
    my $self = shift;
    my $res = {};
    $res->{$_} = 'COUNTER'
        for @{$self->cache_keys};
    return $res;
}

sub result_dispatch
{
    my $self = shift;

    my $result = shift;

    return
        unless defined $result;

    my $key;

    for (keys %$result)
    {
        $key = $_; 
       
        if (/^$O_IPSTAT\./)
        {
            s/^$O_IPSTAT\.//g;
            s/\.0$//g;
            $self->[DATA]->{ $_ipstat->{$_} } = $result->{$key};
        }
        elsif (/^$O_ICMP\./)
        {
            s/^$O_ICMP\.//g;
            s/\.0$//g;
            $self->[DATA]->{ $_icmp->{$_} } = $result->{$key};
        }
        elsif (/^$O_TCP\./)
        {
            s/^$O_TCP\.//g;
            s/\.0$//g;
            $self->[DATA]->{ $_tcp->{$_} } = $_tcp->{$_} eq 'tcpRtoAlgorithm' 
                ? $_tcpRtoAlgorithm->{$result->{$key}} 
                : $result->{$key};
        }
        elsif (/^$O_UDP\./)
        {
            s/^$O_UDP\.//g;
            s/\.0$//g;
            $self->[DATA]->{ $_udp->{$_} } = $result->{$key};
        }
    }
}

sub data
{
    return $_[0]->[DATA];
}

sub oids_build
{
    my $self = shift;

    my $oids_disabled = {};

    my $oid_src = shift || '';

    @$oids_disabled{ (split /:/, $oid_src) } = undef;

    my $snmp_split_request = shift;

    my (@oids, $s);

    my $tables =
    [
        [ $O_IPSTAT, $_ipstat ],
        [ $O_ICMP, $_icmp ],
        [ $O_TCP, $_tcp ],
        [ $O_UDP, $_udp ],
    ];

    for my $tab (@$tables)
    {
        for $s (sort { $a <=> $b} keys %{ $tab->[1] })
        {
            $s = "$tab->[0].$s.0";
            next
                if exists $oids_disabled->{$s};
            push @oids, $s;
        }
    }

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

    return
        if $self->_discover_get_existing_entities($entity);

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error)
    {
        $session->max_msg_size(2944);

        my $result = $session->get_request( -varbindlist => ['1.3.6.1.2.1.6.1.0']);

        $error = $session->error();
        if ($error || ! $result || (defined $result && ! $result->{'1.3.6.1.2.1.6.1.0'}))
        {
            log_debug($error, _LOG_WARNING)
                if $LogEnabled;
            return;
        }


        $self->_discover_add_new_entity($entity);
    }
    else
    {
        log_debug($error, _LOG_WARNING)
            if $LogEnabled;
    }

}

sub _discover_add_new_entity
{
    my ($self, $parent) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s TCP/IP stack stat monitor|, $parent->id_entity), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = 
    {
        id_parent => $parent->id_entity,
        probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
        name => 'TCP/IP',
    };

    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {       
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s TCP/IP stack stat monitor|,
            $parent->id_entity, $entity->id_entity), _LOG_INFO)
            if $LogEnabled;
    }                   
}

sub desc_brief
{   
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    push @$result, sprintf(qq|RTO: %s, min %s, max %s|, $data->{tcpRtoAlgorithm}, $data->{tcpRtoMin}, $data->{tcpRtoMax})
        if $data->{tcpRtoAlgorithm};
    push @$result, sprintf(qq|TCP max connections: %s|, $data->{tcpMaxConn})
        if $data->{tcpMaxConn};
    push @$result, sprintf(qq|default TTL: %s|, $data->{ipDefaultTTL})
        if $data->{ipDefaultTTL};

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $parts = [ [$_ipstat, 'IP statistics'], [$_icmp, 'ICMP statistics'], [$_tcp, 'TCP statistics'], [$_udp, 'UDP statistics'] ];
    my $per;
    my $trc;
           
    $table->addRow(qq|<b>TCP/IP stack settings</b>|);
    $table->setCellColSpan($table->getTableRows, 1, 3);
    for my $part (map { $_->[0] } @$parts)
    {
        for (map { $part->{$_} } sort { $a <=> $b } keys %$part)
        {
            next
                unless defined $NO_CACHE->{$_};
            $table->addRow( $_descr->{$_}, sprintf(qq|<b>%s</b>|, $data->{$_}));
            $table->setCellColSpan($table->getTableRows, 2, 2);
        }
    } 
    $table->addRow("");
    $table->setCellColSpan($table->getTableRows, 1, 3);
    $table->addRow("&nbsp;");
    $table->setCellColSpan($table->getTableRows, 1, 3);
    $table->addRow("");
    $table->setCellColSpan($table->getTableRows, 1, 3);

    for my $part (@$parts)
    {
        $table->addRow(sprintf(qq|<b>%s</b>|, $part->[1]), 'delta', 'counter');

        $part = $part->[0];
        for (map { $part->{$_} } sort { $a <=> $b } keys %$part)
        {   
            next
                unless defined $data->{$_};

            next 
                if defined $NO_CACHE->{$_};

            $trc = $_ . "Counter";
            $trc = $data->{$trc};

            if (defined $ALARMS->{ $_ })
            {
                $per = $ALARMS->{ $_ } && $data->{ $ALARMS->{ $_ } } && $data->{ $ALARMS->{ $_ } } ne 'U'
                    ? $data->{$_}*100/$data->{ $ALARMS->{ $_ } }
                    : undef;

                if ( $per )
                {
                    $table->addRow( $_descr->{$_}, sprintf(qq|<span class="%s">%s; %.2f%</span>|, 
                         (! $data->{$_} ? 'j_10' : 'j_100'), 
                         format_bytes($data->{$_},2),
                         $per),
                         $trc);
                }
                else
                {
                    $data->{$_} eq 'U'
                        ? $table->addRow( $_descr->{$_}, 'unknown', $trc)
                        : $table->addRow( $_descr->{$_}, sprintf(qq|<span class="%s">%s</span>|, 
                            (! $data->{$_} ? 'j_10' : 'j_100'), 
                            format_bytes($data->{$_},2)),
                            $trc);
                }
                next;
            }
 
            $table->addRow( $_descr->{$_}, $data->{$_} eq 'U' ? 'unknown' : format_bytes($data->{$_},2), $trc );
        }
        $table->addRow("");
        $table->setCellColSpan($table->getTableRows, 1, 3);
        $table->addRow("&nbsp;");
        $table->setCellColSpan($table->getTableRows, 1, 3);
        $table->addRow("");
        $table->setCellColSpan($table->getTableRows, 1, 3);
    }
}

=pod
    my $thres;
    my $per;
    
    for my $tr (keys %$ALARMS)
    {
        next
            unless $ch->{$tr}->[1] && $ch->{$tr}->[1] ne 'U';

        if (defined $thres && $ch->{$tr}->[1] > $thres)
        {
             $self->errmsg("$tr units threshold exceeded");
             $self->status(_ST_WARNING);
             next;
        }

        if ($ALARMS->{$tr} && $ch->{ $ALARMS->{$tr} }->[1] > 0 && $ch->{ $ALARMS->{$tr} }->[1] ne 'U')
        {
            $thres = $entity->params(sprintf(qq|tcpip_%s_threshold_percent|, $tr));
            $thres = $threshold_gp
                unless defined $thres;
            $per = $ch->{$tr}->[1] * 100 / $ch->{ $ALARMS->{$tr} }->[1];
            if (defined $thres && $ch->{$tr}->[1] > $thres)
            {
                $self->errmsg("$tr percent threshold exceeded");
                $self->status(_ST_WARNING);
                next;
            }
        }
        $self->errmsg("$tr units detected");
        $self->status(_ST_WARNING);
    }
}
=cut

sub menu_stat
{ 
    return 1;
}

sub menu_stat_no_default
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

    return
        if $default_only;

    my $cgi = CGI->new();
            
    my $url;
    $url_params->{probe} = 'tcpip';
        
=pod        
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

=cut
    $url_params->{probe_prepare_ds} = 'prepare_ds';

for (@{ $self->cache_keys })
{
    $url_params->{probe_specific} = $_;
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}

}


sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    $rrd_graph->title($_descr->{$url_params->{probe_specific}});
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
