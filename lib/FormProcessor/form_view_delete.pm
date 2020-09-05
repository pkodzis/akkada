package FormProcessor::form_view_delete;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Entity;
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

    my $id_view = session_get_param($session, '_ID_VIEW');

    return [1, 'missing id_view']
        unless $id_view;

    eval
    {   
        my $db = DB->new();
        $db->exec( sprintf(qq|DELETE FROM entities_2_views WHERE id_view=%s|, $id_view) );
        $db->exec( sprintf(qq|DELETE FROM views WHERE id_view=%s|, $id_view) );
        session_set_param($db, $session,'_ID_VIEW', 0);
    };

    return [1, $@]
        if $@;

    return [0];
}

1;
