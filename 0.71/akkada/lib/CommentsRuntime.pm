package CommentsRuntime;

use strict;

use warnings FATAL => 'all';
use Apache2::RequestRec ( );
use Apache2::Const -compile => 'OK';

use lib "$ENV{AKKADA}/lib";
use DB;
use HTML::Table;
use Window::Buttons;
use Comments;
use Desktop::GUI;

our $DB = DB->new();

sub handler 
{
    $0 = 'akk@da contacts';
    my $r = shift;

    my $path = $ENV{'PATH_INFO'};

    if (! $path)
    {
        return $Apache2::Const::OK;
    }

    $path =~ s/\///g;
    $path = [ split /\,/, $path ];

    my $id_entity = shift @$path;
    my $id_parent = shift @$path;
    my $parent_name = '';

    my $title;
    my $req = $DB->exec("SELECT id_probe_type,name,id_parent 
        FROM entities,links 
        WHERE id_entity=$id_entity 
        AND entities.id_entity=links.id_child");
    $req = $req->fetchrow_hashref;

    if (! defined $req->{name})
    {
        $req = $DB->exec("SELECT id_probe_type,name FROM entities WHERE id_entity=$id_entity");
        $req = $req->fetchrow_hashref;
    }

    $title = $req->{name};
    if ($req->{id_probe_type} > 1)
    {
        $req = $DB->exec("SELECT * FROM entities WHERE id_entity=$req->{id_parent}");
        $req = $req->fetchrow_hashref;
        $title = "$req->{name}::" . $title;
        $parent_name = $req->{name};
    }

    my $t = HTML::Table->new();
    $t->setAttr('class="w"');

    my $gui = Desktop::GUI->new($DB);

    print qq|
<HTML>  
<HEAD>  
<TITLE>$0</TITLE>
<META HTTP-EQUIV="Pragma" CONTENT="no-cache">
<META HTTP-EQUIV="Expires" CONTENT="-1">
<LINK rel="StyleSheet" href="/css/akkada.css" type="text/css" />
</HEAD><BODY>|;


    my $entity_cgi = CGIEntity->new($gui->users, $gui->session, $DB, undef, $gui->cgi, 
        $gui->tree, $gui->url_params, $gui);

    comments($t, $id_entity, $entity_cgi, 0, 0, $title, 'left');
    comments($t, $id_parent, $entity_cgi, 0, 0, $parent_name, 'left')
        if $id_parent;

    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $buttons->add({ caption => 'close' , url => 'javascript:window.close()' });
    $t->addRow( $buttons->get );

    print $t;

    print "</BODY></HTML>";

    return $Apache2::Const::OK;
}

1;

