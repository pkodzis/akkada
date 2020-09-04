package Probe::ram::arrowpoint_old_mib;

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

our $OID = '1.3.6.1.4.1.2467.1.34.17.1';


my $_mem = {
    10 => 'free',
    12 => 'total',
};

sub oids_build
{
    my $self = shift;
    my $index = shift || 0;

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

    my $index = $self->entity->name;
    $index = (split /:/, $index)[1];

    my $result = $session->get_request( -varbindlist => $self->oids_build($index) );
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
        'free' => 'GAUGE',
        'total' => 'GAUGE',
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

    my $total = $ram->{total};
    my $avail = $ram->{free};

    my $per = $total ne 'U' && $avail ne 'U' && $total
        ? 100-(($avail*100)/$total)
        : undef;

    if (! $ram_threshold_bytes_mode && defined $per)
    {
        if ($per >= 99)
        {   
            $self->errmsg(qq|RAM memory full|);
            $self->status(_ST_MAJOR);
        }   
        elsif ($per >= $threshold_high)
        {   
            $self->errmsg(qq|very low RAM memory free space|);
            $self->status(_ST_MINOR);
        }   
        elsif ($per >= $threshold_medium)
        {   
            $self->errmsg(qq|low RAM memory free space|);
            $self->status(_ST_WARNING);
        }   
    }
    elsif ($ram_threshold_bytes_mode && $avail !~ /\D/)
    {  
        my $threshold_high = $self->entity->params('ram_threshold_minimum_bytes') || '64000000';

        if ($avail <= $threshold_high)
        {   
            $self->errmsg(qq|very low RAM memory free space|);
            $self->status(_ST_MAJOR);
        }
    }
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;
    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $per;
    my $avail = $data->{free};
    my $total = $data->{total};

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
}

sub desc_brief
{        
    my ($self, $entity, $result) = @_;

    my $data = $entity->data;
#use Data::Dumper; warn Dumper $data;
    return
        unless scalar keys %$data > 1;

    my $per;
    my $avail = $data->{free};
    my $total = $data->{total};

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
        push @$args, "DEF:ds0tr=$rrd_file:total:$cf";
        push @$args, "DEF:ds0a=$rrd_file:free:$cf";
        push @$args, "CDEF:ds0u=ds0tr,ds0a,-";
        push @$args, "AREA:ds0u#330099:used";
#        push @$args, "STACK:ds0a#00CC33:available";
    }
    elsif ($url_params->{probe_specific} eq 'total_perc')
    {   
        push @$args, "DEF:ds0tb=$rrd_file:total:$cf";
        push @$args, "DEF:ds0ab=$rrd_file:free:$cf";
        push @$args, "CDEF:ds0ub=ds0tb,ds0ab,-";
        push @$args, "CDEF:ds0u=ds0ub,100,*,ds0tb,/";
        push @$args, "CDEF:ds0a=ds0ab,100,*,ds0tb,/";
        push @$args, "AREA:ds0u#330099:used";
        push @$args, "STACK:ds0a#00CC33:available";
    }

    return ($up, $down, "ds0u");
}

1;
