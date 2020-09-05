#!/akkada/bin/perl -w

use strict;

use lib "$ENV{AKKADA}/lib";
use Tree;
use Log;
use Constants;
use MyException qw(:try);
use Common;
use DB;

my $ppid = $ARGV[0] || die;

$0 = 'nm-tree_cache.pl';

runtime(1);

#try
{
    my $tree = Tree->new({db => DB->new(), master => 1,});
    $tree->run_cache($ppid);
}
=cut
catch Error with
{
    log_exception(shift, _LOG_ERROR);
};
=pod
