#!/akkada/bin/perl -w

my $ppid = $ARGV[0] || die;

$0 = 'nm-status_calc.pl';

use lib "$ENV{AKKADA}/lib";
use StatusCalc;
use Configuration;
use Common;

runtime(1);

try
{
    $sc = StatusCalc->new();
    $sc->run($ppid);
}
catch Error with
{
    log_exception(shift, _LOG_ERROR);
};
