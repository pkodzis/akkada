package Tree;

use vars qw($VERSION $AUTOLOAD %ok_field %ro_field);

$VERSION = 1.0;

use strict;

use Carp;
use DB;
use Tree::Node;
use Constants;
use Common;
use URLRewriter;
use Configuration;
use Cache::File;
use CGI;
use Log;
use Data::Dumper;
use Bit::Vector;

our $Tree = CFG->{Web}->{Tree};
our $TreeLowLevelDebug = CFG->{Web}->{Tree}->{TreeLowLevelDebug};
our $MaxMasterHoldTime = CFG->{Web}->{Tree}->{MaxMasterHoldTime};
our $GroupMode = CFG->{Web}->{Tree}->{GroupMode};
our $FlagsControlDir = CFG->{FlagsControlDir};
our $ImagesDir = CFG->{ImagesDir};
our $ProbesMapRev = CFG->{ProbesMapRev};
our $ProbesMap = CFG->{ProbesMap};
our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};
our $TreeCachePeriod = CFG->{Web}->{TreeCachePeriod} || 5;
our $LogEnabled = CFG->{LogEnabled};
our $StatusRecoveredDeltaTime = CFG->{Web}->{StatusRecoveredDeltaTime} || 60;

# to dla Tree::Node
use constant
{
    ID => 0,
    IS_NODE => 1,
    RIGHTS => 2,

    IMAGE_FUNCTION => 5,
    IMAGE_VENDOR => 6,
    ERR_APPROVED_BY => 7,
    NAME => 8,
    MONITOR => 9,
    IP => 10,
    ID_PROBE_TYPE => 11,
    STATE => 12,
    STATE_WEIGHT => 13,
    STATE_LAST_CHANGE => 14,
    STATUS => 16,
    STATUS_WEIGHT => 17,
    STATUS_LAST_CHANGE => 18,
    ERRMSG => 20,
    FLAP => 22,
    FLAP_COUNT => 23,
    CGROUPS => 24,
    COMMENTS => 25,
    SNMPGDEF => 26,
    ACTIONS => 27,
};

for my $attr (qw( 
		  id_user
		  data
		  cache
		  cmd
                  tree
                  root
                  db
                  ips
                  snmpgdef
                  actions
                  statuses
                  links
                  relations
                  functions
                  rights 
                  root_only
                  preview
                  vendors
                  master
                  nodes 
                  items                  
                  cur
                  selected
                  selected_item
                  total
                  total_m
                  url_params
                  with_rights
             )) { $ok_field{$attr}++; } 

for my $attr (qw( 
		  id_user
		  cache
                  ips
                  statuses
                  nodes
                  total
             )) { $ro_field{$attr}++; } 

our $COMMANDS = 
{
    'add' => 1,
    'reload' => 1,
    'move' => 1,
    'dump_cache_item' => 1,
};

sub AUTOLOAD
{
  my $self = shift;
  my $attr = $AUTOLOAD;
  $attr =~ s/.*:://;
  return unless $attr =~ /[^A-Z]/; 
#if (! $ok_field{$attr})
#{
#use Data::Dumper; warn Dumper([caller(0)]);
#use Data::Dumper; warn Dumper([caller(1)]);
#use Data::Dumper; warn Dumper([caller(2)]);
#use Data::Dumper; warn Dumper([caller(3)]);
#use Data::Dumper; warn Dumper([caller(4)]);
#}
  die "invalid attribute method: ->$attr()" unless $ok_field{$attr};
  die "ro attribute method: ->$attr()" if $ro_field{$attr} && @_;
  $self->{uc $attr} = shift if @_;
  return $self->{uc $attr};
}

sub _locked
{
    my $self = shift;
    return
        unless $self->master;

    my $mh = 0;
    while (flag_file_check($TreeCacheDir, 'master_hold'))
    {
        log_debug(qq|cache locked by slave|, _LOG_WARNING)
            if $LogEnabled;
        sleep $TreeCachePeriod;
        ++$mh;
        if ($mh > $MaxMasterHoldTime)
        {
            flag_file_check($TreeCacheDir, 'master_hold', 1);
            log_debug(qq|master process forced cache unlock|, _LOG_WARNING)
                if $LogEnabled;
        }
    }
    if (flag_file_check($TreeCacheDir, 'init_from_db', 1))
    {
        $self->init('force_db');
    }
    elsif (flag_file_check($TreeCacheDir, 'init_from_cache', 1))
    {
        $self->init;
    }
}

sub run_cache
{
    my $self = shift;
    my $ppid = shift;

    return 
        unless $self->master;

    $SIG{USR1} = \&got_sig_usr1;
    $SIG{USR2} = \&got_sig_usr2;
    $SIG{TRAP} = \&trace_stack;

    my $file;
    my $id;
    my $command;

    my $flag;
    my $rights_change;
    my $acts;
    my $items;

    while(1)
    {
        exit
            if ! kill(0, $ppid);

        $flag = 0;
        $rights_change = 0;
        $acts = {};
        $items = $self->items;

        $self->_locked;

        if (flag_file_check($TreeCacheDir, 'rights_init', 1))
        {
            $self->_rights_init;
            ++$rights_change;
        }

        opendir(DIR, $TreeCacheDir);
        while (defined($file = readdir(DIR)))
        {
	    ($command, $id) = split /\./, $file, 2;

            next
                unless defined $COMMANDS->{$command};

            $self->_locked;
            if ($command eq 'reload')
            {
#use Data::Dumper; log_debug("PREF: $id ". Dumper($items->{$id}),_LOG_ERROR);
                if (defined $items->{$id})
                {
#log_debug("AA: $id reload",_LOG_ERROR);
                    push @{$acts->{reload}}, $id;
                }
                else
                {
#log_debug("AA: $id add",_LOG_ERROR);
                    push @{$acts->{load}}, $id;
                }
            }
            elsif ($command eq 'move')
            {
                $self->move_node( split(/\./, $id) );
            }
            elsif ($command eq 'add')
            {
#log_debug("GG: $id add",_LOG_ERROR);
                push @{$acts->{load}}, $id;
            }
            elsif ($command eq 'dump_cache_item')
            {
                $self->dump_cache_item($id, 0);
            }

            unlink "$TreeCacheDir/$file";

            ++$flag;
        }
        closedir(DIR);

   
        $self->reload_node($acts->{reload}, 1)
            if defined $acts->{reload};
        $self->load_node($acts->{load})
            if defined $acts->{load};

        if ($flag || $rights_change)
        { 
            log_debug("cache saved after $flag changes. " . ($rights_change ? "rights were udated." : ''), _LOG_INFO)
                if $LogEnabled;
            $self->cache_save;
        }

        if (flag_file_check($TreeCacheDir, 'dump_cache', 1))
        {
            $self->dump_cache;
        }
        elsif (flag_file_check($TreeCacheDir, 'dump_cache_full', 1))
        {
            $self->dump_cache_full;
        }
 
        sleep $TreeCachePeriod;
    }
}

sub load_node
{
    my $self = shift;
    my $id = shift;

    my $items = $self->items;

    $id = [ $id ]
        unless ref($id);
    my $ids;
    for (@$id)
    {
        $ids->{$_} = 1
            unless defined $items->{$_};
    }

#log_debug("X: " . join("-", @$id),_LOG_ERROR);
#log_debug("X2: ids " . join("-", keys %$ids),_LOG_ERROR);
    return
        unless keys %$ids;

    $self->_init_db;

    my $links = $self->links;
    my $id_parent;
    my $missing_parents = [];

    for (keys %$ids)
    {
        $id_parent = $links->{ $_ };
        next
            unless defined $id_parent;

        push @$missing_parents, $id_parent
            if $id_parent && ! defined $items->{$id_parent};
    }
    if (@$missing_parents)
    {
        $self->load_node($missing_parents);
        $self->_init_db;
    }

#log_debug("START LAOD: " . join("-", keys %$ids), _LOG_ERROR);
    my $params = $self->get_node_params([keys %$ids]);
    my $node;

    for (keys %$params)
    {   
        $node = $self->make_node ($params->{$_});

        $id_parent = $links->{ $_ };
        $id_parent = 0
            unless defined $id_parent;

        $self->{DATA}->{RELATIONS}->{$_} = $id_parent;

        $self->{DATA}->{ITEMS}->{$_} = $node;
#use Data::Dumper; log_debug("JOB: " . Dumper($self->{DATA}->{ITEMS}->{$_}), _LOG_ERROR);
        $self->{DATA}->{ITEMS}->{$id_parent}->is_node(1);
        $self->{DATA}->{SLAVES}->{$id_parent}->{$_} = 1;
    }
#log_debug("LAOD READY: " . join("-", keys %$ids), _LOG_ERROR);for (keys %{$self->items}) { log_debug("$_: " . $self->items->{$_}->name, _LOG_ERROR); }
    $self->_rights_init;

    $self->cache_save;
}

sub remove_node
{
    my $self = shift;
    my $id = shift;

    my $items = $self->items;
    my $rel = $self->relations;
    my $slv = $self->slaves;
    my $children = $self->get_node_down_family($id);

    for (keys %$children)
    {
        delete $items->{$_};
        delete $rel->{$_};
        delete $slv->{$_};
        delete $self->{PREVIEW}->{$_}; #PREVIEW jest to samo co svl tylko po nalozeniu uprawnien

        flag_files_create($FlagsControlDir, sprintf(qq|%s.remove|, $_));
    }

    my $pid = delete $rel->{$id};

    delete $items->{$id};
    delete $slv->{$pid}->{$id};
    delete $slv->{$id};
    delete $self->{PREVIEW}->{$id};
    flag_files_create($FlagsControlDir, sprintf(qq|%s.remove|, $id));

    $self->fix_is_node($pid);

#    CACHE SAVE odbywa sie w FORM_ENTITY_DELETE
#    $self->cache_save
#        unless $multi_service_mode;

    log_debug(sprintf(qq|delted node %s and its children|, $id), _LOG_INTERNAL)
        if $LogEnabled;
}

sub fix_is_node
{
    my $self = shift;
    my $id = shift;
    my $node = $self->items->{$id};
    return
        unless defined $node;
    if (scalar (keys %{$self->slaves->{$id}}) == 0)
    {
        $node->is_node(0);
    }
    else
    {
        $node->is_node(1);
    }
}

sub move_node
{
    my $self = shift;
    my $id = shift;
    my $old = shift;
    my $new = shift;

    my $items = $self->items;
    my $rel = $self->relations;
    my $slv = $self->slaves;

    if (defined $items->{$new})
    {
        $rel->{$id} = $new;
        $self->{PREVIEW}->{$id} = $new;

        delete $slv->{$old}->{$id};
        $slv->{$new}->{$id} = 1;

        $self->fix_is_node($old);
        $self->fix_is_node($new);

        log_debug(sprintf(qq|node %s: %s => %s|, $id, $old, $new), _LOG_INTERNAL)
            if $LogEnabled;
        $self->_rights_init($id);
        $self->cache_save;
    }
    else
    {
        log_debug(sprintf(qq|node %s: %s => %s not possible; node %s does not exists|, $id, $old, $new, $new), _LOG_ERROR)
            if $LogEnabled;
    }
}

sub get_node_params
{
    my $self = shift;
    my $ids = shift;

    my $db = $self->db;

    my $res = {};

    my $status_calc = $db->exec( sprintf(qq|select id_entity,status,status_weight,UNIX_TIMESTAMP(last_change) AS last_change from statuses where id_entity in (%s)|, join(",", @$ids)) )->fetchall_hashref("id_entity");

    my $nd = $db->exec( sprintf(qq|SELECT err_approved_by,monitor,id_entity,status,status_weight,errmsg,name,
        UNIX_TIMESTAMP(status_last_change) AS status_last_change, id_probe_type, flap, flap_status, flap_errmsg, flap_count
        FROM entities WHERE id_entity in (%s)|, join(",", @$ids)) )->fetchall_hashref("id_entity");

    my $vendor = $db->exec( sprintf(qq|select entities.id_entity,value from entities,parameters,entities_2_parameters where entities.id_entity=entities_2_parameters.id_entity and parameters.id_parameter=entities_2_parameters.id_parameter and parameters.name='vendor' and (entities.id_entity in (%s))|, join(",", @$ids)) )->fetchall_hashref("id_entity");

    my $function = $db->exec( sprintf(qq|select entities.id_entity,value from entities,parameters,entities_2_parameters where entities.id_entity=entities_2_parameters.id_entity and parameters.id_parameter=entities_2_parameters.id_parameter and parameters.name='function' and (entities.id_entity in (%s))|, join(",", @$ids)) )->fetchall_hashref("id_entity");

    my $ip = $db->exec( sprintf(qq|select entities.id_entity,value from entities,parameters,entities_2_parameters where entities.id_entity=entities_2_parameters.id_entity and parameters.id_parameter=entities_2_parameters.id_parameter and parameters.name='ip' and (entities.id_entity in (%s))|, join(",", @$ids)) )->fetchall_hashref("id_entity");

    my $snmpgdef = $db->exec( sprintf(qq|select entities.id_entity,value from entities,parameters,entities_2_parameters where entities.id_entity=entities_2_parameters.id_entity and parameters.id_parameter=entities_2_parameters.id_parameter and parameters.name='snmp_generic_definition_name' and (entities.id_entity in (%s))|, join(",", @$ids)) )->fetchall_hashref("id_entity");

    for (@$ids)
    {
        next
            unless defined $nd->{$_};
        $res->{$_} =
        {
            id => $_,
            status_calc => $status_calc->{$_},
            nd => $nd->{$_},
            vendor => $vendor->{$_} ? $vendor->{$_}->{value} : '',
            function => $function->{$_} ? $function->{$_}->{value} : '',
            ip => $ip->{$_} ? $ip->{$_}->{value} : '',
            snmpgdef => $snmpgdef->{$_} ? $snmpgdef->{$_}->{value} : undef,
        }
    }
    return $res;
}

sub reload_node
{
    my $self = shift;
    my $ids = shift;
    my $cache_save = defined $_[0] ? shift : 1;

    my $items = $self->items;

    $ids = [ $ids ]
        unless ref($ids);

    if ($cache_save == 2)  #used by form_bind_contacts* for update contact groups of entity
    {
        return
            unless defined $items->{ $ids->[0] };
        $items->{ $ids->[0] }->cgroups({});
        my $req = $self->db->exec("SELECT * FROM entities_2_cgroups WHERE id_entity = $ids->[0]");
        while( my $h = $req->fetchrow_hashref )
        {
            $items->{ $h->{id_entity} }->cgroups->{ $h->{id_cgroup} } = 1;
        }
    }

    if ($cache_save == 4)  #used by form_actions_bind_* for update actions
    {
        return
            unless defined $items->{ $ids->[0] };
        $items->{ $ids->[0] }->actions({});
        my $slv = $self->slaves;
        $slv = defined $slv->{ $ids->[0] } ? $slv->{ $ids->[0] } : {};
        my $statement = sprintf("SELECT id_entity,id_e2a FROM entities_2_actions WHERE id_entity=%s", $ids->[0]);
        $statement .= sprintf(" or id_entity in (%s)", join(',', keys %$slv))
            if keys %$slv;
        my $req = $self->db->exec($statement);
        while( my $h = $req->fetchrow_hashref )
        {
            $items->{ $h->{id_entity} }->actions->{ $h->{id_e2a} } = 1;
        }
    }

    if ($cache_save == 3)  #used by form_comments_* for update comments information
    {
        return
            unless defined $items->{ $ids->[0] };
        $items->{ $ids->[0] }->comments(0);
        my $req = $self->db->exec("SELECT * FROM comments WHERE id_entity = $ids->[0]");
        $req = $req->fetchrow_hashref;
        $items->{ $ids->[0] }->comments(1)
             if $req;
    }

#log_debug("START RELAOD: " . join("-", @$ids), _LOG_ERROR);
    my $params = $self->get_node_params($ids);

#use Data::Dumper; log_debug(Dumper($items->{ $ids->[0] }), _LOG_ERROR);
#use Data::Dumper; log_debug(Dumper($params->{ $ids->[0] }), _LOG_ERROR);
    for (keys %$params)
    {
        next 
            unless defined $items->{ $_ };
        $self->make_node
        (
            $params->{$_},
            $items->{$_},
        );
    }
#log_debug("RELAOD READY: " . join("-", @$ids), _LOG_ERROR);

    $self->cache_save
        if $cache_save;
}

sub new 
{
    my $class = shift;
    my $param = shift;
    my $self = 
    {
        DATA => 
        {
            TREE => undef,
            ITEMS => {},
            RELATIONS => {},
            SLAVES => {},
        },
        LINKS => undef,
        ROOT => undef,
        STATUSES => undef,
        IPS => undef,
        NODES => undef,
        VENDORS => undef,
        FUNCTIONS => undef,
        SNMPGDEF => undef,
        SELECTED_ITEM => defined $param->{url_params} ? $param->{url_params}->{id_entity} : undef,
        URL_PARAMS => defined $param->{url_params} ? $param->{url_params} : {},
        WITH_RIGHTS => defined $param->{with_rights} ? $param->{with_rights} : 1,
        ID_USER => $param->{id_user},
        DB => $param->{db},
        ROOT_ONLY => $param->{root_only},
        CACHE => Cache::File->new( cache_root => $TreeCacheDir, cache_umask => 000),
        MASTER => defined $param->{master} ? $param->{master} : 0,
    };

    bless $self, $class;

    $self->init;

    if ($TreeLowLevelDebug)
    {
        $self->dump_cache();
        warn "RIGHTS table: " . Dumper $self->rights;
    }

    return $self;
}

sub tree
{
    return $_[0]->{DATA}->{TREE};
}

sub items
{
    return $_[0]->{DATA}->{ITEMS};
}

sub relations
{
    return $_[0]->{DATA}->{RELATIONS};
}

sub slaves
{
    return $_[0]->{DATA}->{SLAVES};
}

sub dump_cache
{
    my $self = shift;
    my $l = @_ ?  shift : 0;
    my $id = @_ ? shift : 0;

    my $n = $self->items->{$id};

    log_debug(". "x$l . "-: " . $id . "; rights: " . Dumper($n->[RIGHTS]) . "; status: " . $n->status . "; state: ". $n->state . "; name: " . $n->name, _LOG_ERROR);

    ++$l;
    my $rel= $self->relations;
    for (grep { $rel->{$_} == $id } keys %$rel)
    {
        $self->dump_cache($l, $_);
    }
}

sub dump_cache_full
{
    log_debug(Dumper($_[0]), _LOG_ERROR);
}

sub dump_cache_item
{
    my $self = shift;
    my $id = @_ ? shift : 0;
    warn Dumper($self->items->{$id});
}

sub parent
{
    my $self = shift;
    my $id = shift;
   
    return $self->items->{ $self->relations->{$id} }; 
}

sub _clear_data
{
    my $self = shift;
    $self->{ROOT} = undef;
    $self->{DATA}->{TREE} = undef;
    $self->{DATA}->{ITEMS} = undef;
    $self->{DATA}->{RELATIONS} = undef;
    $self->{DATA}->{SLAVES} = undef;
}

sub reinit
{
    my $self = shift;

    return
        unless $self->master;
    
    my $sync = @_ ? shift : 0;

    $self->_clear_data;
    $self->_init_db;
    $self->_init_tree;
    $self->_rights_init;

    $self->cache->clear()
        if $self->master;

    $self->cache_save;

    log_debug(sprintf(qq|tree initialized; cache size: %s|, $self->cache->size()), _LOG_WARNING)
        if $LogEnabled;
}

sub replace_data
{
    my $self = shift;
    my $data = shift;
    delete $self->{ROOT};
    delete $self->{DATA};
    $self->{DATA} = $data;
    $self->{ROOT} = $data->{ITEMS}->{0};
}

sub init_global_db
{
    my $self = shift;

    my $dbh = $self->db->dbh;

    $self->{TOTAL} = $dbh->selectall_arrayref("select count(*) from entities")->[0]->[0];
    $self->{TOTAL_M} = $dbh->selectall_arrayref("select count(*) from entities where monitor<>0")->[0]->[0];
    $self->{VIEWS} = $dbh->selectall_hashref("select id_view,name,status,function,UNIX_TIMESTAMP(last_change) AS last_change,id_view_type from views", "id_view");
}

sub init
{
    my $self = shift;
    my $force_db =  @_ ? shift : 0;

    $self->init_global_db;

    if ($self->master)
    {
        if ($force_db)
        {
            $self->reinit;
        }
        else
        {
            my $data = $self->cache->thaw('gui_data');
            $data
                ? $self->replace_data($data)
                : $self->reinit;
        }
    }
    else
    {
        log_debug("starting loading tree", _LOG_INTERNAL)
            if $LogEnabled;
        my $data = $self->cache->thaw('gui_data');

        if ($data)
        {
            $self->replace_data($data);
            log_debug("building preview", _LOG_DEBUG)
                if $LogEnabled;
            $self->make_preview;
            log_debug("preview ready", _LOG_DEBUG)
                if $LogEnabled;
        }
        log_debug("tree loaded", _LOG_INTERNAL)
            if $LogEnabled;
    }
#log_debug(Dumper($self), _LOG_ERROR);
}

sub _rights_init
{
    my $self = shift;
    my $selected = @_ ? shift : 0;
    my $items = $self->items;
    my $rel = $self->relations;

    log_debug("building rights", _LOG_DEBUG)
        if $LogEnabled;

    my $dbh = $self->db->dbh;
    my @groups = map $_->[0], @{ $self->db->exec( qq|SELECT id_group FROM groups| )->fetchall_arrayref };

    my $rg;

    $self->{RIGHTS} = {};

    for my $group (@groups)
    {

        $rg = $dbh->selectall_hashref(
            sprintf(qq|SELECT id_group, id_entity, SUM(vie) AS vie, SUM(mdy) AS mdy, SUM(cre) AS cre,
            SUM(del) AS del, SUM(com) AS com, SUM(vio) AS vio, SUM(cmo) AS cmo, SUM(ack) AS ack
            FROM rights
            WHERE disabled=0 AND id_group=%s GROUP BY id_entity|,
            $group), "id_entity");
        for (keys %$rg)
        {
            $self->{RIGHTS}->{$_}->{$group} = 
                sprintf(qq|%s%s%s%s%s%s%s%s|,
                    $rg->{$_}->{del} ? 1 : 0,
                    $rg->{$_}->{cre} ? 1 : 0,
                    $rg->{$_}->{mdy} ? 1 : 0,
                    $rg->{$_}->{ack} ? 1 : 0,
                    $rg->{$_}->{cmo} ? 1 : 0,
                    $rg->{$_}->{com} ? 1 : 0,
                    $rg->{$_}->{vio} ? 1 : 0,
                    $rg->{$_}->{vie} ? 1 : 0);
        }
    }

    $self->set_rights($self->slaves, $self->relations, $self->items, $self->rights,
        $selected, 0, users_init($self->db));

    log_debug("rights ready", _LOG_DEBUG)
        if $LogEnabled;
}

sub set_rights
{
    my ($self, $slv, $rel, $items, $rights, $id_selected, $id, $users) = @_;

    my $r;

    $items->{ $id }->[RIGHTS] = {};
    for my $id_user (keys %$users)
    {
        $r = $self->get_rights($id, $rights, $users->{$id_user}->groups);

        if (! defined $r)
        {
            if (defined $items->{ $rel->{$id} })
            {
                 $r = $items->{ $rel->{$id} }->rights($id_user);
            }
        }

        $items->{$id}->rights( $id_user, defined $r 
            ? $r 
            : ( defined $items->{ $rel->{$id} } 
                ? $items->{ $rel->{$id} }->rights($id_user)
                : '00000000'
            )
        );
    }

    for ( grep { $_ != $id } keys %{ $slv->{$id} })
    {
        $self->set_rights($slv, $rel, $items, $rights, $id_selected, $_, $users);
    }
}

sub get_rights
{   
    my ($self, $id_entity, $r, $groups) = @_;
    
    return undef
        unless defined $r->{$id_entity};

    my $v1 = Bit::Vector->new(8); 
    my $v2 = Bit::Vector->new(8);

    my $i = 0; 
    for (@$groups)
    {
        if (defined $r->{$id_entity}->{$_})
        {
            $v2->from_Bin($r->{$id_entity}->{$_});
            $v1->Or($v1, $v2);
            $i++;
        }
    }

    return $i
        ? $v1->to_Bin()
        : undef;
}

sub make_preview
{
    my $self = shift;
    my $hide_not_monitored = shift || 0;
    my $cur = $self->selected_item;
      
    my $o;
    my $items = $self->items;
    my $rel = $self->relations;

    my $url_params = $self->url_params;
    my $selected;
    $selected = $items->{ $url_params->{id_entity} }
        if defined $url_params->{id_entity};
    $selected = $self->root
        unless $selected;

    if ($TreeLowLevelDebug)
    {
        warn "ITEMS: " . join(" ", keys %$items);
        my $tmp;
        for(keys %$items)
        {
            $tmp .= "$_ => " . (defined $rel->{$_} ? $rel->{$_} : 'undef') . "\n";
        }
        warn "ALL ENTITIES PARENTSHIP: " . $tmp;
    }

    $self->selected($selected);

    if ($cur)
    { 
        if ($selected->id_probe_type > 1)
        {
            if (! $Tree->{ShowActiveNodeService} && ! $Tree->{ShowServicesAlarms})
            {
                $cur = $rel->{ $selected->id };
            } 
            elsif (! $Tree->{ShowActiveNodeService} && $Tree->{ShowServicesAlarms})
            {   
                if ($Tree->{ShowServicesAlarms} == 1)
                {   
                    $cur = $rel->{ $selected->id }
                        unless $Tree->{ShowServicesAlarms}
                        && $url_params->{section} eq 'alarms'
                        && $selected->status > _ST_OK
                        && $selected->status < _ST_UNKNOWN;
                }
                elsif ($Tree->{ShowServicesAlarms} == 2)
                { 
                    $cur = $rel->{ $selected->id }
                        unless $Tree->{ShowServicesAlarms} 
                        && $selected->status > _ST_OK
                        && $selected->status < _ST_UNKNOWN;
                } 
            }     
            else
            {
                $cur = $selected->id;
            }
        }
        else
        {
            $cur = $selected->id;
        }
    }

    $cur = 64010
        if (! defined $cur || ! $cur);

    $self->cur($cur);

    my $show;
    my $mode;
    my $gmp;

    if ($GroupMode && defined $url_params->{id_entity})
    {
        if (! $selected->id_probe_type)
        {
            $gmp = $url_params->{id_entity};
        }
        if ($selected->id_probe_type == 1)
        {
            $gmp = $rel->{ $selected->id };
        }
        elsif ($selected->id_probe_type > 1)
        {
            $gmp = $rel->{ $selected->id };
            $gmp = $rel->{ $gmp };
        }
    }

    for my $oid (keys %{ $items } )
    {
        next
            unless $oid;

        $show = 0;

        $o = $items->{$oid};

        ++$show
            if ! $GroupMode && $o->id_probe_type < 2;
        ++$show
            if $GroupMode && ! $o->id_probe_type;

        if (! $show && ! $GroupMode)
        {
            if (! $selected->id_probe_type && defined $url_params->{id_entity})
            {
                $show = 1
                    if $url_params->{id_entity} == $rel->{ $o->id };
            }
            elsif (defined $selected->id && defined $o->id)
            {
                $show = 1
                    if defined $rel->{ $selected->id }
                        && defined $rel->{ $o->id }
                        && $rel->{ $selected->id } == $rel->{ $o->id }
            }
            if ($Tree->{ShowServicesAlarms})
            {
                $mode = $url_params->{mode} || 0;
                $show = 1
                    if $o->status > _ST_OK
                    && $o->status < _ST_UNKNOWN
                    && $o->monitor;
                if ($show && ! $mode)
                {
                    $show = 0
                        if $o->status_weight == 0
                        || $items->{ $rel->{$oid} }->state_weight == 0;
                }
                elsif ($show && $mode == 1)
                {
                    $show = 0
                        if $o->status_weight == 2;
                }
            }
            if ($Tree->{ShowServicesAlarms} == 1 && $url_params->{section} ne 'alarms')
            {
               $show = 0
                   if ! defined $rel->{ $o->id }
                   || ! defined $rel->{ $selected->id }
                   || ! $o->monitor
                   || ($o->status > _ST_OK && $o->status < _ST_UNKNOWN
                   && $selected->id != $rel->{ $o->id }
                   && defined $rel->{ $selected->id } && $rel->{ $selected->id } != $rel->{ $o->id });
            }
        }
        elsif (! $show && $GroupMode)
        {
            $show = 1
                if $rel->{ $o->id } == $gmp;
        }

        next
            unless $show;
        next
            if $hide_not_monitored && ! $o->monitor;

        $self->{PREVIEW}->{$oid} = defined $rel->{ $o->id } ? $rel->{ $o->id } : undef;
    }

    warn "CURRENT PREVIEW: " . Dumper $self->preview
        if $TreeLowLevelDebug;
};

sub cache_save
{
    my $self = shift;
    my $cache = $self->cache;
    my $si = $cache->size();

    if ($self->master && flag_file_check($TreeCacheDir, 'init_from_cache', 1))
    { 
        $self->init;
    }

#use Data::Dumper; log_debug("XXXX: " . Dumper($self->data), _LOG_ERROR);
    $self->cache->freeze( 'gui_data', $self->data);

    flag_files_create($TreeCacheDir, 'init_from_cache')
        unless $self->master;

    log_debug(sprintf(qq|cache saved; size before: %s after: %s|, $si, $cache->size()), _LOG_INFO)
        if $LogEnabled;
}

sub _init_db
{
    my $self = shift;
    my $dbh = $self->db->dbh;

    $self->{LINKS} = $dbh->selectall_arrayref("select * from links");

    $self->{STATUSES} = $dbh->selectall_hashref("select id_entity,status,status_weight,UNIX_TIMESTAMP(last_change) AS last_change from statuses", "id_entity");

    $self->{NODES} = $self->db->dbh->selectall_hashref("SELECT err_approved_by,monitor,id_entity,status,status_weight,errmsg,name,
        UNIX_TIMESTAMP(status_last_change) AS status_last_change, id_probe_type, flap, flap_status, flap_errmsg, flap_count
        FROM entities", "id_entity");

    my $req = $self->db->exec("SELECT * FROM entities_2_cgroups");
    while( my $h = $req->fetchrow_hashref )
    {       
        $self->{NODES}->{ $h->{id_entity} }->{ cgroups }->{ $h->{id_cgroup} } = 1
            if defined $self->{NODES}->{ $h->{id_entity} }; # bez tego if w cacheu pojawiaja sie martwe nody ;/
    }  

    $req = $self->db->exec("SELECT id_entity  FROM comments");
    while( my $h = $req->fetchrow_hashref )
    {       
        $self->{NODES}->{ $h->{id_entity} }->{ comments } = 1
            if defined $self->{NODES}->{ $h->{id_entity} }; # jak wyzej; 
        #przy kasowaniu form_entity_delete pamietac o tabeli comments i entities_2_cgroups
    }  
#log_debug(Dumper($self->nodes),_LOG_ERROR);

    my $tmp;
    my $tmp1;
  
    for my $ar (@{$self->{LINKS}})
    {
        $tmp->{ $ar->[1] } = $ar->[0];
        $tmp1->{ $ar->[0] }->{$ar->[1]} = 1; #do zaladowania akcji, ponizej
    }
  
    for my $ar (@{$self->{LINKS}})
    {
        $tmp->{ $ar->[0] } = 0
            unless defined $tmp->{ $ar->[0] };
    }

    for (keys %{ $self->{NODES} })
    {
        $tmp->{ $_ } = 0
            if ! $self->{NODES}->{$_}->{id_probe_type} && ! defined $tmp->{ $_ };
    }

    $self->{LINKS} =$tmp;

    $req = $self->db->exec("SELECT * FROM entities_2_actions");
    while( my $h = $req->fetchrow_hashref )
    {
        next
            unless defined $self->{NODES}->{ $h->{id_entity} }; # bez tego if w cacheu pojawiaja sie martwe nody ;/
        $self->{NODES}->{ $h->{id_entity} }->{ actions }->{ $h->{id_e2a } } = 1;
        if( defined $tmp1->{ $h->{id_entity} })
        {
            for (keys %{$tmp1->{$h->{id_entity}}})
            {
                next
                    unless defined $self->{NODES}->{$_};
                $self->{NODES}->{ $_ }->{ actions }->{ $h->{id_e2a } } = 0;
            }
        }
    }

    $self->{VENDORS } = $dbh->selectall_hashref("select entities.id_entity,value from entities,parameters,entities_2_parameters where entities.id_entity=entities_2_parameters.id_entity and parameters.id_parameter=entities_2_parameters.id_parameter and parameters.name='vendor'", "id_entity");

    $self->{FUNCTIONS} = $dbh->selectall_hashref("select entities.id_entity,value from entities,parameters,entities_2_parameters where entities.id_entity=entities_2_parameters.id_entity and parameters.id_parameter=entities_2_parameters.id_parameter and parameters.name='function'", "id_entity");

    $self->{SNMPGDEF} = $dbh->selectall_hashref("select * from parameters,entities_2_parameters where parameters.name='snmp_generic_definition_name' and entities_2_parameters.id_parameter = parameters.id_parameter", "id_entity");

    $self->{IPS} = $dbh->selectall_hashref("select * from parameters,entities_2_parameters where parameters.name='ip' and entities_2_parameters.id_parameter = parameters.id_parameter", "id_entity");

    for (keys %{ $self->{IPS} })
    {
        $self->{LINKS}->{$_} = 0
            unless defined $self->{LINKS}->{$_};
    }
}

sub _init_tree
{
    my $self = shift;

    $self->{DATA}->{TREE}->{0} = {};
    $self->{DATA}->{ITEMS}->{0} = Tree::Node->new(
    {
        id => 0,
        name => 'root', 
        state => 127, 
        status => 127, 
    });

    $self->{ROOT} = $self->{DATA}->{ITEMS}->{0};

    return
        if $self->root_only;

    $self->_tree_build($self->{DATA}->{TREE});
    $self->{DATA}->{TREE} = undef;
}

sub get_node
{
    my $self = shift;
    my $id = @_ ? shift : croak("missing argument in get_node");

    return $self->items->{$id};
}

sub _tree_build
{
    my $self = shift;
    my $cur = @_ ? shift : croak("missing argument in tree_build");

    my $items = $self->items;

    for (keys %$cur) 
    {
        $self->_tree_build_children($_, $cur->{$_});
        if ($cur->{$_})
        {
            $self->_tree_build($cur->{$_});
            $items->{$_}->is_node(1)
                if keys %{ $cur->{$_} };
        }
    }

}

sub _tree_build_children
{
    my $self = shift;
    my $cur_id = shift;
    my $cur = shift;

    my $node;
    my $o;
    my $c;

    for $c (grep { $cur_id == $self->{LINKS}->{$_} } keys %{ $self->{LINKS} })
    {   
        next
            unless defined $self->{NODES}->{$c};

        $node = $self->make_node
        ({
            id => $c,
            status_calc => $self->{STATUSES}->{$c},
            ip => $self->{IPS}->{$c} ? $self->{IPS}->{$c}->{value} : undef,
            snmpgdef => $self->{SNMPGDEF}->{$c} ? $self->{SNMPGDEF}->{$c}->{value} : undef,
            vendor => defined $self->{VENDORS}->{$c} ? $self->{VENDORS}->{$c}->{value} : '',
            function => defined $self->{FUNCTIONS}->{$c} ? $self->{FUNCTIONS}->{$c}->{value} : '',
            nd => $self->{NODES}->{$c},
        });

        delete $self->{LINKS}->{$c};
        $cur->{ $c } = {};
        $self->{DATA}->{ITEMS}->{$c} = $node;
        $self->{DATA}->{RELATIONS}->{ $c } = $cur_id;
        $self->{DATA}->{SLAVES}->{ $cur_id }->{ $c } = 1;
    }
}


sub make_node
{
    my $self = shift;

    my $params = shift;
    my $id = $params->{id};
    my $status_calc = $params->{status_calc};
    my $ip = $params->{ip};
    my $vendor = $params->{vendor};
    my $function = $params->{function};
    my $snmpgdef = $params->{snmpgdef};
    my $nd = $params->{nd};

    my $upd = @_ ? shift : 0;

    my $t = time;

    my ($status, $errmsg);

    if ($nd->{flap})
    {
        $status = $nd->{flap_status};
        $errmsg = $nd->{flap_errmsg};
    }
    else
    {
        $status = $nd->{status};
        $errmsg = $nd->{errmsg};
    }

    if ($upd)
    {
        $upd->[NAME] = $nd->{name} ? $nd->{name} : "unknown, id: $id";
        $upd->[IP] = $ip ? $ip : '';
        $upd->[STATE] = $status_calc ? $status_calc->{status} : 127;
        $upd->[STATE_WEIGHT] = $status_calc ? $status_calc->{status_weight} : undef;
        $upd->[STATE_LAST_CHANGE] = $status_calc ? $status_calc->{last_change} : undef;
        $upd->[STATUS] = $status;
        $upd->[STATUS_WEIGHT] = $nd->{status_weight};
        $upd->[STATUS_LAST_CHANGE] = $nd->{status_last_change};
        $upd->[IMAGE_FUNCTION] = $function ? $function : $ProbesMapRev->{ $nd->{id_probe_type} };
        $upd->[IMAGE_VENDOR] = $vendor ? $vendor : '';
        $upd->[ERRMSG] = $errmsg;
        $upd->[ERR_APPROVED_BY] = $nd->{err_approved_by};
        #$upd->[RIGHTS] = '00000000';
        $upd->[MONITOR] = $nd->{monitor};
        $upd->[FLAP] = $nd->{flap};
        $upd->[FLAP_COUNT] = $nd->{flap_count};
        $upd->[SNMPGDEF] = $snmpgdef;
        log_debug(sprintf(qq|node information updated %s|, $id), _LOG_INTERNAL)
            if $LogEnabled;
        return;
    }
#use Data::Dumper; log_debug(Dumper($nd),_LOG_ERROR);
    return Tree::Node->new(
    {
        id => $id,
        name => $nd->{name} ? $nd->{name} : "unknown, id: $id",
        id_probe_type => $nd->{id_probe_type},
        ip => $ip ? $ip : '',
        state => $status_calc ? $status_calc->{status} : 127,
        state_weight => $status_calc ? $status_calc->{status_weight} : undef,
        state_last_change => $status_calc ? $status_calc->{last_change} : undef,
        status => $status,
        status_weight => $nd->{status_weight},
        status_last_change => $nd->{status_last_change},
        image_function => $function ? $function : $ProbesMapRev->{ $nd->{id_probe_type} },
        image_vendor => $vendor ? $vendor : '',
        errmsg => $errmsg,
        err_approved_by => $nd->{err_approved_by},
        monitor => $nd->{monitor},
        flap => $nd->{flap},
        flap_count => $nd->{flap_count},
        cgroups => $nd->{cgroups} || {},
        actions => $nd->{actions} || {},
        comments => $nd->{comments} || 0,
        snmpgdef => $snmpgdef,
    });
}

sub get_node_path
{
    my $self = shift;
    my $cur = shift;
    my $path = [];
    $self->_get_node_path($path, $cur);
    return $path;
}

sub _get_node_path
{
    my $self = shift;
    my $path = shift;
    my $cur = shift;

    push @$path, $cur;

    my $rel = $self->relations;

    $self->_get_node_path($path, $rel->{$cur})
        if defined $rel->{$cur};
}

sub get_node_down_family
{
    my $self = shift;
    my $id = shift;
    my $id_probe_type = @_ ? shift : "";
    my $snmpgdef = "";
    if ($id_probe_type =~ /:/)
    {
        $snmpgdef = (split /:/, $id_probe_type)[1];
        $id_probe_type = (split /:/, $id_probe_type)[0];
    }
    my $family = {};
    $self->_get_node_down_family($family, $id, $id_probe_type, $snmpgdef);
    return $family;
}

sub _get_node_down_family
{
    my $self = shift;
    my $family = shift;
    my $id = shift;
    my $id_probe_type = @_ ? shift : "";
    my $snmpgdef = @_ ? shift : "";


    my $slv = $self->slaves;
    my $items = $self->items;

    for my $cid ( keys %{ $slv->{ $id } } )
    {
        if ($id_probe_type eq "")
        {
            $family->{$cid} = $items->{$cid};
            $self->_get_node_down_family($family, $cid);
        }
        else 
        {
            if ($snmpgdef && $items->{$cid}->id_probe_type eq $id_probe_type && $items->{$cid}->snmpgdef eq $snmpgdef)
            {
                $family->{$cid} = $items->{$cid};
                $self->_get_node_down_family($family, $cid, $id_probe_type, $snmpgdef);
            }
            elsif($items->{$cid}->id_probe_type eq $id_probe_type)
            {
                $family->{$cid} = $items->{$cid};
                $self->_get_node_down_family($family, $cid, $id_probe_type, $snmpgdef);
            }
        }
    }
}

sub html
{
    my $self = shift;
    my $view_mode = shift || _VM_TREE;

    my $cur = $self->cur;

    my $o;
    my $m = {};

    my $items = $self->items;
    my $rel = $self->relations;

    my $pa = defined $cur
        ? $self->get_node_path($cur) 
        : [];   

    my $path = {};
    @$path{ @$pa } = @$pa;
    
    ++$path->{64001} 
        if defined $path->{0};

    my $url_params = $self->url_params;
    my $selected = $self->selected;
    my $preview = $self->preview;

    my $id_user = $self->id_user;

    if ($preview)
    {
        for my $oid (keys %$preview ) 
        {
            next
                unless $oid;

            $o = $items->{$oid};

            next
                unless right_bit_test($o->rights($id_user), _R_VIE);

            if (! $Tree->{ShowActiveNodeService})
            {   
                next
                    if $o->id_probe_type > 1 && $rel->{$selected->id} && $rel->{$selected->id} == $rel->{$o->id};
            }

            $m->{$o->id}->{p} = defined $rel->{$o->id} ? $rel->{$o->id} ? $rel->{$o->id} : 0 : 0;
            $m->{$o->id}->{name} = $o->name;
            $m->{$o->id}->{ip} = $o->ip;
            $m->{$o->id}->{url} = url_get({ id_entity => $o->id, section => $url_params->{section}});
            $m->{$o->id}->{target} = "";
            $m->{$o->id}->{image} = $o->image_function;
            $m->{$o->id}->{image} = "unknown"
                unless $m->{$o->id}->{image};
            $m->{$o->id}->{probe} = $ProbesMapRev->{ $o->id_probe_type };
            $m->{$o->id}->{state} = $o->get_calculated_status;
        }
    }

    my $views = $self->{VIEWS};

    for (keys %$views)
    {
        $views->{$_}->{url} = url_get({section => $url_params->{section}});
    }

    my $res = qq|<script type="text/javascript"><!-- 
        d = new dTree('d');|;

    if (defined $VIEWS_ALLTREES{$view_mode})
    {
        my $loc_url = url_get({ id_entity => 0, section => $url_params->{section}, });

        $loc_url .= sprintf(qq|?form_name=form_view_mode_change&nvm=%s|, _VM_TREE)
            if $view_mode != _VM_TREE;

        $res .= qq|  d.add(0, -1, 'objects','', '', '','','', '', '', '', 1, 1);\n|;
        $res .= qq|  d.add(64010, 0, 'locations', '$loc_url', '', '','','','', '', 'group_top_level', 0, 0);\n|;
        $res .= qq|  d.add(64020, 0, 'views', '', '', '','','','', '', '', 1, 1);\n|;

        for (sort { CGI::cookie("AKKADA_TREE_SORT") eq 'true'
            ?  uc($m->{$a}->{name}) cmp uc($m->{$b}->{name})
                || $m->{$a}->{image} cmp $m->{$b}->{image} 
            : $m->{$a}->{image} cmp $m->{$b}->{image} 
                || uc($m->{$a}->{name}) cmp uc($m->{$b}->{name}) } keys %$m) 
        {
            $res .= qq|  d.add($_, | . ($m->{$_}->{p} ? $m->{$_}->{p} : 64010) . qq| , '$m->{$_}->{name}&nbsp;','$m->{$_}->{url}|;
            $res .= sprintf(qq|?form_name=form_view_mode_change&nvm=%s|, _VM_TREE)
                if $view_mode != _VM_TREE;
            $res .= qq|', '', '$m->{$_}->{target}',|;
            $res .= defined $path->{$_} ? 'true' : '\'\'';

            $res .= -e "$ImagesDir/$m->{$_}->{image}.gif"
                ? qq|,'$m->{$_}->{image}.gif'|
                : qq|,'unknown.gif'|;
            $res .= qq|,'$m->{$_}->{state}'|;
            $res .= qq|,'$m->{$_}->{ip}'|;
            $res .= qq|,'$m->{$_}->{probe}', 0, |;
            $res .= '0'; #($view_mode != _VM_TREE ? 1 : 0);
            $res .= qq|);\n|;
        }

        my $t = time;

        for my $id_view ( sort { uc($views->{$a}->{name}) cmp uc($views->{$b}->{name}) } keys %$views)
        {
            $views->{$id_view}->{function} .= '.gif'
                if $views->{$id_view}->{function};
            $res .= qq|d.add(| . (64020+$id_view) . qq|, 64020, '$views->{$id_view}->{name}', '$views->{$id_view}->{url}?|;
            $res .= defined $VIEWS_ALLVIEWS{$view_mode} 
                ? qq|form_name=form_view_select&id_view=$id_view|
                : qq|form_name=form_view_mode_change&id_view=$id_view|;
            
            if ($view_mode != _VM_TREEVIEWS)
            { 
                 $res .= sprintf(qq|&nvm=%s|, _VM_TREEVIEWS);
            } 

            $views->{$id_view}->{status} = _ST_RECOVERED
                if $views->{$id_view}->{status} == _ST_OK
                    && ($t - $views->{$id_view}->{last_change}) < $StatusRecoveredDeltaTime;

            $res .= qq|','', '', '', '$views->{$id_view}->{function}', '$views->{$id_view}->{status}','','view', 0, 0,| . ($views->{$id_view}->{id_view_type} == _VT_FIND ? '1' : '0')  . qq|);\n|;
        }

        if ($Tree->{ExpandViews})
        {
            my $p;
            my $e2v = $self->db->dbh->selectall_arrayref("select id_entity,id_view from entities_2_views");
            for my $id (sort { $items->{$a->[0]}->name cmp $items->{$b->[0]}->name } @$e2v)
            {
                $o = $items->{$id->[0]};

                next
                    unless right_bit_test($o->rights($id_user), _R_VIE);
                $p = $items->{ $rel->{$id->[0]} };
                $res .= qq|  d.add($id->[0], |;
                $res .= (64020+$id->[1]) . qq| , '|;
                $id = $id->[0];
                $res .= $p->name . ': '
                    if $o->id_probe_type > 1;
                $res .= $o->name;
                $res .= qq|&nbsp;','| . url_get({ id_entity => $id, section => $url_params->{section}});
                $res .= sprintf(qq|?form_name=form_view_mode_change&nvm=%s|, _VM_TREE)
                    if $view_mode != _VM_TREE;
                $res .= qq|', '', '',|;
                $res .= defined $path->{$id} ? 'true' : '\'\'';
             
                $m = $o->image_function;
                $m = "unknown"
                    unless $m;
                $res .= -e "$ImagesDir/$m.gif"
                    ? qq|,'$m.gif'|
                    : qq|,'unknown.gif'|;

                $m = $o->get_calculated_status;
                $res .= qq|,'$m'|;

                $res .= qq|,'| . $o->ip . qq|'|;

                $m = $ProbesMapRev->{ $o->id_probe_type };
                $res .= qq|,'$m', 0, |;
                $res .= ($view_mode != _VM_TREE ? 1 : 0);
                $res .= qq|);\n|;
            }
        }
        $res .= qq|  d.draw($cur);|;
    }
    $res .= qq|//-->\n</script>\n|;
    return $res;
}

sub DESTROY
{
    my $self = shift;

    $self->cache->clear()
        if $self->master;

    $self->{CACHE} = undef;
    $self->{SELECTED_ITEM} = undef;
    $self->{FIND} = undef;
    $self->{ROOT} = undef;
    $self->{DATA}->{TREE} = undef;
    $self->{DATA}->{ITEMS} = undef;
    $self->{DATA}->{RELATIONS} = undef;
    $self->{DATA}->{SLAVES} = undef;
    $self->{LINKS} = undef;
    $self->{STATUSES} = undef;
    $self->{IPS} = undef;
    $self->{SNMPGDEF} = undef;
    $self->{NODES} = undef;
    $self->{VENDORS} = undef;
    $self->{FUNCTIONS} = undef;
    $self->{URL_PARAMS} = undef;
}


1;

