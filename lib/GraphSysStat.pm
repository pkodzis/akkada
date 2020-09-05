package GraphSysStat;

use strict;

use warnings FATAL => 'all';
use Apache2::RequestRec ( );
use Apache2::Const -compile => 'OK';

use lib "$ENV{AKKADA}/lib";
use RRDSysStat;

sub handler 
{
    $0 = 'akk@da - graph';
    my $r = shift;
    $r->content_type('image/gif');
    
    my $graph = RRDSysStat->new();
    $graph->get();
    return $Apache2::Const::OK;
}

1;

