package Probe::cisco_dial_peer_voice;

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
our $IANAifType = CFG->{Probes}->{nic}->{IANAifType};

sub id_probe_type
{
    return 26;
}

use constant
{
    DATA => 10,
};

my $OID = '1.3.6.1.2.1.10.21.1.2.2.1';
my $OIDCFG = '1.3.6.1.2.1.10.21.1.2.1.1';

my $_ds = {
    1 => 'ConnectTime',
    2 => 'ChargedUnits',
    3 => 'SuccessCalls',
    4 => 'FailCalls',
    5 => 'AcceptCalls',
    6 => 'RefuseCalls',
    7 => 'LastDisconnectCause',
    8 => 'LastDisconnectText',
    9 => 'LastSetupTime',
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

    my $index = $entity->params('index');
    throw EEntityMissingParameter(sprintf( qq|index in entity %s|, $id_entity))
        unless $index;

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

        my $oids = $self->oids_build($snmp_split_request, $index);

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
        $self->result_dispatch($result, $index);
        $self->cache_update($entity->id_entity, $self->data);
#print Dumper $self->data; exit;

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

sub cache_keys
{
    my $self = shift;
    return
    [   
        keys %{ $self->rrd_config }
    ];
}

sub down_stats
{
    my $self = shift;
    my $data = $self->data;
    for (keys %{ $self->rrd_config })
    {
        $data->{$_} = 'U';
    }
}

sub errors_and_utilization_status
{
    my $self = shift;
    my $entity = shift;
    my $data = $self->data;

    if (! keys %$data)
    {
        $self->errmsg('peer unavailable');
        $self->status(_ST_MAJOR);
        return;
    }    
}

sub rrd_result
{
    my $self = shift;

    my $h = $self->data;

    return
    {   
        'SuccessCalls' => defined $h->{SuccessCalls} ? $h->{SuccessCalls} : 'U',
        'FailCalls' => defined $h->{FailCalls} ? $h->{FailCalls} : 'U',
        'AcceptCalls' => defined $h->{AcceptCalls} ? $h->{AcceptCalls} : 'U',
        'RefuseCalls' => defined $h->{RefuseCalls} ? $h->{RefuseCalls} : 'U',
    };
}

sub rrd_config
{
    return
    {
        'SuccessCalls' => 'COUNTER',
        'FailCalls' => 'COUNTER',
        'AcceptCalls' => 'COUNTER',
        'RefuseCalls' => 'COUNTER',
    };
}

sub save_data
{       
    my $self = shift;
    my $id_entity = shift;
    
    my $data_dir = $DataDir;
        
    open F, ">$data_dir/$id_entity";
    
    my $c = $self->rrd_config;

    my $ch  = $self->cache->{ $id_entity };
    for ( keys %$ch )
    {   
        print F "delta$_\|$ch->{$_}->[1]\n"
            if defined $c->{$_};
    }   
   
    my $h = $self->data; 
    for (values %$_ds)
    {
        print F "$_\|$h->{$_}\n";
    }
    
    close F;
}

sub result_dispatch
{
    my $self = shift;

    my $result = shift;
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
            s/\.$index$//g;
            if ($_ds->{$_} eq 'LastSetupTime')
            {
                $result->{$key} = timeticks_2_duration( $result->{$key} );
            }
            $self->[DATA]->{ $_ds->{$_} } = $result->{$key};
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

    my $snmp_split_request = shift;
    my $index = shift;

    my (@oids, $s);

    for $s (sort { $a <=> $b} keys %$_ds)
    {
        push @oids, sprintf(qq|%s.%s.%s|, $OID, $s, $index);
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
        my $oid = $OIDCFG . ".4";

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
            s/^$oid.//g;
            $new->{ $_ }->{name} = $st;
        }  

        return
            unless $new; 

        $oid = $OIDCFG . ".2";
        
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
            s/^$oid.//g;
            $new->{ $_ }->{ianaiftype} = $st;
        }  

        my $old = $self->_discover_get_existing_entities($entity);

        for my $index (keys %$old)
        {
            next
                unless defined $new->{$index};

            if ($old->{$index}->{entity}->name eq '')
            {
                $old->{$index}->{entity}->name($new->{$index});
                $old->{$index}->{entity}->db_update_entity;
            }
            if (defined $new->{$index}->{ianaiftype} && $new->{$index}->{ianaiftype} ne '')
            {
                $old->{$index}->{entity}->params('ianaiftype', $new->{ $index }->{ianaiftype});
            }

            delete $new->{$index};
            delete $old->{$index};
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
    my ($self, $parent, $index, $new) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s index %s, name: %s|, $parent->id_entity, $index, $new->{name}), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $new->{name},
       params => {
           index => $index,
           ianaiftype => $new->{ianaiftype},
       }, 
       };


    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {       
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s %s|,
            $parent->id_entity, $entity->id_entity, $index, $new->{name}), _LOG_INFO)
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
        my $index = $entity->params('index');
        $result->{ $index }->{entity} = $entity;
        $result->{ $index }->{ianaiftype} = $entity->params('ianaiftype');
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


    my $c = $self->rrd_config;
    my $t;

    for (keys %$c)
    {   
        $t = $_;
        $t =~ s/(\p{upper})/ $1/g;
        push @$result, sprintf(qq|%s: %s|, $t, $data->{$_});
    };

    my $ianaiftype = $entity->params('ianaiftype');
    if ($ianaiftype)
    {   
        $ianaiftype = $IANAifType->{ $ianaiftype }
                    ? $IANAifType->{ $ianaiftype }->{type}
                    : $ianaiftype;
        push @$result, sprintf(qq|type: %s|, $ianaiftype);
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

    my $ianaiftype = $entity->params('ianaiftype');
    if ($ianaiftype)
    {
        $ianaiftype = $IANAifType->{ $ianaiftype }
                    ? sprintf(qq|%s; %s|,  $IANAifType->{ $ianaiftype }->{type},  $IANAifType->{ $ianaiftype }->{desc})
                    : $ianaiftype;
        $table->addRow(lc("interface type:"), $ianaiftype);
    }

    my $tracks = [ 'ConnectTime', 'ChargedUnits', 'SuccessCalls', 'FailCalls', 'AcceptCalls', 'RefuseCalls', 'LastDisconnectCause', 'LastDisconnectText', 'LastSetupTime' ];

    my $c = $self->rrd_config;

    my ($s, $t);

    for (@$tracks)
    {
        $t = $_;
        $t =~ s/(\p{upper})/ $1/g;
        $s = $data->{$_}; 
        if (defined $c->{$_})
        {
            $table->addRow(lc("$t:"), sprintf(qq|%s (delta: %s)|, $s, $data->{"delta${_}"}));
        }
        else
        {
            $table->addRow(lc("$t:"), $s);
        }
    };
}

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;

    return sprintf(qq|%s%s|,
        $entity->name,
        $entity->status_weight == 0
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
    $url_params->{probe} = 'cisco_dial_peer_voice';

    $url_params->{probe_prepare_ds} = 'prepare_ds_dps';
    $url_params->{probe_specific} = 'perc';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    return
        if $default_only;

    $url_params->{probe_specific} = 'raw';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}

sub prepare_ds_dps_pre
{   
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    if ( $url_params->{probe_specific} eq 'raw' )
    {   
        $rrd_graph->title('number of calls');
        $rrd_graph->unit('no');
    }
    else
    {   
        $rrd_graph->title('percent number of calls');
        $rrd_graph->unit('%');
    }
}

sub prepare_ds_dps
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
        push @$args, "DEF:ds0s=$rrd_file:SuccessCalls:$cf";
        push @$args, "DEF:ds0f=$rrd_file:FailCalls:$cf";
        push @$args, "DEF:ds0a=$rrd_file:AcceptCalls:$cf";
        push @$args, "DEF:ds0r=$rrd_file:RefuseCalls:$cf";
        push @$args, "LINE1:ds0s#00FF00:success";
        push @$args, "LINE1:ds0f#CC3333:fail";
        push @$args, "LINE1:ds0a#00FFdd:accept";
        push @$args, "LINE1:ds0r#FFFF33:refuse";
    }
    elsif ($url_params->{probe_specific} eq 'perc')
    {
        push @$args, "DEF:ds0s=$rrd_file:SuccessCalls:$cf";
        push @$args, "DEF:ds0f=$rrd_file:FailCalls:$cf";
        push @$args, "DEF:ds0a=$rrd_file:AcceptCalls:$cf";
        push @$args, "DEF:ds0r=$rrd_file:RefuseCalls:$cf";
        push @$args, "CDEF:ds0sum=ds0s,ds0f,+,ds0a,+,ds0r,+";
        push @$args, "CDEF:ds0sp=ds0s,100,*,ds0sum,/";
        push @$args, "CDEF:ds0fp=ds0f,100,*,ds0sum,/";
        push @$args, "CDEF:ds0ap=ds0a,100,*,ds0sum,/";
        push @$args, "CDEF:ds0rp=ds0r,100,*,ds0sum,/";
        push @$args, "AREA:ds0sp#00FF00:success";
        push @$args, "STACK:ds0fp#CC3333:fail";
        push @$args, "STACK:ds0ap#00FFdd:accept";
        push @$args, "STACK:ds0rp#FFFF33:refuse";
    }

    return ($up, $down, "ds0s");

}

sub snmp
{
    return 1;
}

1;
