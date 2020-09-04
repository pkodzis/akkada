package Probe::dns_query;

#
# nazwa pola i oczekiwana wartosc => man Net::DNS::RR::_Typ_rekordu_
#

use vars qw($VERSION);

$VERSION = 0.2;

use base qw(Probe);
use strict;

use Net::DNS::Resolver;
use Time::HiRes qw( gettimeofday tv_interval );

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use URLRewriter;

our $DataDir = CFG->{Probe}->{DataDir};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};
our $ThresholdMediumDefault = CFG->{Probes}->{dns_query}->{ThresholdMediumDefault};
our $ThresholdHighDefault = CFG->{Probes}->{dns_query}->{ThresholdHighDefault};
our $DefaultTimeout = CFG->{Probes}->{dns_query}->{DefaultTimeout};

sub id_probe_type
{
    return 14;
}

sub name
{
    return 'DNS query';
}

sub snmp
{
    return 0;
}

use constant
{
    DATA => 11,
    ENTITY => 14,
};

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

sub mandatory_fields
{
    return
    [
        'dns_query_query',
        'dns_query_record_type',
        'dns_query_expected_value',
        'dns_query_field',
    ]
}

sub manual
{
    return 1;
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

    my $dns_hostname = $entity->params('dns_query_query');
    throw EEntityMissingParameter(sprintf( qq|ip in entity %s|, $id_entity))
        unless $ip;

    my $dns_record_type = uc($entity->params('dns_query_record_type') || 'a');
    my $dns_field = lc($entity->params('dns_query_field') || '');
    my $dns_exp = lc($entity->params('dns_query_expected_value') || '');

    throw EEntityMissingParameter(sprintf( qq|unknown DNS record type %s|, $dns_record_type))
        unless defined $Net::DNS::typesbyname{$dns_record_type};
 
    my $timeout = $entity->params('timeout');
    $timeout = $DefaultTimeout
        unless defined $timeout;

    $self->threshold_high($entity->params('threshold_high') || $ThresholdMediumDefault);

    $self->threshold_medium($entity->params('threshold_medium') || $ThresholdHighDefault);

    my $res = new Net::DNS::Resolver;
    $res->udp_timeout($timeout);
    $res->nameservers($ip);
    
    my $t0 = [gettimeofday];

    my $query = $res->query($dns_hostname, $dns_record_type);

    $t0 = tv_interval($t0, [gettimeofday]);
    $self->data->{answer_time} = $t0;

    my $error = $res->errorstring;

#use Data::Dumper; die Dumper $query, $error, $dns_hostname, $dns_record_type;

    if ($error ne 'NOERROR')
    {   
        $self->errmsg('name server error: ' . $error);
        $self->status(_ST_DOWN);
        $self->save_data($id_entity);
        return;
    }

    if ($dns_field && $dns_exp)
    {
        my $ok = 0;
        for my $rr ($query->answer)
        {
            next 
                unless $rr->type eq $dns_record_type;
#use Data::Dumper; print Dumper $rr;
            if ( $dns_exp eq $rr->$dns_field )
            {
                ++$ok;
                last;
            }
        }
        if (! $ok)
        {
            $self->errmsg(sprintf(qq|missing expected value %s of field %s|, $dns_exp, $dns_field));
            $self->status(_ST_MINOR);
        }        
    }

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

    $self->rrd_save($id_entity, $self->status);
    $self->save_data($id_entity);
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
    $url_params->{probe} = 'dns_query';
    
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
