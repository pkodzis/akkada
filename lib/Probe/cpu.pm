package Probe::cpu;

our $VERSION = 0.22;

use base qw(Probe);
use strict;

use Net::SNMP;

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use URLRewriter;

use Probe::cpu::hp_switch;
use Probe::cpu::cisco;
use Probe::cpu::ucd;
use Probe::cpu::host_resources;
use Probe::cpu::altiga;

our $DataDir = CFG->{Probe}->{DataDir};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};

$Number::Format::DECIMAL_FILL = 1;

sub id_probe_type
{
    return 5;
}

sub name
{
    return 'CPU';
}


use constant
{
    _TYPE_HP_SWITCH => 'hp_switch',
    _TYPE_CISCO => 'cisco',
    _TYPE_UCD => 'ucd',
    _TYPE_HOST_RESOURCES => 'host_resources',
    _TYPE_ALTIGA => 'altiga',
};

use constant
{
    CPU => 11,
    LA => 12,
    SESSION => 13,
    ENTITY => 14,
    CPU_TYPE => 15,
    CPU_COUNT => 16,
};

my $O_CISCO_CPU = '1.3.6.1.4.1.9.9.109.1.1.1.1'; # 1 - 3, gauge
my $O_UCD_CPU = '1.3.6.1.4.1.2021.11'; # 50-53, counter
my $O_HOST_RESOURCES_CPU = '1.3.6.1.2.1.25.3.3.1.2'; # walk, gauge
my $O_HP_SWITCH_CPU = '1.3.6.1.4.1.11.2.14.11.5.1.9.6.1'; # gauge
my $O_ALTIGA = '1.3.6.1.4.1.3076.2.1.2.25'; # gauge

sub clear_data
{
    my $self = shift;
    $self->[CPU] = {};
    $self->[CPU_TYPE] = undef;
    $self->[CPU_COUNT] = undef;
    $self->[ENTITY] = undef;
    $self->[LA] = {};
};


sub la
{   
    return $_[0]->[LA];
}

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->[SESSION] = undef;

    return $self;
}

sub cpu
{
    return $_[0]->[CPU];
}

sub cpu_type
{
    my $self = shift;
    $self->[CPU_TYPE] = shift
        if @_;
    return $self->[CPU_TYPE];
}  

sub cpu_count
{
    my $self = shift;
    $self->[CPU_COUNT] = shift
        if @_;
    return $self->[CPU_COUNT];
}  

sub session
{
    my $self = shift;
    $self->[SESSION] = shift
        if @_;
    return $self->[SESSION];
}

sub rrd_load_data
{
    my $self = shift;
    my $table = shift;
    my $entity = shift;
    my $url_params = shift;

    my $cpu_type = $entity->params('cpu_type');

    bless $self, "Probe::cpu::$cpu_type";
    $self->rrd_load_data($table, $entity, $url_params);
    bless $self, "Probe::cpu";
}

sub entity
{
    my $self = shift;
    $self->[ENTITY] = shift
        if @_;
    return $self->[ENTITY];
}

sub discover_mandatory_parameters
{
    my $self = shift;
    my $mp = $self->SUPER::discover_mandatory_parameters();

    push @$mp, ['snmp_community_ro', 'snmp_user'];

    return $mp;
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

    my $cpu_type = $entity->params('cpu_type');
    $self->cpu_type( $cpu_type );

    $self->threshold_high($entity->params('threshold_high'));

    $self->threshold_medium($entity->params('threshold_medium'));

    my ($session, $error) = snmp_session($ip, $entity);

    bless $self, "Probe::cpu::$cpu_type";

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

    bless $self, "Probe::cpu";

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

sub discover_cisco
{
    my $self = shift;
    my $session = $self->session;
    
    my $cpu_type = $session->get_table(-baseoid => $O_CISCO_CPU );

    return undef
        if $self->log_snmp_error( $session->error() );

    for (keys %$cpu_type)
    {  
       delete $cpu_type->{$_}
           unless $cpu_type->{$_} ne '';
    }

    return keys %$cpu_type
        ? _TYPE_CISCO
        : undef;
}


sub discover_hp_switch
{
    my $self = shift;
    my $session = $self->session;

    my $cpu_type = $session->get_table(-baseoid => $O_HP_SWITCH_CPU );

    return undef
        if $self->log_snmp_error( $session->error() );

    for (keys %$cpu_type)
    {  
       delete $cpu_type->{$_}
           unless $cpu_type->{$_} ne '';
    }

    return keys %$cpu_type
        ? _TYPE_HP_SWITCH
        : undef;
}

sub discover_altiga
{
    my $self = shift;
    my $session = $self->session;

    my $cpu_type = $session->get_table(-baseoid => $O_ALTIGA);

    return undef
        if $self->log_snmp_error( $session->error() );

    for (keys %$cpu_type)
    {  
       delete $cpu_type->{$_}
           unless $cpu_type->{$_} ne '';
    }

    return keys %$cpu_type
        ? _TYPE_ALTIGA
        : undef;
}

sub discover_ucd
{
    my $self = shift;
    my $session = $self->session;

    my $cpu_type = $session->get_table(-baseoid => $O_UCD_CPU );

    return undef
        if $self->log_snmp_error( $session->error() );

    for (keys %$cpu_type)
    {  
       delete $cpu_type->{$_}
           unless $cpu_type->{$_} ne '';
    }

    return keys %$cpu_type
        ? _TYPE_UCD
        : undef;
}

sub discover_host_resources
{
    my $self = shift;
    my $session = $self->session;

    my $cpu_type = $session->get_table(-baseoid => $O_HOST_RESOURCES_CPU);

    return undef
        if $self->log_snmp_error( $session->error() );

    for (keys %$cpu_type)
    {  
       delete $cpu_type->{$_}
           unless $cpu_type->{$_} ne '';
    }

    return keys %$cpu_type
        ? (_TYPE_HOST_RESOURCES, scalar keys %$cpu_type)
        : (undef, undef);
}

sub _discover_get_existing_entities
{
    my $self = shift;
    my @list = $self->SUPER::_discover_get_existing_entities(@_);
    return @list
        ? Entity->new($self->dbh, $list[0])
        : undef;
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

    my $old = $self->_discover_get_existing_entities($entity);

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error)
    {
        $session->max_msg_size(2944);
        $self->session( $session );

        my $cpu_type = undef;
        my $cpu_count = '';

        $cpu_type = $self->discover_hp_switch()
            unless defined $cpu_type;
	$cpu_type = $self->discover_cisco()
            unless defined $cpu_type;
        $cpu_type = $self->discover_ucd()
            unless defined $cpu_type;
        $cpu_type = $self->discover_altiga()
            unless defined $cpu_type;
        ($cpu_type, $cpu_count) = $self->discover_host_resources()
            unless defined $cpu_type;

        $session->close
            if $session;
 
        if (defined $old)
        {
            $old->params('cpu_type', $cpu_type)
                if defined $cpu_type;
            $old->params('cpu_count', $cpu_count)
                if defined $cpu_type && $cpu_type eq _TYPE_HOST_RESOURCES && defined $cpu_count;
        }
        else
        {
            $self->_discover_add_new_entity($entity, 'cpu', $cpu_type, $cpu_count)
                if defined $cpu_type;
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
    my ($self, $parent, $name, $cpu_type, $cpu_count) = @_;

    $cpu_count = ''
        unless $cpu_count;
    log_debug(sprintf(qq|adding new entity: id_parent: %s %s cpu_type: %s; cpu_count: %s|, $parent->id_entity, $name, $cpu_type, $cpu_count), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {
           cpu_type => $cpu_type,
       }};
    $entity->{params}->{cpu_count} = $cpu_count
        if $cpu_count;

    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {       
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s cpu_type: %s; cpu_count: %s|,
            $parent->id_entity, $entity->id_entity, $name, $cpu_type, $cpu_count), _LOG_INFO)
            if $LogEnabled;
    }                   
}

sub save_data
{
    my ($self, $table, $entity) = @_;

    my $cpu_type = $entity->params('cpu_type');

    bless $self, "Probe::cpu::$cpu_type";
    $self->save_data($table, $entity);
    bless $self, "Probe::cpu";
}

sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $cpu_type = $entity->params('cpu_type');

    bless $self, "Probe::cpu::$cpu_type";
    $self->desc_brief($entity, $result);
    bless $self, "Probe::cpu";

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $cpu_type = $entity->params('cpu_type');

    bless $self, "Probe::cpu::$cpu_type";
    $self->desc_full_rows($table, $entity);
    bless $self, "Probe::cpu";

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

    my $cpu_type = $entity->params('cpu_type');

    bless $self, "Probe::cpu::$cpu_type";
    $self->stat($table, $entity, $url_params, CGI->new(), $default_only);
    bless $self, "Probe::cpu";

}

sub prepare_ds_pre
{   
    my $self = shift;
    my $rrd_graph = shift;
    my $cpu_type = $rrd_graph->entity->params('cpu_type');

    bless $self, "Probe::cpu::$cpu_type";
    $self->prepare_ds_pre($rrd_graph);
    bless $self, "Probe::cpu";
}

sub prepare_ds_adv_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cpu_type = $rrd_graph->entity->params('cpu_type');

    bless $self, "Probe::cpu::$cpu_type";
    $self->prepare_ds_adv_pre($rrd_graph);
    bless $self, "Probe::cpu";
}

sub prepare_ds_adv
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $cpu_type = $rrd_graph->entity->params('cpu_type');

    my ($up, $down, $df);

    bless $self, "Probe::cpu::$cpu_type";
    ($up, $down, $df) = $self->prepare_ds_adv($rrd_graph, $cf);
    bless $self, "Probe::cpu";
    return ($up, $down, $df);
}

sub popup_items
{
    my $self = shift;

    $self->SUPER::popup_items(@_);

    my $buttons = $_[0]->{buttons};
    my $class = $_[0]->{class};
    my $section = $_[0]->{section};
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "stop raise utilization alarms", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=cpu_stop_warning_high_utilization&add_value=1&id_entity=','current','$class');",});
}

sub snmp
{
    return 1;
}

1;
