package Probe::dns_server;

use vars qw($VERSION);

$VERSION = 0.2;

use base qw(Probe);
use strict;

use Time::HiRes qw( gettimeofday tv_interval );
use Net::DNS::Resolver;

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use URLRewriter;

our $DataDir = CFG->{Probe}->{DataDir};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};
our $DiscoverHostNameDefault = CFG->{Probes}->{dns_server}->{DiscoverHostNameDefault};
our $ThresholdMediumDefault = CFG->{Probes}->{dns_server}->{ThresholdMediumDefault};
our $ThresholdHighDefault = CFG->{Probes}->{dns_server}->{ThresholdHighDefault};
our $DefaultTimeout = CFG->{Probes}->{dns_server}->{DefaultTimeout};

sub id_probe_type
{
    return 13;
}

sub name
{
    return 'DNS server';
}

use constant
{
    DATA => 11,
    ENTITY => 14,
};

sub snmp
{
    return 0;
}

sub clear_data
{
    my $self = shift;
    $self->[DATA] = {};
    $self->[ENTITY] = undef;
};

sub data
{
    return $_[0]->[DATA];
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

    my $id_entity = $entity->id_entity;

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter(sprintf( qq|ip in entity %s|, $id_entity))
        unless $ip;

    my $timeout = $entity->params('timeout');
    $timeout = $DefaultTimeout
        unless defined $timeout;

    $self->threshold_high($entity->params('threshold_high') || $ThresholdHighDefault);

    $self->threshold_medium($entity->params('threshold_medium') || $ThresholdMediumDefault);

    my $dns_hostname = $entity->params('dns_server_hostname') || $DiscoverHostNameDefault;

    my $res = new Net::DNS::Resolver;
    $res->udp_timeout($timeout);
    $res->nameservers($ip);
    
    my $t0 = [gettimeofday];

    my $query = $res->query($dns_hostname);
#use Data::Dumper; print Dumper $query;
    $t0 = tv_interval($t0, [gettimeofday]);
    $self->data->{answer_time} = $t0;

    my $error = $res->errorstring;

    if ($error ne 'NOERROR' && $error ne 'NXDOMAIN')
    {   
        $self->errmsg('name server error: ' . $error);
        $self->status(_ST_DOWN);
    }
    else
    {
        if ($t0 >= $self->threshold_high)
        {   
            $self->errmsg(qq|very slow name server answer|);
            $self->status(_ST_MINOR);
        }        
        elsif ($t0 >= $self->threshold_medium)
        {   
            $self->errmsg(qq|slow name server answer|);
            $self->status(_ST_WARNING);
        }        
    }

    if ($self->status < _ST_DOWN)
    {
        $self->rrd_save($id_entity, $self->status);
        $self->save_data($id_entity);
    }
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

    my $res = new Net::DNS::Resolver;
    $res->udp_timeout(1);
    $res->nameservers($ip);

    my $query = $res->query($DiscoverHostNameDefault);
    my $error = $res->errorstring;

    if ($error eq 'NOERROR' || $error eq 'NXDOMAIN')
    {
        my $old = $self->_discover_get_existing_entities($entity);
        
        if (! defined $old)
        {   
            $self->_discover_add_new_entity($entity, 'dns server');
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

    my $entity_def = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       };

    my $entity = $self->_entity_add($entity_def, $self->dbh);

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

    $h = $self->data;
    print F "answer_time\|$h->{answer_time}\n"
        if defined $h->{answer_time};

    close F;
}  

sub rrd_result
{
    my $data = $_[0]->data;

    return
    {   
        'answer_time' => defined $data->{answer_time} ? $data->{answer_time} : 'U',
    };
}

sub rrd_config
{
    return
    {   
        'answer_time' => 'GAUGE',
    };
}

sub desc_brief
{   
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    if (defined $data->{answer_time})
    {   
        push @$result, sprintf(qq|answer time: %s sec|, $data->{answer_time});
    }  
    else
    {   
        push @$result, qq|answer time: n/a|;
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

    $table->addRow('answer time:', $data->{answer_time});
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

    my $cgi = CGI->new();
        
    my $url;
    $url_params->{probe} = 'dns_server';
    
    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'answer_time';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}           
    
sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    $rrd_graph->unit('sec');
    $rrd_graph->title('server answer time');
}


1;
