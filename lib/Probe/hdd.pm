package Probe::hdd;

use vars qw($VERSION);

$VERSION = 0.23;

use base qw(Probe);
use strict;

use Net::SNMP;

use Probe::hdd::ucd;
use Probe::hdd::host_resources;

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
    return 6;
}

sub name
{
    return 'HDD';
}


use constant
{
    _TYPE_UCD => 'ucd',
    _TYPE_HOST_RESOURCES => 'host_resources',
};

use constant
{
    HDD => 11,
    SESSION => 13,
    ENTITY => 14,
    HDD_TYPE => 15,
};

=pod
  push @oids, ".1.3.6.1.2.1.25.2.3.1.3." . $h->{'port'};
  push @oids, ".1.3.6.1.2.1.25.2.3.1.4." . $h->{'port'}; #block size
  push @oids, ".1.3.6.1.2.1.25.2.3.1.5." . $h->{'port'}; #storageSize
  push @oids, ".1.3.6.1.2.1.25.2.3.1.6." . $h->{'port'}; #storageUsed

  $t[0] = snmpwalk($n, ".1.3.6.1.4.1.2021.9.1.1"); #idx
  if (keys %{$t[0]}) {
    $t[1] = snmpwalk($n, ".1.3.6.1.4.1.2021.9.1.2"); #desc
    $t[4] = snmpwalk($n, ".1.3.6.1.4.1.2021.9.1.9"); #used
    $t[5] = snmpwalk($n, ".1.3.6.1.4.1.2021.9.1.7"); #free byles
=cut

our $O_UCD_HDD = '1.3.6.1.4.1.2021.9.1.3';
our $O_HOST_RESOURCES_HDD = '1.3.6.1.2.1.25.2.3.1.3';

sub clear_data
{
    my $self = shift;
    $self->[HDD] = {};
    $self->[HDD_TYPE] = undef;
    $self->[ENTITY] = undef;
};

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->[SESSION] = undef;

    return $self;
}

sub hdd
{
    return $_[0]->[HDD];
}

sub hdd_type
{
    my $self = shift;
    $self->[HDD_TYPE] = shift
        if @_;
    return $self->[HDD_TYPE];
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

    my $hdd_type = $entity->params('hdd_type');
    $self->hdd_type( $hdd_type );

    $self->threshold_high($entity->params('threshold_high'));

    $self->threshold_medium($entity->params('threshold_medium'));

    my ($session, $error) = snmp_session($ip, $entity);

    bless $self, "Probe::hdd::$hdd_type";

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

    bless $self, "Probe::hdd";

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

sub discover_hdd
{
    my $self = shift;
    my $oid = shift;
    my $session = $self->session;

    my $hdd = $session->get_table(-baseoid => $oid );

    return undef
        if $self->log_snmp_error( $session->error() );

    return undef
        unless keys %$hdd;

#use Data::Dumper; log_debug(Dumper($hdd), _LOG_ERROR); exit;
    my $result = {};
    my $blade_fake = blade_fake();

    for (keys %$hdd)
    {
        next
            unless $hdd->{$_} ne '';
        next
            if $hdd->{$_} =~ /^$blade_fake/;
        $result->{ $hdd->{$_} } = $_;
    }
    #@{$result}{values %$hdd} = keys %$hdd;

#use Data::Dumper; log_debug(Dumper($oid, $result), _LOG_ERROR);
 
    my $res = {}; 
    my $value;

    for my $name (keys %$result)
    {
        $value = $result->{ $name };
	$value =~ s/^$oid\.//g;

        if ($name =~ /Label\:/ && $name =~ /Serial Number/)
        {
            $name = (split /Label/, $name)[0];
            $name =~ s/\s+$//g;
        }

        $res->{$name} = $value;
    }
#use Data::Dumper; log_debug(Dumper($res), _LOG_ERROR);

    return scalar keys %$res
        ? $res
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

            my $hdd_type = $entity->params('hdd_type');
            $result->{$name}->{hdd_type} = $hdd_type
                if defined $hdd_type;
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
        my $hdd_type = '';

        $new = $self->discover_hdd($O_UCD_HDD)
            unless defined $new;

        $hdd_type = _TYPE_UCD
            if defined $new && ! $hdd_type;

        $new = $self->discover_hdd($O_HOST_RESOURCES_HDD)
            unless defined $new;

        $hdd_type = _TYPE_HOST_RESOURCES
            if defined $new && ! $hdd_type;

        $session->close
            if $session;

        if (defined $new && $hdd_type)
        {
            my $old = $self->_discover_get_existing_entities($entity);
            
            for my $name (keys %$old)
            {
                if (defined $new->{$name})
                {
                    $old->{$name}->{entity}->params('hdd_type', $hdd_type);
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
                $self->_discover_add_new_entity($entity, $name, $hdd_type);
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
    my ($self, $parent, $name, $hdd_type) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s hdd_type: %s;|, $parent->id_entity, $name, $hdd_type), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {
           hdd_type => $hdd_type,
       }};

    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {       
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s hdd_type: %s;|,
            $parent->id_entity, $entity->id_entity, $name, $hdd_type), _LOG_INFO)
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

    $h = $self->hdd;
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

    my $hdd_type = $entity->params('hdd_type');

    return
        unless $hdd_type;

    bless $self, "Probe::hdd::$hdd_type";
    $self->desc_brief($entity, $result);
    bless $self, "Probe::hdd";

    return $result;
}


sub desc_full_rows
{
    my ($self, $table, $entity) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $hdd_type = $entity->params('hdd_type');

    return
        unless $hdd_type;

    bless $self, "Probe::hdd::$hdd_type";
    $self->desc_full_rows($table, $entity);
    bless $self, "Probe::hdd";

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
    return ($_[0]->rrd_config, $_[0]->hdd);
}


sub popup_items
{
    my $self = shift;
            
    $self->SUPER::popup_items(@_);
                
    my $buttons = $_[0]->{buttons};
    my $class = $_[0]->{class};
    my $section = $_[0]->{section};
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "set hdd_threshold_bytes_mode", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=hdd_threshold_bytes_mode&add_value=1&id_entity=','current','$class');",});
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

    my $hdd_type = $entity->params('hdd_type');

    bless $self, "Probe::hdd::$hdd_type";
    $self->stat($table, $entity, $url_params, $default_only);
    bless $self, "Probe::hdd";

}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $hdd_type = $rrd_graph->entity->params('hdd_type');
    
    bless $self, "Probe::hdd::$hdd_type";
    $self->prepare_ds_pre($rrd_graph);
    bless $self, "Probe::hdd";
}


sub prepare_ds_bytes_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $hdd_type = $rrd_graph->entity->params('hdd_type');

    bless $self, "Probe::hdd::$hdd_type";
    $self->prepare_ds_bytes_pre($rrd_graph);
    bless $self, "Probe::hdd";
}

sub prepare_ds_bytes
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $hdd_type = $rrd_graph->entity->params('hdd_type');

    my ($up, $down, $df);

    bless $self, "Probe::hdd::$hdd_type";
    ($up, $down, $df) = $self->prepare_ds_bytes($rrd_graph, $cf);
    bless $self, "Probe::hdd";
    return ($up, $down, $df);
}

sub snmp
{
    return 1;
}

1;
