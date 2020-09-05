package FormProcessor::form_unbind_contacts;

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

    $url_params = url_dispatch( $url_params );

    my $id_entity = $url_params->{form}->{id_child};
    return [1, 'unknown entity']
        unless $id_entity;
    return [1, 'unknown entity']
        if $id_entity =~ /\D/;

    eval
    {
        my $db = DB->new();
        $db->exec(sprintf("DELETE FROM entities_2_cgroups WHERE id_entity=%s", $id_entity));
        my $tree = Tree->new({db => $db, with_rights => 0});
        flag_files_create($TreeCacheDir, "master_hold");
        $tree->reload_node( $id_entity, 2 );
        $tree->cache_save;
        flag_file_check($TreeCacheDir, "master_hold", 1);
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
