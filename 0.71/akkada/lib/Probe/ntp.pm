package Probe::ntp;

use vars qw($VERSION);

$VERSION = 0.4;

use base qw(Probe);
use strict;

use Time::HiRes qw(gettimeofday tv_interval);
use IPC::Open3;
use File::Spec;
use Symbol qw(gensym);

use Constants;
use Configuration;
use Log;
use Entity;
use URLRewriter;
use Common;

use RRDGraph;

our $DataDir = CFG->{Probe}->{DataDir};
our $LogEnabled = CFG->{LogEnabled};
our $NTPQ = CFG->{Probes}->{'ntp'}->{ntpq};
our $NTPQ_PARAMS = CFG->{Probes}->{'ntp'}->{ntpq_params};

$|=1;

use constant 
{
    DATA => 10,
};

sub name
{
    return 'NTP';
}

sub id_probe_type
{
    return 25;
}

sub snmp
{
    return 0;
}

sub clear_data
{
    my $self = shift;
    $self->[DATA] = {};
};

sub data
{
    return $_[0]->[DATA];
}

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);

    $self->clear_data;
    my $entity = shift;

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter('ip')
        unless $ip;

    my $result = $self->get_ntpq($ip);

    if (! defined $result)
    {
        $self->errmsg("ntpq file missing $NTPQ");
        $self->status(_ST_BAD_CONF);
    }
    elsif (! @$result)
    {
        $self->errmsg('NTP server didn\'t answer');
        $self->status(_ST_DOWN);
    }
    else
    {
        $self->result_dispatch($result);
    }

    my $id_entity = $entity->id_entity;
    $self->rrd_save($id_entity, $self->status)
        if $self->status < _ST_DOWN;
    $self->save_data($id_entity);
}

sub result_dispatch
{
    my $self = shift;
    my $result = shift;
    my $data = $self->data;

    my @r;

    for (@$result)
    {
        chomp;
        push @r, $_;
    }
    
    $data->{raw} = join("::", @r);

    shift @r;

    my ($f, $g, @k);
    my $d = {};

    my $sync ='';

    for (@r)
    {
        next
            unless $_;
        next
            if /====/;

        ($f,$g) = split //, $_, 2;
        @k = split /\s+/, $g;

        $sync = $k[0]
            if $f eq '*' || $f eq 'o';

        $d->{$k[0]} =
        {
            sync => $f,
            refid =>$k[1],
            stratum => $k[2],
            t => $k[3],
            when => $k[4],
            poll => $k[5],
            reach => $k[6],
            delay => $k[7],
            offset => $k[8],
            jitter => $k[9],
        }
    }
#use Data::Dumper; log_debug(Dumper($d),_LOG_ERROR); 

    if (! $sync)
    {
        $self->errmsg("time synchronization lost");
        $self->status(_ST_MAJOR);
    }
    else
    {
        $data->{remote} = $sync;
        $data->{refid} = $d->{$sync}->{refid};
        $data->{stratum} = $d->{$sync}->{stratum};
        $data->{delay} = $d->{$sync}->{delay};
        $data->{offset} = $d->{$sync}->{offset};
        $data->{jitter} = $d->{$sync}->{jitter};
    }
}

sub rrd_result
{
    my $self = shift;

    my $h = $self->data;
    
    return
    {   
        'stratum' => defined $h->{stratum} ? $h->{stratum} : 'U',
        'delay' => defined $h->{delay} ? $h->{delay} : 'U',
        'offset' => defined $h->{offset} ? $h->{offset} : 'U',
        'jitter' => defined $h->{jitter} ? $h->{jitter} : 'U',
    };
}

sub rrd_config
{   
    return
    {   
        'stratum' => 'GAUGE',
        'delay' => 'GAUGE',
        'offset' => 'GAUGE',
        'jitter' => 'GAUGE',
    };
}

sub get_ntpq
{
    my $self = shift;
    my $ip = shift;

    if (! -e $NTPQ)
    {
        log_debug(qq|ntpq file not found: $NTPQ|, _LOG_ERROR)
            if $LogEnabled;
        return undef;
    }
    my $cmd = sprintf(qq|%s %s %s|, $NTPQ, $NTPQ_PARAMS, $ip);

    open(NULL, ">", File::Spec->devnull);
    my $pid = open3(gensym, \*PH, ">&NULL", $cmd);
    my @result = <PH>;

    waitpid($pid, 0);
    close NULL;

    return []
        unless @result;

    shift @result
        until $result[0] =~ /refid/i || ! scalar @result;
    return \@result;
}


sub discover 
{
    my $self = shift;
    $self->SUPER::discover(@_);
    my $entity = shift;

    my $ip = $entity->params('ip');

    return
        unless $ip;

    my $result = $self->get_ntpq($ip);
    if (defined $result && @$result)
    {
        my $old = $self->_discover_get_existing_entities($entity);
        $self->_discover_add_new_entity($entity)
            unless $old;
    }
    else 
    {
        log_debug(sprintf(qq|entity %s: no NTP server discovered|, $entity->id_entity), _LOG_INFO)
            if $LogEnabled;
    }
}

sub _discover_add_new_entity
{
    my ($self, $parent) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s NTP server|, $parent->id_entity), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = $self->_entity_add({
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => 'NTP server',
       }, $self->dbh);

    if (ref($entity) eq 'Entity')
    {
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s NTP server|, 
            $parent->id_entity, $entity->id_entity), _LOG_INFO)
            if $LogEnabled;
    }
}

sub save_data
{
    my $self = shift;

    my $id_entity = shift;
    
    my $data_dir = $DataDir;

    open F, ">$data_dir/$id_entity";
    
    my $h = $self->data;
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

    push @$result, sprintf(qq|remote: %s|, $data->{remote})
        if defined $data->{remote};
    push @$result, sprintf(qq|refid: %s|, $data->{refid})
        if defined $data->{refid};
    push @$result, sprintf(qq|stratum: %s|, $data->{stratum})
        if defined $data->{stratum};
    push @$result, sprintf(qq|delay: %s|, $data->{delay})
        if defined $data->{delay};
    push @$result, sprintf(qq|offset: %s|, $data->{offset})
        if defined $data->{offset};
    push @$result, sprintf(qq|jitter: %s|, $data->{jitter})
        if defined $data->{jitter};

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity, $url_params) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless defined $data->{raw} && $data->{raw};

    $data->{raw} =~ s/::/\n/g;

    my $legend = [
        ['space', 'reject', 'The peer is discarded as unreachable, synchronized to this server<br>(synch loop) or outrageous synchronization distance.' ],
        ['x', 'falsetick', 'The peer is discarded by the intersection algorithm as a falseticker.'],
        ['.', 'excess', 'The peer is discarded as not among the first ten peers sorted by<br>synchronization distance and so is probably a poor candidate for<br>further consideration.'],
        ['-', 'outlyer', 'The peer is discarded by the clustering algorithm as an outlyer.'],
        ['+', 'candidat', 'The peer is a survivor and a candidate for the combining algorithm.'],
        ['#', 'selected', 'The peer is a survivor, but not among the first six peers sorted by<br>synchronization distance. If the association is ephemeral, it may be<br>demobilized to conserve resources.'],
        ['*', 'sys.peer', 'The peer has been declared the system peer and lends its variables<br>to the system variables.'],
        ['o', 'pps.peer', 'The peer has been declared the system peer and lends its variables<br>to the system variables. However, the actual system synchronization<br>is derived from a pulse-per-second (PPS) signal, either indirectly via<br>the PPS reference clock driver or directly via kernel interface.'],
    ];

    my $t = HTML::Table->new(-border=>1, -spacing=>0);
    $t = table_begin('legend', 3, $t);
    for my $i (0..$#$legend)
    {
        #$legend->[$i]->[0] = sprintf(qq|<pre>%s</pre>|,$legend->[$i]->[0]);
        $t->addRow(@{$legend->[$i]});
    }

    $table->addRow(sprintf(qq|<pre>%s</pre>|, $data->{raw}));
    $table->addRow($t->getTable);
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

   #$result .= "&nbsp;[SCRIPT]"
   #     if $entity->params('tcp_generic_script');

    return $result;
}  

sub menu_stat_no_default
{
    return 1;
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
    $url_params->{probe} = 'ntp';
    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'delay';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    
    return
        if $default_only;

    $url_params->{probe_specific} = 'offset';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    $url_params->{probe_specific} = 'jitter';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    $url_params->{probe_specific} = 'stratum';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    $rrd_graph->title($url_params->{probe_specific});
    if ($url_params->{probe_specific} eq 'stratum')
    {
        $rrd_graph->unit('no');
    }
    else
    {
        $rrd_graph->unit('sec');
    }

}

1;
