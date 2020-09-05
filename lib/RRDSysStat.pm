package RRDSysStat;

use strict;
use RRDs;
use POSIX;
use Time::HiRes qw( gettimeofday );

use Configuration;

our $RRDDir = CFG->{Probe}->{RRDDir};
our $FileTmp = CFG->{Web}->{RRDGraph}->{DirTmp};

$FileTmp .= '/'
    unless $FileTmp =~ /\/$/;

sub new 
{
    my $class = shift;
    my $self = {};
    bless $self, $class;

    my $tmp = $ENV{'PATH_INFO'};
    $tmp =~ s/^\///;
    my $tmp = [ split /\//, $tmp ];

    die "missing argument name"
        unless @$tmp && $tmp->[0];

    die "missing argument begin"
        unless @$tmp && $tmp->[1];

    $self->{name} = $tmp->[0];
    $self->{begin} = $tmp->[1];
    $self->{width} = defined $tmp->[2] ? $tmp->[2] : undef;
    $self->{height} = defined $tmp->[3] ? $tmp->[3] : undef;

    return $self;
}

sub name { return $_[0]->{name}; }
sub begin { return $_[0]->{begin}; }
sub width { return $_[0]->{width}; }
sub height { return $_[0]->{height}; }

sub get
{
    my $self = shift;

    my $name = "args_" . $self->name;

    my $args = $self->$name;
#use Data::Dumper; warn Dumper $args;

    my $ft = $FileTmp . gettimeofday . $$;

    $args->[0] = $ft;

    RRDs::graph(@$args);

    my $error = RRDs::error();
    warn $error
        if $error;
    open(H, "<$ft")
        or die "open: $! $ft";

    print STDOUT <H>;
    close(H);

    unlink($ft)
        or warn "unlink \"$ft\": $!";
}

sub args_logs
{
    my $self = shift;

    my $args = [];

    my $rrd_file = sprintf(qq|%s/sysstat.logs|, $RRDDir);

    push @$args, ''; # sub get -> podmienia te wartosc na prawdziwa nazwe pliku

    push @$args, '-g';
    #push @$args, '-j';
    #    if $self->only_graph eq 'on';

    push @$args, '-a', 'PNG';
    push @$args, '--start', $self->begin;
    push @$args, '--end', 'now';
    push @$args, '--slope-mode';
    push @$args, '--interlaced';
    push @$args, '--color', "SHADEA#FFFFFF";
    push @$args, '--color', "SHADEB#FFFFFF";
    push @$args, '--color', "BACK#FFFFFF";
    push @$args, 'HRULE:0#6E6E6B';
    push @$args, "DEF:ds0a=$rrd_file:logs:MAX";
    push @$args, 'CDEF:ds0aa=ds0a,1,*';
    push @$args, 'AREA:ds0aa#333399:average';
    push @$args, 'CDEF:down_up=ds0a,UN,INF,0,IF';
    push @$args, 'AREA:down_up#FFFFCC';
    push @$args, '--width', defined $self->width ? $self->width : '200';
    push @$args, '--height', defined $self->height ? $self->height : '60';

    return $args;
}


sub args_status
{
    my $self = shift;

    my $args = [];

    my $rrd_file = sprintf(qq|%s/sysstat.status|, $RRDDir);

    push @$args, ''; # sub get -> podmienia te wartosc na prawdziwa nazwe pliku

    #push @$args, '-g';
    #push @$args, '-j';
    #    if $self->only_graph eq 'on';

    push @$args, '-a', 'PNG';
    push @$args, '--start', $self->begin;
    push @$args, '--end', 'now';
    push @$args, '--slope-mode';
    push @$args, '--interlaced';
    push @$args, '--color', "SHADEA#FFFFFF";
    push @$args, '--color', "SHADEB#FFFFFF";
    push @$args, '--color', "BACK#FFFFFF";
    push @$args, 'HRULE:0#6E6E6B';
    push @$args, "DEF:nst=$rrd_file:Nostatus:MAX";
    push @$args, 'AREA:nst#dddddd:No status';
    push @$args, "DEF:bcf=$rrd_file:Badconfiguration:MAX";
    push @$args, 'AREA:bcf#FA8072:Bad configuration:STACK';
    push @$args, "DEF:ini=$rrd_file:Init:MAX";
    push @$args, 'AREA:ini#FFFAFA:Init:STACK';
    push @$args, "DEF:unk=$rrd_file:Unknown:MAX";
    push @$args, 'AREA:unk#C0C0C0:Unknown:STACK';
    push @$args, "DEF:war=$rrd_file:Warning:MAX";
    push @$args, 'AREA:war#7FFFD4:Warning:STACK';
    push @$args, "DEF:min=$rrd_file:Minor:MAX";
    push @$args, 'AREA:min#FFFF00:Minor:STACK';
    push @$args, "DEF:maj=$rrd_file:Major:MAX";
    push @$args, 'AREA:maj#FFA500:Major:STACK';
    push @$args, "DEF:dow=$rrd_file:Down:MAX";
    push @$args, 'AREA:dow#FF0000:Down:STACK';
    push @$args, "DEF:nos=$rrd_file:NoSNMP:MAX";
    push @$args, 'AREA:nos#aa00ff:No SNMP:STACK';
    push @$args, "DEF:unr=$rrd_file:Unreachable:MAX";
    push @$args, 'AREA:unr#4444aa:Unreachable:STACK';
    push @$args, "DEF:ok=$rrd_file:OK:MAX";
    push @$args, 'AREA:ok#00ff00:OK:STACK';
    push @$args, 'CDEF:oka=ok,1,*'; #to musi byc na koncu
    push @$args, 'CDEF:down_up=oka,UN,INF,0,IF';
    push @$args, 'AREA:down_up#FFFFCC';
    push @$args, '--width', defined $self->width ? $self->width : '260';
    push @$args, '--height', defined $self->height ? $self->height : '100';

    return $args;
}


sub args_status_unr
{
    my $self = shift;

    my $args = [];

    my $rrd_file = sprintf(qq|%s/sysstat.status|, $RRDDir);

    push @$args, ''; # sub get -> podmienia te wartosc na prawdziwa nazwe pliku

    #push @$args, '-g';
    #push @$args, '-j';
    #    if $self->only_graph eq 'on';

    push @$args, '-a', 'PNG';
    push @$args, '--start', $self->begin;
    push @$args, '--end', 'now';
    push @$args, '--slope-mode';
    push @$args, '--interlaced';
    push @$args, '--color', "SHADEA#FFFFFF";
    push @$args, '--color', "SHADEB#FFFFFF";
    push @$args, '--color', "BACK#FFFFFF";
    push @$args, 'HRULE:0#6E6E6B';
    push @$args, "DEF:unr=$rrd_file:Unreachable:MAX";
    push @$args, 'AREA:unr#4444aa:Unreachable';
    push @$args, "DEF:nos=$rrd_file:NoSNMP:MAX";
    push @$args, 'AREA:nos#aa00ff:No SNMP:STACK';
    push @$args, 'CDEF:unra=unr,1,*'; #to musi byc na koncu
    push @$args, 'CDEF:down_up=unra,UN,INF,0,IF';
    push @$args, 'AREA:down_up#FFFFCC';
    push @$args, '--width',  defined $self->width ? $self->width : '260';
    push @$args, '--height', defined $self->height ? $self->height : '60';

    return $args;
}

1;
