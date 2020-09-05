package FormProcessor::form_options_mandatory;

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

our $StatusCalcDir = CFG->{StatusCalc}->{StatusCalcDir};
our $FlagsControlDir = CFG->{FlagsControlDir};
our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

our $CMDMode = 0;

sub process
{
    my $url_params = shift;

    if (! $CMDMode)
    {
        $url_params = url_dispatch();
    }

    my $db = DB->new();

    my $entity;

    eval
    {
        $entity = Entity->new($db, $url_params->{form}->{id_entity});
    };

    return [1, "internal: cannot load entity"]
        unless $entity;

    flag_files_create($TreeCacheDir, "master_hold");

    my $tree = Tree->new({db => $db, with_rights => 0});

    my $status_calculated = node_get_status($db, $url_params->{form}->{id_entity});

    for my $param (keys %{ $url_params->{form} })
    {
        next
            if $param eq 'form_name';
        next
            if $param eq 'id_entity';
        next
            if $param eq 'monitor_children';
        next
            if $param eq 'check_period_children';

        if ($param eq 'calculated_status_weight')
        {
            if ($url_params->{form}->{calculated_status_weight} ne $status_calculated->{status_weight})
            {
                $db->exec(sprintf(qq|UPDATE statuses SET status_weight='%s' WHERE id_entity=%d|, 
                    $url_params->{form}->{calculated_status_weight}, $url_params->{form}->{id_entity}));
                flag_files_create($StatusCalcDir, $entity->id_entity);
                flag_files_create($StatusCalcDir, $entity->id_parent);
                $entity->history_record(
                    sprintf(qq|calculated status weight changed from %s to %s by user|, 
                    $status_calculated->{status_weight},
                    $url_params->{form}->{calculated_status_weight}));
            }
        } 
        if ($param eq 'id_parent' && $entity->id_probe_type > 1)
        {
            flag_file_check($TreeCacheDir, "master_hold", 1);
            return [1, "only groups and node can have id_parent change"];
        }
        elsif ($param eq 'id_parent')
        {
            my $id_parent = $entity->id_parent;
            my $id_parent_new = $url_params->{form}->{id_parent};

            next
                if $id_parent_new eq $id_parent;

            if ($entity->id_probe_type || $id_parent_new)
            {
                if ($entity->id_probe_type && !$id_parent_new)
                {
                    flag_file_check($TreeCacheDir, "master_hold", 1);
                    return [1, "root can contain only grous"];
                }

                my $parent;
                eval
                {
                    $parent = Entity->new($db, $id_parent_new);
                };

                if (! $parent)
                {
                    flag_file_check($TreeCacheDir, "master_hold", 1);
                    return [1, "unknown parent"];
                }

                if ($parent->id_probe_type > 0)
                {
                    flag_file_check($TreeCacheDir, "master_hold", 1);
                    return [1, "only group can be a parent"];
                }
            }

            my $path = $tree->get_node_path($id_parent_new);

            for (@$path)
            {
                if ($_ eq $url_params->{form}->{id_entity})
                {
                    flag_file_check($TreeCacheDir, "master_hold", 1);
                    return [1, sprintf(qq|id_parent %s is id_entity %s child. change impossible.|, 
                        $id_parent_new, $url_params->{form}->{id_entity})];
                }
            }

#flag_files_create($TreeCacheDir, "master_hold");
            if ($id_parent && $id_parent_new)
            {
                $db->exec(sprintf(qq|UPDATE links SET id_parent=%d WHERE id_child=%d|, 
                    $url_params->{form}->{id_parent}, $url_params->{form}->{id_entity}));
            }
            elsif ($id_parent)
            {
                $db->exec(sprintf(qq|DELETE FROM links WHERE id_child=%d|, $url_params->{form}->{id_entity}));
            }
            else
            {
                $db->exec(sprintf(qq|INSERT INTO links VALUES(%d,%d)|,
                    $url_params->{form}->{id_parent}, $url_params->{form}->{id_entity}));
            }

            $tree->move_node($url_params->{form}->{id_entity}, $id_parent, $id_parent_new);
#flag_file_check($TreeCacheDir, "master_hold", 1);

            $entity->status_calc_flag_create( $id_parent_new )
                if $id_parent_new;
            $entity->status_calc_flag_create( $id_parent )
                if $id_parent;

            flag_files_create(CFG->{FlagsControlDir}, 'entities_init.Available');
            flag_files_create(CFG->{FlagsControlDir}, 'available2.init_graph');

        }
        if ($param eq 'monitor' && $url_params->{form}->{$param} ne $entity->$param)
        {
            $entity->$param($url_params->{form}->{$param});
            if (CFG->{ProbesMapRev}->{ $entity->id_probe_type } eq 'node' && $url_params->{form}->{monitor_children})
            {
                my $ids = child_get_ids($db, $url_params->{form}->{id_entity});

                my $en;
                for (@$ids)
                {
                    $en = Entity->new($db, $_);
                    $en->monitor($url_params->{form}->{$param});
                    $en->db_update_entity;
                }
            }
            flag_files_create(CFG->{FlagsControlDir}, 'available2.init_graph');
        }
        if ($param eq 'check_period' && $url_params->{form}->{$param} ne $entity->$param)
        {
            $entity->$param($url_params->{form}->{$param});
            if (CFG->{ProbesMapRev}->{ $entity->id_probe_type } eq 'node' && $url_params->{form}->{check_period_children})
            {
                my $ids = child_get_ids($db, $url_params->{form}->{id_entity});
                my $en;
                for (@$ids)
                {
                    try
                    {
                        $en = Entity->new($db, $_);
                        $en->check_period($url_params->{form}->{$param});
                        $en->db_update_entity;
                    }
                    catch  EEntityDoesNotExists with
                    {
                    }
                    except
                    {
                    };
                }
            }
        }
        
        if ($param ne 'check_period' && $param ne 'monitor' && $param ne 'id_parent' && $param ne 'calculated_status_weight')
        {
            $entity->$param($url_params->{form}->{$param});
        }
    }
    $entity->db_update_entity(1);
    $tree->reload_node( $entity->id_entity, 1 );
    flag_file_check($TreeCacheDir, "master_hold", 1);

    return [0];
}

1;
