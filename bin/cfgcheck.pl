#!/usr/bin/perl

use strict;

if (! defined $ENV{AKKADA})
{
    print "not defined env variable AKKADA\n";
    exit 1;
}
else
{
    my @w = ( $ENV{AKKADA}, "$ENV{AKKADA}/etc" );
    for (@w)
    {
        if (! -e $_)
        {
            print "directory does not exists: $_\n";
            exit 1;
        }
    }
}

my $find = `which find`;
$find =~ s/\n//g;
if (! -e $find)
{
    print "find file not available in paths\n";
    exit 1;
}

my $grep = `which grep`;
$grep=~ s/\n//g;
if (! -e $grep)
{
    print "find file not available in paths\n";
    exit 1;
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
my $f;

my $problems = 0;

for my $file (sort { lc $a->[1] cmp lc $b->[1] } @files)
{
    if (! -e $file->[1])
    {
        ++$problems;
        push @result, "PROBLEM: file $file->[1] does not exists (linked via $file->[0])";
        next;
    }
    eval { $f = do $file->[1]; };
    if (! defined $f)
    {
        ++$problems;
        push @result, "PROBLEM: syntax error in file $file->[1] (linked via $file->[0])";
        next;
    }
    #push @result, "OK: $file->[1] (linked via $file->[0])";
}

#print "\n\n\nAKK\@DA configuration report:\n============================\n";
print join("\n", @result), "\n";

$f = $problems ? "PROBLEM (count: $problems)" : "OK";

print "AKK\@DA: configuration syntax $f\n\n";

exit $problems;


