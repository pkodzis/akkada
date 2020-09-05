package Probe::cpu::ucd;

use vars qw($VERSION);

$VERSION = 0.4;

use base qw(Probe::cpu);
use strict;

use Net::SNMP;
use Time::HiRes qw( gettimeofday tv_interval );

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use URLRewriter;


our $DataDir = CFG->{Probe}->{DataDir};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};

our $OID_CPU = '1.3.6.1.4.1.2021.11'; # 50-53, counter
our $OID_LA = '1.3.6.1.4.1.2021.10.1'; # 1 - 3, gauge

use constant
{
    RRD_RESULT => 22,
};

my $_ssCpu = {
    50 => 'ssCpuRawUser',
    51 => 'ssCpuRawNice',
    52 => 'ssCpuRawSystem',
    53 => 'ssCpuRawIdle',
    54 => 'ssCpuRawWait',   #ODPALIC !!!!
    55 => 'ssCpuRawKernel',
    56 => 'ssCpuRawInterrupt',
};  
 
my $_laEntry = {
    2 => 'laNames', #name
    3 => 'laLoad',
    4 => 'laConfig', #mozliwe do nadpiania parameterami cpu_la_threshhold
    100 => 'laErrorFlag', #0: ok; 1: error
    101 => 'laErrMessage',#errmsg
};  
 
my $_laName = {
    1 => 'Load-1',
    2 => 'Load-5',
    3 => 'Load-15',
}; 

sub rrd_load_data
{
    my $self = shift;
    return ($self->rrd_config, $self->rrd_result);
}

sub rrd_result
{
    return $_[0]->[RRD_RESULT];
}

sub oids_build
{
    my $self = shift;

    my @oids = ();

    for (keys %$_ssCpu)
    {
        push @oids, "$OID_CPU.$_.0";
    }
    for (keys %$_laEntry)
    {
        push @oids, "$OID_LA.$_.1";
        push @oids, "$OID_LA.$_.2";
        push @oids, "$OID_LA.$_.3";
    }
    return \@oids;
}

sub entity_test
{
    my $self = shift;
    my $session = $self->session;

    $self->[RRD_RESULT] = $self->rrd_config;
    my $rru = $self->[RRD_RESULT];
    @$rru{ keys %$rru } = ('U') x scalar keys %$rru;

    my $result = $session->get_request( -varbindlist => $self->oids_build() );
    my $error = $session->error();
#use Data::Dumper; print Dumper($result);
    if (! $error )
    {   
        $self->result_dispatch($result);

        $self->cache_update($self->entity->id_entity, $self->cpu);
        $self->utilization_status;
    }
    else
    {   
        $self->errmsg('snmp error: ' . $error);
        $self->status(_ST_MAJOR);
    }
}

sub cache_keys
{
    return 
    [
        'ssCpuRawUser',
        'ssCpuRawNice',
        'ssCpuRawSystem',
        'ssCpuRawIdle',
        'ssCpuRawWait',
        'ssCpuRawKernel',
        'ssCpuRawInterrupt',
    ];
}

sub rrd_config
{
    return
    {   
        'ssCpuRawUser' => 'COUNTER',
        'ssCpuRawNice' => 'COUNTER',
        'ssCpuRawSystem' => 'COUNTER',
        'ssCpuRawIdle' => 'COUNTER',
        'ssCpuRawWait' => 'COUNTER',
        'ssCpuRawKernel' => 'COUNTER',
        'ssCpuRawInterrupt' => 'COUNTER',
        'Load-1' => 'GAUGE',
        'Load-5' => 'GAUGE',
        'Load-15' => 'GAUGE',
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
    my $la = $self->la;
    my $key;
    my @ar;

    my $rru = $self->rrd_result;

    for (keys %$result)
    {   
        $key = $_;

        if (/^$OID_CPU\./)
        {
            s/^$OID_CPU\.//g;
            s/\.0$//g;
            $cpu->{ $_ssCpu->{$_} } = $result->{$key};

            $rru->{ $_ssCpu->{$_} } = $result->{$key} eq '' ? 'U' : $result->{$key}
                if defined $rru->{ $_ssCpu->{$_} };

        } 
        elsif (/^$OID_LA\./)
        {
            s/^$OID_LA\.//g;
            @ar = split /\./, $_;
            $la->{ $ar[1] }->{ $_laEntry->{$ar[0]} } = $result->{$key};
            if ( $_laEntry->{$ar[0]} eq 'laLoad' )
            {
                $rru->{ $_laName->{$ar[1]} } = $result->{$key}
            }
        }
    }
#use Data::Dumper; log_debug("DUPA" . Dumper($self->entity->id_entity, $self->cpu, $self->la, $self->rrd_result), _LOG_DEBUG);
#use Data::Dumper; log_debug("XXX:" . $self->entity->id_entity . ":" . $self->rrd_result->{ssCpuRawIdle}, _LOG_DEBUG);
}

sub probe_name
{
    return "cpu";
}

sub utilization_status
{   
    my $self = shift;
    my $cpu = $self->cpu;
    my $la = $self->la;

    my $threshold;
    my $entity = $self->entity;

    my $cpu_stop_warning_high_utilization = $entity->params('cpu_stop_warning_high_utilization');

    for my $i (keys %$la)
    {
         if ($i == 1)
         {
             $threshold = $entity->params('cpu_ucd_la_1_threshhold');
         }
         elsif ($i == 2)
         {
             $threshold = $entity->params('cpu_ucd_la_5_threshhold');
         }
         elsif ($i == 3)
         {
             $threshold = $entity->params('cpu_ucd_la_15_threshhold');
         }
         if ($threshold)
         {
             if ($la->{$i}->{laLoad} > $threshold)
             {
                 $self->errmsg(sprintf(qq|manualy set %s threshold %.2f exceeded: %.2f|,
                     $la->{$i}->{laName}, $threshold, $la->{$i}->{laLoad}));
                 $self->status(_ST_MAJOR);
             }
         }
         if ($la->{$i}->{laErrorFlag})
         {
             $self->errmsg($la->{$i}->{laErrMessage});
             $self->status(_ST_MAJOR);
         }
    }

    my $cpu_p;
    my $cpu_sum = 0;

    my $ch = $self->cache->{ $entity->id_entity };

    for (keys %$ch)
    {
        next
            if $_ eq 'delta' || $_ eq 'timestamp';
        $cpu_sum += $ch->{$_}->[1]
            unless $ch->{$_}->[1] eq 'U';
    }

    return
        unless $cpu_sum;

    my $cpu_agg = 0;

    for (keys %$ch)
    {
        next
            if $_ eq 'delta' || $_ eq 'timestamp' || $_ eq 'ssCpuRawIdle';
        next
            if $ch->{$_}->[1] eq 'U';

        $cpu_p = ($ch->{$_}->[1]*100)/ $cpu_sum;
        $cpu_agg += $cpu_p;

        $_ =~ s/^ssCpuRaw//g;
        $_ = lc $_;

        if ($cpu_p >= $self->threshold_high)
        {
            $self->errmsg(sprintf(qq|high %s CPU utilization|, $_));
            $self->status(_ST_MINOR)
                unless $cpu_stop_warning_high_utilization;
        }
        elsif ($cpu_p >= $self->threshold_medium)
        {
            $self->errmsg(sprintf(qq|medium %s CPU utilization|, $_));
            $self->status(_ST_WARNING)
                unless $cpu_stop_warning_high_utilization;
        }
    }

    top_save($entity->id_entity, 'cpu', $cpu_agg)
        unless $cpu_stop_warning_high_utilization;

    if ( $self->entity->params('cpu_ucd_utilization_aggregate'))
    {
        if ($cpu_agg >= $self->threshold_high)
        {
            $self->errmsg(sprintf(qq|high aggregated CPU utilization|));
            $self->status(_ST_MINOR)
                unless $cpu_stop_warning_high_utilization;
        }
        elsif ($cpu_agg >= $self->threshold_medium)
        {
            $self->errmsg(sprintf(qq|medium aggregated CPU utilization|));
            $self->status(_ST_WARNING)
                unless $cpu_stop_warning_high_utilization;
        }
    }
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;

    my $data_dir = $DataDir;

    open F, ">$data_dir/$id_entity";

    my $c = $self->rrd_config;

    my $ch  = $self->cache->{ $id_entity };
    for ( keys %$ch )
    {   
        print F "$_\|$ch->{$_}->[1]\n"
            if defined $c->{$_};
    }

    my $h = $self->rrd_result;
    for (1..3)
    {
        print F "$_laName->{$_}|$h->{ $_laName->{$_} }\n";
    }

    close F;

}

sub desc_brief
{   
    my ($self, $entity, $result) = @_;

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $cpu_s;
    my $cpu_u;
    for my $key (keys %$data)
    {
        next
            unless $key =~ /^ssCpu/;
        if ($data->{$key} =~ /\D/)
        {
            $cpu_s += $data->{$key};
            $cpu_u += $data->{$key}
                if $key ne 'ssCpuRawIdle';
#warn $key, ": ",$cpu_s, " ", $cpu_u;
        }
    }

    if ($cpu_s)
    {
         my $p = ($cpu_u*100)/$cpu_s;
         push @$result, sprintf(qq|usage: <font class="%s">%.2f%%</font>|, percent_bar_style_select($p), $p);
    }
    else
    {
        push @$result, "usage: unknown";
    }

    push @$result, sprintf(qq|load avg: %.2f\|%.2f\|%.2f|, 
        defined $data->{'Load-1'} ? $data->{'Load-1'} : 'n/a',
        defined $data->{'Load-5'} ? $data->{'Load-5'} : 'n/a',
        defined $data->{'Load-15'} ? $data->{'Load-15'} : 'n/a');

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;
    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

#use Data::Dumper; $table->addRow("<pre>" . Dumper($data) . "</pre>");

    my $cpu_s;
    for (keys %$data)
    {
        next
            unless $_ =~ /^ssCpu/;
        $cpu_s += $data->{$_}
            if $data->{$_} =~ /\D/;
    }

    if ($cpu_s)
    {
        my ($p, $r, $n);
        for (sort keys %$_ssCpu)
        {
            $n = $_ssCpu->{$_};
            $r = $data->{ $n };
            $p = ($r*100)/$cpu_s;
            $n =~ s/^ssCpuRaw//g;
            $n = lc $n;
            if ($n eq 'idle')
            {
                $table->addRow(qq|$n:|, sprintf(qq|%.2f%%|, $p), sprintf(qq|%.2f ticks|, $r));
            }
            elsif ($r eq 'U')
            {
                $table->addRow("$n:", ' unknown ');
            }
            else
            {
                $table->addRow(qq|$n:|, sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($p), $p),
                    sprintf(qq|%.2f ticks|, $r));
            }
        }
    }
    else
    {
        for my $n (keys %$_ssCpu)
        {
            $n = $_ssCpu->{$n};
            $n =~ s/^ssCpuRaw//g;
            $n = lc $n;
            $table->addRow("$n:", ' unknown ');
        }
    }
    $table->addRow('');

    $table->addRow("load (1min):", sprintf(qq|%.2f|, $data->{'Load-1'}));
    $table->addRow("load (5min):", sprintf(qq|%.2f|, $data->{'Load-5'}));
    $table->addRow("load (15min):", sprintf(qq|%.2f|, $data->{'Load-15'}));

    if ($cpu_s)
    {
        my $i = $table->getTableRows;
        $table->setCellColSpan($i - 3, 1, 3);
        for ($i - 2 .. $i)
        {
            $table->setCellColSpan($_, 2, 2);
        }
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
    my $default_only = defined @_ ? shift : 0;
    
    my $url;
    $url_params->{probe} = 'cpu';
        
    $url_params->{probe_prepare_ds} = 'prepare_ds_adv';
    $url_params->{probe_specific} = 'percent';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    
    $url_params->{probe_prepare_ds} = 'prepare_ds_adv';
    $url_params->{probe_specific} = 'load';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
   
    return
        if $default_only;
 
    $url_params->{probe_prepare_ds} = 'prepare_ds_adv';
    $url_params->{probe_specific} = 'ticks';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    
}

sub prepare_ds_adv_pre
{   
    my $self = shift;
    my $rrd_graph = shift;
    my $url_params = $rrd_graph->url_params;

    if ($url_params->{probe_specific} eq 'load')
    {
        $rrd_graph->unit('no.');
        $rrd_graph->title('average load');
    }
    elsif ($url_params->{probe_specific} eq 'ticks')
    {
        $rrd_graph->unit('ticks');
        $rrd_graph->title('raw usage');
    }
    elsif ($url_params->{probe_specific} eq 'percent')
    {
        $rrd_graph->unit('%');
        $rrd_graph->title('usage');
    }
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

    my $fillIdleOnGraphsPercent = CFG->{Probes}->{cpu}->{ucd}->{fillIdleOnGraphsPercent};
    my $fillIdleOnGraphsRaw = CFG->{Probes}->{cpu}->{ucd}->{fillIdleOnGraphsRaw};

    if ($url_params->{probe_specific} eq 'load')
    {
        push @$args, "DEF:ds01=$rrd_file:Load-1:$cf";
        push @$args, "DEF:ds02=$rrd_file:Load-5:$cf";
        push @$args, "DEF:ds03=$rrd_file:Load-15:$cf";
        push @$args, "LINE1:ds03#CC9933:15 min";
        push @$args, "LINE1:ds02#CC3333:5 min";
        push @$args, "LINE1:ds01#FFFF33:1 min";
        return (1, 0, "ds01");
    }
    elsif ($url_params->{probe_specific} eq 'ticks')
    {
        push @$args, "DEF:dsS=$rrd_file:ssCpuRawSystem:$cf";
        push @$args, "AREA:dsS#CC0099:system";

        push @$args, "DEF:dsN=$rrd_file:ssCpuRawNice:$cf";
        push @$args, "STACK:dsN#669966:nice";

        push @$args, "DEF:dsU=$rrd_file:ssCpuRawUser:$cf";
        push @$args, "STACK:dsU#FF6600:user";

        push @$args, "DEF:dsW=$rrd_file:ssCpuRawWait:$cf";
        push @$args, "STACK:dsW#FFFF33:wait";

        push @$args, "DEF:dsK=$rrd_file:ssCpuRawKernel:$cf";
        push @$args, "STACK:dsK#99CCFF:kernel";

        push @$args, "DEF:dsIn=$rrd_file:ssCpuRawInterrupt:$cf";
        push @$args, "STACK:dsIn#663333:interrupt";

        push @$args, "DEF:dsI=$rrd_file:ssCpuRawIdle:$cf";
        push @$args, "STACK:dsI#00FF66:idle"
            if $fillIdleOnGraphsRaw;

        return (1, 0, "dsU");
    }
    elsif ($url_params->{probe_specific} eq 'percent')
    {
        push @$args, "DEF:dsS=$rrd_file:ssCpuRawSystem:$cf";
        push @$args, "DEF:dsN=$rrd_file:ssCpuRawNice:$cf";
        push @$args, "DEF:dsU=$rrd_file:ssCpuRawUser:$cf";
        push @$args, "DEF:dsW=$rrd_file:ssCpuRawWait:$cf";
        push @$args, "DEF:dsK=$rrd_file:ssCpuRawKernel:$cf";
        push @$args, "DEF:dsIn=$rrd_file:ssCpuRawInterrupt:$cf";
        push @$args, "DEF:dsI=$rrd_file:ssCpuRawIdle:$cf";

        push @$args, "CDEF:psS=dsS,UN,0,dsS,IF";
        push @$args, "CDEF:psN=dsN,UN,0,dsN,IF";
        push @$args, "CDEF:psU=dsU,UN,0,dsU,IF";
        push @$args, "CDEF:psW=dsW,UN,0,dsW,IF";
        push @$args, "CDEF:psK=dsK,UN,0,dsK,IF";
        push @$args, "CDEF:psIn=dsIn,UN,0,dsIn,IF";
        push @$args, "CDEF:psI=dsI,UN,0,dsI,IF";

        push @$args, "CDEF:total=psS,psN,+,psU,+,psW,+,psK,+,psIn,+,psI,+";
        push @$args, "CDEF:pdsS=psS,100,*,total,/";
        push @$args, "CDEF:pdsN=psN,100,*,total,/";
        push @$args, "CDEF:pdsU=psU,100,*,total,/";
        push @$args, "CDEF:pdsW=psW,100,*,total,/";
        push @$args, "CDEF:pdsK=psK,100,*,total,/";
        push @$args, "CDEF:pdsIn=psIn,100,*,total,/";
        push @$args, "CDEF:pdsI=psI,100,*,total,/";

        push @$args, "AREA:pdsS#CC0099:system";
        push @$args, "STACK:pdsN#669966:nice";
        push @$args, "STACK:pdsU#FF6600:user";
        push @$args, "STACK:pdsW#FFFF33:wait";
        push @$args, "STACK:pdsK#99CCFF:kernel";
        push @$args, "STACK:pdsIn#663333:interrupt";
        push @$args, "STACK:pdsI#00FF66:idle"
            if $fillIdleOnGraphsPercent;


        return (1, 0, "dsU");
    }
}

1;
