package FormProcessor::form_general_view;

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
        my $view;

        if (defined $url_params->{form}->{vmn})
        {
             $view = $url_params->{form}->{vmn} > -1 && $url_params->{form}->{vmn} < 4
                 ? $url_params->{form}->{vmn}
                 : 0;
             session_set_param(DB->new(), $session, '_GENERAL_VIEW_NODE', $view);
        }
        elsif (defined $url_params->{form}->{vm})
        {
             $view = $url_params->{form}->{vm} > -1 && $url_params->{form}->{vm} < 2
                 ? $url_params->{form}->{vm}
                 : 0;
             session_set_param(DB->new(), $session, '_GENERAL_VIEW', $view);
        }
    };

    return [1, $@]
        if $@;

    return [0];
}

1;
