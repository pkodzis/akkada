package WSTreeRuntime;

use strict;

use warnings FATAL => 'all';
use Apache2::RequestRec ( );
use Apache2::Const -compile => 'OK';

use lib "$ENV{AKKADA}/lib";
use WSTree;
use DB;

our $DB = DB->new();

sub handler 
{
    $0 = 'akk@da';
    my $r = shift;

    my $wst = WSTree->new($DB);

    print $wst->get;
    undef $wst;

    return $Apache2::Const::OK;
}

1;

