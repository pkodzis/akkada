package FormProcessor::form_users_select;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;


my $items =
{   
        id => 1,
};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $session = session_get;

    my $options = $session->param('_PERMITIONS') || {};

    eval {
        for (keys %$items)
        {
            $options->{ $_ } = defined $url_params->{form}->{$_}
                ? $url_params->{form}->{$_}
                : '';
        }
    };
    $session->param('_PERMITIONS', $options);

    return [1, $@]
        if $@;

    return [0];
}

1;
