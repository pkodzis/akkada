package Probe::hdd::ucd;

use vars qw($VERSION);

$VERSION = 0.1;

use base qw(Probe::hdd);
use strict;

use Net::SNMP;
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
our $Monitor = CFG->{Probes}->{hdd}->{host_resources}->{Monitor};

$Number::Format::DECIMAL_FILL = 1;

our $OID = '1.3.6.1.4.1.2021.9.1';

my $_dskEntry = {
    2 => 'dskPath',
    3 => 'dskDevice',
    6 => 'dskTotal',
    7 => 'dskAvail',
    8 => 'dskUsed',
    9 => 'dskPercent',
    10 => 'dskPercentNode',
    12 => 'dskErrorMsg',
};

sub oids_build
{
    my $self = shift;
    my $index = shift;

    my @oids = ();

    for (keys %$_dskEntry)
    {
        push @oids, "$OID.$_.$index";
    }

#use Data::Dumper; print Dumper(\@oids); 
    return \@oids;
}

sub entity_test
{
    my $self = shift;
    my $session = $self->session;

    my $entity = $self->entity;
  
    my $index = undef; 
    my $result = $self->discover_hdd( "$OID.3" );

    $index = $result->{ $entity->name }
        if defined $result;

    if (! defined $index)
    {
        $self->errmsg('not found');
        $self->status(_ST_MAJOR);
        return;
    }

    $result = $session->get_request( -varbindlist => $self->oids_build( $index ) );

    my $error = $session->error();
    if (! $error )
    {
        $self->result_dispatch($result);

        $self->utilization_status;
        $entity->description_dynamic( $self->hdd->{dskPath} );
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
        'dskAvail' => 'GAUGE',
        'dskUsed' => 'GAUGE',
        'dskPercent' => 'GAUGE',
        'dskPercentNode' => 'GAUGE',
    };
}

sub result_dispatch
{
    my $self = shift;
    my $result = shift;
#print $self->entity->id_entity, ": \n"; use Data::Dumper; print Dumper($result); 
    if (scalar keys %$result == 0)
    {   
        $self->errmsg('hdd information not found');
        $self->status(_ST_MAJOR);
        return;
    }

    my $hdd = $self->hdd;

    my $key;
    my $index;

    for (keys %$result)
    {           
        $key = $_;

        if (/^$OID\./)
        {
            s/^$OID\.//g;
            $index = (split /\./, $_)[0];
            $hdd->{ $_dskEntry->{$index} } = $result->{$key};
        }
    }
    for ( qw( dskTotal dskAvail dskUsed ) )
    {
        next
            unless defined $hdd->{$_};
        next
            unless $hdd->{$_} !~ /\D/;
        $hdd->{$_} *= 1024;
    }
    for ( qw( dskTotal dskAvail dskUsed dskPercent dskPercentNode ) )
    {
        next
            if $hdd->{$_} ne '' && $hdd->{$_} !~ /\D/;
        $hdd->{$_} = 'U';
    }
}

sub probe_name
{
    return "hdd";
}

sub utilization_status
{   
    my $self = shift;
    my $hdd = $self->hdd;
    my $entity = $self->entity;

    my $hdd_threshold_bytes_mode = $entity->params('hdd_threshold_bytes_mode') || 0;
    my $hdd_stop_raise_inode_alarms = $entity->params('hdd_stop_raise_inode_alarms') || 0;

    my $threshold_medium = $self->threshold_medium;
    my $threshold_high = $self->threshold_high;

    #print "#", $hdd->{dskPercentNode}, "#\n\n";
    if (defined $hdd->{dskPercentNode} && $hdd->{dskPercentNode} !~ /\D/ && ! $hdd_stop_raise_inode_alarms)
    {
        if ( $hdd->{dskPercentNode} > 99)
        {   
            $self->errmsg(qq|<b>file system is dead!!!</b>|);
            $self->status(_ST_MAJOR);
        }
        elsif ( $hdd->{dskPercentNode} >= $threshold_high )
        {   
            $self->errmsg(qq|<b>very low free inodes; file system will die soon!!!<b>|);
            $self->status(_ST_MINOR);
        }
        elsif ( $hdd->{dskPercentNode} >= $threshold_medium)
        {   
            $self->errmsg(qq|low free inodes|);
            $self->status(_ST_WARNING);
        }
    }

    top_save($entity->id_entity, 'hdd', $hdd->{dskPercent})
        unless $hdd_threshold_bytes_mode;

    if (! $hdd_threshold_bytes_mode && $hdd->{dskPercent} !~ /\D/)
    {
        if ($hdd->{dskPercent} >= 99)
        {   
            $self->errmsg(qq|disk full|);
            $self->status(_ST_MAJOR);
        }
        elsif ($hdd->{dskPercent} >= $threshold_high)
        {   
            $self->errmsg(qq|very low disk free space|);
            $self->status(_ST_MINOR);
        }
        elsif ($hdd->{dskPercent} >= $threshold_medium)
        {   
            $self->errmsg(qq|low disk free space|);
            $self->status(_ST_WARNING);
        }
    }
    elsif ($hdd_threshold_bytes_mode && $hdd->{dskAvail} !~ /\D/)
    {
        my $threshold_high = $entity->params('hdd_threshold_minimum_bytes') || '128000000';

#print $hdd->{dskAvail}, "#", $threshold_high, "#\n\n";
        if ($hdd->{dskAvail} <= $threshold_high)
        {
            $self->errmsg(qq|very low disk free space|);
            $self->status(_ST_MAJOR);
        }
    }
    if ($hdd->{dskErrorMsg})
    {
        $self->errmsg(sprintf(qq|snmp agent error message: %s|, $hdd->{dskErrorMsg}));
        $self->status(_ST_MAJOR);
    }
}

sub desc_brief
{   
    my ($self, $entity, $result) = @_;

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    if ($data->{'dskPercent'} eq 'U' && $data->{'dskUsed'} eq 'U')
    {
        push @$result, "used space: unknown";
    }
    else
    {
        push @$result, sprintf(qq|used space: <font class="%s">%s/%sB; %s%%</font>|,
            percent_bar_style_select($data->{'dskPercent'}),
            format_bytes($data->{'dskUsed'}),
            format_bytes($data->{'dskTotal'}),
            $data->{'dskPercent'});
    }

    my $hdd_stop_raise_inode_alarms = $entity->params('hdd_stop_raise_inode_alarms') || 0;

    if ($data->{'dskPercentNode'} eq 'U')
    {
        push @$result, "used inodes: unknown";
    }
    elsif(! $hdd_stop_raise_inode_alarms)
    {
        push @$result, sprintf(qq|used inodes: <font class="%s">%s%%</font>|,
            percent_bar_style_select($data->{'dskPercentNode'}),
            $data->{'dskPercentNode'});
    }
    else
    {
        push @$result, sprintf(qq|used inodes: %s%%|, $data->{'dskPercentNode'});
    }

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;
    my $data = $entity->data;
    my $hdd_stop_raise_inode_alarms = $entity->params('hdd_stop_raise_inode_alarms') || 0;

    return
        unless scalar keys %$data > 1;

    if ($data->{'dskPercentNode'} eq 'U')
    {
        $table->addRow("used inodes:", 'unknown');
    }
    elsif(! $hdd_stop_raise_inode_alarms)
    {
        $table->addRow("used inodes:", sprintf(qq|<font class="%s">%s%%</font>|,
            percent_bar_style_select($data->{'dskPercentNode'}), 
            $data->{'dskPercentNode'}));
    }
    else
    {
        $table->addRow("used inodes:", sprintf(qq|%s%%</font>|, $data->{'dskPercentNode'}));
    }

    if ($data->{'dskPercent'} eq 'U' && $data->{'dskUsed'} eq 'U')
    {
        $table->addRow("used space:", 'unknown');
    }
    else
    {
        $table->addRow("used space:", sprintf(qq|<font class="%s">%sB; %s%%</font>|,
            percent_bar_style_select($data->{'dskPercent'}), 
            format_bytes($data->{'dskUsed'}),
            $data->{'dskPercent'}));
    }

    $table->addRow("available space:", 
        $data->{'dskAvail'} eq 'U'
            ? 'unknown'
            : sprintf(qq|%sB; %s%%|, format_bytes($data->{'dskAvail'}), 100-$data->{'dskPercent'}));

    $table->addRow("total space:",
        $data->{'dskTotal'} eq 'U'
            ? 'unknown'
            : format_bytes($data->{'dskTotal'}) . 'B');
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
    $url_params->{probe} = 'hdd';

    $url_params->{probe_prepare_ds} = 'prepare_ds_bytes';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    return
        if $default_only;

    $url_params->{probe_prepare_ds} = 'prepare_ds';

    $url_params->{probe_specific} = 'dskPercent';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'dskPercentNode';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    if ( $url_params->{probe_specific} eq 'dskPercentNode')
    {
        $rrd_graph->unit('%');
        $rrd_graph->title('usage inodes');
    }
    elsif ( $url_params->{probe_specific} eq 'dskPercent')
    {
        $rrd_graph->unit('%');
        $rrd_graph->title('usage');
    }
}

sub prepare_ds_bytes_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    $rrd_graph->unit('bytes');
    $rrd_graph->title('usage');
}

sub prepare_ds_bytes
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;

    my $rrd_file = sprintf(qq|%s/%s.%s|, CFG->{Probe}->{RRDDir}, $entity->id_entity, $url_params->{probe});

    my $up = 1;
    my $down = 0;

    push @$args, "DEF:ds0u=$rrd_file:dskUsed:$cf";
    push @$args, "DEF:ds0a=$rrd_file:dskAvail:$cf";
    push @$args, "AREA:ds0u#330099:used";
    push @$args, "STACK:ds0a#00CC33:available";

    return ($up, $down, "ds0u");
}

1;
