package FormProcessor::form_services_options;

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
use Tree;

our $StatusCalcDir = CFG->{StatusCalc}->{StatusCalcDir};
our $FlagsControlDir = CFG->{FlagsControlDir};
our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

sub services_dispatch
{
    my $url_params = shift;

    my $f = $$url_params->{form};

    my @t;
    my $g;

    for my $s (keys %$f)
    {
        next
            if $s eq 'id_entity';
        @t = split /_/, $s, 2;
        $g->{$t[0]}->{$t[1]} = $f->{$s};
    }
    $$url_params->{form} = $g;
}

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );
    delete $url_params->{form}->{form_name};
    services_dispatch( \$url_params );

    my $db = DB->new();

    my $entity;
    my $cur;
    my $count = 0;
    my $node;

    flag_files_create($TreeCacheDir, "master_hold");
    my $tree = Tree->new({db => $db, with_rights => 0});
    my $items = $tree->items;

    my @del;
    for my $id_entity (keys %{ $url_params->{form} })
    {
        $cur = $url_params->{form}->{$id_entity};

        if ($cur->{delete})
        {
            $node = $items->{$id_entity};

            if (! $node || (defined $node && $node->id_probe_type < 1))
            {
                flag_file_check($TreeCacheDir, "master_hold", 1);
                return [1, 'stop hacking me you ugly bug!'];
            }
            push @del, $id_entity;
            delete $url_params->{form}->{$id_entity};
        }
    }

    if (@del)
    { 
        $tree->remove_node( $_, 1 )
            for @del;
        $tree->cache_save;
        $db->exec( sprintf(qq|DELETE FROM entities_2_parameters WHERE id_entity=%s|, join(" OR id_entity=", @del)));
        $db->exec( sprintf(qq|DELETE FROM links WHERE id_child=%s|, join(" OR id_child=", @del)));
        $db->exec( sprintf(qq|DELETE FROM statuses WHERE id_entity=%s|, join(" OR id_entity=", @del)));
        $db->exec( sprintf(qq|DELETE FROM entities_2_views WHERE id_entity=%s|, join(" OR id_entity=", @del)));
        $db->exec( sprintf(qq|DELETE FROM entities WHERE id_entity=%s|, join(" OR id_entity=", @del)));
        #$db->exec( sprintf(qq|DELETE FROM history24 WHERE id_entity=%s|, join(" OR id_entity=", @del)));
    }

    for my $id_entity (keys %{ $url_params->{form} })
    {
        $entity = Entity->new($db, $id_entity);

        next
            unless $entity;

        $cur = $url_params->{form}->{$id_entity};

        next
            unless delete $cur->{update};
        for my $param (keys %$cur)
        {
           ++$count
               if $cur->{$param} ne $entity->$param;
           $entity->$param($cur->{$param});
        }
        $entity->db_update_entity(1);

        $tree->reload_node( $entity->id_entity, 1 );
    }

    flag_file_check($TreeCacheDir, "master_hold", 1);

    if ($entity && ($count || @del))
    {
        $entity->status_calc_flag_create( $entity->id_parent );
    }

    return [0, sprintf(qq|%d fields updated; %s entities deleted|, $count, scalar @del)];
}

1;
