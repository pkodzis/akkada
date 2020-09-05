#!/akkada/bin/perl

use lib "$ENV{AKKADA}/lib";
use Configuration;

$dirname = CFG->{Probe}->{LastCheckDir};


my $perf_delta;
my $perf_last_check;

my $total = 0;

opendir(DIR, $dirname) or die "can't opendir $dirname: $!";
while (defined($file = readdir(DIR))) {
    next
        unless $file =~ /^[0-9].+$/;
    open F, "+<$dirname/$file";
    seek(F, 0, 0);
    @s = split /:/, <F>;
    close F;
    ++$total;
$perf_delta->{$s[1]}++;
$perf_last_check->{ time - $s[0] }++;
    #print $file, ": ", time - $s[0], "\n";
}
closedir(DIR);

my $pr;

for (sort { $a <=> $b } keys %$perf_delta)
{
    if ($_ < 61) { $pr->{60} = $pr->{60} + $perf_delta->{$_}; }
#    elsif ($_ < 62) { $pr->{61} = $pr->{61} + $perf_delta->{$_}; }
#    elsif ($_ < 63) { $pr->{62} = $pr->{62} + $perf_delta->{$_}; }
#    elsif ($_ < 64) { $pr->{63} = $pr->{63} + $perf_delta->{$_}; }
#    elsif ($_ < 65) { $pr->{64} = $pr->{64} + $perf_delta->{$_}; }
    elsif ($_ < 66) { $pr->{65} = $pr->{65} + $perf_delta->{$_}; }
    elsif ($_ < 71) { $pr->{70} = $pr->{70} + $perf_delta->{$_}; }
    elsif ($_ < 76) { $pr->{75} = $pr->{75} + $perf_delta->{$_}; }
    elsif ($_ < 81) { $pr->{80} = $pr->{80} + $perf_delta->{$_}; }
    elsif ($_ < 86) { $pr->{85} = $pr->{85} + $perf_delta->{$_}; }
    elsif ($_ < 91) { $pr->{90} = $pr->{90} + $perf_delta->{$_}; }
    elsif ($_ < 121) { $pr->{120} = $pr->{120} + $perf_delta->{$_}; }
    elsif ($_ < 151) { $pr->{150} = $pr->{150} + $perf_delta->{$_}; }
    elsif ($_ < 181) { $pr->{180} = $pr->{180} + $perf_delta->{$_}; }
    elsif ($_ < 211) { $pr->{210} = $pr->{210} + $perf_delta->{$_}; }
    elsif ($_ < 241) { $pr->{240} = $pr->{240} + $perf_delta->{$_}; }
    elsif ($_ > 240) { $pr->{241} = $pr->{241} + $perf_delta->{$_}; }
}

my $rr;
for (sort { $a <=> $b } keys %$perf_last_check)
{
    if ($_ < 61) { $rr->{60} = $rr->{60} + $perf_last_check->{$_}; }
    elsif ($_ < 66) { $rr->{65} = $rr->{65} + $perf_last_check->{$_}; }
    elsif ($_ < 71) { $rr->{70} = $rr->{70} + $perf_last_check->{$_}; }
    elsif ($_ < 76) { $rr->{75} = $rr->{75} + $perf_last_check->{$_}; }
    elsif ($_ < 81) { $rr->{80} = $rr->{80} + $perf_last_check->{$_}; }
    elsif ($_ < 86) { $rr->{85} = $rr->{85} + $perf_last_check->{$_}; }
    elsif ($_ < 91) { $rr->{90} = $rr->{90} + $perf_last_check->{$_}; }
    elsif ($_ < 121) { $rr->{120} = $rr->{120} + $perf_last_check->{$_}; }
    elsif ($_ < 151) { $rr->{150} = $rr->{150} + $perf_last_check->{$_}; }
    elsif ($_ < 181) { $rr->{180} = $rr->{180} + $perf_last_check->{$_}; }
    elsif ($_ < 211) { $rr->{210} = $rr->{210} + $perf_last_check->{$_}; }
    elsif ($_ < 241) { $rr->{240} = $rr->{240} + $perf_last_check->{$_}; }
    elsif ($_ > 240) { $rr->{241} = $rr->{241} + $perf_last_check->{$_}; }
}

my $short = $ARGV[0];

print "delta report:\n";
for (sort { $a <=> $b } keys %{ $short ? $pr : $perf_delta })
{
    print sprintf("%s: %s\n", $_, $short ? $pr->{$_} : $perf_delta->{$_});
}

print "last check:\n";
for (sort { $a <=> $b } keys %{ $short ? $rr : $perf_last_check })
{
    print sprintf("%s: %s\n", $_, $short ? $rr->{$_} : $perf_last_check->{$_});
}

print "\ntotal entities count: $total\n";
