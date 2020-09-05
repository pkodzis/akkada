package Probe::cpu::cisco;

use vars qw($VERSION);

$VERSION = 0.3;

use base qw(Probe::cpu);
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

our $OID = '1.3.6.1.4.1.9.9.109.1.1.1.1'; # 1 - 3, gauge

my $_cpmCPU = {
    3 => 'cpmCPUTotal5sec',
    4 => 'cpmCPUTotal1min',
    5 => 'cpmCPUTotal5min',
};

sub rrd_load_data
{
    return ($_[0]->rrd_config, $_[0]->cpu);
}

sub entity_test
{
    my $self = shift;
    my $session = $self->session;

    my $result = $session->get_table(-baseoid => $OID);
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

sub rrd_config
{
    return
    {
        'cpmCPUTotal1min' => 'GAUGE',
        'cpmCPUTotal5min' => 'GAUGE',
        'cpmCPUTotal5sec' => 'GAUGE',
    };
}

sub result_dispatch
{   
    my $self = shift;
    my $result = shift;

    if (scalar keys %$result == 0)
    {
        $self->errmsg('CPU information not found');
        $self->status(_ST_MAJOR);
        return;
    }

    my $cpu = $self->cpu;
    my @i;
    my $key;
    for (keys %$result)
    {
        $key = $_;
        $_ =~ s/^$OID\.//g;
        @i = split /\./, $_;
        next
            unless defined $_cpmCPU->{$i[0]};
        $cpu->{ $_cpmCPU->{$i[0]} } = $result->{$key};
    }
}

sub utilization_status
{  
    my $self = shift;  
    my $cpu = $self->cpu;
    my $entity = $self->entity;

    my $cpu_stop_warning_high_utilization = $entity->params('cpu_stop_warning_high_utilization');

    for my $c (keys %$cpu)
    {
        if ($cpu->{$c} >= $self->threshold_high)
        {
            $self->errmsg(sprintf(qq|high CPU %s utilization|, $c));
            $self->status(_ST_MINOR)
                unless $cpu_stop_warning_high_utilization;
        }
        elsif ($cpu->{$c} >= $self->threshold_medium)
        {  
            $self->errmsg(sprintf(qq|medium CPU %s utilization|, $c));
            $self->status(_ST_WARNING)
                unless $cpu_stop_warning_high_utilization;
        }
    }

    top_save($entity->id_entity, 'cpu', $cpu->{cpmCPUTotal5min})
        unless $cpu_stop_warning_high_utilization;
}

sub probe_name
{
    return "cpu";
}

sub save_data
{
    my $self = shift;

    my $id_entity = shift;

    my $data_dir = $DataDir;

    my $h;

    open F, ">$data_dir/$id_entity";

    $h = $self->cpu;
    for ( map { "$_\|$h->{$_}\n" } keys %$h )
    {   
        print F $_;
    }

    close F;
}

sub desc_brief
{   
    my ($self, $entity, $result) = @_;

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    if (defined $data->{cpmCPUTotal1min})
    {   
        push @$result, sprintf(qq|usage: <font class="%s">%.2f%%</font>|,                                                                       percent_bar_style_select($data->{cpmCPUTotal1min}), $data->{cpmCPUTotal1min});
    }
    else
    {   
        push @$result, "usage: unknown";
    }

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;
    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    $table->addRow("CPU Total 5sec :",
        sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($data->{cpmCPUTotal5sec}), $data->{cpmCPUTotal5sec}));
    $table->addRow("CPU Total 1min :",
        sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($data->{cpmCPUTotal1min}), $data->{cpmCPUTotal1min}));
    $table->addRow("CPU Total 5min :",
        sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($data->{cpmCPUTotal5min}), $data->{cpmCPUTotal5min}));
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
    my $cgi = shift;

    my $url;
    $url_params->{probe} = 'cpu';

    $url_params->{probe_prepare_ds} = 'prepare_ds_adv';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}

sub prepare_ds_adv_pre
{   
    my $self = shift;
    my $rrd_graph = shift;

    $rrd_graph->unit('%');
    $rrd_graph->title('utilization');
}

sub prepare_ds_adv
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    return
        if $cf ne 'AVERAGE';

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;

    my $rrd_file = sprintf(qq|%s/%s.%s|, CFG->{Probe}->{RRDDir}, $entity->id_entity, $url_params->{probe});

    push @$args, "DEF:ds01=$rrd_file:cpmCPUTotal5sec:$cf";
    push @$args, "DEF:ds02=$rrd_file:cpmCPUTotal1min:$cf";
    push @$args, "DEF:ds03=$rrd_file:cpmCPUTotal5min:$cf";
    push @$args, "LINE1:ds01#CC3333:5 sec";
    push @$args, "LINE1:ds02#CC9933:1 min";
    push @$args, "LINE1:ds03#FFFF33:5 min";
    return (1, 0, "ds01");
}

1;
