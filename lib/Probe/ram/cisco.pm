package Probe::ram::cisco;

use vars qw($VERSION);

$VERSION = 0.1;

use base qw(Probe::ram);
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

$Number::Format::DECIMAL_FILL = 1;

our $OID = '1.3.6.1.4.1.9.9.48.1.1.1';

my $_mem = {
    2 => 'PoolName',
    5 => 'PoolUsed',
    6 => 'PoolFree',
    7 => 'PoolLargestFree',
};

sub oids_build
{
    my $self = shift;
    my $index = shift;

    my @oids = ();
    
    for (keys %$_mem)
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
    my $result = $self->discover_ram_cisco( "$OID.2" );
        
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
        $self->utilization_status
            unless $entity->params('ram_disable_memory_full_alarm_total');
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
        'PoolUsed' => 'GAUGE',
        'PoolFree' => 'GAUGE',
        'PoolLargestFree' => 'GAUGE',
    };
}

sub result_dispatch
{
    my $self = shift;
    my $result = shift;
#print $self->entity->id_entity, ": \n"; use Data::Dumper; print Dumper($result); 
    if (scalar keys %$result == 0)
    {   
        $self->errmsg('ram information not found');
        $self->status(_ST_MAJOR);
        return;
    }

    my $ram = $self->ram;

    my $key;
    my $index;

    for (keys %$result)
    {           
        $key = $_;

        if (/^$OID\./)
        {
            s/^$OID\.//g;
            $index = (split /\./, $_)[0];
            $ram->{ $_mem->{$index} } = $result->{$key};

            next
                if $_mem->{$index} eq 'PoolName';

            if ($result->{$key} !~ /\D/ && $result->{$key} ne '')
            {
                #$ram->{ $_mem->{$index} } *= 1024;
            }
            else
            {
                $ram->{ $_mem->{$index} } = 'U';
            }
        }
    }
#use Data::Dumper; print Dumper $ram; exit;
}

sub probe_name
{
    return "ram";
}

sub utilization_status
{   
    my $self = shift;
    my $ram = $self->ram;
    my $entity = $self->entity;

    my $ram_threshold_bytes_mode = $entity->params('ram_threshold_bytes_mode') || 0;

    my $threshold_medium = $self->threshold_medium;
    my $threshold_high = $self->threshold_high;

    my $used = $ram->{PoolUsed};
    my $avail = $ram->{PoolFree};
    my $total = 'U';

    my $name = $entity->name;

    $total = $used+$avail
        if $used ne 'U' && $avail ne 'U';

    my $per = $total ne 'U' && $total
        ? 100-(($avail*100)/$total)
        : undef;

    top_save($entity->id_entity, 'ram', $per)
        unless $ram_threshold_bytes_mode;

    if (! $ram_threshold_bytes_mode && defined $per)
    {   
        if ($per >= 99)
        {    
            $self->errmsg(qq|$name memory full|);
            $self->status(_ST_MAJOR);
        }   
        elsif ($per >= $threshold_high)
        {   
            $self->errmsg(qq|very low $name memory free space|);
            $self->status(_ST_MINOR);
        }       
        elsif ($per >= $threshold_medium)
        {   
            $self->errmsg(qq|low $name memory free space|);
            $self->status(_ST_WARNING); 
        }   
    }   
    elsif ($ram_threshold_bytes_mode && $avail !~ /\D/)
    {   
        my $threshold_high = $self->entity->params('ram_threshold_minimum_bytes') || '64000000';

        if ($avail <= $threshold_high)
        {
            $self->errmsg(qq|very low $name memory free space|);
            $self->status(_ST_MAJOR);
        }
    }

}

sub desc_brief
{        
    my ($self, $entity, $result) = @_;

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $per;
    my $used = $data->{PoolUsed};
    my $avail = $data->{PoolFree};
    my $total = 'U';
    $total = $used+$avail;

    if ($avail eq 'U' || $total eq 'U' || ! $total)
    {    
        push @$result, "used: unknown";
    }  
    else
    {    
        $per = 100 - ($avail*100)/$total;
        push @$result, sprintf(qq|used: <font class="%s">%sB/%sB; %.2f%%</font>|,
            percent_bar_style_select($per),
            format_bytes($total-$avail),
            format_bytes($total),
            $per);
    }

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;
    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $used = $data->{PoolUsed};
    my $avail = $data->{PoolFree};
    my $total = 'U';

    $total = $used+$avail
        if $used ne 'U' && $avail ne 'U';

    my $per = $total ne 'U' && $total
        ? 100-(($avail*100)/$total)
        : undef;

    if ($avail eq 'U' || $total eq 'U' || ! $total)
    {   
        $table->addRow("used:", 'unknown');
        $table->addRow("free:", 'unknown');
    }
    else
    {   
        $per = 100 - ($avail*100)/$total;
        $table->addRow("used:", sprintf(qq|<font class="%s">%sB; %.2f%%</font>|,
            percent_bar_style_select($per),
            format_bytes($total-$avail),
            $per));
        $table->addRow("free:", sprintf(qq|%sB; %.2f%%|, format_bytes($avail), 100-$per));
    }
    if ($total eq 'U' || ! $total)
    {
        $table->addRow("total:", 'unknown');
    }
    else
    {
        $table->addRow("total:", sprintf(qq|%sB|, format_bytes($total)));
    }

    my $s = $data->{PoolLargestFree};
    $table->addRow("largest number of contiguous bytes:", $s eq 'U' ? 'unknown' : sprintf(qq|%sB|, format_bytes($s)));

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
    $url_params->{probe} = 'ram';

    my $data = $entity->data;

    $url_params->{probe_prepare_ds} = 'prepare_ds_bytes';

    $url_params->{probe_specific} = 'total_perc';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    return
        if $default_only;

    $url_params->{probe_specific} = 'total';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds';

    $url_params->{probe_specific} = 'PoolLargestFree';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    $rrd_graph->unit('bytes');
    $rrd_graph->title('largest number of contiguous bytes');
}

sub prepare_ds_bytes_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    if ( $url_params->{probe_specific} !~ /_perc$/ )
    {
        $rrd_graph->unit('bytes');
    }
    else
    {
        $rrd_graph->unit('%');
    }

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

    if ($url_params->{probe_specific} eq 'total')
    {
        push @$args, "DEF:ds0u=$rrd_file:PoolUsed:$cf";
        push @$args, "DEF:ds0a=$rrd_file:PoolFree:$cf";
        push @$args, "AREA:ds0u#330099:used";
#        push @$args, "STACK:ds0a#00CC33:available";
    }
    elsif ($url_params->{probe_specific} eq 'total_perc')
    {
        push @$args, "DEF:ds0ub=$rrd_file:PoolUsed:$cf";
        push @$args, "DEF:ds0ab=$rrd_file:PoolFree:$cf";
        push @$args, "CDEF:ds0tb=ds0ub,ds0ab,+";
        push @$args, "CDEF:ds0u=ds0ub,100,*,ds0tb,/";
        push @$args, "CDEF:ds0a=ds0ab,100,*,ds0tb,/";
        push @$args, "AREA:ds0u#330099:used";     
        push @$args, "STACK:ds0a#00CC33:available";
    }

    return ($up, $down, "ds0u");
}

1;
