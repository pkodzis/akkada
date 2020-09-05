package Probe::host_resources_system;

use vars qw($VERSION);

$VERSION = 0.17;

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
    return 19;
}

sub name
{
    return 'system statistics';
}


use constant
{
    DATA => 11,
    SESSION => 13,
    ENTITY => 14,
};

our $OID = '1.3.6.1.2.1.25.1';

my $_entry =
{
    2 => 'hrSystemDate',
    5 => 'hrSystemNumUsers',
    6 => 'hrSystemProcesses',
    7 => 'hrSystemMaxProcesses',
};

sub oids_build
{   
    my $self = shift;

    my @oids = ();

    for (keys %$_entry)
    {   
        push @oids, "$OID.$_.0";
    }

    return \@oids;
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

    $self->threshold_high($entity->params('threshold_high'));

    $self->threshold_medium($entity->params('threshold_medium'));

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error)
    {
        $session->max_msg_size(2944);
        $self->session( $session );

        my $result = $session->get_request( -varbindlist => $self->oids_build() );

        my $error = $session->error();
        if (! $error )
        {
            $self->result_dispatch($result);
            $self->utilization_status;
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

    if ($self->status < _ST_DOWN)
    {
        $self->rrd_save($id_entity, $self->status);
        $self->save_data($id_entity);
    }

    $session->close
        if $session;
}

sub result_dispatch
{
    my $self = shift;
    my $result = shift;

    if (scalar keys %$result == 0)
    {
        $self->errmsg('data information not found');
        $self->status(_ST_MAJOR);
        return;
    }

    my $data = $self->data;

    my $key;
    my $index;
    my @d;

    for (keys %$result)
    {
        $key = $_;

        if (/^$OID\./)
        {
            s/^$OID\.//g;
            $index = (split /\./, $_)[0];
            $data->{ $_entry->{$index} } = $result->{$key};
            if ($_entry->{$index} eq 'hrSystemDate')
            {
=pod
#log_debug("X1: " .  $result->{$key}, _LOG_ERROR);
                $result->{$key} = unpack( "H*", $result->{$key});
#log_debug("X2: " .  $result->{$key}, _LOG_ERROR);
                $result->{$key} =  pack( "H*", scalar $result->{$key});
#log_debug("X3: " .  $result->{$key}, _LOG_ERROR);
                @d = unpack "H4C*", $result->{$key};
#log_debug("X3: " .  join(":", @d), _LOG_ERROR);
=cut
#use Data::Dumper; log_debug(Dumper( $result->{$key}, _LOG_ERROR));

#                $result->{$key} = unpack( "H*", $result->{$key});

#use Data::Dumper; log_debug(Dumper( $result->{$key}, _LOG_ERROR));

#                $result->{$key} =  pack( "H*", scalar $result->{$key});

#use Data::Dumper; log_debug(Dumper( $result->{$key}, _LOG_ERROR));

#                @d = unpack "H4C*", $result->{$key};

#use Data::Dumper; log_debug(Dumper( \@d, _LOG_ERROR));

#                $data->{ $_entry->{$index} } = sprintf(qq|%s-%s-%s %s:%s:%s|, hex $d[0], $d[1], $d[2], $d[3], $d[4], $d[5]);
#                $data->{ $_entry->{$index} } .= sprintf(qq| %s%s:%s|, $d[7] == 43 ? '+' : '-', $d[8], $d[9])
#                    if (@d > 7);
                $data->{ $_entry->{$index} } = snmp_DateAndTime_2_str($result->{$key});
            }
        }
    }
    $data->{hrSystemProcesses} = 'U'
        if $data->{hrSystemProcesses} eq '' || $data->{hrSystemProcesses} =~ /\D/;
    $data->{hrSystemMaxProcesses} = 'U'
        if $data->{hrSystemMaxProcesses} eq '' || $data->{hrSystemMaxProcesses} =~ /\D/;
}

sub utilization_status
{  
    my $self = shift;
    my $data = $self->data;
    my $entity = $self->entity;

    my $host_resources_system_processes_max = $entity->params('host_resources_system_processes_max') || 0;

    if (defined $data->{hrSystemProcesses} && $data->{hrSystemProcesses} !~ /\D/)
    {
        if ($host_resources_system_processes_max && $data->{hrSystemProcesses} > $host_resources_system_processes_max)
        {
            $self->errmsg(qq|too many processes|);
            $self->status(_ST_DOWN);
        }

        if (defined $data->{hrSystemMaxProcesses} && $data->{hrSystemMaxProcesses} && $data->{hrSystemMaxProcesses} !~ /\D/)
        {
            my $p = ($data->{hrSystemProcesses}*100)/$data->{hrSystemMaxProcesses};
            if ($p > $self->threshold_high)
            {
                $self->errmsg(qq|processes count threshold high exceded|);
                $self->status(_ST_MAJOR);
            }
            elsif ($p > $self->threshold_medium)
            {
                $self->errmsg(qq|processes count threshold medium exceded|);
                $self->status(_ST_MINOR);
            }
        }
    }
}

sub rrd_config
{   
    return
    {
        'hrSystemProcesses' => 'GAUGE',
        'hrSystemNumUsers' => 'GAUGE',
    };
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
        $self->session( $session );

        my $new = $session->get_table(-baseoid => $OID);

        return 
            if $self->log_snmp_error( $session->error() );

        return 
            unless keys %$new;

        $session->close
            if $session;

        if (defined $new)
        {
            $self->_discover_add_new_entity($entity)
                unless $self->_discover_get_existing_entities($entity);
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
    my ($self, $parent) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s system|, $parent->id_entity), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => 'system',
       };

    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {       
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s system|,
            $parent->id_entity, $entity->id_entity), _LOG_INFO)
            if $LogEnabled;
    }                   
}

sub save_data
{       
    my $self = shift;

    my $id_entity = shift;
    
    my $data_dir = $DataDir;

    my $h; 

    open F, ">$data_dir/$id_entity";

    $h = $self->data;
    for ( map { "$_\|$h->{$_}\n" } keys %$h )
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
    
    if (defined $data->{hrSystemProcesses})
    {
        push @$result, sprintf(qq|processes: %s/%s|, $data->{hrSystemProcesses}, $data->{hrSystemMaxProcesses});
    }
    else
    {
        push @$result, qq|processes: n/a|;
    }

    if (defined $data->{hrSystemNumUsers})
    {
        push @$result, sprintf(qq|users: %s|, $data->{hrSystemNumUsers});
    }
    else
    {
        push @$result, qq|users: n/a|;
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

    $table->addRow("users count:", $data->{'hrSystemNumUsers'} eq 'U' ? 'n/a' : $data->{'hrSystemNumUsers'});
    $table->addRow("processes count:", $data->{'hrSystemProcesses'} eq 'U' ? 'n/a' : $data->{'hrSystemProcesses'});
    $table->addRow("processes max count:", $data->{'hrSystemMaxProcesses'} eq 'U' ? 'n/a' : $data->{'hrSystemMaxProcesses'});
    $table->addRow("system date:", defined $data->{'hrSystemDate'} ? $data->{'hrSystemDate'} : 'n/a');
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

sub rrd_load_data
{
    return ($_[0]->rrd_config, $_[0]->data);
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

    my $cgi = CGI->new();
        
    my $url;
    $url_params->{probe} = 'host_resources_system';
    
    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'hrSystemProcesses';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    
    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'hrSystemNumUsers';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    
}           
    
sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $url_params = $rrd_graph->url_params;
    $rrd_graph->unit('no.');
    if ( $url_params->{probe_specific} eq 'hrSystemProcesses' )
    {
        $rrd_graph->title('processes count');
    }
    elsif ( $url_params->{probe_specific} eq 'hrSystemNumUsers' )
    {
        $rrd_graph->title('users count');
    }
}

sub snmp
{
    return 1;
}

1;
