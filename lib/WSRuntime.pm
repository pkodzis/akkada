package WSRuntime;

use strict;

use warnings FATAL => 'all';
use Apache2::RequestRec ( );
use Apache2::Const -compile => 'OK';

use lib "$ENV{AKKADA}/lib";
use WS;
use DB;

our $DB = DB->new();

sub handler 
{
    $0 = 'akk@da';
    my $r = shift;

    my $ws = WS->new($DB);

    print $ws->get;
    undef $ws;

    return $Apache2::Const::OK;
}

1;

