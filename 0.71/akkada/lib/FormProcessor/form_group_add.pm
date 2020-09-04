package FormProcessor::form_group_add;

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

    eval {


       my $entity = {
           probe_name => 'group',
           name => $url_params->{form}->{name},
           id_parent => $url_params->{form}->{id_parent},
       };
       $entity->{params}->{function} = $url_params->{form}->{function}
           if $url_params->{form}->{function};

       $entity = entity_add( $entity );

       flag_files_create($TreeCacheDir, "master_hold");
       my $tree = Tree->new({db => DB->new(), with_rights => 0});
       $tree->load_node( $entity->id_entity);
       $tree->cache_save;
       flag_file_check($TreeCacheDir, "master_hold", 1);

    };
    return [1, $@]
        if $@;

    return [0];
}

1;
