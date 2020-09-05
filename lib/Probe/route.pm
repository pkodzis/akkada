package Probe::route;

use vars qw($VERSION);

$VERSION = 0.1;

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
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};

sub id_probe_type
{
    return 18;
}

sub name
{
    return 'route entry';
}

use constant
{
    IPROUTE => 11,
    SESSION => 13,
    ENTITY => 14,
};

our $OID = '1.3.6.1.2.1.4.21.1';

my $_ipRoute =
{
    1 => 'ipRouteDest',
    #2 => 'ipRouteIfIndex',
    #3 => 'ipRouteMetric1',
    #4 => 'ipRouteMetric2',
    #5 => 'ipRouteMetric3',
    #6 => 'ipRouteMetric4',
    7 => 'ipRouteNextHop',
    8 => 'ipRouteType',
    9 => 'ipRouteProto',
    10 => 'ipRouteAge',
    11 => 'ipRouteMask',
    #12 => 'ipRouteMetric5',
    #13 => 'ipRouteInfo',
};

my $_ipRouteType =
{
    1 => 'other',
    2 => 'invalid',
    3 => 'direct',
    4 => 'indirect',
};

my $_ipRouteProto =
{
    1 => 'other',
    2 => 'local',
    3 => 'netmgmt',
    4 => 'icmp',
    5 => 'egp',
    6 => 'ggp',
    7 => 'hello',
    8 => 'rip',
    9 => 'is-is',
    10 => 'es-is',
    11 => 'ciscoIgrp',
    12 => 'bbnSpfIgp',
    13 => 'ospf',
    14 => 'bgp',
};

sub clear_data
{
    my $self = shift;
    $self->[IPROUTE] = {};
    $self->[ENTITY] = undef;
};

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->[SESSION] = undef;

    return $self;
}

sub ipRoute
{
    return $_[0]->[IPROUTE];
}

sub session
{
    my $self = shift;
    $self->[SESSION] = shift
        if @_;
    return $self->[SESSION];
}

sub mandatory_fields
{
    return
    [
        'route_next_hop',
    ]
}

sub manual
{
    return 1;
}

sub entity
{
    my $self = shift;
    $self->[ENTITY] = shift
        if @_;
    return $self->[ENTITY];
}

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);
    
    my $entity = shift;
    
    $self->clear_data;
    $self->entity($entity);

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

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error)
    {
        $session->max_msg_size(2944);
        $self->session( $session );

        my $result = $session->get_request( -varbindlist => $self->oids_build( $entity->name ) );

        my $error = $session->error();
        if (! $error )
        {   
            $self->result_dispatch($result);
            $self->utilization_status();
        }  
        else
        {   
            $self->errmsg('snmp error: ' . $error);
            $self->status(_ST_MAJOR);
        }

    }
    else
    {
        $self->errmsg($error);
        $self->status(_ST_MAJOR);
    }

#use Data::Dumper; print Dumper $self->ipRoute, $self->errmsg, $self->status; exit;

    $self->save_data($id_entity);

    $session->close
        if $session;
}


sub utilization_status
{ 
    my $self = shift;
    my $ipRoute = $self->ipRoute;
    my $entity = $self->entity;

    my $route_next_hop = $entity->params('route_next_hop');
    if (! defined $route_next_hop)
    {
        $self->errmsg(qq|missing route_next_hop parameter|);
        $self->status(_ST_BAD_CONF);
    }

    if (defined $ipRoute && ref($ipRoute) eq 'HASH')
    {   
        if (defined $ipRoute->{ipRouteType} && $ipRoute->{ipRouteType} eq 'invalid')
        {   
            $self->errmsg(qq|route not exists or invalid|);
            $self->status(_ST_DOWN);
        }
        elsif (! defined $ipRoute->{ipRouteNextHop})
        {   
            $self->errmsg(qq|unknown next hop|);
            $self->status(_ST_MAJOR);
        }
        elsif ($ipRoute->{ipRouteNextHop} ne $route_next_hop)
        {   
            $self->errmsg(qq|bad next hop|);
            $self->status(_ST_DOWN);
        }
    }   
    else
    {   
        $self->errmsg(qq|route not found|);
        $self->status(_ST_DOWN);
    }
}


sub oids_build
{  
    my $self = shift;
    my $index = shift;

    my @oids = ();

    for (keys %$_ipRoute)
    {
        push @oids, "$OID.$_.$index";
    }

    return \@oids;
}

sub result_dispatch
{
    my $self = shift;
    my $result = shift;
        
    if (scalar keys %$result == 0)
    {   
        $self->errmsg('route information not found');
        $self->status(_ST_MAJOR);
        return;
    }       
            
    my $ipRoute = $self->ipRoute;

    my $key;
    my $index;
        
    for (keys %$result)
    {   
        $key = $_;
            
        if (/^$OID\./)
        {
            s/^$OID\.//g;
            $index = (split /\./, $_)[0];
            if ( $_ipRoute->{$index} eq 'ipRouteProto' )
            {
                $ipRoute->{ $_ipRoute->{$index} } = defined $_ipRouteProto->{ $result->{$key} } 
                     ? $_ipRouteProto->{ $result->{$key} }
                     : $result->{$key};
            }
            elsif ( $_ipRoute->{$index} eq 'ipRouteType' )
            {
                $ipRoute->{ $_ipRoute->{$index} } = defined $_ipRouteType->{ $result->{$key} } 
                     ? $_ipRouteType->{ $result->{$key} }
                     : $result->{$key};
            }
            else
            {
                $ipRoute->{ $_ipRoute->{$index} } = $result->{$key};
            }
        }
    }
}

sub log_snmp_error
{
    my $self = shift;
    if ($_[0])
    {
        log_debug($_[0], _LOG_WARNING)
            if $LogEnabled;
        return 1;
    }
    return 0;
}

sub discover_mode
{
    return _DM_NODISCOVER;
}

sub discover
{
    log_debug('configuration error! this probe does not support discover', _LOG_WARNING)
        if $LogEnabled;
    return;
}

sub save_data
{       
    my $self = shift;

    my $id_entity = shift;
    
    my $data_dir = $DataDir;

    my $h; 

    open F, ">$data_dir/$id_entity";

    $h = $self->ipRoute;
    for ( map { "$_\|$h->{$_}\n" } keys %$h )
    {       
        print F $_;
    }   

    close F;
}  

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;


    my $tracks = [ 'ipRouteNextHop', 'ipRouteMask', 'ipRouteType', 'ipRouteProto', 'ipRouteAge', 'ipRouteInfo', ];
    my $t;

    for (@$tracks)
    {   
        $t = $_;
        $t =~ s/^ipRoute//g;
        $t =~ s/(\p{upper})/ $1/g;
        $table->addRow(lc("$t:"), $data->{$_})
            if $data->{$_};
    }
}   

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;

    my $result = sprintf(qq|%s%s|,
        $entity->name,
        $entity->status_weight == 0
            ? '*'
            : '');

    return $result;
}

sub snmp
{
    return 1;
}

1;
