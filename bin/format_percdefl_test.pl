#!/usr/bin/perl

print "usage: $0 <low base> <high base> <value>\n"
    if @ARGV < 3;
exit
    if @ARGV < 3;

$vlow = $ARGV[0];
$vhigh = $ARGV[1];
$value = $ARGV[2];

print "you entered - low: $ARGV[0]; high: $ARGV[1]; value: $ARGV[2]\n";

$value = $vlow
    if $value < $vlow;
$value = $vhigh
    if $value > $vhigh;

$z = $value - $vlow;
$vhigh = $vhigh- $vlow;
$vlow = 0;

print "after translation - low: $vlow; high: $vhigh; value: $z\n";

$pol = $vhigh/2;

print "deflection range: 0 - $pol\n";

if ($z < $pol)
{
    $x = 100 - $z*100/$pol;
}
else
{
    $z = $z - $pol;
    $x = $z *100/$pol;
}

print "deflection: $x %\n";
