#!/akkada/bin/perl -w

my $ppid = $ARGV[0] || die;

$0 = 'nm-discover.pl';

use lib "$ENV{AKKADA}/lib";
use Data::Dumper;
use Entity;
use MyException qw(:try);
use Discover;
use Log;
use Configuration;
use Common;

runtime(1);

#try
{
    $d = Discover->new();
    $d->run($ppid);
}
=pod
catch Error with
{
    log_exception(shift, _LOG_ERROR);
};
=cut


