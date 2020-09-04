package Probe::cpu::host_resources;

use vars qw($VERSION);

$VERSION = 0.2;

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

our $OID = '1.3.6.1.2.1.25.3.3.1.2'; # walk, gauge

sub rrd_load_data
{
    return ($_[0]->rrd_config, $_[0]->cpu);
}

sub entity_test
{
    my $self = shift;
    my $session = $self->session;

    my $cpu_count = $self->entity->params('cpu_count');
    $self->cpu_count( $cpu_count );

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
    my $self = shift;

    my $result = {};
    for (1 .. $self->cpu_count)
    {
        $result->{$_} = 'GAUGE';
    }
    return $result;
}

sub result_dispatch
{   
    my $self = shift;
    my $result = shift;
    my $cpu_count = $self->cpu_count;

    if (scalar keys %$result == 0)
    {   
        $self->errmsg('CPU information not found');
        $self->status(_ST_MAJOR);
        return;
    }
    elsif (! $cpu_count || scalar keys %$result != $cpu_count)
    {   
        # zmiana liczby procesorow
        $self->entity->params('cpu_count', scalar keys %$result);
    }

    my $cpu = $self->cpu;
    my $i = 1;
    for (keys %$result)
    {
        $cpu->{$i} = $result->{$_};
        $i++;
    }
}

sub utilization_status
{
    my $self = shift;
    my $cpu = $self->cpu;
    my $entity = $self->entity;

    my $cpu_stop_warning_high_utilization = $entity->params('cpu_stop_warning_high_utilization');

    if ($entity->params('cpu_host_resources_utilization_aggregate'))
    {
        my $cpu_count = $self->cpu_count;

        my $ut = 0;
        for (keys %$cpu)
        {
            $ut += $cpu->{$_};
        }

        $ut = $ut / $cpu_count;

        if ($ut >= $self->threshold_high)
        {
            $self->errmsg(qq|high aggregated CPU utilization|);
            $self->status(_ST_MINOR)
                unless $cpu_stop_warning_high_utilization;
        }
        elsif ($ut >= $self->threshold_medium)
        {
            $self->errmsg(qq|medium aggregated CPU utilization|);
            $self->status(_ST_WARNING)
                unless $cpu_stop_warning_high_utilization;
        }
    }
    else
    {
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
    }
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

    my $cpu_count = $entity->params('cpu_count');
    my $cpu_host_resources_utilization_aggregate = $entity->params('cpu_host_resources_utilization_aggregate');

    if ($cpu_host_resources_utilization_aggregate)
    {
        my $ut;
        for (1 .. $cpu_count)
        {
            $ut += $data->{$_};
        }

        $ut = $ut / $cpu_count;
        push @$result, sprintf(qq|aggregated usage: <font class="%s">%.2f%%</font>|, percent_bar_style_select($ut), $ut);
    }

    my $res = 'usage: ';
    for (1 .. $cpu_count)
    {
        $res .= sprintf(qq|#$_: <font class="%s">%.2f%%</font> |, 
            percent_bar_style_select($data->{$_}), defined $data->{$_} ? $data->{$_} : 'unknown');
    }

    push @$result, $res;

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;
    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $cpu_host_resources_utilization_aggregate = $entity->params('cpu_host_resources_utilization_aggregate');

    my $cpu_count = $entity->params('cpu_count');


    if ($cpu_host_resources_utilization_aggregate)
    {
        my $ut;
        for (1 .. $cpu_count)
        {
            $ut += $data->{$_};
        }

        $ut = $ut / $cpu_count;
        $table->addRow("CPU aggregated:",
            sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($ut), $ut));
    }

    for (1 .. $cpu_count)
    {
        $table->addRow("CPU #$_:",
            sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($data->{$_}), defined $data->{$_} ? $data->{$_} : 'unknown'));    
    }
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
    $url_params->{probe_prepare_ds} = 'prepare_ds';

    my $cpu_count = $entity->params('cpu_count');

    for (1 .. $cpu_count)
    {
        $url_params->{probe_specific} = $_;
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    }
}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $url_params = $rrd_graph->url_params;
    $rrd_graph->unit('%');
    $rrd_graph->title($url_params->{probe_specific});
}

1;
