#!/akkada/bin/perl -w

die "usage: np-run.pl <probe name> <ppid>\n"
    unless @ARGV;

my $module = $ARGV[0] || die;
my $ppid = $ARGV[1] || die;

$0 = "np-$module.pl";

use lib "$ENV{AKKADA}/lib";

use Entity;
use MyException qw(:try);
use Log;
use Configuration;
use strict;
use Constants;
use Common;

if ($ARGV[2])
{
    $Configuration::cfg->{'TraceLevel'} = $ARGV[2];
}

my $probe;

eval "require Probe::$module; \$probe = Probe::${module}->new();"
    or log_debug($@, _LOG_WARNING);

#try
{
    runtime(0);
    $probe->run($ppid);
}
=pod
catch Error with
{
    log_exception(shift, 0);
};
=cut
