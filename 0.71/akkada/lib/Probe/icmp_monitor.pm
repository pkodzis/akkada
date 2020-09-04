package Probe::icmp_monitor;

use vars qw($VERSION);

$VERSION = 0.49;

use base qw(Probe);
use strict;

use Number::Format qw(:subs);

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use URLRewriter;

our $DataDir = CFG->{Probe}->{DataDir};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};
our $ICMPMonitorStatusDir = CFG->{ICMPMonitor}->{StatusDir};

$Number::Format::DECIMAL_FILL = 1;

sub id_probe_type
{
    return 22;
}

sub name
{
    return 'ICMP';
}


sub mandatory_fields
{
    return
    [   
        'nic_ip',
    ]
}

sub manual
{
    return 1;
}

sub snmp
{
    return 0;
}

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);

    my $entity = shift;

    my $id_entity = $entity->id_entity;

    if (! $entity->params('nic_ip_icmp_check_disable'))
    {
        $self->icmp_monitor( $entity->params('nic_ip') );
        $self->save_data( $id_entity );
    }
}

sub icmp_monitor
{
    my $self = shift;
    my $nic_ip = shift;

    if (defined $nic_ip && $nic_ip)
    {
        if (flag_file_check($ICMPMonitorStatusDir, sprintf(qq|%s.lost|,$nic_ip)))
        {
            $self->errmsg("lost ICMP packets");
            $self->status(_ST_MAJOR);
        }
        elsif (flag_file_check($ICMPMonitorStatusDir, sprintf(qq|%s.delay|,$nic_ip)))
        {
            $self->errmsg("ICMP packets delay too high");
            $self->status(_ST_MINOR);
        }
    }
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

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;

    my @i;
    push @i, '*' if $entity->status_weight == 0;
    push @i, '*' if $entity->params('nic_ip_icmp_check_disable');

    return sprintf(qq|%s%s|,
        $entity->name,
        @i
            ? join('', @i)
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
    my $cgi = CGI->new();
            
    my $url;
    $url_params->{probe} = 'icmp_monitor';
        
    if ($entity->params('nic_ip') && ! $entity->params('nic_ip_icmp_check_disable'))
    {
        $url_params->{probe_prepare_ds} = 'prepare_ds_smoke';
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    }

}

sub prepare_ds_smoke_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $entity = $rrd_graph->entity;
    my $nic_ip = $entity->params('nic_ip');
    my $rrd_file = sprintf(qq|%s/%s.icmp_monitor|, CFG->{Probe}->{RRDDir}, $nic_ip);

    my $pingCount = 20;
    my $url_params = $rrd_graph->url_params;

    my $begin = $rrd_graph->begin;

    my $max = findmax($rrd_file, $pingCount, $begin, $rrd_graph->end);

    my $args = $rrd_graph->args;

    push @$args, ( '--width',$rrd_graph->width, '--height',$rrd_graph->height);
    push @$args, ('COMMENT:Median Ping RTT  (',
      "DEF:median=$rrd_file:median:AVERAGE",
      "DEF:loss=$rrd_file:loss:AVERAGE",
      "LINE2:median#202020");
    push @$args, ( 'GPRINT:median:AVERAGE:loss )  avg\: %.1lf %ss\l');

    $rrd_graph->scale( $max->{ $begin } );
    $rrd_graph->unit('sec');
    $rrd_graph->title($nic_ip . ' ping');
}

sub prepare_ds_smoke
{
    my $self = shift;
    my $rrd_graph = shift;

    my $entity = $rrd_graph->entity;
    my $rrd_file = sprintf(qq|%s/%s.icmp_monitor|, CFG->{Probe}->{RRDDir}, $entity->params('nic_ip'));

    my $pingCount = 20;
    my $url_params = $rrd_graph->url_params;

    my $scale = $rrd_graph->scale;

    my %lc = 
    (
        0                  => ['0',   '#26ff00'],
        1                  => ["1/$pingCount",  '#00b8ff'],
        2                  => ["2/$pingCount",  '#0059ff'],
        3                  => ["3/$pingCount",  '#5e00ff'],
        4                  => ["4/$pingCount",  '#7e00ff'],
        int($pingCount/2)  => [int($pingCount/2)."/$pingCount", '#dd00ff'],
        $pingCount-1       => [($pingCount-1)."/$pingCount",    '#ff0000'],
    );

    my $args = $rrd_graph->args;

    push @$args, map {"DEF:ping${_}=$rrd_file:ping${_}:AVERAGE"} 1..$pingCount;
    push @$args, map {"CDEF:cp${_}=ping${_},0,$scale,LIMIT"} 1..$pingCount;

    my $smoke = smokecol($pingCount);
    push @$args, @$smoke;

    my $last = -1;
    my $swidth = $scale / $rrd_graph->height;

    foreach my $loss (sort {$a <=> $b} keys %lc)
    {
        push @$args, ("CDEF:me$loss=loss,$last,GT,loss,$loss,LE,*,1,UNKN,IF,median,*",
            "CDEF:meL$loss=me$loss,$swidth,-",
            "CDEF:meH$loss=me$loss,0,*,$swidth,2,*,+",
            "AREA:meL$loss",
            "STACK:meH$loss$lc{$loss}[1]:$lc{$loss}[0]");
        $last = $loss;
    }

    return (1, 0, "median");
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;
    open F, ">$DataDir/$id_entity";
    close F;
}

1;
