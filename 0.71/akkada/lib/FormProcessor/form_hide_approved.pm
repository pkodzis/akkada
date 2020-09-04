package FormProcessor::form_hide_approved;

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
        my $view = session_get_param($session, '_HIDE_APPROVED') || 0;

        $view = ! $view;

        session_set_param(DB->new(), $session, '_HIDE_APPROVED', $view);
    };

    return [1, $@]
        if $@;

    return [0];
}

1;
