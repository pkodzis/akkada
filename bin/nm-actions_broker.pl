#!/akkada/bin/perl -w

my $ppid = $ARGV[0] || die;

$0 = 'nm-actions_broker.pl';

use lib "$ENV{AKKADA}/lib";
use Data::Dumper;
use Entity;
use MyException qw(:try);
use ActionsBroker;
use Log;
use Configuration;
use Common;

runtime(1);

#try
{
    $d = ActionsBroker->new();
    $d->run($ppid);
}
=pod
catch Error with
{
    log_exception(shift, _LOG_ERROR);
};
=cut



