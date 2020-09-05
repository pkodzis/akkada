package FormProcessor::form_entity_find;

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
        name => 1,
        ip => 1,
        case => 1,
        id_probe_type => 1,
        id_parent => 1,
        treefind => 1,
        status => 1,
        function => 1,
        cdata => 1,
};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $session = session_get;

    my $options = $session->param('_FIND') || {};

    my $vm = session_get_param($session, '_VIEW_MODE') || 0;

    my $db = DB->new();

    if ($url_params->{form}->{treefind} || ! defined $VIEWS_ALLFIND{$vm}) {
        $vm = defined $VIEWS_LIGHT{$vm}
            ? _VM_TREEFIND_LIGHT
            : _VM_TREEFIND;
        session_set_param($db, $session, '_VIEW_MODE', $vm);
    }
    elsif (! $url_params->{form}->{treefind} && ! defined $VIEWS_FIND{$vm}) {
        $vm = defined $VIEWS_LIGHT{$vm}
            ? _VM_FIND_LIGHT
            : _VM_FIND;
        session_set_param($db, $session, '_VIEW_MODE', $vm);
    }

    session_set_param($db, $session, '_VIEW_MODE', _VM_FIND)
        unless defined $VIEWS_ALLFIND{$vm};

    eval {
        for (keys %$items)
        {
            $options->{ $_ } = defined $url_params->{form}->{$_}
                ? $url_params->{form}->{$_}
                : '';
        }
    };
    $session->param('_FIND', $options);

    return [1, $@]
        if $@;

    return [0];
}

1;
