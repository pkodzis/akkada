#!/akkada/bin/perl -w

my $ppid = $ARGV[0] || die;

$0 = 'nm-db_watch.pl';

use lib "$ENV{AKKADA}/lib";
use DBWatch;
use Common;

runtime(1);

$|=1;

try
{
    $dbw = DBWatch->new();
    $dbw->run($ppid);
}
catch Error with
{
    log_exception(shift, _LOG_ERROR);
};

