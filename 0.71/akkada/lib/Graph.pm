package Graph;

use strict;

use warnings FATAL => 'all';
use Apache2::RequestRec ( );
use Apache2::Const -compile => 'OK';

use lib "$ENV{AKKADA}/lib";
use RRDGraph;
use DB;

our $DB = DB->new();


sub handler 
{
    $0 = 'akk@da - graph';
    my $r = shift;
    $r->content_type('image/gif');
    
    my $graph = RRDGraph->new($DB);
    $graph->get;
    return $Apache2::Const::OK;
}

1;

