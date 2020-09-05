#!/usr/bin/perl -w

use lib "$ENV{AKKADA}/lib";
use Common;

die "missing password"
    unless @ARGV;
print Common::crypt_pass(shift);
print "\n";

