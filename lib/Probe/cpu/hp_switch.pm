package Probe::cpu::hp_switch;

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

our $OID = '1.3.6.1.4.1.11.2.14.11.5.1.9.6.1'; # gauge

sub rrd_load_data
{
    return ($_[0]->rrd_config, $_[0]->cpu);
}

sub entity_test
{
    my $self = shift;
    my $session = $self->session;

    my $result = $session->get_request( -varbindlist => ["$OID.0"] );
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
        'CPU' => 'GAUGE',
    };
}

sub result_dispatch
{   
    my $self = shift;
    my $result = shift;

    if (scalar keys %$result == 0)
    {   
        $self->errmsg('CPU & load information not found');
        $self->status(_ST_MAJOR);
        return;
    }

    my $cpu = $self->cpu;

    for (keys %$result)
    {
        if (/^$OID\./)
        {
            $cpu->{ CPU } = $result->{$_};
            last;
        }
    }
#use Data::Dumper; die Dumper($self->cpu);
}

sub utilization_status
{
    my $self = shift;
    my $cpu = $self->cpu;

    return
        unless defined $cpu->{CPU};

    $cpu = $cpu->{CPU};

    my $entity = $self->entity;

    my $cpu_stop_warning_high_utilization = $entity->params('cpu_stop_warning_high_utilization');

    if ($cpu >= $self->threshold_high)
    {   
        $self->errmsg(qq|high CPU utilization|);
        $self->status(_ST_MINOR)
            unless $cpu_stop_warning_high_utilization;
    }
    elsif ($cpu >= $self->threshold_medium)
    {   
        $self->errmsg(qq|medium CPU utilization|);
        $self->status(_ST_WARNING)
            unless $cpu_stop_warning_high_utilization;
    }

    top_save($entity->id_entity, 'cpu', $cpu)
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

    if (defined $data->{CPU})
    {   
        push @$result, sprintf(qq|usage: <font class="%s">%.2f%%</font>|, percent_bar_style_select($data->{CPU}), $data->{CPU});
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

    if (defined $data->{CPU})
    {   
        $table->addRow("CPU:",
            sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($data->{CPU}), $data->{CPU}));
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

    $url_params->{probe_specific} = 'CPU';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
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
