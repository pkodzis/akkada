package Runtime;

use strict;

use warnings FATAL => 'all';
use Apache2::RequestRec ( );
use Apache2::Const -compile => 'OK';

use lib "$ENV{AKKADA}/lib";
use Desktop::GUI;
use DB;

our $DB = DB->new();

sub handler 
{
    $0 = 'akk@da';
    my $r = shift;

    my $gui = Desktop::GUI->new($DB);

    print $gui->get;
    undef $gui;

    return $Apache2::Const::OK;
}

1;

