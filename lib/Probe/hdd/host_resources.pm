package Probe::hdd::host_resources;

use vars qw($VERSION);

$VERSION = 0.1;

use base qw(Probe::hdd);
use strict;

use Net::SNMP;
use Number::Format qw(:subs);
use Data::Dumper;

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
our $MaxSNMPSplitRequest = CFG->{MaxSNMPSplitRequest};

$Number::Format::DECIMAL_FILL = 1;

our $OID = '1.3.6.1.2.1.25.2.3.1';

my $_hrStorageEntry =
{
    2 => 'hrStorageType',
    3 => 'hrStorageDescr',
    4 => 'hrStorageAllocationUnits',
    5 => 'hrStorageSize',
    6 => 'hrStorageUsed',
    7 => 'hrStorageAF',
};

my $_hrStorageTypes =
{
    0 => ['unknown', 0],
    1 => ['other', 0],
    2 => ['RAM memory', 1],
    3 => ['virtual, paged or swap memory', 1],
    4 => ['fixed disk', 1],
    5 => ['removable disk', 0],
    6 => ['floppy disk', 0],
    7 => ['compact disc', 0],
    8 => ['RAM disc', 1],
    9 => ['flash memory', 0],
    10 => ['network file system', 1],
};

sub cache_keys
{
    return
    [
        'hrStorageAF',
    ];
}

sub oids_build
{
    my $self = shift;
    my $index = shift;
    my $snmp_split_request = shift;

    my $oids_disabled = {};

    my $oid_src = shift || '';

    @$oids_disabled{ (split /:/, $oid_src) } = undef;

    my @oids = ();
    my $s;

    for (keys %$_hrStorageEntry)
    {
        $s = "$OID.$_";
        next
            if exists $oids_disabled->{$s};
        push @oids, "$s.$index";
    }

    return [\@oids]
        if $snmp_split_request == 1;

    my $split = 0;
    my $result;

    for (@oids)
    {
        push @{$result->[$split]}, $_;
        ++$split;
        $split = 0
            if $split == $snmp_split_request;
    }
    return $result;
}

sub entity_test
{
    my $self = shift;
    my $session = $self->session;

    my $entity = $self->entity;
    my $name = $entity->name;
  
    my $index = undef; 
    my $result = $self->discover_hdd( "$OID.3" );

    $index = $result->{ $name }
        if defined $result;

    if (! defined $index)
    {
        $self->errmsg('not found');
        $self->status(_ST_MAJOR);
        return;
    }

    my $snmp_split_request = $entity->params_own->{'snmp_split_request'};
    log_debug(sprintf(qq|entity %s snmp_split_request: %s|, $entity->id_entity, $snmp_split_request), _LOG_DEBUG)
        if $LogEnabled && $snmp_split_request;
    $snmp_split_request = 1
        unless $snmp_split_request;

    my $oids_disabled = $entity->params_own->{'oids_disabled'};
    log_debug(sprintf(qq|entity %s oids_disabled: %s|, $entity->id_entity, $oids_disabled), _LOG_DEBUG)
        if $LogEnabled && $oids_disabled;

    my $oids = $self->oids_build( $index, $snmp_split_request, $oids_disabled );
#use Data::Dumper; log_debug(Dumper($entity->name), _LOG_ERROR);
#use Data::Dumper; log_debug(Dumper($oids), _LOG_ERROR);

    if ($snmp_split_request == 1)
    {
        $result = $session->get_request( -varbindlist => $oids->[0] );
    }
    else
    {
        my $res;
        for (@$oids)
        {
            $res = $session->get_request( -varbindlist => $_ );

            if ($session->error)
            {
                $oids->[0] = $_;
                last;
            }

            for (keys %$res)
            {
                $result->{$_} = $res->{$_};
            }
        }
    }

#use Data::Dumper; log_debug(Dumper($result), _LOG_ERROR);
    my $error = $session->error_status();
    my $hdd = $self->hdd;

    if ($error == 1)
    {
        if ($snmp_split_request <= $MaxSNMPSplitRequest)
        {
            ++$snmp_split_request;
            $entity->params('snmp_split_request', $snmp_split_request);
        }
        else
        {
            log_debug(sprintf(qq|maximum snmp_split_request value %s already set. cannot fix that!!! check configuration|,
                $MaxSNMPSplitRequest), _LOG_ERROR);
        }
    }
    elsif ($error == 2)
    {
        my $bad_oid = $oids->[0]->[$session->error_index - 1];

        if ($bad_oid =~ /^$OID/)
        {
            my @s = split /\./, $bad_oid;
            pop @s;
            $bad_oid = join(".", @s);

            $oids_disabled = defined $oids_disabled
                ? join(":", $oids_disabled, $bad_oid)
                : $bad_oid;

            $entity->params('oids_disabled', $oids_disabled);
        }
    }
    elsif (! $error || $error == 129 || $error == 128)
    {
        $self->result_dispatch($result);
        $self->cache_update($entity->id_entity, $hdd );
        if ($_hrStorageTypes->{ $hdd->{hrStorageType} }->[1])
        {
            $self->utilization_status;
        }
        $self->entity->params('function', 'ram')
            if $hdd->{hrStorageType} == 2 || $hdd->{hrStorageType} == 8;
        if (defined $hdd->{hrStorageDescr} && $hdd->{hrStorageDescr})
        {
            $name =~ s/\\/\\\\/g;
            $hdd->{hrStorageDescr} =~ s/^$name//g;
            $entity->description_dynamic($hdd->{hrStorageDescr})
                if $hdd->{hrStorageDescr};
        }
        if (defined $Monitor->{$_hrStorageTypes->{ $hdd->{hrStorageType} }->[0]}
            && $Monitor->{$_hrStorageTypes->{ $hdd->{hrStorageType} }->[0]} == 0)
        {
            $self->entity->monitor(0);
            $self->entity->db_update_entity;
        }
    }   
    else
    {
        #$self->errmsg('snmp error: ' . $session->error);
        $self->errmsg(sprintf('snmp error: index %s status %s; msg %s;', $session->error_index, $error, $session->error));
        $self->status(_ST_MAJOR);
    }
}

sub rrd_config
{
    return 
    {
        'hrStorageUsed' => 'GAUGE',
        'hrPercentUsed' => 'GAUGE',
        'hrStorageSize' => 'GAUGE',
        'hrStorageAF' => 'COUNTER',
    };
}

sub result_dispatch
{
    my $self = shift;
    my $result = shift;
#use Data::Dumper; print Dumper($result); 
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
            $hdd->{ $_hrStorageEntry->{$index} } = $result->{$key};
        }
    }

    $key = '1.3.6.1.2.1.25.2.1.';
    if ($hdd->{hrStorageType} =~ /$key/)
    {
        $hdd->{hrStorageType} = (split /^$key/, $hdd->{hrStorageType})[1];
    }
    else
    {
        $hdd->{hrStorageType} = 0;
    }

    if ($hdd->{hrStorageUsed} =~ /\D/
        || $hdd->{hrStorageSize} =~ /\D/
        || $hdd->{hrStorageAllocationUnits} =~ /\D/
        || $hdd->{hrStorageUsed} eq ''
        || $hdd->{hrStorageSize} eq ''
        || $hdd->{hrStorageAllocationUnits} eq '')
    {
        $hdd->{hrStorageUsed} = 'U';
        $hdd->{hrStorageSize} = 'U';
    }
    else
    {
        $hdd->{hrStorageUsed} *= $hdd->{hrStorageAllocationUnits};
        $hdd->{hrStorageSize} *= $hdd->{hrStorageAllocationUnits};
    }

    $hdd->{hrPercentUsed} = 'U';
    $hdd->{hrPercentUsed} = ($hdd->{hrStorageUsed}*100)/$hdd->{hrStorageSize}
        if $hdd->{hrStorageSize} && $hdd->{hrStorageSize} ne 'U';
#print "name: $hdd->{hrStorageDescr}: type: $hdd->{hrStorageType}; storage size: $hdd->{hrStorageSize}\n\n";
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

    my $threshold_medium = $self->threshold_medium;
    my $threshold_high = $self->threshold_high;

    if (! $hdd_threshold_bytes_mode)
    {
        ($hdd->{hrStorageType} == 2 || $hdd->{hrStorageType} == 8)
            ? top_save($entity->id_entity, 'ram', $hdd->{hrPercentUsed})
            : top_save($entity->id_entity, 'hdd', $hdd->{hrPercentUsed});
    }

    if (! $hdd_threshold_bytes_mode && $hdd->{hrPercentUsed} && $hdd->{hrPercentUsed} ne 'U')
    {
        if ($hdd->{hrPercentUsed} >= 99)
        {   
            $self->errmsg(qq|storage full|);
            $self->status(_ST_MAJOR);
        }
        elsif ($hdd->{hrPercentUsed} >= $threshold_high)
        {   
            $self->errmsg(qq|very low free space|);
            $self->status(_ST_MINOR);
        }
        elsif ($hdd->{hrPercentUsed} >= $threshold_medium)
        {   
            $self->errmsg(qq|low free space|);
            $self->status(_ST_WARNING);
        }
    }
    elsif ($hdd_threshold_bytes_mode && $hdd->{hrStorageUsed} && $hdd->{hrStorageUsed} ne 'U')
    {
        my $threshold_high = $entity->params('hdd_threshold_minimum_bytes') || '128000000';

        if (($hdd->{'hrStorageSize'} - $hdd->{'hrStorageUsed'}) <= $threshold_high)
        {
            $self->errmsg(qq|very low free space|);
            $self->status(_ST_MAJOR);
        }
    }

    my $ch = $self->cache->{$entity->id_entity};
    if ( $ch->{hrStorageAF}->[1] && $ch->{hrStorageAF}->[1] ne 'U')
    {
        $self->errmsg('allocation unit failures');
        $self->status(_ST_MINOR);
    }
}

sub save_data
{       
    my $self = shift;

    my $id_entity = shift;
 
    my $data_dir = $DataDir;
    
    open F, ">$data_dir/$id_entity";
    
    my $h = $self->hdd;
    my $ch = $self->cache->{$id_entity};
    for ( map { $_ eq 'hrStorageAF' ? "$_\|$ch->{$_}->[1]\n" : "$_\|$h->{$_}\n" } keys %$h )
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

    if ($data->{'hrStorageUsed'} ne 'U')
    {
         push @$result, sprintf(qq|used: <font class="%s">%s/%sB; %.2f%%</font>|,
             percent_bar_style_select($data->{'hrPercentUsed'}),
             format_bytes($data->{'hrStorageUsed'}),
             format_bytes($data->{'hrStorageSize'}),
             $data->{'hrPercentUsed'});
    }
    else
    {
        push @$result, "used: unknown";
    }

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;
    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    $table->addRow("storage type:", $_hrStorageTypes->{ $data->{hrStorageType} }->[0] );
    $table->addRow("used space:", $data->{'hrStorageUsed'} eq 'U'
        ? 'unknown'
        : sprintf(qq|<font class="%s">%sB; %.2f%%</font>|,
        percent_bar_style_select($data->{'hrPercentUsed'}), 
        format_bytes($data->{'hrStorageUsed'}),
        $data->{'hrPercentUsed'}));
    $table->addRow("available space:", $data->{'hrStorageSize'} eq 'U'
        ? 'unknown'
        : sprintf(qq|%sB; %.2f%%|,
        format_bytes($data->{'hrStorageSize'} - $data->{'hrStorageUsed'}),
        100-$data->{'hrPercentUsed'}));
    $table->addRow("total space:", $data->{'hrStorageSize'} eq 'U'
        ? 'unknown'
        : format_bytes($data->{'hrStorageSize'}) . 'B');
    $table->addRow("allocation unit failures:", $data->{hrStorageAF} eq 'U'
        ? 'unknown'
        : $data->{hrStorageAF} );
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

    $url_params->{probe_specific} = 'hrPercentUsed';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'hrStorageAF';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    if ( $url_params->{probe_specific} eq 'hrStorageAF')
    {
        $rrd_graph->unit('no.');
        $rrd_graph->title('allocation unit failures');
    }
    elsif ( $url_params->{probe_specific} eq 'hrPercentUsed')
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

    push @$args, "DEF:ds0u=$rrd_file:hrStorageUsed:$cf";
    push @$args, "DEF:ds0s=$rrd_file:hrStorageSize:$cf";
    push @$args, "CDEF:ds0a=ds0s,ds0u,-";
    push @$args, "AREA:ds0u#330099:used";
    push @$args, "STACK:ds0a#00CC33:available";

    return ($up, $down, "ds0u");
}

1;
