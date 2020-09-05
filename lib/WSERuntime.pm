package WSERuntime;

use strict;

use warnings FATAL => 'all';
use Apache2::RequestRec ( );
use Apache2::Const -compile => 'OK';

use lib "$ENV{AKKADA}/lib";
use WSE;
use DB;

our $DB = DB->new();

sub handler 
{
    $0 = 'akk@da';
    my $r = shift;

    my $wse = WSE->new($DB);

    print $wse->get;
    undef $wse;

    return $Apache2::Const::OK;
}

1;

