package FormProcessor::form_alarms_sort;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;


sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $session = session_get;

    eval
    {
        session_set_param(DB->new(), $session, '_ALARMS_SORT_ORDER', $url_params->{form}->{order});
        session_set_param(DB->new(), $session, '_ALARMS_SORT_ASCENDING', $url_params->{form}->{ascending});
    };

    return [1, $@]
        if $@;

    return [0];
}

1;
