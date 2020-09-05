package FormProcessor::form_actions_bind_create;

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
our $FlagsControlDir = CFG->{FlagsControlDir};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $id_entity = $url_params->{form}->{id_entity};
    return [1, 'unknown entity']
        unless $id_entity;
    return [1, 'unknown entity']
        if $id_entity =~ /\D/;

    return [1, 'select action']
        unless $url_params->{form}->{id_action};
    return [1, 'select contacts group']
        unless $url_params->{form}->{id_cgroup};
    return [1, 'select time period']
        unless $url_params->{form}->{id_time_period};

    eval
    {
        my $db = DB->new();

        $db->dbh->do(sprintf("INSERT INTO entities_2_actions VALUES(%s,%s,%s,%s,DEFAULT)", 
            $id_entity, 
            $url_params->{form}->{id_action},
            $url_params->{form}->{id_cgroup},
            $url_params->{form}->{id_time_period},));

        my $ids = child_get_ids($db, $id_entity);
        push @$ids, $id_entity;
        flag_files_create($FlagsControlDir, "$_.load_actions")
            for @$ids;


        flag_files_create($TreeCacheDir, "master_hold");
        my $tree = Tree->new({db => $db, with_rights => 0});
        $tree->reload_node( $id_entity, 4 );
        $tree->cache_save;
        flag_file_check($TreeCacheDir, "master_hold", 1);
        flag_files_create($FlagsControlDir, "actions_load");
    };

    if ($@)
    {
        if ($@ =~ /Duplicate entry/)
        {
            return [1, 'duplicate entry'];
        }
        return [1, $@];
    }

    return [0];
}

1;
