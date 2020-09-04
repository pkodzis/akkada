#!/akkada/bin/perl -w

my $ppid = $ARGV[0] || die;

$0 = 'nm-job_planner.pl';

use lib "$ENV{AKKADA}/lib";
use JobPlanner;
use Configuration;
use Common;

runtime(1);

try
{
    $jp = JobPlanner->new();
    $jp->run($ppid);
}
catch Error with
{
    log_exception(shift, _LOG_ERROR);
};
