package FormProcessor::form_entity_delete;

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
use Log;

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $id = $url_params->{form}->{id_entity};
    return [1, 'unknown entity']
        unless $id;
    return [1, 'unknown entity']
        if $id =~ /\D/;

    eval
    {   
        my $db = DB->new();

        flag_files_create($TreeCacheDir, "master_hold");

        my $tree = Tree->new({db => $db, with_rights => 0});

        my $node = $tree->items->{$id};

        if (! $node)
        {
            flag_file_check($TreeCacheDir, "master_hold", 1);
            return [1, 'stop hacking me you ugly bug!'];
        }

        my $entity = Entity->new( $db, $id);

        my $req;
        my $chld = $tree->get_node_down_family($id);
        $chld = [ keys %$chld ];
        if ($#$chld < 0)
        {
            $req = $db->exec( sprintf(qq|SELECT * FROM links WHERE id_parent=%s|, $id))->fetchall_hashref('id_child');
        }
        else
        {
            $req = $db->exec( sprintf(qq|SELECT * FROM links WHERE id_parent=%s|, 
                join(" OR id_parent=", @$chld, $id)))->fetchall_hashref('id_child');
        }


        $req = [ keys %$req ];
        if ($#$req > 0)
        {
            $db->exec( sprintf(qq|DELETE FROM entities_2_parameters WHERE id_entity=%s|, join(" OR id_entity=", @$req) ) );
            $db->exec( sprintf(qq|DELETE FROM links WHERE id_child=%s|, join(" OR  id_child=", @$req) ) );
            $db->exec( sprintf(qq|DELETE FROM statuses WHERE id_entity=%s|, join(" OR id_entity=", @$req) ) );
            $db->exec( sprintf(qq|DELETE FROM entities_2_views WHERE id_entity=%s|, join(" OR  id_entity=", @$req) ) );
            $db->exec( sprintf(qq|DELETE FROM comments WHERE id_entity=%s|, join(" OR  id_entity=", @$req) ) );
            $db->exec( sprintf(qq|DELETE FROM entities_2_cgroups WHERE id_entity=%s|, join(" OR  id_entity=", @$req) ) );
            $db->exec( sprintf(qq|DELETE FROM entities WHERE id_entity=%s|, join(" OR  id_entity=", @$req) ) );
            #$db->exec( sprintf(qq|DELETE FROM history24 WHERE id_entity=%s|, join(" OR  id_entity=", @$req) ) );
        }
        elsif ($#$req == 0)
        {
            $db->exec( sprintf(qq|DELETE FROM entities_2_parameters WHERE id_entity=%s|, $req->[0] ) );
            $db->exec( sprintf(qq|DELETE FROM links WHERE id_child=%s|, $req->[0] ) );
            $db->exec( sprintf(qq|DELETE FROM statuses WHERE id_entity=%s|, $req->[0] ) );
            $db->exec( sprintf(qq|DELETE FROM entities_2_views WHERE id_entity=%s|, $req->[0] ) );
            $db->exec( sprintf(qq|DELETE FROM comments WHERE id_entity=%s|, $req->[0] ) );
            $db->exec( sprintf(qq|DELETE FROM entities_2_cgroups WHERE id_entity=%s|, $req->[0] ) );
            $db->exec( sprintf(qq|DELETE FROM entities WHERE id_entity=%s|, $req->[0] ) );
            #$db->exec( sprintf(qq|DELETE FROM history24 WHERE id_entity=%s|, join(" OR  id_entity=", @$req) ) );
        }

        $db->exec( sprintf(qq|DELETE FROM entities_2_parameters WHERE id_entity=%s|, $id) );
        $db->exec( sprintf(qq|DELETE FROM links WHERE id_child=%s|, $id) );
        $db->exec( sprintf(qq|DELETE FROM statuses WHERE id_entity=%s|, $id) );
        $db->exec( sprintf(qq|DELETE FROM entities_2_views WHERE id_entity=%s|, $id) );
        $db->exec( sprintf(qq|DELETE FROM comments WHERE id_entity=%s|, $id) );
        $db->exec( sprintf(qq|DELETE FROM entities_2_cgroups WHERE id_entity=%s|, $id) );
        $db->exec( sprintf(qq|DELETE FROM entities WHERE id_entity=%s|, $id) );
        #$db->exec( sprintf(qq|DELETE FROM history24 WHERE id_entity=%s|, $id) );

        $tree->remove_node( $id );
        $tree->cache_save();

        flag_file_check($TreeCacheDir, "master_hold", 1);

        $entity->status_calc_flag_create( $entity->id_parent );

    };
    return [1, $@]
        if $@;

    return [0];
}

1;
