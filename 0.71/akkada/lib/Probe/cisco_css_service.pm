package Probe::cisco_css_service;

use vars qw($VERSION);

$VERSION = 0.13;

use base qw(Probe);
use strict;

use Net::SNMP;

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use URLRewriter;

our $DataDir = CFG->{Probe}->{DataDir};
our $LogEnabled = CFG->{LogEnabled};
our $MaxSNMPSplitRequest = CFG->{MaxSNMPSplitRequest};

sub id_probe_type
{
    return 11;
}

sub name
{
    return 'Cisco CSS service';
}

use constant
{
    APSVCENTRY => 10,
};

my $OID = '1.3.6.1.4.1.2467.1.15.2.1';

my $_apSvcEntry =
{
    1 => 'apSvcName',
    3 => 'apSvcIPAddress',
    4 => 'apSvcIPProtocol',
    5 => 'apSvcPort',
    6 => 'apSvcKALType',
    7 => 'apSvcKALFrequency',
    8 => 'apSvcKALMaxFailure',
    9 => 'apSvcKALRetryPeriod',
    10 => 'apSvcKALUri',
    11 => 'apSvcKALMethod',
    12 => 'apSvcEnable',
    13 => 'apSvcType',
    16 => 'apSvcWeight',
    17 => 'apSvcState',
    18 => 'apSvcShortLoad',
    19 => 'apSvcMaxConnections',
    20 => 'apSvcConnections',
    21 => 'apSvcTransitions',
    26 => 'apSvcStatus',
    29 => 'apSvcKALName',
    30 => 'apSvcLongLoad',
    31 => 'apSvcKALPort',
    39 => 'apSvcRedirectDomain',
    40 => 'apSvcAvgLoad',
    47 => 'apSvcRedirectString',
    51 => 'apSvcKALState',
};

my $_apSvcStatus =
{
    1 => 'active',
    2 => 'notInService',
    3 => 'notReady',
    4 => 'createAndGo',
    5 => 'createAndWait',
    6 => 'destroy',
};

my $_apSvcIPProtocol =
{
    0 => 'any',
    6 => 'tcp',
    17 => 'ucp',
};

my $_apSvcKALType = 
{
    0 => 'none',
    1 => 'icmp',
    2 => 'http',
    3 => 'ftp',
    4 => 'tcp',
    5 => 'named',
    6 => 'script',
};

my $_apSvcKALMethod  =
{
    0 => 'head',
    1 => 'get',
    2 => 'post',
};

my $_apSvcEnable =
{
    0 => 'disable',
    1 => 'enable',
};

my $_apSvcType =
{
    1 => 'local',
    2 => 'redirect',
    4 => 'proxyCache',
    8 => 'transparentCache',
    16 => 'automaticRedirect',
    32 => 'replicationStore',
    64 => 'replicationCache',
    128 => 'smashCache',
    256 => 'redundancyUp',
    512 => 'nciInfoOnly',
    1024 => 'nciDirectReturn',
    2048 => 'replicationStoreRedirect',
    4096 => 'replicationCacheRedirect',
};

my $_apSvcState =
{
    1 => 'suspended',
    2 => 'down',
    4 => 'alive',
    5 => 'dying',
};

my $_apSvcKALState =
{
    0 => 'none',
    1 => 'suspended',
    2 => 'down',
    4 => 'alive',
    5 => 'dying',
};

sub clear_data
{
    my $self = shift;
    $self->[APSVCENTRY] = {};
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

    my $name = join '.', unpack( 'c*', $entity->name );

    #my $oids_disabled = $entity->params('oids_disabled');
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

        my $oids = $self->oids_build($oids_disabled, $snmp_split_request, $name, $index);

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

        }
#use Data::Dumper; print Dumper $result;
        $self->result_dispatch($result, $name, $index);
#print Dumper $self->apSvcEntry;

        $self->errors_and_utilization_status($entity);
         
        $session->close
            if $session;
    }
    else
    {
        $self->errmsg($error);
        $self->status(_ST_DOWN);
    }

    #zapisanie danych do pliku
    $self->save_data($id_entity);
    $self->rrd_save($id_entity, $self->status)
        if $self->status < _ST_DOWN;
}

sub down_stats
{
    my $self = shift;
    my $apSvcEntry = $self->apSvcEntry;
    for (keys %{ $self->rrd_config })
    {
        $apSvcEntry->{$_} = 'U';
    }
}

sub errors_and_utilization_status
{
    my $self = shift;
    my $entity = shift;
    my $apSvcEntry = $self->apSvcEntry;

    if (! keys %$apSvcEntry)
    {
        $self->errmsg('service unavailable');
        $self->status(_ST_DOWN);
        return;
    }    

#print "apSvcEnable:", $apSvcEntry->{apSvcEnable}, "\n\n";

    if (defined $apSvcEntry->{apSvcEnable} && $apSvcEntry->{apSvcEnable} eq 'disable')
    {
        if (! $entity->params('cisco_css_service_stop_warning_suspended_state'))
        {
            $self->status(_ST_WARNING);
        }
        else
        {
            #$self->status(_ST_NOSTATUS);
        }
        $self->errmsg(qq|service state: suspended|);
        $self->down_stats;
        return;
    }

    if (defined $apSvcEntry->{apSvcState} && $apSvcEntry->{apSvcState} ne 'suspended' && $apSvcEntry->{apSvcState} ne 'alive')
    {
        if ($apSvcEntry->{apSvcState} eq 'down' && $entity->params('cisco_css_service_stop_warning_down_state'))
        {
            #$self->status(_ST_NOSTATUS);
        }
        else
        {
            $self->status(_ST_DOWN);
        }
        $self->errmsg(sprintf(qq|service state: %s|, $apSvcEntry->{apSvcState}));
        $self->down_stats;
        return;
    }

    if (defined $apSvcEntry->{apSvcStatus} 
        && $apSvcEntry->{apSvcStatus} ne 'active' 
        && $apSvcEntry->{apSvcStatus} ne '0' 
        && $apSvcEntry->{apSvcStatus} ne 'createAndGo')
    {
        $self->errmsg(sprintf(qq|service row status: %s|, $apSvcEntry->{apSvcStatus}));
        $self->status(_ST_DOWN);
        $self->down_stats;
        return;
    }

    if (defined $apSvcEntry->{apSvcKALState} 
        && $apSvcEntry->{apSvcKALState} eq 'dying' 
        && $apSvcEntry->{apSvcKALState} eq 'down')
    {
        $self->errmsg(sprintf(qq|service keepalive state: %s|, $apSvcEntry->{apSvcKALState}));
        $self->status(_ST_DOWN);
        $self->down_stats;
        return;
    }

    my $u;

    if (defined $apSvcEntry->{apSvcConnections} && defined $apSvcEntry->{apSvcMaxConnections} && $apSvcEntry->{apSvcMaxConnections})
    {
        $u = ($apSvcEntry->{apSvcConnections}*100)/$apSvcEntry->{apSvcMaxConnections};
        if ($u && $u > $self->threshold_high)
        {
            $self->errmsg(qq|high connections level|);
            $self->status(_ST_MAJOR);
        }
        elsif ($u && $u > $self->threshold_medium)
        {
            $self->errmsg(qq|medium connections level|);
            $self->status(_ST_WARNING);
        }
    }

if (! $entity->params('cisco_css_service_stop_warning_high_load')
    && ! $entity->params('cisco_css_service_stop_warning_high_short_load'))
{

    if (defined $apSvcEntry->{apSvcShortLoad} && $apSvcEntry->{apSvcShortLoad})
    {
        $u = ($apSvcEntry->{apSvcShortLoad}*100)/255;
#print "#$u#\n";
#print "#", $self->threshold_high, "#\n";
        if ($u && $u > $self->threshold_high)
        {
            $self->errmsg(qq|high short load|);
            $self->status(_ST_MAJOR);
        }
        elsif ($u && $u > $self->threshold_medium)
        {
            $self->errmsg(qq|medium short load|);
            $self->status(_ST_WARNING);
        }
    }
}

if (! $entity->params('cisco_css_service_stop_warning_high_load')
    && ! $entity->params('cisco_css_service_stop_warning_high_long_load'))
{
    if (defined $apSvcEntry->{apSvcLongLoad} && $apSvcEntry->{apSvcLongLoad})
    {
        $u = ($apSvcEntry->{apSvcLongLoad}*100)/255;
        if ($u && $u > $self->threshold_high)
        {   
            $self->errmsg(qq|high long load|);
            $self->status(_ST_MAJOR);
        }
        elsif ($u && $u > $self->threshold_medium)
        {   
            $self->errmsg(qq|medium long load|);
            $self->status(_ST_WARNING);
        }
    }
}
if (! $entity->params('cisco_css_service_stop_warning_high_load')
    && ! $entity->params('cisco_css_service_stop_warning_high_average_load'))
{
    if (defined $apSvcEntry->{apSvcAvgLoad} && $apSvcEntry->{apSvcAvgLoad})
    {
        $u = ($apSvcEntry->{apSvcAvgLoad}*100)/255;
        if ($u && $u > $self->threshold_high)
        {
            $self->errmsg(qq|high average load|);
            $self->status(_ST_MAJOR);
        }
        elsif ($u && $u > $self->threshold_medium)
        {
            $self->errmsg(qq|medium average load|);
            $self->status(_ST_WARNING);
        }
    }

    }
}

sub rrd_result
{
    my $self = shift;

    my $h = $self->apSvcEntry;

    return
    {   
        'apSvcShortLoad' => defined $h->{apSvcShortLoad} ? $h->{apSvcShortLoad} : 'U',
        'apSvcConnections' => defined $h->{apSvcConnections} ? $h->{apSvcConnections} : 'U',
        'apSvcTransitions' => defined $h->{apSvcTransitions} ? $h->{apSvcTransitions} : 'U',
        'apSvcLongLoad' => defined $h->{apSvcLongLoad} ? $h->{apSvcLongLoad} : 'U',
        'apSvcAvgLoad' => defined $h->{apSvcAvgLoad} ? $h->{apSvcAvgLoad} : 'U',
    };
}

sub rrd_config
{
    return
    {
        'apSvcShortLoad' => 'GAUGE',
        'apSvcConnections' => 'GAUGE',
        'apSvcTransitions' => 'COUNTER',
        'apSvcLongLoad' => 'GAUGE',
        'apSvcAvgLoad' => 'GAUGE',
    };
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;


    my $data_dir = $DataDir;

    my $h;

    open F, ">$data_dir/$id_entity";

    $h = $self->apSvcEntry;
#use Data::Dumper; print Dumper $h;
    for ( map { "$_\|$h->{$_}\n" } keys %$h )
    {
        print F $_;
    }

    close F;
}



sub result_dispatch
{
    my $self = shift;

    my $result = shift;
    my $name = shift;
    my $index = shift;

    return
        unless defined $result;

    my $key;

    for (keys %$result)
    {
        $key = $_; 
        if (/^$OID\./)
        {
            s/^$OID\.//g;
            s/\.$index.$name$//g;

            if ($_apSvcEntry->{$_} eq 'apSvcIPProtocol')
            {
                $self->[APSVCENTRY]->{ $_apSvcEntry->{$_} } = $_apSvcIPProtocol->{ $result->{$key} };
            }
            elsif ($_apSvcEntry->{$_} eq 'apSvcKALType')
            {
                $self->[APSVCENTRY]->{ $_apSvcEntry->{$_} } = $_apSvcKALType->{ $result->{$key} };
            }
            elsif ($_apSvcEntry->{$_} eq 'apSvcKALMethod')
            {
                $self->[APSVCENTRY]->{ $_apSvcEntry->{$_} } = $_apSvcKALMethod->{ $result->{$key} };
            }
            elsif ($_apSvcEntry->{$_} eq 'apSvcEnable')
            {
                $self->[APSVCENTRY]->{ $_apSvcEntry->{$_} } = $_apSvcEnable->{ $result->{$key} };
            }
            elsif ($_apSvcEntry->{$_} eq 'apSvcType')
            {
                $self->[APSVCENTRY]->{ $_apSvcEntry->{$_} } = $_apSvcType->{ $result->{$key} };
            }
            elsif ($_apSvcEntry->{$_} eq 'apSvcState')
            {
                $self->[APSVCENTRY]->{ $_apSvcEntry->{$_} } = $_apSvcState->{ $result->{$key} };
            }
            elsif ($_apSvcEntry->{$_} eq 'apSvcKALState')
            {
                $self->[APSVCENTRY]->{ $_apSvcEntry->{$_} } = $_apSvcKALState->{ $result->{$key} };
            }
            elsif ($_apSvcEntry->{$_} eq 'apSvcStatus')
            {
                $self->[APSVCENTRY]->{ $_apSvcEntry->{$_} } = defined $_apSvcStatus->{ $result->{$key} }
                    ? $_apSvcStatus->{ $result->{$key} }
                    : $result->{$key};
            }
            elsif (defined $_apSvcEntry->{$_})
            {
                $self->[APSVCENTRY]->{ $_apSvcEntry->{$_} } = $result->{$key};
            }
        }
    }
}

sub apSvcEntry
{
    return $_[0]->[APSVCENTRY];
}

sub oids_build
{
    my $self = shift;

    my $oids_disabled = {};

    defined $_[0]
        ? @$oids_disabled{ (split /:/, shift) } = undef
        : shift;

    my $snmp_split_request = shift;
    my $name = shift;
    my $index = shift;

    my (@oids, $s);

    for $s (sort { $a <=> $b} keys %$_apSvcEntry)
    {
        next
            if $s == 1;
        $s = "$OID.$s";
        next
            if exists $oids_disabled->{$s};
        push @oids, sprintf(qq|%s.%s.%s|, $s, $index, $name);
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

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error)
    {
        $session->max_msg_size(2944);

        my $result;
        my $new;

        my $st; #tmp string
        my $oid = $OID . ".1";

        $result = $session->get_table(-baseoid => $oid);
        $error = $session->error();

        if ($error)
        {
            log_debug($error, _LOG_WARNING)
                if $LogEnabled;
            return;
        }

        for (keys %$result)
        {
            $st = $result->{$_};

            next
                unless $st;

            s/^$oid.//g;
            $new->{ $st } = (split /\./, $_)[0];
        }  
   
        return
            unless $new; 

        my $old = $self->_discover_get_existing_entities($entity);

        for my $name (keys %$old)
        {
            next
                unless  defined $new->{$name};

            $old->{$name}->{entity}->params('index', $new->{$name})
                if $new->{$name} ne $old->{$name}->{index};

            if ($old->{$name}->{entity}->status eq _ST_BAD_CONF)
            {
                $old->{$name}->{entity}->errmsg('');
                $old->{$name}->{entity}->status(_ST_UNKNOWN);
            }

            delete $new->{$name};
            delete $old->{$name};
        }

        for (keys %$new)
        {
            $self->_discover_add_new_entity($entity, $_, $new->{$_});
            delete $new->{$_};
        }

        for (keys %$old)
        {
        #    $old->{$_}->{entity}->status(_ST_BAD_CONF);
        #    $old->{$_}->{entity}->db_update_entity;
        # albo serwis jest gaszony albo go nie ma. jak to wykryc?
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
    my ($self, $parent, $name, $index) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s index %d|, $parent->id_entity, $name, $index), _LOG_DEBUG)
        if $LogEnabled;

    $name =~ s/\000$//;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {
           index => $index,
       }, 
       };


    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {       
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s|,
            $parent->id_entity, $entity->id_entity, $name,), _LOG_INFO)
            if $LogEnabled;
    }                   
}

sub _discover_get_existing_entities
{

    my $self = shift;

    my @list = $self->SUPER::_discover_get_existing_entities(@_);

    my $result;

    for (@list)
    {

        my $entity = Entity->new($self->dbh, $_);
        my $name = $entity->name;

        $result->{ $name }->{entity} = $entity;
        $result->{ $name }->{index} = $entity->params('index');
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

    push @$result, $data->{apSvcIPAddress}
        if defined $data->{apSvcIPAddress} && $data->{apSvcIPAddress};

    push @$result, sprintf(qq|state: <span class="%s">%s</span>|, 
        $data->{apSvcState} eq 'alive' ? 'g8' : 'g9', $data->{apSvcState})
        if defined $data->{apSvcState} && $data->{apSvcState};

    if (defined $data->{apSvcAvgLoad} && $data->{apSvcAvgLoad} ne 'U')
    {   
        my $p = ($data->{apSvcAvgLoad}*100)/255;
        push @$result, sprintf(qq|load avg: <font class="%s">%.2f%%</font>|,                                                          percent_bar_style_select($p), $p, $data->{apSvcAvgLoad});
    }
    else
    {   
        push @$result, qq|load avg: n/a|;
    }

    if (defined $data->{apSvcConnections} && $data->{apSvcConnections} ne 'U' )
    {   
        #use Data::Dumper; warn Dumper $data->{apSvcMaxConnections};
        if ($data->{apSvcMaxConnections})
        {
             my $p = ($data->{apSvcConnections}*100)/$data->{apSvcMaxConnections};
             push @$result, sprintf(qq|conn: <font class="%s">%s/%s</font>|, 
                 percent_bar_style_select($p), $data->{apSvcConnections}, $data->{apSvcMaxConnections});
        }
        else
        {
             push @$result, sprintf(qq|conn: %s|, $data->{apSvcConnections});
        }
    }
    else
    {   
        push @$result, qq|conn: n/a|;
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

    $table->addRow("admin state:", sprintf(qq|<b>%s</b>|,$data->{apSvcEnable}));
    $table->addRow("operation state:", 
        sprintf(qq|<span class="%s">%s</span>|,$data->{apSvcState} eq 'alive' ? 'g8' : 'g9', $data->{apSvcState}));
    $table->addRow("row status:",
        sprintf(qq|<span class="%s">%s</span>|,
            $data->{apSvcStatus} eq 'active' || $data->{apSvcStatus} eq 'createAndGo' 
                ? 'g8' : 'g9', $data->{ apSvcStatus }));

    my ($s, $t, $p);

    my $tracks = [ 'apSvcIPAddress', 'apSvcIPProtocol', 
        'apSvcPort', 'apSvcType', 'apSvcRedirectDomain', 'apSvcRedirectString', 'apSvcWeight' ];

    for (@$tracks)
    {
        $t = $_;
        $t =~ s/apSvc//g;
        $t =~ s/(\p{upper})/ $1/g;
        $t =~ s/I P/IP/g;
        $s = $data->{$_}; 
        $s = 'any'
            if $_ eq 'apSvcPort' && ! $s;
        $table->addRow(lc("$t:"), $s);
    };
    $table->addRow("");
    $table->setCellColSpan($table->getTableRows, 1, 2);

    $tracks = [ 'apSvcConnections', 'apSvcMaxConnections', 'apSvcAvgLoad', 'apSvcShortLoad', 'apSvcLongLoad', 'apSvcTransitions', ];

    for (@$tracks)
    {
        $t = $_;
        $t =~ s/apSvc//g;
        $t =~ s/(\p{upper})/ $1/g;
        $s = $data->{$_}; 
        if ($_ eq 'apSvcConnections' && $data->{apSvcMaxConnections})
        {
            $p = ($s*100)/$data->{apSvcMaxConnections};
            $s = sprintf(qq|<font class="%s">%s; %.2f%% of allowed maximum</font>|, percent_bar_style_select($p), $s, $p);
        }
        elsif ($_ =~ /Load/ && $s ne 'U')
        {
            $p = ($s*100)/255;
            $s = sprintf(qq|<font class="%s">%.2f%% (raw: %s)</font>|, percent_bar_style_select($p), $p, $s);
        }
        $table->addRow(lc("$t:"), $s);
    };
    $table->addRow("");
    $table->setCellColSpan($table->getTableRows, 1, 2);
    
    $tracks = [ 'apSvcKALName', 'apSvcKALState', 'apSvcKALType', 
        'apSvcKALPort', 'apSvcKALFrequency', 'apSvcKALMaxFailure', 
        'apSvcKALRetryPeriod', 'apSvcKALUri', 'apSvcKALMethod', ];

    for (@$tracks)
    {
        $t = $_;
        $t =~ s/apSvcKAL/keepalive /g;
        $t =~ s/(\p{upper})/ $1/g;

        $s = $data->{$_}; 
        if ($_ eq 'apSvcKALState')
        {
            $s = sprintf(qq|<span class="%s">%s</span>|,$s eq 'alive' ? 'g8' : 'g9', $s);
        }
        elsif ($_ eq 'apSvcKALPort' && ! $s)
        {
            $s = 'any';
        }
        $table->addRow(lc("$t:"), $s);
    };
}

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;

    return sprintf(qq|%s%s|,
        $entity->name,
        $entity->status_weight == 0
        || $entity->params('cisco_css_service_stop_warning_suspended_state')
        || $entity->params('cisco_css_service_stop_warning_down_state')
        || $entity->params('cisco_css_service_stop_warning_high_load')
            ? '*'
            : '');
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
    $url_params->{probe} = 'cisco_css_service';

    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'apSvcConnections';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    return
        if $default_only;

    $url_params->{probe_prepare_ds} = 'prepare_ds_load';
    $url_params->{probe_specific} = 'perc';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds_load';
    $url_params->{probe_specific} = 'raw';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'apSvcTransitions';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}

sub prepare_ds_load_pre
{   
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    if ( $url_params->{probe_specific} eq 'raw' )
    {   
        $rrd_graph->title('raw load');
        $rrd_graph->unit('no');
    }
    else
    {   
        $rrd_graph->title('percent load');
        $rrd_graph->unit('%');
    }
}

sub prepare_ds_load
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;

    my $rrd_file = sprintf(qq|%s/%s.%s|, CFG->{Probe}->{RRDDir}, $entity->id_entity, $url_params->{probe});

    my $up = 1;
    my $down = 0;

    if ($url_params->{probe_specific} eq 'raw')
    {
        push @$args, "DEF:ds0a=$rrd_file:apSvcAvgLoad:$cf";
        push @$args, "DEF:ds0s=$rrd_file:apSvcShortLoad:$cf";
        push @$args, "DEF:ds0l=$rrd_file:apSvcLongLoad:$cf";
        push @$args, "LINE1:ds0l#FFFF33:long";
        push @$args, "LINE1:ds0s#CC3333:short";
        push @$args, "LINE1:ds0a#CC9933:average";
    }
    elsif ($url_params->{probe_specific} eq 'perc')
    {
        push @$args, "DEF:ds0a=$rrd_file:apSvcAvgLoad:$cf";
        push @$args, "DEF:ds0s=$rrd_file:apSvcShortLoad:$cf";
        push @$args, "DEF:ds0l=$rrd_file:apSvcLongLoad:$cf";
        push @$args, "CDEF:ds0ap=ds0a,100,*,255,/";
        push @$args, "CDEF:ds0sp=ds0s,100,*,255,/";
        push @$args, "CDEF:ds0lp=ds0l,100,*,255,/";
        push @$args, "LINE1:ds0lp#FFFF33:long";
        push @$args, "LINE1:ds0sp#CC3333:short";
        push @$args, "LINE1:ds0ap#CC9933:average";
    }

    return ($up, $down, "ds0a");

}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $url_params = $rrd_graph->url_params;
    $rrd_graph->unit('');

    my $title = $url_params->{probe_specific};
    $title =~ s/apSvc//g;
    $rrd_graph->title($title);
}

sub popup_items
{
    my $self = shift;

    $self->SUPER::popup_items(@_);

    my $buttons = $_[0]->{buttons};
    my $class = $_[0]->{class};
    my $section = $_[0]->{section};
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "stop warning suspended state", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=cisco_css_service_stop_warning_suspended_state&add_value=1&id_entity=','current','$class');",}); 
    $buttons->add({ caption => "stop warning down state", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=cisco_css_service_stop_warning_down_state&add_value=1&id_entity=','current','$class');",}); 
    $buttons->add({ caption => "stop warning high load", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=cisco_css_service_stop_warning_high_load&add_value=1&id_entity=','current','$class');",}); 

}

sub snmp
{
    return 1;
}

1;
