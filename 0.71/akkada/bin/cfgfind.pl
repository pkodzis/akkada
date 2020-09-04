#!/usr/bin/perl

use strict;

my @look = @ARGV;

usage()
    unless @look;

if (! defined $ENV{AKKADA})
{
    print "not defined env variable AKKADA\n";
    exit;
}
else
{
    my @w = ( $ENV{AKKADA}, "$ENV{AKKADA}/etc" );
    for (@w)
    {
        if (! -e $_)
        {
            print "directory does not exists: $_\n";
            exit;
        }
    }
}

my $find = `which find`;
$find =~ s/\n//g;
if (! -e $find)
{
    print "find file not available in paths\n";
    exit;
}

my $grep = `which grep`;
$grep=~ s/\n//g;
if (! -e $grep)
{
    print "find file not available in paths\n";
    exit;
}

my @files;

open F, qq($find $ENV{AKKADA}/etc -type f -exec $grep -H "do \"\\$ENV" {} \\; |);
while (<F>)
{
    chomp;
    s/,//g;
    s/'//g;
    s/"//g;
    s/\s+//g;
    push @files, [ split /:/, $_, 2 ];
    $files[$#files]->[1] = (split /\=\>do/, $files[$#files]->[1], 2)[1];
    $files[$#files]->[1] =~ s/\$ENV\{AKKADA\}/$ENV{AKKADA}/g;
}
close F;

my @result;
my $cfg = do "$ENV{AKKADA}/etc/akkada.conf";

my $f = $cfg;
my @seen;

for (@look)
{
    push @seen, $_;
    if (defined $f->{$_})
    {
        $f = $f->{$_};
    }
    else
    {
        print "unknown option: " . join(" ", @seen) . "\n";
        exit;
    }
}

use Data::Dumper;
$Data::Dumper::Indent = 1;
$f = Dumper $f;
$f =~ s/\$VAR1 = //g;
print sprintf(qq|option "%s" found in files:\n\n|, join(" ", @seen));

my $i = 0;
my $g;

do
{
    $g = join("/", @seen) . ".conf";
    for (@files)
    {
        if ($_->[1] =~ /$g/)
        {
           ++$i;
           print $_->[1], "\n"
        }
    }
    pop @seen;
} until $i;

print "\n", $f;

sub usage
{
    print "usage:\n$0 <variable> <variable>\ne.g. to fine variable {Web}->{Tree} definition $0 \"Web Tree\"\n";
    exit;
}

