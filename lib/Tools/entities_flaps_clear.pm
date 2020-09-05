package Tools::entities_flaps_clear;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use Common;
use Window::Buttons;
use Desktop::GUI;
use DB;
use Entity;
use HTML::Table;
use Configuration;

use Data::Dumper;
use Log;

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};


sub desc
{
    my $db = DB->new();
    my $dbh = $db->dbh;

    my $entities = $dbh->selectall_hashref("select id_entity, name from entities where flap>0", "id_entity");

    if (! keys %$entities)
    {
        return "currently there are no flaps detected.";
    }


    my $table = table_begin("detected flaps", 2);

    $table->addRow
    (
         make_col_title("name"),
         make_col_title("id"),
    );

    $table->addRow($entities->{$_}->{name}, $_)
        for sort { uc $entities->{$a}->{name} cmp uc $entities->{$b}->{name} } keys %$entities;

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return <<EOF;
this tool clears all detected flaps listed below:
$table
EOF
}

sub button_start
{

    my $db = DB->new();
    my $dbh = $db->dbh;

    my $entities = $dbh->selectall_hashref("select id_entity, name from entities where flap>0", "id_entity");

    if (! keys %$entities)
    {
        return "";
    }

    my $url_params = shift;
    $url_params = url_dispatch( $url_params );

    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $buttons->add({ caption => 'start' , url => url_get({section => 'tool', start => 1}, $url_params), });
    return $buttons->get;
}


sub make_col_title
{
    my ($name ) = @_;
    return sprintf(qq|<font class="g4">%s</font>|, $name);
}

sub run
{
    my $url_params = shift;
    $url_params = url_dispatch( $url_params );

    my $db = DB->new();
    my $dbh = $db->dbh;

    my $entities = $dbh->selectall_hashref("select id_entity, name from entities where flap>0", "id_entity");

    return [0, 'no flaps found']
        unless keys %$entities;

    my $entity;
    my @result;

    flag_files_create($TreeCacheDir, "master_hold");
    my $tree = Tree->new({db => $db, with_rights => 0});

    for my $id_entity (sort { uc $entities->{$a}->{name} cmp uc $entities->{$b}->{name} } keys %$entities)
    {
        $entity = Entity->new( $db, $id_entity);
        $entity->flaps_clear;
        $tree->reload_node( $id_entity, 1 );
        push @result, [ $entities->{$id_entity}->{name}, $id_entity, 'cleared' ];
    };

    $tree->cache_save;
    flag_file_check($TreeCacheDir, "master_hold", 1);

    my $table = table_begin("entities flaps clear report", 3);

    $table->addRow
    (
         make_col_title("name"),
         make_col_title("id"),
         make_col_title("status"),
    );

    $table->addRow(@$_)
        for @result;

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return [0, $table];
}

1;
