package WSTree;

use base qw(WSBase);
use strict;

use Configuration;
use Constants;
use Common;
use Log;
use Tree;
use JSON;
use POSIX;


our $LogEnabled = CFG->{LogEnabled};
our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};
our $ImagesDir = CFG->{ImagesDir};
our $ProbesMapRev = CFG->{ProbesMapRev};

our $tree;
our $probes;

sub get
{
    my $self = shift;

    my $url_params = $self->url_params;
#use Data::Dumper; warn Dumper($url_params);
    my $id_user = $self->session->param('_LOGGED');

    if (! $self->is_logged || ! $id_user)
    {
        return 2;
    }

#    $self->header;

    my $nid = defined $url_params->{form} && defined $url_params->{form}->{node}
        ? $url_params->{form}->{node}
        : 0;

    $tree = Tree->new({url_params => $url_params, id_user => $id_user, db => $self->dbh, root_only => 0 });

    if (defined $url_params->{wskey} && $url_params->{wskey})
    {
        my $wskey = $url_params->{wskey};
        $wskey = "ext_$wskey";
        return $self->$wskey;
    }

    my $slv = $tree->slaves;

    return to_json([])
        unless defined $slv->{$nid};

    my @chlist = keys %{$slv->{$nid}};

    my $items = $tree->items;

    return to_json([])
        if $items->{$nid}->id_probe_type;

    if (! keys %{ $tree->items })
    {
        print sprintf(qq|<html><head><meta http-equiv="Refresh" content="60 url="></head><body><h2>internal akk\@da error: entities cache unavailable. probably it is stopped.</h2><bgsound SRC="%s" loop=1></body></html>|,
            CFG->{Web}->{SoundAlarmFile}->{6});
        exit;
    };

    my @result;
    my $leaf;
    my $item;

    for (@chlist) {
        next
            unless defined $items->{$_};

        $item = $items->{$_};

        $leaf = ! $item->id_probe_type # && $item->is_node
            ? JSON::false
            : JSON::true;

        push @result,
        {
            id => $_, 
            text => $item->name,
            leaf => $leaf,
            icon => sprintf(qq|../img/%s.gif|, $item->image_function),
        };
    }

    return to_json(\@result);
}

sub ext_move
{
    my $self = shift;

    my $db = $self->dbh;
    my $url_params = $self->url_params;

    my $entity;

    eval
    {
        $entity = Entity->new($db, $url_params->{form}->{node});
    };

    return "internal: cannot load entity"
        unless $entity;

    flag_files_create($TreeCacheDir, "master_hold");

    my $id_parent = $entity->id_parent;
    my $id_parent_new = $url_params->{form}->{parent};

    return 1
        if $id_parent_new eq $id_parent;

    if ($entity->id_probe_type || $id_parent_new)
    {
        if ($entity->id_probe_type && !$id_parent_new)
        {
            flag_file_check($TreeCacheDir, "master_hold", 1);
            return "root can contain only groups";
        }

        my $parent;
        eval
        {
            $parent = Entity->new($db, $id_parent_new);
        };

        if (! $parent)
        {
            flag_file_check($TreeCacheDir, "master_hold", 1);
            return "unknown parent";
        }

        if ($parent->id_probe_type > 0)
        {
            flag_file_check($TreeCacheDir, "master_hold", 1);
            return "only group can be a parent";
        }
    }

    my $path = $tree->get_node_path($id_parent_new);

    for (@$path)
    {
        if ($_ eq $url_params->{form}->{node})
        {
            flag_file_check($TreeCacheDir, "master_hold", 1);
            return sprintf(qq|id_parent %s is id_entity %s child. change impossible.|,
                $id_parent_new, $url_params->{form}->{node});
        }
    }

    if ($id_parent && $id_parent_new)
    {
        $db->exec(sprintf(qq|UPDATE links SET id_parent=%d WHERE id_child=%d|,
            $url_params->{form}->{parent}, $url_params->{form}->{node}));
    }
    elsif ($id_parent)
    {
        $db->exec(sprintf(qq|DELETE FROM links WHERE id_child=%d|, $url_params->{form}->{node}));
    }
    else
    {
        $db->exec(sprintf(qq|INSERT INTO links VALUES(%d,%d)|,
            $url_params->{form}->{parent}, $url_params->{form}->{node}));
    }

    $tree->move_node($url_params->{form}->{node}, $id_parent, $id_parent_new);

    $entity->status_calc_flag_create( $id_parent_new )
        if $id_parent_new;
    $entity->status_calc_flag_create( $id_parent )
        if $id_parent;

    flag_files_create(CFG->{FlagsControlDir}, 'entities_init.Available');
    flag_files_create(CFG->{FlagsControlDir}, 'available2.init_graph');

    $tree->reload_node( $entity->id_entity, 1 );
    flag_file_check($TreeCacheDir, "master_hold", 1);

    return 1;
}


sub image
{
    my $self = shift;
    my $name = shift || '';
    my $what = shift || '';

    return ''
        unless $name;

    my $img = -e "$ImagesDir/$name.gif"
        ? "/img/$name.gif"
        : "/img/unknown.gif";

    return $self->cgi->img({ src=>$img, class => "o", alt => "$what: $name"})
}

sub load_probes
{
    my $self = shift;

    my $libdir = CFG->{LibDir} . "/Probe";
    my ($file, $probe);

    opendir(DIR, $libdir);
    while ( defined($file = readdir(DIR)) )
    {
        next
            if $file !~ /\.pm$/;
        $file = (split /\.pm$/, $file)[0];
        eval "require Probe::$file; \$probe = Probe::${file}->new();" or die $@;
        $probes->{$file} = $probe;
    }
    closedir(DIR);
}

sub ext_entgeninfo
{
    my $self = shift;

    my $url_params = $self->url_params;

    my $eid = defined $url_params->{form} && defined $url_params->{form}->{eid}
        ? $url_params->{form}->{eid}
        : 0;

    my $items = $tree->items;

    return 
        unless defined $items->{$eid};

    my $item = $items->{$eid};

    my $entity;

    eval
    {
        $entity = Entity->new($self->dbh, $eid);
    };

    return "internal: cannot load entity"
        unless $entity;

    my $last_change = $entity->status_last_change && $entity->monitor
        ? strftime("%D %T", localtime($entity->status_last_change))
        : 'n/a';

my $result = [
{
eid => 0,
vendor => '',
name => '<span class="ak-tbl-head">name</span>',
status => '',
statusid => 0,
function => '',
last_change => '<span class="ak-tbl-head">last change</span>',
last_check => '<span class="ak-tbl-head">age of data</span>',
},
];
my $result = [
{
eid => $eid,
vendor => $self->image($item->image_vendor, 'vendor'),
name => $item->name,
status => status_name($item->get_calculated_status),
statusid => $item->get_calculated_status,
function => $self->image($item->image_function, 'function'),
last_change => $last_change,
last_check => entity_get_last_check_timestamp($entity),
}
];

return "{results:" . to_json($result) . "}";

}

sub ext_entinfo
{
    my $self = shift;

    my $url_params = $self->url_params;

    my $eid = defined $url_params->{form} && defined $url_params->{form}->{eid}
        ? $url_params->{form}->{eid}
        : 0;

    my $entity;

    eval
    {
        $entity = Entity->new($self->dbh, $eid);
    };

    return "internal: cannot load entity"
        unless $entity;

    $self->load_probes;

    my $probe = $ProbesMapRev->{ $entity->id_probe_type };

    return $probe && $entity->id_probe_type 
        ? $probes->{$probe}->desc_full($entity, $self->url_params) 
        : ''
}

1;
