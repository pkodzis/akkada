#!/akkada/bin/perl -w
use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use lib "$ENV{AKKADA}/lib";
use MyException qw(:try);
use Configuration;
use DB;

try
{
    our $DBH = DB->new();
    print "database connection OK.\n";
}
catch Error with
{
    my $error = shift;
    print $error->Error::stringify('text');
}

