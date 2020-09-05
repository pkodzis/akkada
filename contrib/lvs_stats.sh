#!/usr/bin/perl

#
# this script provides LVS stats data to snmpd agent. 
# should be copied to the server with LVS and
# attached to the snmpd daemon by adding e.g. line to the snmpd.conf
# file:
#
# exec  "<service name>" /usr/local/bin/lvs_stats.pl <virtual server name> [real server]
#
# after snmpd daemon restart AKK@DA will detect new sevice
# and will start to monitor it.  If you need to raise any alarms
# see UCD_EXT probe documentation at http://akkada.tivi.net.pl/
# (mode STAT)
#

use strict;

my $EXEC = '/sbin/ipvsadm';
my $D = {};
my $prot;
my $name;
my $type;
my @tmp;

open F, "$EXEC |";
while (<F>)
{
    next
        if /^IP Virtual|^Prot|RemoteAddress/;
    chomp;

    if (!/  -\>/)
    {
        s/ +/ /;
        ($prot, $name, $type) = split / /, $_;
        $D->{$name}->{prot} = $prot;
        $D->{$name}->{type} = $type;
        $D->{$name}->{summary} = { ActiveConn => 0, InActConn => 0 };
        $D->{$name}->{details} = {};
    }
    elsif ($name)
    {
        s/ +/ /g;
        s/^ //g;
        @tmp = split / /, $_;
        $D->{$name}->{details}->{$tmp[1]} = { Forward => $tmp[2], Weight => $tmp[3], ActiveConn => $tmp[4], InActConn => $tmp[5] };
        $D->{$name}->{summary}->{ActiveConn} += $tmp[4];
        $D->{$name}->{summary}->{InActConn} += $tmp[5];
    }
}
close F;

if (! @ARGV)
{
    usage();
}
elsif (! defined $D->{$ARGV[0]})
{
    print "AKKADA||STAT||output=U::cfs=GAUGE::title=active||output=U::cfs=GAUGE::title=inactive";
}
elsif (@ARGV == 1)
{
    print sprintf(qq/AKKADA||STAT||output=%s::cfs=GAUGE::title=active||output=%s::cfs=GAUGE::title=inactive/, 
        $D->{$ARGV[0]}->{summary}->{ActiveConn},
        $D->{$ARGV[0]}->{summary}->{InActConn});
}
elsif (@ARGV == 2)
{
    if (! defined $D->{$ARGV[0]}->{details}->{$ARGV[1]})
    {
        print "AKKADA||STAT||output=U::cfs=GAUGE::title=active||output=U::cfs=GAUGE::title=inactive";
    }
    else
    {
        print sprintf(qq/AKKADA||STAT||output=%s::cfs=GAUGE::title=active||output=%s::cfs=GAUGE::title=inactive/, 
            $D->{$ARGV[0]}->{details}->{$ARGV[1]}->{ActiveConn},
            $D->{$ARGV[0]}->{details}->{$ARGV[1]}->{InActConn});
    }
}

sub usage
{
    print "usage: $0 <virtual name> [real server]\n\navailable snmpd.conf entries:\n";
    for $name (sort keys %$D)
    {
        print qq|exec "$name virtual server" $0 $name\n|;
        for (sort keys %{$D->{$name}->{details}})
        {
            print qq|exec "$name $_" $0 $name $_\n|;
        }
    }
}

