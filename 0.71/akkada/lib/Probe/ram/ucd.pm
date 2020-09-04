package Probe::ram::ucd;

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

our $OID = '1.3.6.1.4.1.2021.4';

my $_mem = {
    3 => 'memTotalSwap',
    4 => 'memAvailSwap',
    5 => 'memTotalReal',
    6 => 'memAvailReal',
    7 => 'memTotalSwapTXT',
    8 => 'memAvailSwapTXT',
    9 => 'memTotalRealTXT',
    10 => 'memAvailRealTXT',
    11  => 'memTotalFree',
    13 => 'memShared',
    14 => 'memBuffer',
    15 => 'memCached',
    101 => 'memSwapErrorMsg',
};

sub oids_build
{
    my $self = shift;

    my @oids = ();

    for (keys %$_mem)
    {
        push @oids, "$OID.$_.0";
    }

#use Data::Dumper; print Dumper(\@oids); 
    return \@oids;
}

sub entity_test
{
    my $self = shift;
    my $session = $self->session;

    my $result = $session->get_request( -varbindlist => $self->oids_build() );
#use Data::Dumper; print Dumper($result);
    my $error = $session->error();
    if (! $error )
    {
        $self->result_dispatch($result);

#use Data::Dumper; print Dumper($self->ram);
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
        'memTotalSwap' => 'GAUGE',
        'memAvailSwap' => 'GAUGE',
        'memTotalReal' => 'GAUGE',
        'memAvailReal' => 'GAUGE',
        'memTotalSwapTXT' => 'GAUGE',
        'memAvailSwapTXT' => 'GAUGE',
        'memTotalRealTXT' => 'GAUGE',
        'memAvailRealTXT' => 'GAUGE',
        'memTotalFree' => 'GAUGE',
        'memShared' => 'GAUGE',
        'memBuffer' => 'GAUGE',
        'memCached' => 'GAUGE',
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

            if ($_mem->{$index} ne 'memSwapErrorMsg')
            {
                if ($result->{$key} !~ /\D/ && $result->{$key} ne '')
                {
                    $ram->{ $_mem->{$index} } *= 1024;
                }
                else
                {
                    $ram->{ $_mem->{$index} } = 'U';
                }
            }
        }
    }
}

sub probe_name
{
    return "ram";
}

sub utilization_status_common
{
    my $self = shift;

    my $ram_threshold_bytes_mode = shift;

    my $threshold_medium = shift;
    my $threshold_high = shift;

    my $total = shift;
    my $avail = shift;
    my $name = shift;

    my $per = $total ne 'U' && $avail ne 'U' && $total
        ? 100-(($avail*100)/$total)
        : undef;

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

sub utilization_status
{   
    my $self = shift;
    my $ram = $self->ram;
    my $entity = $self->entity;

    my $ram_threshold_bytes_mode = $entity->params('ram_threshold_bytes_mode') || 0;

    my $threshold_medium = $self->threshold_medium;
    my $threshold_high = $self->threshold_high;

    $self->utilization_status_common($ram_threshold_bytes_mode, $threshold_medium, $threshold_high, 
        $ram->{memTotalSwap}, $ram->{memAvailSwap}, 'swap')
        unless $entity->params('ram_disable_memory_full_alarm_swap');
    $self->utilization_status_common($ram_threshold_bytes_mode, $threshold_medium, $threshold_high, 
        $ram->{memTotalReal}, $ram->{memAvailReal}, 'real')
        unless $entity->params('ram_disable_memory_full_alarm_real');

    $self->utilization_status_common($ram_threshold_bytes_mode, $threshold_medium, $threshold_high, 
        $ram->{memTotalSwapTXT}, $ram->{memAvailSwapTXT}, 'swap text')
        unless $entity->params('ram_disable_memory_full_alarm_swap');
    $self->utilization_status_common($ram_threshold_bytes_mode, $threshold_medium, $threshold_high, 
        $ram->{memTotalRealTXT}, $ram->{memAvailRealTXT}, 'real text')
        unless $entity->params('ram_disable_memory_full_alarm_real');

    $self->utilization_status_common($ram_threshold_bytes_mode, $threshold_medium, $threshold_high, 
        $ram->{memTotalReal}+$ram->{memTotalSwap}, $ram->{memTotalFree}, 'total (real+swap)')
        unless $ram->{memTotalSwap} eq 'U'
        || $ram->{memTotalReal} eq 'U'
        || $entity->params('ram_disable_memory_full_alarm_total');

    if ($ram->{memSwapErrorMsg})
    {
        $self->errmsg(sprintf(qq|snmp agent error message: %s|, $ram->{memSwapErrorMsg}));
        $self->status(_ST_MAJOR);
    }
}

sub desc_brief
{   
    my ($self, $entity, $result) = @_;

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $per;
    my $total = $data->{'memTotalReal'}+$data->{'memTotalSwap'};
    my $avail = $data->{'memTotalFree'};

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

    $self->desc_full_rows_common($table, $entity, $data->{'memTotalReal'}+$data->{'memTotalSwap'},
        $data->{'memTotalFree'}, '');    

    $table->addRow();
    $table->setCellColSpan($table->getTableRows, 1, 2);

    $self->desc_full_rows_common($table, $entity, $data->{'memTotalReal'}, $data->{'memAvailReal'}, 'real');    
    $self->desc_full_rows_common($table, $entity, $data->{'memTotalSwap'}, $data->{'memAvailSwap'}, 'swap');    
    $self->desc_full_rows_common($table, $entity, $data->{'memTotalRealTXT'}, $data->{'memAvailRealTXT'}, 'real text')
        if $data->{'memTotalRealTXT'} ne 'U';
    $self->desc_full_rows_common($table, $entity, $data->{'memTotalSwapTXT'}, $data->{'memAvailSwapTXT'}, 'swap text')
        if $data->{'memTotalSwapTXT'} ne 'U';

    $table->addRow();
    $table->setCellColSpan($table->getTableRows, 1, 2);

    my $s = $data->{memShared};
    $table->addRow("shared memory:", $s eq 'U' ? 'unknown' : sprintf(qq|%sB|, format_bytes($s)));
    $s = $data->{memBuffer};
    $table->addRow("buffered memory:", $s eq 'U' ? 'unknown' : sprintf(qq|%sB|, format_bytes($s)));
    $s = $data->{memCached};
    $table->addRow("cached memory:", $s eq 'U' ? 'unknown' : sprintf(qq|%sB|, format_bytes($s)));


}

sub desc_full_rows_common
{
    my ($self, $table, $entity, $total, $avail, $name) = @_; 
    my $per;

    if ($avail eq 'U' || $total eq 'U' || ! $total)
    {
        $table->addRow("used $name:", 'unknown');
        $table->addRow("free $name:", 'unknown');
    }
    else
    {
        $per = 100 - ($avail*100)/$total; 
        $table->addRow("used $name:", sprintf(qq|<font class="%s">%sB; %.2f%%</font>|,
            percent_bar_style_select($per),
            format_bytes($total-$avail),
            $per)); 
        $table->addRow("free $name:", sprintf(qq|%sB; %.2f%%|, format_bytes($avail), 100-$per)); 
    }
    if ($total eq 'U' || ! $total)
    {
        $table->addRow("total $name:", 'unknown');
    }  
    else
    {
        $table->addRow("total $name:", sprintf(qq|%sB|, format_bytes($total)));
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

    $url_params->{probe_specific} = 'real_perc';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'swap_perc';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'total';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'real';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'swap';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    if ($data->{'memTotalRealTXT'} ne 'U')
    {
        $url_params->{probe_specific} = 'real text';
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    }

    if ($data->{'memTotalSwapTXT'} ne 'U')
    {
        $url_params->{probe_specific} = 'swap text';
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    }

    $url_params->{probe_prepare_ds} = 'prepare_ds';

    $url_params->{probe_specific} = 'memShared';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'memBuffer';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'memCached';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    if ( $url_params->{probe_specific} eq 'memShared')
    {
        $rrd_graph->unit('bytes');
        $rrd_graph->title('total shared memory');
    }
    elsif ( $url_params->{probe_specific} eq 'memBuffer')
    {
        $rrd_graph->unit('bytes');
        $rrd_graph->title('total buffered memory');
    }
    elsif ( $url_params->{probe_specific} eq 'memCached')
    {
        $rrd_graph->unit('bytes');
        $rrd_graph->title('total cached memory');
    }
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

    my $title = $url_params->{probe_specific};

    $title =~ s/_perc$//g;
    $rrd_graph->title($title . ' memory usage');
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
        push @$args, "DEF:ds0tr=$rrd_file:memTotalReal:$cf";
        push @$args, "DEF:ds0ts=$rrd_file:memTotalSwap:$cf";
        push @$args, "DEF:ds0a=$rrd_file:memTotalFree:$cf";
        push @$args, "CDEF:ds0u=ds0tr,ds0ts,+,ds0a,-";
        push @$args, "AREA:ds0u#330099:used";
    #    push @$args, "STACK:ds0a#00CC33:available";
    }
    elsif ($url_params->{probe_specific} eq 'total_perc')
    {
        push @$args, "DEF:ds0tr=$rrd_file:memTotalReal:$cf";
        push @$args, "DEF:ds0ts=$rrd_file:memTotalSwap:$cf";
        push @$args, "DEF:ds0ab=$rrd_file:memTotalFree:$cf";
        push @$args, "CDEF:ds0tb=ds0tr,ds0ts,+";
        push @$args, "CDEF:ds0ub=ds0tb,ds0ab,-";
        push @$args, "CDEF:ds0u=ds0ub,100,*,ds0tb,/";
        push @$args, "CDEF:ds0a=ds0ab,100,*,ds0tb,/";
        push @$args, "AREA:ds0u#330099:used";     
        push @$args, "STACK:ds0a#00CC33:available";
    }
    elsif ($url_params->{probe_specific} eq 'real')
    {
        push @$args, "DEF:ds0tr=$rrd_file:memTotalReal:$cf";
        push @$args, "DEF:ds0a=$rrd_file:memAvailReal:$cf";
        push @$args, "CDEF:ds0u=ds0tr,ds0a,-";
        push @$args, "AREA:ds0u#330099:used";
    #    push @$args, "STACK:ds0a#00CC33:available";
    }
    elsif ($url_params->{probe_specific} eq 'real_perc')
    {   
        push @$args, "DEF:ds0tb=$rrd_file:memTotalReal:$cf";
        push @$args, "DEF:ds0ab=$rrd_file:memAvailReal:$cf";
        push @$args, "CDEF:ds0ub=ds0tb,ds0ab,-";
        push @$args, "CDEF:ds0u=ds0ub,100,*,ds0tb,/";
        push @$args, "CDEF:ds0a=ds0ab,100,*,ds0tb,/";
        push @$args, "AREA:ds0u#330099:used";
        push @$args, "STACK:ds0a#00CC33:available";
    }
    elsif ($url_params->{probe_specific} eq 'swap')
    {
        push @$args, "DEF:ds0tr=$rrd_file:memTotalSwap:$cf";
        push @$args, "DEF:ds0a=$rrd_file:memAvailSwap:$cf";
        push @$args, "CDEF:ds0u=ds0tr,ds0a,-";
        push @$args, "AREA:ds0u#330099:used";
    #    push @$args, "STACK:ds0a#00CC33:available";
    }
    elsif ($url_params->{probe_specific} eq 'swap_perc')
    {   
        push @$args, "DEF:ds0tb=$rrd_file:memTotalSwap:$cf";
        push @$args, "DEF:ds0ab=$rrd_file:memAvailSwap:$cf";
        push @$args, "CDEF:ds0ub=ds0tb,ds0ab,-";
        push @$args, "CDEF:ds0u=ds0ub,100,*,ds0tb,/";
        push @$args, "CDEF:ds0a=ds0ab,100,*,ds0tb,/";
        push @$args, "AREA:ds0u#330099:used";
        push @$args, "STACK:ds0a#00CC33:available";
    }
    elsif ($url_params->{probe_specific} eq 'real text')
    { 
        push @$args, "DEF:ds0tr=$rrd_file:memTotalRealTXT:$cf";
        push @$args, "DEF:ds0a=$rrd_file:memAvailRealTXT:$cf";
        push @$args, "CDEF:ds0u=ds0tr,ds0a,-";
        push @$args, "AREA:ds0u#330099:used";
        push @$args, "STACK:ds0a#00CC33:available";
    } 
    elsif ($url_params->{probe_specific} eq 'swap text')
    {
        push @$args, "DEF:ds0tr=$rrd_file:memTotalSwapTXT:$cf";
        push @$args, "DEF:ds0a=$rrd_file:memAvailSwapTXT:$cf";
        push @$args, "CDEF:ds0u=ds0tr,ds0a,-";
        push @$args, "AREA:ds0u#330099:used";     
        push @$args, "STACK:ds0a#00CC33:available";
    }

    return ($up, $down, "ds0u");
}

1;
