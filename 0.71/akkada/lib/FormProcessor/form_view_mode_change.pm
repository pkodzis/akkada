package FormProcessor::form_view_mode_change;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;

my $view_modes =
{
    0 => 1,
    1 => 1,
    2 => 1,
    3 => 1,
    10 => 1,
    11 => 1,
};


sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $session = session_get;

    my $vm = session_get_param($session, '_VIEW_MODE') || 0;

    my $nvm = defined $url_params->{form}->{nvm}
        ? $url_params->{form}->{nvm}
        : undef;

    my $switch = defined $url_params->{form}->{switch}
        ? $url_params->{form}->{switch}
        : undef;

    if (defined $nvm)
    {
        $nvm = 0
            unless defined $view_modes->{ $nvm };
    }
    elsif (defined $switch)
    {
        $nvm = $VIEWS_SWITCH{$vm};
    }

    my $db;
    if (defined $nvm && $vm != $nvm)
    {
         $db = DB->new();
         session_set_param($db, $session, '_VIEW_MODE', $nvm)
    }

    if (defined $url_params->{form}->{id_view})
    {
         my $id_view  = session_get_param($session, '_ID_VIEW');

         if ($id_view != $url_params->{form}->{id_view})
         {
             $db = DB->new()
                 unless $db;
             session_set_param($db, $session, '_ID_VIEW', $url_params->{form}->{id_view});
         }
    }

    return [1, $@]
        if $@;

    return [0];
}

1;
