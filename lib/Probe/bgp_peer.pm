package Probe::bgp_peer;

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
    return 23;
}

use constant
{
    DATA => 11,
    SESSION => 13,
    ENTITY => 14,
};

our $OID = '1.3.6.1.2.1.15.3.1';

my $_bgpPeer =
{
    1 => 'bgpPeerIdentifier',
    2 => 'bgpPeerState',
    3 => 'bgpPeerAdminStatus',
    4 => 'bgpPeerNegVer',
    5 => 'bgpPeerLocalAddr',
    6 => 'bgpPeerLocalPort',
    7 => 'bgpPeerRemoteAddr',
    8 => 'bgpPeerRemotePort',
    9 => 'bgpPeerRemoteAs',
    10 => 'bgpPeerInUpdates',
    11 => 'bgpPeerOutUpdates',
    12 => 'bgpPeerInTotalM',
    13 => 'bgpPeerOutTotalM',
    14 => 'bgpPeerLastError',
};

my $_bgpPeerState = 
{
    1 => 'idle',
    2 => 'connect',
    3 => 'active',
    4 => 'opensent',
    5 => 'openconfirm',
    6 => 'established',
};

sub name
{
    return 'BGP peer';
}

sub rrd_result
{       
    my $self = shift;
    my $data = $self->data;
    return
    {
        'bgpPeerInUpdates' => defined $data->{bgpPeerInUpdates} ? $data->{bgpPeerInUpdates} : 'U',
        'bgpPeerOutUpdates' => defined $data->{bgpPeerOutUpdates} ? $data->{bgpPeerOutUpdates} : 'U',
        'bgpPeerInTotalM' => defined $data->{bgpPeerInTotalM} ? $data->{bgpPeerInTotalM} : 'U',
        'bgpPeerOutTotalM' => defined $data->{bgpPeerOutTotalM} ? $data->{bgpPeerOutTotalM} : 'U',
    }; 
}   
    
sub rrd_config
{
    return
    {
        'bgpPeerInUpdates' => 'COUNTER',
        'bgpPeerOutUpdates' => 'COUNTER',
        'bgpPeerInTotalM' => 'COUNTER',
        'bgpPeerOutTotalM' => 'COUNTER',
    };
}       

sub cache_keys
{
    return
    [
        keys %{ $_[0]->rrd_config }
    ];
}

sub clear_data
{
    my $self = shift;
    $self->[DATA] = {};
    $self->[ENTITY] = undef;
};

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->[SESSION] = undef;

    return $self;
}

sub data
{
    return $_[0]->[DATA];
}

sub session
{
    my $self = shift;
    $self->[SESSION] = shift
        if @_;
    return $self->[SESSION];
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
            $self->cache_update($id_entity, $self->data);
            $self->cache_string($id_entity, 'bgpPeerLastError', $self->data->{bgpPeerLastError});
            $self->utilization_status();
#use Data::Dumper; log_debug($id_entity . ": " . Dumper($self->data), _LOG_ERROR);
        }  
        else
        {   
            $self->errmsg('snmp error: ' . $error);
            $self->status(_ST_MAJOR);
        }
        $self->rrd_save($id_entity, $self->status);
    }
    else
    {
        $self->errmsg($error);
        $self->status(_ST_MAJOR);
    }

#use Data::Dumper; print Dumper $self->data, $self->errmsg, $self->status; exit;
    $self->save_data($id_entity);

    $session->close
        if $session;
}


sub utilization_status
{ 
    my $self = shift;
    my $bgp = $self->data;
    my $entity = $self->entity;

    my $bgp_peer_state_ignore = $entity->params('bgp_peer_state_ignore');
    my $bgp_peer_errors_ignore = $entity->params('bgp_peer_errors_ignore');

    if ( defined $bgp && $bgp->{bgpPeerState} eq '')
    {
        $self->errmsg(qq|unknown BGP peer|);
        $self->status(_ST_DOWN);
    }
    elsif ( defined $bgp && $bgp->{bgpPeerState} ne 'established' && ! $bgp_peer_state_ignore)
    {
        $self->errmsg(sprintf(qq|BGP session down; current state: %s|, $bgp->{bgpPeerState}));
        $self->status(_ST_DOWN);
    }
    elsif ( defined $bgp && $bgp->{bgpPeerLastError} ne  '' && ! $bgp_peer_errors_ignore)
    {
#use Data::Dumper; log_debug(Dumper($self->cache('strings')),_LOG_ERROR);
        if ($self->cache_string($entity->id_entity, 'bgpPeerLastError')->[0])
        {
            $self->errmsg("an error has occurred");
            $self->status(_ST_MINOR);
        }
    }
}


sub oids_build
{  
    my $self = shift;
    my $index = shift;

    my @oids = ();

    for (keys %$_bgpPeer)
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
        $self->errmsg('bgp peer information not found');
        $self->status(_ST_MAJOR);
        return;
    }       
            
    my $bgp = $self->data;

    my $key;
    my $index;
        
    for (keys %$result)
    {   
        $key = $_;
            
        if (/^$OID\./)
        {
            s/^$OID\.//g;
            $index = (split /\./, $_)[0];
            if ( $_bgpPeer->{$index} eq 'bgpPeerState' )
            {
                $bgp->{ $_bgpPeer->{$index} } = defined $_bgpPeerState->{ $result->{$key} } 
                     ? $_bgpPeerState->{ $result->{$key} }
                     : $result->{$key};
            }
            else
            {
                $bgp->{ $_bgpPeer->{$index} } = $result->{$key};
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
            s/^$oid\.//;
            $new->{ $_ } = $st;
        }

        return
            unless $new;

        my $old = $self->_discover_get_existing_entities($entity);

        for my $name (keys %$old)
        {
            next
                unless defined $new->{$name};

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
            $self->_discover_add_new_entity($entity, $_);
            delete $new->{$_};
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
    my ($self, $parent, $name) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s|, $parent->id_entity, $name), _LOG_DEBUG)
        if $LogEnabled;

    $name =~ s/\000$//;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
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
    };
    return $result;
}

sub save_data
{       
    my $self = shift;

    my $id_entity = shift;
    
    my $data_dir = $DataDir;

    open F, ">$data_dir/$id_entity";

    my $h = $self->data;
    my $ch = $self->cache->{$id_entity};
    my $chk = $self->rrd_config;

    for ( map { defined $chk->{$_} ? ( defined $ch->{$_}->[1] ? "$_\|$ch->{$_}->[1]\n" : "$_\|U\n" ) : "$_\|$h->{$_}\n" } keys %$h )
    {
        print F $_;
    }
    
    close F;
}  

sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    push @$result, sprintf(qq|remote AS: %s|, $data->{bgpPeerRemoteAs})
        if defined $data->{bgpPeerRemoteAs};
    push @$result, sprintf(qq|bgp state: %s|, $data->{bgpPeerState})
        if defined $data->{bgpPeerRemoteAs};
            
    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    $table->addRow("remote AS:", sprintf(qq|<b>%s</b>|,$data->{bgpPeerRemoteAs}))
        if $data->{bgpPeerRemoteAs};
    $table->addRow("session status:", sprintf(qq|<span class="%s">%s</span>|,
        $data->{bgpPeerState} eq 'established' ? 'g8' : 'g9', $data->{bgpPeerState}))
        if $data->{bgpPeerState};

    my $tracks = 
    [ 
        #['bgpPeerLastError', 'last error'],
        ['bgpPeerRemoteAddr','remote address'],
        ['bgpPeerRemotePort','remote port'],
        ['bgpPeerLocalAddr','local address'],
        ['bgpPeerLocalPort','local port'],
        ['bgpPeerIdentifier','local identifier'],
        ['bgpPeerAdminStatus','administration status'],
        ['bgpPeerNegVer', 'negotiated version'],
    ];

    my $t;

    for (@$tracks)
    {   
        $t = $_->[1];
        $table->addRow(lc("$t:"), $data->{$_->[0]})
            if $data->{$_->[0]};
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

    my $stats =
    {
       'bgpPeerInTotalM' => 1,
       'bgpPeerOutTotalM' => 1,
       'bgpPeerInUpdates'=> 0,
       'bgpPeerOutUpdates' => 0,
    };

    my $url;
    $url_params->{probe} = 'bgp_peer';
    $url_params->{probe_prepare_ds} = 'prepare_ds';

    for (keys %$stats)
    { 
        next
            if $default_only && ! $stats->{$_};
        $url_params->{probe_specific} = $_;
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    }
}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $url_params = $rrd_graph->url_params;
    $rrd_graph->unit('no.');

    my $stats =
    {
       'bgpPeerInTotalM' => 'input messages',
       'bgpPeerOutTotalM' => 'output messages',
       'bgpPeerInUpdates'=> 'input updates',
       'bgpPeerOutUpdates' => 'output updates',
    };

    $rrd_graph->title( $stats->{ $url_params->{probe_specific} });
}

sub snmp
{
    return 1;
}

1;
