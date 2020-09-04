#!/usr/bin/perl

use strict;

if (! defined $ENV{AKKADA})
{
    print "not defined env variable AKKADA\n";
    exit;
}

my $cfg = do "$ENV{AKKADA}/etc/akkada.conf";

use Data::Dumper;
$Data::Dumper::Indent = 1;

print Dumper $cfg;



