package Probe::ucd_process;

use vars qw($VERSION);

$VERSION = 0.17;

use base qw(Probe);
use strict;

use Net::SNMP qw(snmp_dispatcher oid_lex_sort ticks_to_time);
use Number::Format qw(:subs);

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use Time::HiRes qw( gettimeofday tv_interval );
use URLRewriter;


our $DataDir = CFG->{Probe}->{DataDir};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};
our $MaxSNMPSplitRequest = CFG->{MaxSNMPSplitRequest};

$Number::Format::DECIMAL_FILL = 1;

sub id_probe_type
{
    return 8;
}

sub name
{
    return 'process';
}


use constant
{
    PROCESS => 11,
    SESSION => 13,
    ENTITY => 14,
};

our $OID = '1.3.6.1.4.1.2021.2.1';

my $_entry =
{
    2 => 'prNames',
    5 => 'prCount',
    101 => 'prErrMessage',
    
};

sub oids_build
{   
    my $self = shift;
    my $index = shift;

    my @oids = ();

    for (keys %$_entry)
    {   
        push @oids, "$OID.$_.$index";
    }

    return \@oids;
}

sub clear_data
{
    my $self = shift;
    $self->[PROCESS] = {};
    $self->[ENTITY] = undef;
};

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->[SESSION] = undef;

    return $self;
}

sub process
{
    return $_[0]->[PROCESS];
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

        my $index = undef;
        my $result = $self->discover_process;

        $index = $result->{ $entity->name }
            if defined $result;

        if (! defined $index)
        {
            $self->errmsg('not found');
            $self->status(_ST_MAJOR);
            return;
        }

        $result = $session->get_request( -varbindlist => $self->oids_build( $index ) );

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
        $self->rrd_save($id_entity,$self->status);
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
        $self->errmsg('process information not found');
        $self->status(_ST_MAJOR);
        return;
    }

    my $process = $self->process;

    my $key;
    my $index;

    for (keys %$result)
    {
        $key = $_;

        if (/^$OID\./)
        {
            s/^$OID\.//g;
            $index = (split /\./, $_)[0];
            $process->{ $_entry->{$index} } = $result->{$key};
        }
    }
    $process->{prCount} = 'U'
        if $process->{prCount} eq '' || $process->{prCount} =~ /\D/;
}

sub utilization_status
{  
    my $self = shift;
    my $process = $self->process;
    my $entity = $self->entity;

    my $ucd_process_min = $entity->params('ucd_process_min') || 0;
    my $ucd_process_max = $entity->params('ucd_process_max') || 0;

    if ($process->{prCount} !~ /\D/)
    {
        if ($ucd_process_min && ! $process->{prCount})
        {
            $self->errmsg(qq|no process|);
            $self->status(_ST_DOWN);
        }
        elsif ($ucd_process_min && $process->{prCount} < $ucd_process_min)
        {
            $self->errmsg(qq|too less processes|);
            $self->status(_ST_MINOR);
        }
        elsif ($ucd_process_max && $process->{prCount} > $ucd_process_max)
        {
            $self->errmsg(qq|too few processes|);
            $self->status(_ST_MINOR);
        }
    }

    if ($process->{prErrMessage})
    {
        $self->errmsg(sprintf(qq|snmp agent error message: %s|, $process->{prErrMessage}));
        $self->status(_ST_MAJOR);
    }
}

sub rrd_config
{   
    return
    {
        'prCount' => 'GAUGE',
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

sub discover_process
{
    my $self = shift;
    my $session = $self->session;

    my $process = $session->get_table(-baseoid => "$OID.2" );

    return undef
        if $self->log_snmp_error( $session->error() );

    return undef
        unless keys %$process;

    my $result = {};

    my $blade_fake = blade_fake();
    for (keys %$process)
    {
        next
            unless $process->{$_};
        next
            if $process->{$_} =~ /^$blade_fake/;
        $result->{ $process->{$_} } = $_;
    }
    for (keys %$result)
    {
        $result->{$_} =~ s/^$OID\.2\.//g;
    }

    return scalar keys %$result
        ? $result
        : undef;
}

sub _discover_get_existing_entities
{
    my $self = shift;
    my @list = $self->SUPER::_discover_get_existing_entities(@_);

    my $result;

    for (@list)
    {   

        my $entity = Entity->new($self->dbh, $_);
        if (defined $entity)
        {   

            my $name = $entity->name;

            $result->{ $name }->{entity} = $entity;
        };
    };

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
        $self->session( $session );

        my $new = undef;

        $new = $self->discover_process();

        $session->close
            if $session;

        if (defined $new)
        {
            my $old = $self->_discover_get_existing_entities($entity);
            
            for my $name (keys %$old)
            {
                if (defined $new->{$name})
                {
                    delete $new->{$name};
                }
                else
                {
                    $old->{$name}->{entity}->status(_ST_BAD_CONF);
                    $old->{$name}->{entity}->db_update_entity;
                }
            }
            for my $name (keys %$new)
            {
                $self->_discover_add_new_entity($entity, $name);
            }
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
            $parent->id_entity, $entity->id_entity, $name), _LOG_INFO)
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

    $h = $self->process;
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
    
    if (defined $data->{prCount})
    {
        push @$result, sprintf(qq|processes count: %s|, $data->{prCount});
    }
    else
    {
        push @$result, qq|processes count: n/a|;
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

    $table->addRow("processes count:",
        $data->{'prCount'} eq 'U'
            ? 'unknown'
            : $data->{'prCount'});
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
    return ($_[0]->rrd_config, $_[0]->process);
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
    $url_params->{probe} = 'ucd_process';
    
    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'prCount';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    
}           
    
sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    $rrd_graph->unit('no.');
    $rrd_graph->title('processes count');
}

sub snmp
{
    return 1;
}

1;
