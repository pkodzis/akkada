package Probe::ram;

use vars qw($VERSION);

$VERSION = 0.12;

use base qw(Probe);
use strict;

use Net::SNMP;

use Probe::ram::ucd;
use Probe::ram::cisco;
use Probe::ram::hp_switch;
use Probe::ram::arrowpoint_old_mib;

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
    return 7;
}

sub name
{
    return 'RAM';
}

use constant
{
    _TYPE_UCD => 'ucd',
    _TYPE_CISCO => 'cisco',
    _TYPE_HP_SWITCH => 'hp_switch',
    _TYPE_ARROWPOINT_OLD_MIB => 'arrowpoint_old_mib',
};

use constant
{
    RAM => 11,
    SESSION => 13,
    ENTITY => 14,
    RAM_TYPE => 15,
};

our $O_UCD_RAM = '1.3.6.1.4.1.2021.4';
our $O_CISCO_RAM = '1.3.6.1.4.1.9.9.48.1.1.1.2';
our $O_HP_SWITCH_RAM = '1.3.6.1.4.1.11.2.14.11.5.1.1.2.1.1.1.5';
our $O_ARROWPOINT_OLD_MIB_RAM = '1.3.6.1.4.1.2467.1.34.17.1.4';

sub clear_data
{
    my $self = shift;
    $self->[RAM] = {};
    $self->[RAM_TYPE] = undef;
    $self->[ENTITY] = undef;
};

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->[SESSION] = undef;

    return $self;
}

sub ram
{
    return $_[0]->[RAM];
}

sub ram_type
{
    my $self = shift;
    $self->[RAM_TYPE] = shift
        if @_;
    return $self->[RAM_TYPE];
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

    my $ram_type = $entity->params('ram_type');
    $self->ram_type( $ram_type );

    $self->threshold_high($entity->params('threshold_high'));

    $self->threshold_medium($entity->params('threshold_medium'));

    my ($session, $error) = snmp_session($ip, $entity);

    bless $self, "Probe::ram::$ram_type";

    if (! $error)
    {
        $session->max_msg_size(2944);
        $self->session( $session );
        $self->entity_test();
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

    bless $self, "Probe::ram";

    $session->close
        if $session;

#print "#", $self->status, "#", join(':',@{$self->errmsg}),"#";
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

sub discover_ram
{
    my $self = shift;
    my $oid = shift;
    my $session = $self->session;

    my $ram = $session->get_table(-baseoid => $oid );

    return undef
        if $self->log_snmp_error( $session->error() );

    delete $ram->{$oid}
        if defined $ram->{$oid};

    for (keys %$ram)
    {
       delete $ram->{$_}
           unless $ram->{$_} ne '';
    }

    return undef
        unless keys %$ram;

    return { 'RAM' => 1 };
}

sub discover_ram_cisco
{   
    my $self = shift;
    my $oid = shift;
    my $session = $self->session;

    my $ram = $session->get_table(-baseoid => $oid );

    return undef
        if $self->log_snmp_error( $session->error() );

    delete $ram->{$oid}
        if defined $ram->{$oid};

    return undef
        unless keys %$ram;

    my $result = {};

    for (keys %$ram)
    {   
        next
            unless $ram->{$_} ne '';
        $result->{ $ram->{$_} } = $_;
    }

    for (keys %$result)
    {   
        $result->{$_} =~ s/^$oid\.//g;
    }

    return scalar keys %$result
        ? $result
        : undef;
}


sub discover_ram_arrowpoint
{  
    my $self = shift;
    my $oid = shift;
    my $session = $self->session;

    my $ram = $session->get_table(-baseoid => $oid );
#use Data::Dumper; print Dumper $oid, $ram;
    return undef 
        if $self->log_snmp_error( $session->error() );

    delete $ram->{$oid}
        if defined $ram->{$oid};

    return undef 
        unless keys %$ram;

    my $result = {};

    my $s;
    for (keys %$ram)
    {   
        next
            unless $ram->{$_} ne '';
        $s = $ram->{$_};
        s/^$oid\.//g;
        $result->{ $s . ':' . $_ } = $_;
    }

#use Data::Dumper; print Dumper $result;

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

            my $ram_type = $entity->params('ram_type');
            $result->{$name}->{ram_type} = $ram_type
                if defined $ram_type;
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
        my $ram_type = '';

        $new = $self->discover_ram($O_UCD_RAM)
            unless defined $new;
        $ram_type = _TYPE_UCD
            if defined $new && ! $ram_type;

        $new = $self->discover_ram_cisco($O_CISCO_RAM)
            unless defined $new;
        $ram_type = _TYPE_CISCO
            if defined $new && ! $ram_type;

        $new = $self->discover_ram($O_HP_SWITCH_RAM)
            unless defined $new;
        $ram_type = _TYPE_HP_SWITCH
            if defined $new && ! $ram_type;
#print "#";	
        $new = $self->discover_ram_arrowpoint($O_ARROWPOINT_OLD_MIB_RAM)
            unless defined $new;
        $ram_type = _TYPE_ARROWPOINT_OLD_MIB
            if defined $new && ! $ram_type;

#print "#";	
        $session->close
            if $session;

        if (defined $new && $ram_type)
        {   
            my $old = $self->_discover_get_existing_entities($entity);

            for my $name (keys %$old)
            {   
                if (defined $new->{$name})
                {   
                    $old->{$name}->{entity}->params('ram_type', $ram_type);
                    $old->{$name}->{entity}->db_update_entity;
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
                $self->_discover_add_new_entity($entity, $name, $ram_type);
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
    my ($self, $parent, $name, $ram_type) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s ram_type: %s;|, $parent->id_entity, $name, $ram_type), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {
           ram_type => $ram_type,
       }};

    $entity->{params}->{ram_disable_memory_full_alarm_real} = 1
        if $ram_type eq _TYPE_UCD;

    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {       
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s ram_type: %s;|,
            $parent->id_entity, $entity->id_entity, $name, $ram_type), _LOG_INFO)
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

    $h = $self->ram;
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

    my $ram_type = $entity->params('ram_type');

    bless $self, "Probe::ram::$ram_type";
    $self->desc_full_rows($table, $entity);
    bless $self, "Probe::ram";

}   


sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $ram_type = $entity->params('ram_type');

    bless $self, "Probe::ram::$ram_type";
    $self->desc_brief($entity, $result);
    bless $self, "Probe::ram";

    return $result;
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
    return ($_[0]->rrd_config, $_[0]->ram);
}


sub popup_items
{
    my $self = shift;
            
    $self->SUPER::popup_items(@_);
                
    my $buttons = $_[0]->{buttons};
    my $class = $_[0]->{class};
    my $section = $_[0]->{section};
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "set ram_threshold_bytes_mode", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=ram_threshold_bytes_mode&add_value=1&id_entity=','current','$class');",});
    $buttons->add({ caption => "set ram_disable_memory_full_alarm_real", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=ram_disable_memory_full_alarm_real&add_value=1&id_entity=','current','$class');",});
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

    my $ram_type = $entity->params('ram_type');

    bless $self, "Probe::ram::$ram_type";
    $self->stat($table, $entity, $url_params, $default_only);
    bless $self, "Probe::ram";

}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $ram_type = $rrd_graph->entity->params('ram_type');
    
    bless $self, "Probe::ram::$ram_type";
    $self->prepare_ds_pre($rrd_graph);
    bless $self, "Probe::ram";
}


sub prepare_ds_bytes_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $ram_type = $rrd_graph->entity->params('ram_type');

    bless $self, "Probe::ram::$ram_type";
    $self->prepare_ds_bytes_pre($rrd_graph);
    bless $self, "Probe::ram";
}

sub prepare_ds_bytes
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $ram_type = $rrd_graph->entity->params('ram_type');

    my ($up, $down, $df);

    bless $self, "Probe::ram::$ram_type";
    ($up, $down, $df) = $self->prepare_ds_bytes($rrd_graph, $cf);
    bless $self, "Probe::ram";
    return ($up, $down, $df);
}

sub snmp
{
    return 1;
}

1;
