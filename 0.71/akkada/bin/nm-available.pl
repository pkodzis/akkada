#!/akkada/bin/perl -w


my $ppid = $ARGV[0] || die;

$0 = 'nm-available.pl';

use lib "$ENV{AKKADA}/lib";
use Data::Dumper;
use Entity;
use MyException qw(:try);
use Available;
use Log;
use Configuration;
use Common;

runtime(1);

try
{
    $d = Available->new();
    $d->run($ppid);
}
catch Error with
{
    log_exception(shift, _LOG_ERROR);
};


