package FormProcessor::form_entity_recheck;

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

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch();

    my $db = DB->new();

    my $entity;

    eval
    {
        $entity = Entity->new($db, $url_params->{form}->{id_entity});
    };

    return [1, "internal: cannot load entity"]
        unless $entity;

    flag_files_create($TreeCacheDir, "master_hold");
    $entity->set_status(_ST_UNKNOWN, '');
    my $tree = Tree->new({db => $db, with_rights => 0});
    $tree->reload_node( $entity->id_entity, 1 );
    $tree->cache_save;
    flag_file_check($TreeCacheDir, "master_hold", 1);

    return [0];
}

1;
