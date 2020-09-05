#!/akkada/bin/perl -w

my $ppid = $ARGV[0] || die;

$0 = 'nm-top.pl';

use lib "$ENV{AKKADA}/lib";
use MyException qw(:try);
use Top;
use Log;
use Configuration;
use Common;

runtime(1);

#try
{
    $d = Top->new();
    $d->run($ppid);
}
=pod
catch Error with
{
    log_exception(shift, _LOG_ERROR);
};
=cut



