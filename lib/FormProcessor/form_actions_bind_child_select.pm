package FormProcessor::form_actions_bind_child_select;

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

    my $options = $session->param('_ACTIONS') || {};

    $options->{ id_child } = defined $url_params->{form}->{id_child} && $url_params->{form}->{id_child}
        ? $url_params->{form}->{id_child}
        : $options->{id_parent};

    $session->param('_ACTIONS', $options);

    return [1, $@]
        if $@;

    return [0];
}

1;
