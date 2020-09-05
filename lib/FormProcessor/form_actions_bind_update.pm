package FormProcessor::form_actions_bind_update;

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
use Log;

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};
our $FlagsControlDir = CFG->{FlagsControlDir};


sub dispatch
{
    my $url_params = shift;

    my $f = $$url_params->{form};

    my @t;
    my @u;
    my $g;

    for my $s (keys %$f)
    {
        next
            if $s eq 'id_entity';
        next
            if $s eq 'form_name';
        @t = split /\./, $s, 2;
        @u = split /\./, $t[1], 4;
        if ($t[0] eq 'delete'
            || ($t[0] eq 'id_action' && $u[1] != $f->{$s})
            || ($t[0] eq 'id_cgroup' && $u[2] != $f->{$s})
            || ($t[0] eq 'id_time_period' && $u[3] != $f->{$s}))
        {
            $g->{$t[1]}->{$t[0]} = $f->{$s};
        }
    }
    $$url_params->{form} = $g;
}

sub condition
{
    my $key = shift;
    return sprintf(qq|id_entity=%s AND id_action=%s AND id_cgroup=%s AND id_time_period=%s|, split(/\./, $key) );
}

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $id_entity = $url_params->{form}->{id_entity};

    dispatch(\$url_params);

    my $db = DB->new();

    flag_files_create($TreeCacheDir, "master_hold");
    my $tree = Tree->new({db => $db, with_rights => 0});
    my $items = $tree->items;

    my @st;

    eval
    {

    for (keys %{ $url_params->{form} })
    {
        @st = ();
        if (defined $url_params->{form}->{$_}->{delete})
        {
            log_debug(sprintf(qq|DELETE FROM entities_2_actions WHERE %s|, condition($_)),_LOG_ERROR);
            $db->dbh->do( sprintf(qq|DELETE FROM entities_2_actions WHERE %s|, condition($_)));
        }
        else
        {
            die 'select action'
                if ! defined $url_params->{form}->{$_}->{id_action}
                && ! defined $url_params->{form}->{$_}->{id_cgroup}
                && ! defined $url_params->{form}->{$_}->{id_time_period};

            push @st, sprintf(qq|id_action=%s|, $url_params->{form}->{$_}->{id_action})
                if defined $url_params->{form}->{$_}->{id_action};
            push @st, sprintf(qq|id_cgroup=%s|, $url_params->{form}->{$_}->{id_cgroup})
                if defined $url_params->{form}->{$_}->{id_cgroup};
            push @st, sprintf(qq|id_time_period=%s|, $url_params->{form}->{$_}->{id_time_period})
                if defined $url_params->{form}->{$_}->{id_time_period};

            log_debug(sprintf(qq|UPDATE entities_2_actions SET %s WHERE %s|, join(",",@st), condition($_)), _LOG_ERROR);
            $db->dbh->do(sprintf(qq|UPDATE entities_2_actions SET %s WHERE %s|, join(",",@st), condition($_)));
        }
    }

    };

    if ($@)
    {
        flag_file_check($TreeCacheDir, "master_hold", 1);
        if ($@ =~ /Duplicate entry/)
        {
            return [1, 'duplicate entry'];
        }
        return [1, $@];
    }

    my $ids = child_get_ids($db, $id_entity);
    push @$ids, $id_entity;
    flag_files_create($FlagsControlDir, "$_.load_actions")
        for @$ids;


    $tree->reload_node( $id_entity, 4 );
    $tree->cache_save;
    flag_file_check($TreeCacheDir, "master_hold", 1);
    flag_files_create($FlagsControlDir, "actions_load");

    return [0, ''];
}

1;
