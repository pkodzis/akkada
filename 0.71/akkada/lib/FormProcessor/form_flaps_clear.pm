package FormProcessor::form_flaps_clear;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Entity;
use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Tree;
use Common;

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $entity;
    my $db;

    eval
    {
        $db = DB->new();
        $entity = Entity->new($db, $url_params->{id_entity});
    };

    return [1, "internal: cannot load entity"]
        unless $entity;

    if ($entity->flap)
    {
        $entity->flaps_clear;
    }
    else
    {
        $entity->flaps_reset;
    };

    flag_files_create($TreeCacheDir, "master_hold");
    my $tree = Tree->new({db => $db, with_rights => 0});
    $tree->reload_node( $entity->id_entity, 1 );
    $tree->cache_save;
    flag_file_check($TreeCacheDir, "master_hold", 1);

    return [0];
}

1;
