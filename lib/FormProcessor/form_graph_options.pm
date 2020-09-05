package FormProcessor::form_graph_options;

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
    begin => 1,
    end => 1,
    width => 1,
    height => 1,
    only_graph => 1,
    zoom => 1,
    no_legend => 1,
    no_x_grid => 1,
    no_y_grid => 1,
    no_title => 1,
    scale => 1,
    force_scale => 1,
};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch;

    my $session = session_get;

    my $options = session_get_param($session, '_GRAPH_OPTIONS') || {};

    eval {
        for (keys %$items)
        {
            $options->{ $_ } = defined $url_params->{form}->{$_}
                ? $url_params->{form}->{$_}
                : '';
        }
    };
    session_set_param(DB->new(), $session, '_GRAPH_OPTIONS', $options);

    return [1, $@]
        if $@;

    return [0];
}

1;
