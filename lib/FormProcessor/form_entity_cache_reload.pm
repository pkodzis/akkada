package FormProcessor::form_entity_cache_reload;

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

    return [1, "id_entity not defined"]
        unless $url_params->{form}->{id_entity};

    flag_files_create($TreeCacheDir, "master_hold");
    my $tree = Tree->new({db => DB->new(), with_rights => 0});
    $tree->reload_node( $url_params->{form}->{id_entity}, 1 );
    $tree->cache_save;
    flag_file_check($TreeCacheDir, "master_hold", 1);

    return [0];
}

1;
