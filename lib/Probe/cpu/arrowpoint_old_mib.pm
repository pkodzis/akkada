package Probe::cpu::arrowpoint_old_mib;

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

my $OID = '1.3.6.1.4.1.2467.1.34.17.1'; # gauge

my $_cpu =
{
     13 => 'current',
     14 => '5_min_avg',
};

sub rrd_load_data
{
    return ($_[0]->rrd_config, $_[0]->cpu);
}

sub oids_build
{
    my $self = shift;

    my @oids = ();

    for (keys %$_cpu)
    {   
        push @oids, "$OID.$_.6.1";
    }
    return \@oids;
}

sub entity_test
{
    my $self = shift;
    my $session = $self->session;

    my $result = $session->get_request( -varbindlist => $self->oids_build() );

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
        'current' => 'GAUGE',
        '5_min_avg' => 'GAUGE',
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
    my $key;

    for (keys %$result)
    {
        $key = $_;

        if (/^$OID\./)
        {
            s/^$OID\.//g;
            s/\.6\.1$//g;
            $cpu->{ $_cpu->{$_} } = $result->{$key};
            $cpu->{ $_cpu->{$_} } = 'U'
                if $cpu->{ $_cpu->{$_} } eq '';
        }
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
        next
            unless defined $cpu->{$c};
        next
            unless $cpu->{$c};
        next
            if $cpu->{$c} eq 'U';
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

    top_save($entity->id_entity, 'cpu', $cpu->{'5_min_avg'})
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

    if (defined $data->{current})
    {   
        push @$result, sprintf(qq|usage: <font class="%s">%.2f%%</font>|, 
            percent_bar_style_select($data->{current}), $data->{current});
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

    if (defined $data->{current})
    {   
        $table->addRow("current:",
            sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($data->{current}), $data->{current}));
    }
    if (defined $data->{'5_min_avg'})
    {   
        $table->addRow("5 min average:",
            sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($data->{'5_min_avg'}), $data->{'5_min_avg'}));
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

    push @$args, "DEF:ds01=$rrd_file:current:$cf";
    push @$args, "DEF:ds02=$rrd_file:5_min_avg:$cf";
    push @$args, "LINE1:ds01#CCBB33:current";
    push @$args, "LINE1:ds02#CC3333:5 min average";
    return (1, 0, "ds01");
}

1;
