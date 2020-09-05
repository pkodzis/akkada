package FormProcessor::form_bind_contacts;

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

        my $e2g = {};
        my $ne2g = {};

        my $req = $db->exec("SELECT * FROM entities_2_cgroups where id_entity=" . $id_entity);
        while( my $h = $req->fetchrow_hashref )
        {   
            $e2g->{ $h->{id_cgroup } } = 1;
        }
        $url_params->{form}->{entities_2_cgroups} = [ $url_params->{form}->{entities_2_cgroups} ]
             unless ref($url_params->{form}->{entities_2_cgroups}) eq 'ARRAY';

        for (@{ $url_params->{form}->{entities_2_cgroups} })
        {   
            $ne2g->{$_} = 1;
        }
        for (keys %$ne2g)
        {   
            next
                if defined $e2g->{$_} || $_ eq '';
            $db->exec(sprintf("INSERT INTO entities_2_cgroups VALUES(%s,%s)", $id_entity, $_));
        }
        for (keys %$e2g)
        {   
            next
                if defined $ne2g->{$_} || $_ eq '';
            $db->exec(sprintf("DELETE FROM entities_2_cgroups WHERE id_entity=%s AND id_cgroup=%s", $id_entity, $_));
        }
        flag_files_create($TreeCacheDir, "master_hold");
        my $tree = Tree->new({db => $db, with_rights => 0});
        $tree->reload_node( $id_entity, 2 );
        $tree->cache_save;
        flag_file_check($TreeCacheDir, "master_hold", 1);
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
