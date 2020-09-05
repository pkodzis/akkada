package FormProcessor::form_alarm_approval;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;
use Tree;
use CGI;
use Views;

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};
sub interesting
{
    my $tree = shift;
    my $items = shift;
    my $view_mode = shift;
    my $view_entities = shift;
    my $mode = shift;
    my $root = shift;
    my $id = shift;

    return 0
        unless defined $items->{$id};

    return 0
        unless $items->{$id}->status > _ST_OK && $items->{$id}->status < _ST_UNKNOWN;

    return 0
        if $items->{$id}->err_approved_by;

    return 0
        if ($view_mode == _VM_TREEVIEWS || $view_mode == _VM_VIEWS || $view_mode == _VM_VIEWS_LIGHT)
            && ! defined $view_entities->{$id};

    my $par = $tree->parent($id);

    return 0
        if $par->status == _ST_UNREACHABLE && $id != $root;

    return 0
        if $items->{$id}->status_weight == 0 && $mode < 2;

    return 0
        if $par->state_weight == 0 && $mode < 1; # calculated status weight

    return 0
        unless $items->{$id}->monitor;

    return 1;
}

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $dbh = DB->new();
    my $id_entity = $url_params->{form}->{id_entity};
    my $atype = $url_params->{form}->{atype};
    my $entity;

    return [1, "internal: cannot approve root alarm!"]
        if ! $atype && !$id_entity;

    $entity = $id_entity 
        ? Entity->new($dbh, $id_entity) 
        : undef;

    my $session = session_get;
    my $id_user = $session->param('_LOGGED');
    my $ip = $session->param('_SESSION_REMOTE_ADDR');


    flag_files_create($TreeCacheDir, "master_hold");
    my $tree = Tree->new({db => $dbh, with_rights => 1, id_user => $id_user});

    if (! $atype && ! $atype && defined $entity)
    {
        if ($entity->status == _ST_OK || $entity->status >= _ST_UNKNOWN || $entity->err_approved_by)
        {
            flag_file_check($TreeCacheDir, "master_hold", 1);
            return [0]
        }
        #return [0]
        #    unless $entity->status > _ST_OK && $entity->status < _ST_UNKNOWN;
        #return [0]
        #    if $entity->err_approved_by;

        $entity->err_approved_by($id_user, $ip);
        $tree->reload_node( $entity->id_entity, 1 );
        $tree->cache_save();
        flag_file_check($TreeCacheDir, "master_hold", 1);
        return [0];
    }

    my $view_mode = session_get_param($session, '_VIEW_MODE');
    my $root = defined $entity && $view_mode != _VM_VIEWS && $view_mode != _VM_VIEWS_LIGHT && $view_mode != _VM_TREEVIEWS
        ? $id_entity
        : 0;

    my $items = $tree->items;
    my $rel = $tree->relations;
    my $view_entities = {};
    my $mode = $url_params->{alarms_mode} || 0;
    my @job;
    my $par;
    my $id_probe_type;

    my $views = Views->new($dbh, $session, CGI->new(), $url_params);

    if ($view_mode == _VM_VIEWS
        || $view_mode == _VM_TREEVIEWS
        || $view_mode == _VM_VIEWS_LIGHT)
    {   
        for (@{ $views->view_entities })
        {
            for ( @{child_get_ids_all($dbh, $_)})
            {
                ++$view_entities->{$_};
            }
        }
    }


    if ($atype eq '1')
    {
        if (! defined $rel->{$id_entity})
        {
            flag_file_check($TreeCacheDir, "master_hold", 1);
            return;
        }
        #    unless defined $rel->{$id_entity};

        my $children = child_get_ids($dbh, $rel->{$id_entity});

        for (@$children)
        {
            push @job, $_
                if interesting($tree, $items, $view_mode, $view_entities, $mode, $root, $_);
        }
    }
    elsif ($atype eq '2')
    {
        if (! defined $items->{$id_entity})
        {
            flag_file_check($TreeCacheDir, "master_hold", 1);
            return;
        }
        #return
        #    unless defined $items->{$id_entity};

        $id_probe_type = $items->{$id_entity}->id_probe_type;

        for (keys %$items)
        {
            push @job, $_
                if interesting($tree, $items, $view_mode, $view_entities, $mode, $root, $_)
                    && $items->{$_}->id_probe_type eq $id_probe_type;
        }
    }
    elsif ($atype eq '3')
    {
        my $nodes = $tree->get_node_down_family($root);

        if (! keys %$nodes)
        {
            flag_file_check($TreeCacheDir, "master_hold", 1);
            return [0];
        }
        #return [0]
        #    unless keys %$nodes;

        for (keys %$nodes)
        {
            push @job, $_
                if interesting($tree, $items, $view_mode, $view_entities, $mode, $root, $_);
        }
    }
    elsif ($atype eq '4')
    {
        for ( split(/,/, $url_params->{form}->{entities}))
        {
            push @job, $_
                if defined $items->{$_};
        }
    }

    return [0]
        unless @job;

    my $req = $dbh->exec( sprintf(qq|SELECT *, UNIX_TIMESTAMP(status_last_change) AS time2 
        FROM entities WHERE id_entity IN (%s) AND err_approved_by=0|, 
        join(",", @job)) )->fetchall_hashref("id_entity");

    my $time = time();
    my $err_approved_at;
    for $id_entity (keys %$req)
    {
        $err_approved_at = $time - $req->{$id_entity}->{time2};
        $dbh->exec(sprintf(qq|UPDATE entities SET err_approved_by=%s, err_approved_at=%s, err_approved_ip='%s' WHERE id_entity=%s|,
            $id_user, $err_approved_at, $ip, $id_entity));
        $dbh->exec(sprintf(qq|INSERT INTO history24 values(DEFAULT, %d, %d, %d, '%s', NOW(), %s, %s, '%s', 0)|,
            $id_entity, $req->{$id_entity}->{status}, $req->{$id_entity}->{status},
            ($req->{$id_entity}->{flap} ? $req->{$id_entity}->{flap_errmsg} : $req->{$id_entity}->{errmsg}),
            $err_approved_at, $id_user, $ip));
    }

    if (keys %$req)
    {
        $tree->reload_node([keys %$req], 1);
       # $tree->cache_save(); reload_node z parameterm 1 to zalatwia
    }

    flag_file_check($TreeCacheDir, "master_hold", 1);

    return [0];
}

1;
