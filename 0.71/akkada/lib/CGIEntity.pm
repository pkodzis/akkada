package CGIEntity;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.21;

use strict;         
use MyException qw(:try);
use Configuration;
use Constants;
use Common;
use POSIX;
use URLRewriter;
use Forms;
use NetAddr::IP;

use constant 
{
    ENTITY => 0,
    CGI => 1,
    TITLE_MAIN => 2,
    TITLE_CHILDREN_LEAFS => 3,
    TITLE_CHILDREN_NODES => 4,
    PROBES => 5,
    TREE => 6,
    DBH => 7,
    URL_PARAMS => 8,
    TITLE_PARENT => 9,
    SESSION => 10,
    USERS => 11,
    DESKTOP => 12,
};

our $OldLastCheckAlarm = CFG->{Web}->{OldLastCheckAlarm};
our $ImagesDir = CFG->{ImagesDir};
our $RightsNames = CFG->{Web}->{RightsNames};
our $ProbesMapRev = CFG->{ProbesMapRev};
our $ProbesMap = CFG->{ProbesMap};

sub new
{       
    my $class = shift;

    my $self;

    $self->[USERS] = shift;
    $self->[SESSION] = shift;

    $self->[DBH] = shift;

    $self->[ENTITY] = shift;

    $self->[CGI] = shift;

    $self->[TREE] = shift;

    $self->[URL_PARAMS] = shift;

    $self->[DESKTOP] = shift;

    my $params = shift;

    $self->[TITLE_MAIN] = $params->{title_main} 
        ? $params->{title_main}
        : 'entity';

    $self->[TITLE_PARENT] = $params->{title_parent} 
        ? $params->{title_parent}
        : 'parent';

    $self->[TITLE_CHILDREN_LEAFS] = $params->{title_children_leafs} 
        ? $params->{title_children_leafs}
        : 'services';

    $self->[TITLE_CHILDREN_NODES] = $params->{title_children_nodes} 
        ? $params->{title_children_nodes}
        : 'nodes';

    bless $self, $class;

    $self->load_probes;

    return $self;
}

sub desktop
{
    return $_[0]->[DESKTOP];
}

sub session
{
    return $_[0]->[SESSION];
}

sub users
{
    return $_[0]->[USERS];
}

sub tree
{
    return $_[0]->[TREE];
}

sub url_params
{
    return $_[0]->[URL_PARAMS];
}

sub dbh
{
    return $_[0]->[DBH];
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
        $self->[PROBES]->{$file} = $probe;
    }
    closedir(DIR);
}

sub probes
{
    return $_[0]->[PROBES];
}

sub title_parent
{
    return sprintf("%s", $_[0]->[TITLE_PARENT]);
}

sub title_main
{
    return sprintf("%s", $_[0]->[TITLE_MAIN]);
}

sub title_children_leafs
{
    return sprintf("%s", $_[0]->[TITLE_CHILDREN_LEAFS]);
}

sub title_children_nodes
{
    return sprintf("%s", $_[0]->[TITLE_CHILDREN_NODES]);
}

sub entity
{
    return $_[0]->[ENTITY];
}

sub cgi
{
    return $_[0]->[CGI];
}

sub entity_info
{
    my $self = shift;
    my $table = table_begin();
    $table->addRow( "", "name", "", "", "last change", "last check","");
    $table->setCellAttr(1, 2, 'class="g4"');
    $table->setCellAttr(1, 5, 'class="g4"');
    $table->setCellAttr(1, 6, 'class="g4"');

    my ($status, $last_check) = $self->entity_row_main($table);

    $self->entity_row_main_style($table, 2, $status, $last_check);

    return scalar $table;
}

sub entity_general
{
    my $self = shift;

    return 
        unless $self->entity;

    my $content = shift;
   
    $content->addRow( $self->entity_info );

    my $entity = $self->entity;

    if ($entity)
    {
        my $probe = $ProbesMapRev->{ $entity->id_probe_type };
        $content->addRow($self->probes->{$probe}->desc_full($entity, $self->url_params) )
            if defined $self->probes->{$probe};
    }

    $self->entity_parameters_optional($content)
        if session_get_param($self->session, '_GENERAL_SHOW_PARAMETERS');

}

sub entity_parameters_optional
{
    my $self = shift;
    my $content = shift;

    my $params_own = $self->entity->params_own;
    my $params = $self->entity->[5];

    #return
    #    unless scalar keys %$params;

    my $table = table_begin('parameters', 3);

    my $color = 0;

    for (sort { uc($a) cmp uc($b) } keys %$params)
    {   
        $table->addRow("&nbsp;$_&nbsp;", 
            $_ =~ /password/ || $_ =~ /community/ ? "*****" : $params->{$_}, 
            $params_own->{$_} ? '' : 'inherited');
        $table->setRowAttr($table->getTableRows, sprintf(qq|class="tr_%d"|, $color));
        $color = ! $color;
    }
    $table->addRow("&nbsp;flap_monitor&nbsp;", $self->entity->flap_monitor, 'mandatory');
    $table->setRowAttr($table->getTableRows, sprintf(qq|class="tr_%d"|, $color));

    $content->addRow( scalar $table )
        if $table->getTableRows;
}

sub alarms_correlate
{
    my $self = shift;
    my $correlate = shift;

    my $tmp;
    my $ip;

    my $ctmp = {};

    for my $id (keys %$correlate)
    {
        $tmp = [ split /#/, $correlate->{$id} ];
        for (@$tmp)
        {
            $_ = [split /:/, $_];
        }
        $ip = NetAddr::IP->new( $tmp->[0]->[0], $tmp->[0]->[1] );
        $correlate->{$id} = defined $ip
            ? $ip->network->cidr
            : undef;
        if (defined $correlate->{$id})
        {
            ++$ctmp->{ $correlate->{$id} };
            if (! defined $correlate->{links} || ! defined $correlate->{links}->{$correlate->{$id}})
            {
                $correlate->{links}->{$correlate->{$id}} = [];
            }
            push @{ $correlate->{links}->{$correlate->{$id}} }, $id;
        }
    }
    for (keys %$correlate)
    {
        next
            if $_ eq 'links';
        delete $correlate->{$_}
            if $ctmp->{ $correlate->{$_} } < 2;
    }
    if (defined $correlate->{links})
    {
        for (keys %{$correlate->{links}})
        {
            delete $correlate->{links}->{$_}
                unless $#{ $correlate->{links}->{$_} };
        }
    }
#use Data::Dumper; warn Dumper($ctmp); warn Dumper($correlate);
}

sub alarms
{
    my $self = shift;
    
    my $view_mode = $self->desktop->view_mode;
    my $view_entities = {};
        
    my $root = defined $self->entity &&  ! defined $VIEWS_ALLVIEWS{$view_mode} && ! defined $VIEWS_TREEFIND{$view_mode}
        ? $self->entity->id_entity
        : 0;
    
    my $tree = $self->tree;
    my $nodes = $tree->get_node_down_family($root);
    my $rel = $tree->relations;
    my $items = $tree->items;
    my $desktop = $self->desktop;

    $nodes->{$root} = $items->{$root}
        if defined $items->{$root};
    return ''   
        unless keys %$nodes;
    
    my $dbh = $self->dbh;

    if (defined $VIEWS_ALLVIEWS{$view_mode})
    {
        for (@{ $desktop->views->view_entities })
        {
            for ( @{child_get_ids_all($dbh, $_)})
            {
                ++$view_entities->{$_};
            }
        }
    }
    elsif (defined $VIEWS_ALLFIND{$view_mode})
    {
        my $tmp = $desktop->find->view_entities;
        if (ref($tmp) eq 'ARRAY')
        {
            for (@{ $desktop->find->view_entities })
            {
                for ( @{child_get_ids_all($dbh, $_)})
                {
                    ++$view_entities->{$_};
                }
            }
        }
    }
#use Data::Dumper; warn Dumper $view_entities;

    my $status;
    my $last_check;
    my $color = 0;
    my $count = 0;
    my $last_check_timestamp;
    my $err_approved_by;

    my $parent_cur = -1;
    my $parent_count = 0;

    my $url_params = $self->url_params;
    my $session = $self->session;
    my $mode = $url_params->{alarms_mode} || 0;

    my @job;
    my $sound_alarm = 0;
    my $total_alarm = 0;
    my $level_alarm = 0;
    my $approval = 0;


    my $par;

    for my $id (keys %$nodes)
    {
        next
            if (defined $VIEWS_ALLVIEWS{$view_mode} || defined $VIEWS_ALLFIND{$view_mode}) && ! defined $view_entities->{$id};
        next
            unless $nodes->{$id}->status > _ST_OK && $nodes->{$id}->status < _ST_UNKNOWN;

        $par = $tree->parent($id);

        next
            if $par->status == _ST_UNREACHABLE && $id != $root;

        next
            if $nodes->{$id}->status_weight == 0 && $mode < 2;

        next
            if $par->id && $par->state_weight == 0 && $mode < 1; # calculated status weight

        next
            unless $nodes->{$id}->monitor;

        next
            unless $desktop->matrix($url_params->{section}, $items->{$id});

        ++$total_alarm;
        if (! $nodes->{$id}->err_approved_by)
        {
            ++$sound_alarm;
            $level_alarm = $nodes->{$id}->status
                if $level_alarm < $nodes->{$id}->status;
        }

        next
            if $url_params->{hide_approved} && $nodes->{$id}->err_approved_by;

        ++$approval
           unless $nodes->{$id}->err_approved_by;

        push @job, $id;
    }

    my $entities = {};
    my $correlate = {};
    my $correlation = ! session_get_param($self->session, '_CORRELATION');

    for my $id (@job)
    {
        try
        {
       $entities->{$id} = Entity->new( $dbh, $id, 1);
       $entities->{ $rel->{$id} } = Entity->new( $dbh, $rel->{$id}, 1)
           if ! defined $entities->{ $rel->{$id} } && defined $rel->{$id} && $rel->{$id};
        }
        catch  EEntityDoesNotExists with
        {
        }
        except
        {
        };
       $correlate->{ $id } = $entities->{$id}->data->{ipAddrEntry}
           if defined $entities->{$id} && defined $entities->{$id}->data->{ipAddrEntry} && $correlation;
    }

#use Data::Dumper; warn Dumper($correlate);

    $self->alarms_correlate($correlate)
        if $correlation;

#use Data::Dumper; warn Dumper($correlate);

    my $order = session_get_param($self->session, '_ALARMS_SORT_ORDER') || CFG->{Web}->{AlarmsSortOrderDefault};
    my $ascending = session_get_param($self->session, '_ALARMS_SORT_ASCENDING');

    my $tmain = table_begin();

    my $table = $self->alarms_table_begin($approval);

    for my $id (sort { 
        $ascending
        ?
        (
        $order eq 'parent' 
            ? 
              uc($items->{ $rel->{$a} }->name) cmp uc($items->{ $rel->{$b} }->name)
              || $rel->{$a} <=> $rel->{$b}
              || $nodes->{$b}->status <=> $nodes->{$a}->status
              || uc($nodes->{$a}->name) cmp uc($nodes->{$b}->name)
        : $order eq 'name'
            ?
              uc($items->{ $a }->name) cmp uc($items->{ $b }->name)
        : $order eq 'error'
            ?
              uc($items->{ $a }->errmsg) cmp uc($items->{ $b }->errmsg)
        : ($order eq 'start time' || $order eq 'duration')
            ?
              $items->{ $a }->status_last_change <=> $items->{ $b }->status_last_change
        :
              $nodes->{$b}->status <=> $nodes->{$a}->status
              || uc($items->{ $rel->{$a} }->name) cmp uc($items->{ $rel->{$b} }->name)
              || $rel->{$a} <=> $rel->{$b}
              || uc($nodes->{$a}->name) cmp uc($nodes->{$b}->name)
        )
        :
        (
        $order eq 'parent'
            ? 
              uc($items->{ $rel->{$b} }->name) cmp uc($items->{ $rel->{$a} }->name)
              || $rel->{$a} <=> $rel->{$b}
              || $nodes->{$b}->status <=> $nodes->{$a}->status
              || uc($nodes->{$a}->name) cmp uc($nodes->{$b}->name)
        : $order eq 'name'
            ? 
              uc($items->{ $b }->name) cmp uc($items->{ $a }->name)
        : $order eq 'error'
            ? 
              uc($items->{ $b }->errmsg) cmp uc($items->{ $a }->errmsg)
        : ($order eq 'start time' || $order eq 'duration')
            ? 
              $items->{ $b }->status_last_change <=> $items->{ $a }->status_last_change
        :     
              $nodes->{$a}->status <=> $nodes->{$b}->status
              || uc($items->{ $rel->{$a} }->name) cmp uc($items->{ $rel->{$b} }->name)
              || $rel->{$a} <=> $rel->{$b}
              || uc($nodes->{$a}->name) cmp uc($nodes->{$b}->name)
        )
        } @job)
    {

        next
            if $correlation && defined $correlate->{$id};

        if ($parent_cur != $rel->{$id})
        {
            if ($parent_count)
            {
                $parent_cur = $table->getTableRows - $parent_count + 1;
                $table->setCellRowSpan($parent_cur, 1, $parent_count);
                $table->setCellRowSpan($parent_cur, 2, $parent_count);
                $table->setCellRowSpan($parent_cur, 3, $parent_count);
                $parent_count = 0;
            }
            $parent_cur = $rel->{$id};
        }

        ($status, $last_check_timestamp, $last_check, $err_approved_by)
            = $self->alarm_row($table, $nodes->{$id}, $items->{$rel->{$id}}, $url_params, $id, $entities);
        $self->alarm_row_style($table, $table->getTableRows, $status, $color, $last_check_timestamp, $last_check, $err_approved_by);
        $color = ! $color;
        $parent_count++;
        $count++;
    }

    if ($parent_count)
    {
        $parent_cur = $table->getTableRows - $parent_count + 1;
        $table->setCellRowSpan($parent_cur, 1, $parent_count);
        $table->setCellRowSpan($parent_cur, 2, $parent_count);
        $table->setCellRowSpan($parent_cur, 3, $parent_count);
    }

    if ($sound_alarm && CFG->{Web}->{SoundAlarm} && ! session_get_param($session, '_ALARMS_SOUND_OFF'))
    {
        $table->addRow(qq|<bgsound SRC="| . CFG->{Web}->{SoundAlarmFile}->{$level_alarm} . qq|" LOOP="| . 
            (CFG->{Web}->{SoundAlarmCountMode}
                ? ($sound_alarm < CFG->{Web}->{SoundInfinite} ? $sound_alarm : "infinite")
                : CFG->{Web}->{SoundAlarmCount}) . qq|">|);
    }

    return scalar $table
        unless $correlation; 

    if ($count)
    {
        $tmain->addRow
        ( 
            $self->cgi->img({ onClick =>qq|bc(this, 'active_alarms')|, src => "/img/o.gif", }), 
            sprintf(qq|<div id="active_alarms">%s</div>|, scalar $table),
        );
        $tmain->setCellAttr($tmain->getTableRows, 1, 'class="g3"');
    }

    $color = 0;
    $count = 0;
    $table = $self->alarms_table_begin($approval, $correlation);

    for my $cor (keys %{$correlate->{links}})
    {
              
    for my $id (sort { 
        $ascending
        ?
        (
        $order eq 'parent' 
            ? 
              uc($items->{ $rel->{$a} }->name) cmp uc($items->{ $rel->{$b} }->name)
              || $rel->{$a} <=> $rel->{$b}
              || $nodes->{$b}->status <=> $nodes->{$a}->status
              || uc($nodes->{$a}->name) cmp uc($nodes->{$b}->name)
        : $order eq 'name'
            ?
              uc($items->{ $a }->name) cmp uc($items->{ $b }->name)
        : $order eq 'error'
            ?
              uc($items->{ $a }->errmsg) cmp uc($items->{ $b }->errmsg)
        : ($order eq 'start time' || $order eq 'duration')
            ?
              $items->{ $a }->status_last_change <=> $items->{ $b }->status_last_change
        :
              $nodes->{$b}->status <=> $nodes->{$a}->status
              || uc($items->{ $rel->{$a} }->name) cmp uc($items->{ $rel->{$b} }->name)
              || $rel->{$a} <=> $rel->{$b}
              || uc($nodes->{$a}->name) cmp uc($nodes->{$b}->name)
        )
        :
        (
        $order eq 'parent'
            ? 
              uc($items->{ $rel->{$b} }->name) cmp uc($items->{ $rel->{$a} }->name)
              || $rel->{$a} <=> $rel->{$b}
              || $nodes->{$b}->status <=> $nodes->{$a}->status
              || uc($nodes->{$a}->name) cmp uc($nodes->{$b}->name)
        : $order eq 'name'
            ? 
              uc($items->{ $b }->name) cmp uc($items->{ $a }->name)
        : $order eq 'error'
            ? 
              uc($items->{ $b }->errmsg) cmp uc($items->{ $a }->errmsg)
        : ($order eq 'start time' || $order eq 'duration')
            ? 
              $items->{ $b }->status_last_change <=> $items->{ $a }->status_last_change
        :     
              $nodes->{$a}->status <=> $nodes->{$b}->status
              || uc($items->{ $rel->{$a} }->name) cmp uc($items->{ $rel->{$b} }->name)
              || $rel->{$a} <=> $rel->{$b}
              || uc($nodes->{$a}->name) cmp uc($nodes->{$b}->name)
        )
        } @{ $correlate->{links}->{$cor} })
    {
        ($status, $last_check_timestamp, $last_check, $err_approved_by)
            = $self->alarm_row($table, $nodes->{$id}, $items->{$rel->{$id}}, $url_params, $id, $entities, $correlate->{links}->{$cor});
        $self->alarm_row_style($table, $table->getTableRows, $status, $color, $last_check_timestamp, $last_check, $err_approved_by, 1, $color);
        $count++;
    }
        $parent_count = $correlate->{links}->{$cor};
        $parent_count = @$parent_count;
        $parent_cur = $table->getTableRows - $parent_count + 1;
        $table->setCellRowSpan($parent_cur, 1, $parent_count);

        $table->addRow();
        #$table->setCellColSpan($table->getTableRows, 1, 13);
        #$table->setCellAttr($table->getTableRows, 1, 'class="n6"');
        $color = ! $color;
    }

    if ($count)
    {
        $tmain->addRow('&nbsp;', '')
            if $tmain->getTableRows == 1;
        $tmain->addRow(
            $self->cgi->img({ onClick =>qq|bc(this, 'c_active_alarms')|, src => "/img/o.gif", }),
            sprintf(qq|<div id="c_active_alarms">%s</div>|, scalar $table),
        );
        $tmain->setCellAttr($tmain->getTableRows, 1, 'class="g3"');
    }

    $tmain->setCell(1,1, '')
        if $tmain->getTableRows == 1;
   
    return scalar $tmain;
}

sub alarms_table_make_col_name
{
    my $self = shift;
    my $name = shift;
    my $order = shift;
    my $ascending = session_get_param($self->session, '_ALARMS_SORT_ASCENDING');
    $ascending = ! $ascending
        if $name eq $order;
    return sprintf(qq|<a class="g4" href="%s?form_name=form_alarms_sort&order=%s&ascending=%s">%s</a>|, 
        url_get({}, $self->url_params), 
        $name,
        $ascending,
        $name);
}

sub alarms_table_begin
{   
    my $self = shift;
    my $approval = @_ ? shift : 0;
    my $correlation = @_ ? shift : 0;
   
    my $cgi = $self->cgi;
 
    my $table = table_begin($correlation ? 'correlated active alarms' : 'active alarms', 12);

    $table->setAlign('left');

    my $order = session_get_param($self->session, '_ALARMS_SORT_ORDER') || CFG->{Web}->{AlarmsSortOrderDefault};

    $approval = $approval 
        ? $cgi->a({ href =>
        sprintf(qq|%s?%s|, url_get({}, $self->url_params), 'form_name=form_alarm_approval&atype=3&id_entity=' . $self->url_params->{id_entity}),
              class=> 'info' }, $cgi->img({alt => 'approve selected alarm', src => '/img/checkmark.gif'}))
        : 'approval';
   
    my @row;
    push @row, ""
        if $correlation;
 
    push @row, (
        "", 
        $self->alarms_table_make_col_name("parent", $order),
        "", 
        $self->alarms_table_make_col_name("name", $order), 
        $self->alarms_table_make_col_name("status", $order), 
        "", 
        $self->alarms_table_make_col_name("error", $order), 
        $self->alarms_table_make_col_name("duration", $order), 
        "brief", 
        $self->alarms_table_make_col_name("start time", $order), 
        "last check", 
        "", 
        $approval);

    $table->addRow(@row); 
    $table->setCellAttr(2, 2+$correlation, 'class="g4"');
    $table->setCellAttr(2, 4+$correlation, 'class="g4"');
    $table->setCellAttr(2, 7+$correlation, 'class="g4"');
    $table->setCellAttr(2, 8+$correlation, 'class="g4"');
    $table->setCellAttr(2, 9+$correlation, 'class="g4"');
    $table->setCellAttr(2, 10+$correlation, 'class="g4"');
    $table->setCellAttr(2, 11+$correlation, 'class="g4"');
    $table->setCellAttr(2, 12+$correlation, 'class="g4"');
    $table->setCellAttr(2, 13+$correlation, 'class="j1"');

    return $table;                 
}


sub alarm_row_style 
{   
    my $self = shift;
    my $table = shift;
    my $row = shift;
    my $status = shift;
    my $style = shift;
    my $last_check_timestamp = shift;
    my $last_check = shift;
    my $err_approved_by = shift;
    my $corr = shift || 0;
    my $corr_style = shift || 0;
    
    $table->setCellAttr($row, 1, sprintf(qq|class="%s"|, $corr_style ? "n7" : "n8") )
        if $corr;

    $table->setCellAttr($row, 1+$corr, 'class="n"');
    $table->setCellAttr($row, 2+$corr, 'class="g3"');
    $table->setCellAttr($row, 3+$corr, 'class="n"');
    $table->setCellAttr($row, 4+$corr, 'class="g7"');
    $table->setCellAttr($row, 5+$corr, qq|class="ts| . $status . qq|"|);
    $table->setCellAttr($row, 6+$corr, 'class="t2"');
    
    $table->setCellAttr($row, 7+$corr, 'class="g9"');
    $table->setCellAttr($row, 8+$corr, 'class="g2"');

    $table->setCellAttr($row, 9+$corr, 'class="g7"');

    $table->setCellAttr($row, 10+$corr, 'class="g2"');

    $last_check_timestamp ne 'n/a' && time - $last_check > $OldLastCheckAlarm
        ? $table->setCellAttr($row, 11+$corr, 'class="h"')
        : $table->setCellAttr($row, 11+$corr, 'class="g2"');

    $table->setCellAttr($row, 12+$corr, 'class="m"');
    $table->setCellAttr($row, 13+$corr, $err_approved_by ? 'class="g1"' : 'class="m"');

    $table->setRowAttr($row, sprintf(qq|class="tr_%d"|, $style));
}   

sub a_onclick
{
    my $self = shift;
    my $h = shift;
    my $url_params = $self->url_params;
    my $id = $h->{ id };
    my $probe = $h->{ probe };
    my $name = $h->{ name };
    my $class = defined $h->{ class } ? $h->{ class } : "s";
    my $top_level = defined $h->{ top_level } ? $h->{ top_level } : 0;

    my $view_mode = $self->desktop->view_mode;

    $probe .= '_top_level'
        if $top_level;

    return $self->cgi->a({
        -onMouseOver => qq|set_OBJ($id, '$probe', 1)|,
        -onMouseOut =>qq|clear_OBJ()|,
        -onClick =>qq|open_flyout()|,
        -href => "#",
        -class =>$class}, $name);
}

sub a_popup
{
    my $self = shift;
    my $h = shift;
    my $url_params = $self->url_params;
    my $id = $h->{ id };
    my $probe = $h->{ probe };
    my $name = $h->{ name };
    my $class = defined $h->{ class } ? $h->{ class } : "s";
    my $section = defined $h->{ section } ? $h->{ section } : $url_params->{section};
    my $top_level = defined $h->{ top_level } ? $h->{ top_level } : 0;

    my $view_mode = $self->desktop->view_mode;

    $top_level 
        ? $self->desktop->put_popup_top($probe)
        : $self->desktop->put_popup($probe);

    my $url = url_get({ id_entity => $id, section => $section }, $self->url_params);

    if (defined $VIEWS_ALLVIEWS{$view_mode} || defined $VIEWS_ALLFIND{$view_mode})
    {
        $url .= sprintf(qq|?form_name=form_view_mode_change&nvm=%s|, defined $VIEWS_HARD{$view_mode} ? _VM_TREE : _VM_TREE_LIGHT);
    }

    $probe .= "_top_level"
        if $top_level;

    return $self->cgi->a({
        -onMouseOver => qq|set_OBJ($id, '$probe', 0)|,
        -onMouseOut =>qq|clear_OBJ()|,
        -href => $url,
        -class =>$class}, $name);
}

sub a_popup_bqv
{       
    my $self = shift;
    my $h = shift;
    my $url_params = $self->url_params;
    my $id = $h->{ id };
    my $id_probe_type = $h->{ id_probe_type };
    my $probe = $h->{ probe };
    my $name = $h->{ name };
    my $class = defined $h->{ class } ? $h->{ class } : "s";
    my $section = defined $h->{ section } ? $h->{ section } : $url_params->{section};

    my $view_mode = $self->desktop->view_mode;

    my $url = url_get({ id_entity => $id, section => $section }, $self->url_params);

    $url .= sprintf(qq|?form_name=form_entity_find&treefind=1&id_entity=0&id_parent=%s&id_probe_type=%s|, 
        $id, $id_probe_type);
    
    return $self->cgi->a({
        -onMouseOver => qq|set_OBJ($id, '$probe', 0)|,
        -onMouseOut =>qq|clear_OBJ()|,
        -href => $url,
        -class =>$class}, $name);
}

sub alarm_row
{
    my $self = shift;
    my $table = shift;
    my $node = shift;
    my $parent = shift;
    my $url_params = shift;
    my $id = shift;
    my $entities = shift;
    my $corr = shift || undef;

    my $entity = $entities->{$id};
    my $entity_parent = $parent->id
        ? $entities->{ $parent->id }
        : undef;

    my $cgi = $self->cgi;

    my $status = $node->status;
    my $start_time = $node->status_last_change;

    my $err_approved_by = $entity->err_approved_by;

    my $probe = $ProbesMapRev->{$entity->id_probe_type};

    my @result;

    push @result, '&nbsp;'
        if $corr;

    push @result, $self->image_vendor( $parent->image_vendor );

    if ($entity_parent)
    {
        push @result, $self->a_popup(
        {
            id => $parent->id,
            probe => $ProbesMapRev->{$entity_parent->id_probe_type}, 
            name => $self->entity_get_name($entity_parent, $ProbesMapRev->{$entity_parent->id_probe_type}),
        });
    }
    else
    {
        push @result, $cgi->a({ href => url_get({id_entity => $parent->id, section => 'general'}, $self->url_params), class=> 's' }, 
            $cgi->b('root'))
    }

    push @result, $self->image_function($parent);

    push @result, $self->a_popup(
    {
        id => $node->id,
        probe => $probe,
        name => $self->entity_get_name($entity, $probe),
        section => 'general',
    });

    push @result, status_name($status);

    push @result, $self->image_function($node);

    push @result, $node->flap ? sprintf(qq|%d flaps since %s; <font color="#606060">last error: "%s"</font>|, 
        $node->flap_count, duration($node->flap), $node->errmsg) : $node->errmsg;

    if ($self->probes->{$probe}->alarm_utils_button && $node->errmsg && $entity->monitor)
    {
        $result[$#result] .= $self->probes->{$probe}->alarm_utils_button_get($node->id, $node->id_probe_type, $url_params);
    }

    push @result, duration($start_time);

    my $brief = $entity->monitor
        ? $self->probes->{$probe}->desc_brief_get($entity)
        : ['not monitored'];

    push @result, defined $brief && ref($brief)
        ? join('; ', @$brief)
        : '';

    push @result, strftime("%D %T", localtime($start_time));
=pod
    push @result, $status eq _ST_UNREACHABLE || $status eq _ST_NOSNMP
        ? 'n/a'
        : $self->entity_get_last_check_timestamp($probe, $entity);
=cut
    push @result, $self->entity_get_last_check_timestamp($probe, $entity);

    push @result, $self->contacts_img($entity->id_entity) . $self->comments_img($entity->id_entity);

    push @result, $err_approved_by
        ? 'after ' . duration_row($entity->err_approved_at) 
             . ' by ' . (defined $self->users->{$err_approved_by} ? $self->users->{$err_approved_by}->username : 'unknown' )
             . ' (' . $entity->err_approved_ip . ')'
        : $self->desktop->matrix('form_alarm_approval', $node)
            ? $cgi->a({ href => 
              sprintf(qq|%s?%s|, url_get({}, $self->url_params), 'form_name=form_alarm_approval&id_entity=' . $node->id),
              class=> 'info' }, $cgi->img({alt => 'approve selected alarm', src => '/img/checkmark.gif'})) . 
              $cgi->a({ href => 
              sprintf(qq|%s?%s|, url_get({}, $self->url_params), 'form_name=form_alarm_approval&atype=1&id_entity=' . $node->id),
              class=> 'info' }, $cgi->img({alt => 'approve host alarms', src => '/img/aah.gif'})) . "&nbsp" .
              $cgi->a({ href => 
              sprintf(qq|%s?%s|, url_get({}, $self->url_params), 'form_name=form_alarm_approval&atype=2&id_entity=' . $node->id),
              class=> 'info' }, $cgi->img({alt => 'approve selected alarm type on all hosts', src => '/img/aat.gif'})) 
            : '';

    if (defined $corr && ref($corr) eq 'ARRAY' && ! $err_approved_by)
    {
        $result[$#result] .= "&nbsp;" . $cgi->a({ href =>
              sprintf(qq|%s?%s|, url_get({}, $self->url_params), 'form_name=form_alarm_approval&atype=4&id_entity=' . $node->id
                  . "&entities=" . join(",", @$corr)),
              class=> 'info' }, $cgi->img({alt => 'approve correlated alarm', src => '/img/aac.gif'}));
    }

    $table->addRow(@result);

    return ($status, $result[$#result - 1], $entity->data->{last_check}, $err_approved_by);
}

sub entity_options
{
    my $self = shift;

    return 
        unless $self->entity;
   
    my $content = shift;

    $content->addRow( $self->entity_info );

    my $table = HTML::Table->new();
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');

    $self->entity_row_params($table);

    $content->addRow( scalar $table )
        if $table->getTableRows;
}


sub services_options
{
    my $self = shift;

    return
        unless $self->entity;
  
    my $content = shift;

    $content->addRow( $self->entity_info );

    my $children = $self->entity_get_children;
    return
        unless keys %{ $children->{leafs} };
    $children = $children->{leafs};

    my $table= HTML::Table->new();
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');

    my $cont;
    my $cgi = $self->cgi;
    my $services_options = CFG->{Web}->{ServicesOptions};
    my @tmp;
    my $entity;
    my $s;

    $cont->{form_name} = 'form_services_options';
    $cont->{form_title} = 'services options';
    push @{ $cont->{buttons} }, { caption => "process", url => "javascript:document.forms['form_services_options'].submit()" };

    $cont->{title_row} = [ '', 'name', 'status', '<img src=/img/trash.gif>', 'error message', (map { $_->[0] } @$services_options), 'update' ];

    my $items = $self->tree->items;
    my $desktop = $self->desktop;
    my $url_params = $self->url_params;
    my $probe;

    for my $id_entity (
        sort
        {
            $children->{$a}->id_probe_type <=> $children->{$b}->id_probe_type ||
            uc $children->{$a}->name cmp uc $children->{$b}->name
        }
        keys %$children)
    {

        next
            unless $desktop->matrix($url_params->{section}, $items->{$id_entity});

        $entity = $children->{$id_entity};
        @tmp = ();

        for (@$services_options)
        {
            $s = $_->[0];
            push @tmp, $cgi->textfield({ name => sprintf(qq|%d_%s|, $id_entity, $s) , 
                value => ($entity->$s), class => "textfield",
                size => $_->[1],
                }),
        }

        $s = $items->{$id_entity}->get_calculated_status;

        $probe = $ProbesMapRev->{$entity->id_probe_type};

        push @{ $cont->{rows} },
            [
                $self->image_function($items->{$id_entity}),
                $self->a_popup(
                {
                    id => $id_entity,
                    probe => $probe,
                    name => $self->entity_get_name_with_desc_dynamic($entity, $probe),
                }),
                status_name($s),
                $cgi->checkbox({name => "${id_entity}_delete", label => ""}),
                $items->{$id_entity}->errmsg,
                @tmp,
                $cgi->checkbox({name => "${id_entity}_update", label => ""}),
            ];

        push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 3, 1, 't2'];
        push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 3, 2, 'f'];
        push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 3, 3, sprintf(qq|ts%s|, $s)];
        push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 3, 5, 'g9'];
        push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 3, 6 + @tmp, 'g9'];
    }

    $content->addRow( form_create($cont) );
}

sub image_function
{
    my $self = shift;
    my $node = shift;
    my $alt = shift || '';

    my $function = $node->image_function;
    my $probes = $self->probes;
    my $probe = $ProbesMapRev->{$node->id_probe_type};
    
    my $name;
    if ($node->id_probe_type != 1)
    {
        if ($probe eq 'snmp_generic')
        {
            $name = $probes->{'snmp_generic'}->name($node->snmpgdef);
        }
        else
        {
            $name = defined $probes->{$probe} ? $probes->{$probe}->name : $probe;
        }
    }
    else
    {
        $name = $function;
        $name =~ s/_/ /g;
    }

    my $img = -e "$ImagesDir/$function.gif"
        ? "/img/$function.gif"
        : "/img/unknown.gif";
    return $self->cgi->img({ src=>$img, class => 'o', alt => $alt ? $alt : "function: $name"});
}

sub image_vendor
{
    my $self = shift;
    my $vendor = shift || '';

    return ''
        unless $vendor;

    my $img = -e "$ImagesDir/$vendor.gif"
        ? "/img/$vendor.gif"
        : "/img/unknown.gif";
    return $self->cgi->img({ src=>$img, class => 'o', alt => "vendor: $vendor"})
}

sub entity_children_very_short_get
{
    my $self = shift;

    my $with_leafs = @_ ? shift : 1;

    my $children = $self->entity_get_children;

    my $result;
    $result = $self->entity_very_short($self->title_children_leafs, $children->{leafs})
        if $with_leafs;
    $result .= $self->entity_very_short($self->title_children_nodes, $children->{nodes});

    return $result;
}

sub entity_children_long_get
{
    my $self = shift;

    my $with_leafs = @_ ? shift : 1;

    my $children = $self->entity_get_children;

    my $result;
    $result = $self->entity_long($self->title_children_leafs, $children->{leafs})
        if $with_leafs;
    $result .= $self->entity_long($self->title_children_nodes, $children->{nodes});

    return $result;
}

sub entity_children_very_short_bouquet_get
{
    my $self = shift;
    my $content = shift;

    my $children = $self->entity_get_children_bouquet;

    my $result;
    $result = $self->entity_bouquet_very_short($self->title_children_leafs, $children, $content);

    return $result;
}

sub entity_children_long_bouquet_get
{
    my $self = shift;
    my $content = shift;

    my $children = $self->entity_get_children_bouquet;

    my $result;
    $result = $self->entity_bouquet_long($self->title_children_leafs, $children, $content);

    return $result;
}

sub entity_view_very_short_get
{
    my $self = shift;

    my $entities = $self->entity_get_view;

    return $self->entity_very_short('', $entities);
}

sub entity_view_long_get
{
    my $self = shift;

    my $entities = $self->entity_get_view;

    return $self->entity_long('', $entities);
}


sub entity_very_short_desc
{
    my $self = shift;

    my $cgi = $self->cgi;

    my $entity = @_
        ? shift
        : $self->entity;

    return ''
        unless $entity;

    my $id_probe_type = $entity->id_probe_type;
    my $id_entity = $entity->id_entity;

    my $tree = $self->tree;
    my $items = $tree->items;
    my $rel = $tree->relations;
    my $node = $items->{$id_entity};

    my $probe = $ProbesMapRev->{$id_probe_type};

    my $result_end .= qq|<font style="font-size: 18px;"><font style="font-size: 8px">&nbsp;</font></font>|;

    my $status = $node->get_calculated_status;

    my $errmsg = $node->errmsg;

    my $result_inside;

    my $img_alt = sprintf(qq|status %s|, status_name($status));

    if ($entity->monitor)
    {
        $img_alt .= sprintf(qq|: %s|, $errmsg)
            if $errmsg;
    }
    else
    {
        $img_alt .= ': not monitored';
    }

    $result_inside .= $self->image_vendor( $node->image_vendor, $img_alt )
        if (CFG->{Web}->{ListViewShowVendorsImages} && $probe eq 'node');
    
    $result_inside .= $self->image_function($node, $img_alt)
        if (CFG->{Web}->{ListViewShowFunctionsImages});

    if (defined $VIEWS_ALLVIEWS{$self->desktop->view_mode} || defined $VIEWS_FIND{$self->desktop->view_mode})
    {
        $result_inside .= sprintf(qq|%s: |, $items->{ $rel->{$id_entity} }->name);
    }

    $result_inside .= $self->entity_get_name_with_desc($entity, $probe);

    return $self->a_popup(
    {
        id => $id_entity, 
        probe => $probe,
        name => $result_inside,
        class => sprintf(qq|sc%d|, $status )
    }) . $result_end;
}

sub entity_very_short_desc_bouquet
{
    my $self = shift;

    my $cgi = $self->cgi;

    my $entities = shift;
    my $probe_name = shift;
    my $content = shift;

    return ''
        unless $entities;

    my $entities_count = $entities->{entities_count};

    my $result_end .= qq|<font style="font-size: 18px;"><font style="font-size: 8px">&nbsp;</font></font>|;

    my $status = defined $entities->{bad_status}
        ? $entities->{bad_status}
        : $entities->{status};

    my $result_inside;

    my $img_alt = sprintf(qq|status %s|, status_name($status));

    $result_inside .= $self->image_function($self->tree->get_node($entities->{sample_id}), $img_alt)
        if (CFG->{Web}->{ListViewShowFunctionsImages});

    $result_inside .= $probe_name . sprintf(qq| #%s|, $entities_count) 
        . ($entities->{entities_count_bad} ? sprintf(qq| (%s)|, $entities->{entities_count_bad}) : '');

    #
    # make popup menu for bouqet service
    #

    my $id_probe_type = $ProbesMap->{'snmp_generic'} eq $entities->{id_probe_type}
            ? sprintf("%s:%s", $entities->{id_probe_type}, $entities->{snmpgdef})
            : $entities->{id_probe_type};

    my $probe_name_raw = $entities->{id_parent} . "_" . $id_probe_type;
    $probe_name_raw =~ s/:/_/g;

    $content->addRow($self->probes->{'group'}->popup_menu_bqv($entities->{id_parent}, $id_probe_type, $probe_name_raw)); 
 
    return $self->a_popup_bqv(
    {
        id => $entities->{id_parent},
        id_probe_type => $id_probe_type,
        probe => $probe_name_raw,
        name => $result_inside,
        class => sprintf(qq|sc%d|, $status )
    }) . $result_end;
}

sub entity_get_name_with_desc
{
    my $self = shift;
    my $entity = shift;
    my $probe = shift;

    my $result = sprintf(qq|&nbsp;%s&nbsp;|, $self->entity_get_name($entity, $probe));

    my $description = $entity->description;
    if ($description)
    {
        $description = sprintf(qq|%s...|, substr($description, 0, 32))
            if (length($description) > 32);
        $result .= sprintf(qq|[<i>%s</i>]|, $description);
    }
    return $result;
}

sub entity_get_name_with_desc_dynamic
{
    my $self = shift;
    my $entity = shift;
    my $probe = shift;

    my $result = sprintf(qq|&nbsp;%s&nbsp;|, $self->entity_get_name($entity, $probe));

    my $description = $entity->description_dynamic;
    if ($description)
    {
        $description = sprintf(qq|%s...|, substr($description, 0, 32))
            if (length($description) > 32);
        $result .= sprintf(qq|[<i>%s</i>]|, $description);
    }
    return $result;
}

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;
    my $probe = shift;

    my $name = $self->probes->{$probe}
        ? $self->probes->{$probe}->entity_get_name($entity)
        : $entity->name;

    return $name
        ? $name
        : "unknown, id:" . $entity->id_entity;
}

sub entity_get_parent
{
    my $self = shift;

    my $entity = $self->entity;

    return {}
        unless $entity;

    my $id_parent = $entity->id_parent;

    my $result;

        try
        {

    $result = $id_parent
        ? { $id_parent => Entity->new($self->dbh, $id_parent, 1) }
        : {};

        }
            catch  EEntityDoesNotExists with
        {
        }
        except
        {
        };

    return $result;
}

sub entity_get_children
{
    my $self = shift;

    my $url_params = $self->url_params;
    my $hide_not_monitored = $url_params->{hide_not_monitored};

    my $children = { nodes =>{}, leafs => {} };

    my $id_entity = $self->entity;

    $id_entity = $id_entity
        ? $id_entity->id_entity
        : 0;

    my $tree = $self->tree;
    my $items = $tree->items;
    my $rel = $tree->relations;

    return 
        unless $items->{$id_entity};

    return $children
        if $items->{$id_entity}->id_probe_type > 1;

    my $dbh = $self->dbh;
    my $desktop= $self->desktop;

    foreach (grep { $rel->{$_} == $id_entity} keys %$rel)
    {
        next
            unless $_;
        next
            unless $desktop->matrix($url_params->{section}, $items->{$_});
        next
            if $hide_not_monitored && ! $items->{$_}->monitor;

        try
        {

        if ($items->{$_}->id_probe_type < 2)
        {
            $children->{nodes}->{$_} = Entity->new($dbh, $_);
        }
        else
        {
            $children->{leafs}->{$_} = Entity->new($dbh, $_);
        }

        }
        catch  EEntityDoesNotExists with
        {
        }
        except
        {
        };
    }
    return $children;
}

sub entity_get_children_bouquet
{
    my $self = shift;
    
    my $url_params = $self->url_params;
    my $hide_not_monitored = $url_params->{hide_not_monitored};
    
    my $children = { };
    
    my $id_entity = $self->entity;
    
    $id_entity = $id_entity
        ? $id_entity->id_entity
        : 0;
        
    my $tree = $self->tree;
    my $items = $tree->items;
    my $rel = $tree->relations;
    
    return
        unless $items->{$id_entity};
        
    return $children
        if $items->{$id_entity}->id_probe_type > 1;
        
    my $dbh = $self->dbh;
    my $desktop= $self->desktop;
    my $status;
    my $probe;
    my $probe_name;
    my $probes = $self->probes;
    my $monitor;

    foreach (grep { $rel->{$_} == $id_entity} keys %$rel)
    {
        next
            unless $_;
        next
            unless $desktop->matrix($url_params->{section}, $items->{$_});

        $monitor = $items->{$_}->monitor;

        next
            if $hide_not_monitored && ! $monitor;

        $status = $items->{$_}->status;
        $probe = $ProbesMapRev->{ $items->{$_}->id_probe_type };

#warn $probe;
#use Data::Dumper; warn Dumper($items->{$_});

        $probe_name = $probe eq 'snmp_generic'
            ? $probes->{$probe}->name($items->{$_}->snmpgdef)
            : $probes->{$probe}->name;

        $children->{ $probe_name }->{sample_id} = $_
            unless defined $children->{ $probe_name }->{sample_id};
        $children->{ $probe_name }->{probe} = $probe
            unless defined $children->{ $probe_name }->{probe};
        $children->{ $probe_name }->{id_parent} = $id_entity
            unless defined $children->{ $probe_name }->{id_parent};
        $children->{ $probe_name }->{image_function} = $items->{$_}->image_function
            unless defined $children->{ $probe_name }->{image_function};
        $children->{ $probe_name }->{id_probe_type} = $items->{$_}->id_probe_type
            unless defined $children->{ $probe_name }->{id_probe_type};
        $children->{ $probe_name }->{snmpgdef} = $items->{$_}->snmpgdef
            unless defined $children->{ $probe_name }->{snmpgdef};

        ++$children->{ $probe_name }->{entities_count};

        ++$children->{ $probe_name }->{statuses}->{$status};
        if ($monitor && $status > _ST_OK && $status <= _ST_UNKNOWN )
        {
            ++$children->{ $probe_name }->{entities_count_bad};
            $children->{ $probe_name }->{bad_status} = $status
                if ! defined $children->{ $probe_name }->{bad_status}
                   || $children->{ $probe_name }->{bad_status} < $status;
        }
        elsif ($monitor && $status != _ST_NOSTATUS)
        {
            $children->{ $probe_name }->{status} = $status
                if ! defined $children->{ $probe_name }->{status}
                   || $children->{ $probe_name }->{status} < $status;
        }
        elsif (! defined $children->{ $probe_name }->{status})
        {
            $children->{ $probe_name }->{status} = _ST_OK;
        }
    }

#use Data::Dumper; warn Dumper($children);

    return $children;
}

sub entity_get_view
{
    my $self = shift;

    my $entities = [];

    my $view_mode = $self->desktop->view_mode;

    my $desktop = $self->desktop;
    my $items = $self->tree->items;
    my $url_params = $self->url_params;

    my $view_entities;
    my $hide_not_monitored = $self->url_params->{hide_not_monitored};

    if (defined $VIEWS_ALLVIEWS{$view_mode})
    {
        $view_entities = $desktop->views->view_entities;
    }
    elsif (defined $VIEWS_ALLFIND{$view_mode})
    {
        $view_entities = $desktop->find->view_entities;
    }

#use Data::Dumper; warn Dumper($view_entities);

    return []
        unless $view_entities;

    my $dbh = $self->dbh;

    for (@$view_entities)
    {
        next
            unless $_;
        next
            unless $desktop->matrix($url_params->{section}, $items->{$_});
        next
            if $hide_not_monitored && ! $items->{$_}->monitor;

        try
        {
            push @$entities, Entity->new($dbh, $_);
        }
        catch  EEntityDoesNotExists with
        {
        }
        except
        {
        };
    }

    return $entities;
}


sub entity_very_short
{
    my $self = shift;
    my $title = shift;
    my $children = shift;

    my $result = '';

    if (ref($children) eq 'HASH')
    {

    for (
        sort
        { 
            $children->{$a}->id_probe_type <=> $children->{$b}->id_probe_type ||
            uc $children->{$a}->name cmp uc $children->{$b}->name
        }
        keys %$children)
    {
        $result .= $self->entity_very_short_desc($children->{$_});
    }

    }
    else
    {
        for (
        sort
        { 
            $a->id_probe_type <=> $b->id_probe_type ||
            uc $a->name cmp uc $b->name
        }
        @$children)
        {
            $result .= $self->entity_very_short_desc($_);
        }
    }

    if ($result)
    {
        my $table = table_begin($title, 1);
        $table->addRow(qq|<p style="line-height: 500%;">| . $result . qq|</p>|);
        return scalar $table;
    }
    else
    {
        return '';
    }
}

sub entity_bouquet_very_short
{
    my $self = shift;
    my $title = shift;
    my $children = shift;
    my $content = shift;

    my $result = '';

    for ( sort { $a <=> $b } keys %$children)
    {
        $result .= $self->entity_very_short_desc_bouquet($children->{$_}, $_, $content);
    }

    if ($result)
    {
        my $table = table_begin($title, 1);
        $table->addRow(qq|<p style="line-height: 500%;">| . $result . qq|</p>|);
        return scalar $table;
    }
    else
    {
        return '';
    }
}

sub entity_bouquet_long
{
    my $self = shift;
    my $title = shift;
    my $children = shift;
    my $content = shift;

    if (ref($children) eq 'HASH')
    {
        return ''
            unless keys %{ $children };
    }

    my $table = table_begin($title, 4);

    my $color = 0;

    $self->entity_row_bouquet_long_title($table);
    $self->entity_row_bouquet_long_title_style($table, $title);

    my $status;

    for my $probe_name ( sort { uc $a cmp uc $b } keys %$children)
    {
        $status = $self->entity_row_bouquet_long($table, $children->{$probe_name}, $probe_name, $content);
        $self->entity_row_bouquet_long_style($table, $table->getTableRows, $status);

        $table->setRowClass($table->getTableRows, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return scalar $table;
}

sub entity_row_bouquet_long
{
    my $self = shift;
    my $table = shift;
    my $entities = shift;
    my $probe_name = shift;
    my $content = shift;

    next
        unless $entities;
    my $entities_count = $entities->{entities_count};
    my $status = defined $entities->{bad_status}
        ? $entities->{bad_status}
        : $entities->{status};

    my @result;

    push @result, $self->image_function($self->tree->get_node($entities->{sample_id}));


=pod
    push @result, $self->cgi->a({ -href=> sprintf(qq|%s?form_name=form_entity_find&treefind=1&id_entity=0&id_parent=%s&id_probe_type=%s|,
        url_get({}, $self->url_params),
        $entities->{id_parent},
        ($ProbesMap->{'snmp_generic'} == $entities->{id_probe_type})
            ? sprintf("%s:%s", $entities->{id_probe_type}, $entities->{snmpgdef})
            : $entities->{id_probe_type}),
        }, $probe_name);
=cut

    my $id_probe_type = $ProbesMap->{'snmp_generic'} eq $entities->{id_probe_type}
            ? sprintf("%s:%s", $entities->{id_probe_type}, $entities->{snmpgdef})
            : $entities->{id_probe_type};

    my $probe_name_raw = $entities->{id_parent} . "_" . $id_probe_type;
    $probe_name_raw =~ s/:/_/g;

    $content->addRow($self->probes->{'group'}->popup_menu_bqv($entities->{id_parent}, $id_probe_type, $probe_name_raw));

    push @result, $self->a_popup_bqv(
    {
        id => $entities->{id_parent},
        id_probe_type => $id_probe_type,
        probe => $probe_name_raw,
        name => $probe_name,
        class => 'v',
    });

    push @result, status_name($status);
    push @result, $self->entities_statuses($entities->{statuses});

    $table->addRow(@result);
    return $status;
}

sub entities_statuses
{
    my $self = shift;
    my $statuses = shift;
    my $table = table_begin();
    $table->setAlign("LEFT");

    my $i = 1;
    for (sort { $a <=> $b } keys %$statuses)
    {
        $table->setCell(1, $i, sprintf("&nbsp;%s&nbsp;(%s)", status_name($_), $statuses->{$_}));
        $table->setCellAttr(1, $i, qq|class="ts| . $_ . qq|"|);
        ++$i;
    }

    return $table;
}

sub entity_long
{
    my $self = shift;
    my $title = shift;
    my $children = shift;
#use Data::Dumper; warn Dumper([caller(0)]);
#use Data::Dumper; warn Dumper([caller(1)]);
#use Data::Dumper; warn Dumper([caller(2)]);
#use Data::Dumper; warn Dumper([caller(3)]);
    if (ref($children) eq 'HASH')
    {
        return ''
            unless keys %{ $children };
    }
    else
    {
        return 
            unless @$children;
    }

    my $table = table_begin($title, 7);

    my $color = 0;
    my $status;
    my $last_check;

    if (ref($children) eq 'HASH')
    {

    $self->entity_row_title($table);
    $self->entity_row_title_style($table, $title);

    for my $id_entity (
        sort
        {   
            $children->{$a}->id_probe_type <=> $children->{$b}->id_probe_type ||
            uc $children->{$a}->name cmp uc $children->{$b}->name
        }
        keys %$children)
    {   
        ($status, $last_check) = $self->entity_row($table, $children->{$id_entity});
        $self->entity_row_style($table, $table->getTableRows, $status, $children->{$id_entity}, $last_check);
        $table->setRowClass($table->getTableRows, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    }
    else
    {

    $self->entity_row_title($table);
    $self->entity_row_title_style($table, $title);

    for my $entity (
        sort
        {   
            $a->id_probe_type <=> $b->id_probe_type ||
            uc $a->name cmp uc $b->name
        }
        @$children)
    {   
        ($status, $last_check) = $self->entity_row($table, $entity) ;
        $self->entity_row_style($table, $table->getTableRows, $status, $entity, $last_check);
        $table->setRowClass($table->getTableRows, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    }

    return scalar $table;
}

sub tree_get_groups_list
{
    my $self = shift;
    my $result = shift;
    my $id = shift;
    my $with_root = shift;

    my $tree = $self->tree;
    my $items = $tree->items;
    my $path = $tree->get_node_path($id);

    shift @$path
        unless $with_root;

    push @$result, 
    [
        $id, 
        sprintf(qq|%s %s|, "-" x $#$path, $items->{$id}->name ? $items->{$id}->name : sprintf('unknown, id: %s', $id)),
    ]
        if $id || $with_root;

    my $rel = $tree->relations;

    for (sort { $items->{$a}->name cmp $items->{$b}->name } grep { $rel->{$_} == $id } keys %$rel)
    {
        next
            if $items->{$_}->id_probe_type;
        $self->tree_get_groups_list($result, $_, $with_root);
    }

    return $result;
}

sub entity_get_parents_list
{
    my $self = shift;
    my $probe = shift;
    my $id_default = @_ ? shift : '';
    my $cfg = CFG;

    my $tree = $self->tree;
    my $items = $tree->items;

    my $result = [];
    $self->tree_get_groups_list($result, 0, $probe eq 'node' ? 0 : 1);

    my $id_node = $self->url_params->{id_entity} || 0;

    my $node = $id_node
        ? $items->{ $id_node }
        : $items->{ 0 };

    my $node_children =  $tree->get_node_down_family($id_node);

    my $req = {};
    my $key = [];

    for (@$result)
    {
        if ($probe ne 'node' && $id_node)
        {
            next
                if $id_node == $_->[0];
            next
                if defined $node_children->{ $_->[0] };
        }

        push @$key, $_->[0];
        $req->{$_->[0]} = $_->[1];
    }

    return $self->cgi->popup_menu(-name=>'id_parent',
                                   -values=> $key,
                                   -default=> $id_default ne '' ? $id_default : $self->entity->id_parent,
                                   -labels=> $req,
                                   -class => 'textfield',);
}

sub entity_get_parents_list_group_add
{   
    my $self = shift;
    my $probe = shift;
    my $id_default = @_ ? shift : '';
    my $cfg = CFG;

    my $tree = $self->tree;
    my $items = $tree->items;

    my $result = [];
    $self->tree_get_groups_list($result, 0, $probe eq 'node' ? 0 : 1);

    my $id_node = $self->url_params->{id_entity} || 0;

    my $node = $id_node
        ? $items->{ $id_node }
        : $items->{ 0 };

    my $node_children =  $tree->get_node_down_family($id_node);

    my $req = {};
    my $key = [];

    for (@$result)
    {   
        push @$key, $_->[0];
        $req->{$_->[0]} = $_->[1];
    }

    return $self->cgi->popup_menu(-name=>'id_parent',
                                   -values=> $key,
                                   -default=> $id_default ne '' ? $id_default : $self->entity->id_parent,
                                   -labels=> $req,
                                   -class => 'textfield',);
}

sub entity_row_params
{
    my $self = shift;
    my $table = shift;
    my $entity = $self->entity;

    return
        unless $entity;

    my $params = $entity->params_own;
    my $cgi = $self->cgi;

    my $probe = $ProbesMapRev->{ $entity->id_probe_type };
    
    my $cont;
    $cont->{id_entity} = $entity->id_entity;
    $cont->{form_name} = 'form_options_mandatory';
    $cont->{form_title} = 'mandatory options';
    push @{ $cont->{buttons} }, { caption => "process", url => "javascript:document.forms['form_options_mandatory'].submit()" };

    push @{ $cont->{rows} }, 
        ['name', $cgi->textfield({ name => 'name', value => $entity->name, class => "textfield",}), ''];
    push @{ $cont->{rows} }, 
        ['description static', $cgi->textfield({ name => 'description_static', value => $entity->description_static, class => "textfield",}), ''];
    push @{ $cont->{rows} }, ['description dynamic', $entity->description_dynamic, ''];


    push @{ $cont->{rows} }, 
    [
        'check period', $cgi->textfield({ name => 'check_period', value => $entity->check_period, class => "textfield",}),
        $entity->id_probe_type < 2 ? $cgi->checkbox({name => "check_period_children", label => "with services", }) : '',
    ];

    push @{ $cont->{rows} }, 
    [
        'monitor',
        $cgi->textfield({ name => 'monitor', value => $entity->monitor, class => "textfield",}),
        $entity->id_probe_type < 2 ? $cgi->checkbox({name => "monitor_children", label => "with services", }) : '',
    ];

    push @{ $cont->{rows} }, 
        ['status weight', $cgi->textfield({ name => 'status_weight', value => $entity->status_weight, class => "textfield",}),
        sprintf(qq|<nobr>&nbsp;current status: <span class="ts%s">%s</span>&nbsp;</nobr>|, $entity->status, status_name($entity->status)) ];

    push @{ $cont->{styles} }, [ scalar @{ $cont->{rows} } + 2, 2, 'f'];

    if ( $probe eq 'node' || $probe eq 'group' )
    {
        my $status_calculated = node_get_status($self->dbh, $entity->id_entity);
        push @{ $cont->{rows} }, 
            ['calculated status weight', $cgi->textfield({ name => 'calculated_status_weight', value => $status_calculated->{status_weight}, class => "textfield",}) 
            , sprintf(qq|<nobr>&nbsp;current calculated status: <span class="ts%s">%s</span>&nbsp;</nobr>|, $status_calculated->{status}, status_name($status_calculated->{status}) )];
        push @{ $cont->{styles} }, [ scalar @{ $cont->{rows} } + 2, 2, 'f'];

        push @{ $cont->{rows} }, 
            ['parent', $self->entity_get_parents_list($probe), '' ];

    }

    $table->addRow( form_create($cont) );
    $table->setCellColSpan($table->getTableRows, 1, $table->getTableCols-1);

    #$table->addRow( "<hr>" );
    $table->setCellColSpan($table->getTableRows, 1, $table->getTableCols-1);

    $cont = {};
    $cont->{form_name} = 'form_options_update';
    $cont->{form_title} = 'parameters';
    $cont->{id_entity} = $entity->id_entity;
    push @{ $cont->{buttons} }, { caption => "process", url => "javascript:document.forms['form_options_update'].submit()" };

    my $params_ro = $self->dbh->exec( qq|SELECT name,ro FROM parameters| )->fetchall_hashref('name');
    @{$params_ro}{keys %$params_ro} = values %$params_ro;

    my $params_all = $entity->[5];
    for (sort { uc($a) cmp uc($b) } keys %$params_all)
    {
        if (defined $params->{$_})
        {
            push @{ $cont->{rows} }, ["&nbsp;$_&nbsp;",
                $params_ro->{$_}->{ro} ? $params->{$_} : 
                    ($_ =~ /password/ || $_ =~ /community/)
                        ? $cgi->password_field({ name => $_, value => $params->{$_}, class => "textfield",})
                        : ($_ eq 'function' || $_ eq 'vendor')
                            ? build_img_chooser($cgi, 'form_options_update', $_, $params->{$_}, $cont)
                            : $cgi->textfield({ name => $_, value => $params->{$_}, class => "textfield",}),
                $params_ro->{$_}->{ro} 
                     ? ('', '<nobr>read only</nobr>')
                     : ($cgi->checkbox({name => "delete_$_", label => "", }), "&nbsp;<img src=/img/trash.gif>"), 
                ];
        }
        else
        {
            push @{ $cont->{rows} }, ["&nbsp;$_&nbsp;", 
                $_ =~ /password/ || $_ =~ /community/ ? "*****" : $params_all->{$_},
                '', 'inherited',
                ];
        }
    }
    if (defined $cont->{rows})
    {
        $table->addRow( form_create($cont) );
        $table->setCellColSpan($table->getTableRows, 1, $table->getTableCols-1);
    }

    $cont = {};
    $cont->{form_name} = 'form_options_add';
    $cont->{id_entity} = $entity->id_entity;
    push @{ $cont->{buttons} }, { caption => "process", url => "javascript:document.forms['form_options_add'].submit()" };

    my $popup_menu = $self->dbh->exec( sprintf(qq|SELECT name FROM parameters WHERE id_parameter NOT IN
        (SELECT id_parameter FROM entities_2_parameters WHERE id_entity = %d);
        |, $self->entity->id_entity) )->fetchall_arrayref;

    @$popup_menu = sort { uc($a) cmp uc($b) } map { $_->[0] } @$popup_menu
        if $popup_menu;

    push @$popup_menu, '';
    @$popup_menu = sort @$popup_menu;

    $popup_menu = $cgi->popup_menu({ name => 'add_name', values => $popup_menu, -class => 'textfield' });

    push @{ $cont->{rows} }, ['add parameter', $popup_menu,
        $cgi->textfield({ name => 'add_value', value => '', class => "textfield",})];

    $table->addRow( form_create($cont) );
    $table->setCellColSpan($table->getTableRows, 1, $table->getTableCols-1);

    $cont = {};
    $cont->{form_name} = 'form_parameters_modify';
    $cont->{id_entity} = $entity->id_entity;
    push @{ $cont->{buttons} }, { caption => "process", url => "javascript:document.forms['form_parameters_modify'].submit()" };

    push @{ $cont->{rows} }, ['bulk parameters modify', 
        $cgi->textarea({-name =>'bulk', class => "textfield", value => '', rows => 6, columns => 40 }),
        ];

    $table->addRow( form_create($cont) );
    $table->setCellColSpan($table->getTableRows, 1, $table->getTableCols-1);
}

sub entity_row_main_style
{ 
    my $self = shift;
    my $table = shift;
    my $row = shift;
    my $status = shift;
    my $last_check = shift;

    $table->setCellAttr($row, 1, 'class="t2"');
    $table->setCellAttr($row, 2, 'class="f"');
    $table->setCellAttr($row, 3, qq|class="ts| . $status . qq|"|);
    $table->setCellAttr($row, 4, 'class="t2"');

    $table->setCellAttr($row, 5, 'class="f"');
    $last_check ne 'n/a' && time - $self->entity->data->{last_check} > $OldLastCheckAlarm
        ? $table->setCellAttr($row, 6, 'class="g"')
        : $table->setCellAttr($row, 6, 'class="f"');
     
    $table->setCellAttr($row, 7, 'class="m"');

    $table->setRowAttr($row, qq|class="tr_0"|);
}

sub entity_row_title_style
{
    my $self = shift;
    my $table = shift;
    my $row = shift;

    $row = $row ? 2 : 1;

    my $view_mode = $self->desktop->view_mode;

    $view_mode = defined $VIEWS_VIEWS{$view_mode} 
        #|| defined $VIEWS_TREEFIND{$view_mode} 
        || defined $VIEWS_FIND{$view_mode}
        ? 2
        : 0;

    if ($view_mode)
    {
        $table->setCellAttr($row, 2, 'class="g4"');
    }

    $table->setCellAttr($row, $view_mode + 2, 'class="g4"');
    $table->setCellAttr($row, $view_mode + 5, 'class="g4"');
    $table->setCellAttr($row, $view_mode + 6, 'class="g4"');
    $table->setCellAttr($row, $view_mode + 7, 'class="g4"');
    $table->setCellAttr($row, $view_mode + 8, 'class="g4"');
}

sub entity_row_bouquet_long_title_style
{
    my $self = shift;
    my $table = shift;
    my $row = shift;

    $row = $row ? 2 : 1;

    $table->setCellAttr($row, 2, 'class="g4"');
    $table->setCellAttr($row, 3, 'class="g4"');
    $table->setCellAttr($row, 4, 'class="g4"');
}



sub entity_row_title
{
    my $self = shift;
    my @res;

    my $view_mode = $self->desktop->view_mode;
    push @res, '','parent'
        if defined $VIEWS_ALLVIEWS{$view_mode}
        || defined $VIEWS_FIND{$view_mode};

    push @res,
         "",                                       
         "name",                                   
         "",                                     
         "",
         "brief",
         "error",
         "last change",
         "last check";

    $_[0]->addRow( @res );
}   


sub entity_row_bouquet_long_title
{
    my $self = shift;
    my @res;

    push @res,
         "",
         "probe name",
         "status",
         "entities statuses";

    $_[0]->addRow( @res );
}

sub entity_row_main
{ 
    my $self = shift;
    my $table = shift;

    my $entity = @_ ? shift : $self->entity;

    return 
        unless $entity;

    my $monitor = $entity->monitor;

    my $cgi = $self->cgi;

    my $status_last_change = $entity->status_last_change;
    
    my $id_entity = $entity->id_entity;

    my $tree = $self->tree;
    my $node = $tree->get_node($id_entity);
    my $status = $node->get_calculated_status;

    my $probe = $ProbesMapRev->{$entity->id_probe_type};

    my @result;

    push @result, $self->image_vendor( $node->image_vendor );

    push @result, $self->a_popup(
    {
        id => $entity->id_entity, 
        probe => $probe,
        name => $self->entity_get_name($entity, $probe),
    });

    push @result, status_name($status);

    push @result, $self->image_function($node);

    push @result, $entity->status_last_change && $monitor
        ? strftime("%D %T", localtime($entity->status_last_change))
        : 'n/a';

    my $data = $entity->data;

    my $pnode = $tree->parent($id_entity);
    push @result, $self->entity_get_last_check_timestamp($probe, $entity);
=pod
    push @result, (defined $pnode && $pnode->status eq _ST_UNREACHABLE) || $status eq _ST_UNREACHABLE || $status eq _ST_NOSNMP || ! $monitor
        ? 'n/a'
        : $self->entity_get_last_check_timestamp($probe, $entity);
=cut

    push @result, $self->contacts_img($entity->id_entity);

    $table->addRow(@result);

    return ($status, $result[$#result - 1]);
}

sub entity_get_last_check_timestamp
{
    my $self = shift;
    my $probe = shift;
    my $entity = shift;
    my $data = $entity->data;

    return 'n/a'
        unless defined $data;

    $data = $data->{last_check};
#use Data::Dumper; return Dumper($data);
    return 'n/a'
        unless defined $data && $entity->monitor;

    return strftime("%D %T", localtime($data));
}

sub entity_row
{
    my $self = shift;
    my $table = shift;
    my $entity = shift;
    my $vendor = @_ ? shift : 1;

    return
        unless $entity;

    my $view_mode = $self->desktop->view_mode;

    $entity->load_data;

    my $entity_parent = undef;

    try
    {
        $entity_parent = Entity->new( $self->dbh, $entity->id_parent )
            if (defined $VIEWS_ALLVIEWS{$view_mode} || defined $VIEWS_FIND{$view_mode})
            && $entity->id_parent;
    }
    catch  EEntityDoesNotExists with
    {
    }
    except
    {
    };

    my $cgi = $self->cgi;

    my $status_last_change = $entity->status_last_change;

    my $id_entity = $entity->id_entity;

    my $tree = $self->tree;
    my $node = $tree->get_node($id_entity);
    my $status = $node->get_calculated_status;

    my $id_probe_type = $entity->id_probe_type;
    my $probe = $ProbesMapRev->{$id_probe_type};

    my @result;

    if (defined $VIEWS_ALLVIEWS{$view_mode} || defined $VIEWS_FIND{$view_mode})
    {
        my $id_parent = $entity->id_parent;
        my $parent = $tree->get_node( $id_parent );

        push @result, $self->image_vendor( $parent->image_vendor )
            if $vendor;

        if ($entity_parent)
        {
            push @result, $self->a_popup(
            {
                id => $id_parent,
                probe => $ProbesMapRev->{$entity_parent->id_probe_type},
                name => $self->entity_get_name($entity_parent, $ProbesMapRev->{$entity_parent->id_probe_type}),
            });
        }
        else
        {
            $cgi->b('root')
        }

        push @result, $self->image_function($parent);

    }
    else
    {
        push @result, $self->image_vendor( $node->image_vendor )
            if $vendor;
    }

    push @result, $self->a_popup(
    {
        id => $id_entity, 
        probe => $probe,
        name => $self->entity_get_name($entity, $probe),
    });

    push @result, status_name($status);

    push @result, $self->image_function($node);

    my $monitor = $entity->monitor;

    my $brief = $monitor
        ? $self->probes->{$probe}->desc_brief_get($entity)
        : ['not monitored'];

    push @result, defined $brief && ref($brief)
        ? join('; ', @$brief)
        : '';

    push @result, $monitor ? $node->errmsg : '';


    if ($self->probes->{$probe}->alarm_utils_button && $monitor && $node->errmsg)
    {   
        $result[$#result] .= $self->probes->{$probe}->alarm_utils_button_get($node->id, $node->id_probe_type, $self->url_params);
    }

    push @result, $monitor
        ? $status_last_change
            ? strftime("%D %T", localtime($status_last_change))
            : 'n/a'
        : 'n/a';

    my $pnode = $tree->parent($id_entity);
    push @result, $self->entity_get_last_check_timestamp($probe, $entity);
=pod
    push @result, (defined $pnode && $pnode->status eq _ST_UNREACHABLE) || $status eq _ST_UNREACHABLE || $status eq _ST_NOSNMP || ! $monitor
        ? 'n/a'
        : $self->entity_get_last_check_timestamp($probe, $entity);
=cut

    push @result, $self->contacts_img($id_entity, 1) . $self->comments_img($id_entity, 1);

    $table->addRow(@result);

    return ($status, $result[$#result-1]);
}


sub entity_row_bouquet_long_style
{
    my $self = shift;
    my $table = shift;
    my $row = shift;
    my $status = shift;

    $table->setCellAttr($row, 1, 'class="t2"');
    $table->setCellAttr($row, 3, qq|class="ts| . $status . qq|"|);
}

sub entity_row_style
{ 
    my $self = shift;
    my $table = shift;
    my $row = shift;
    my $status = shift;
    my $entity = shift;
    my $last_status = shift;
    my $vendor = @_ ? shift : 1;

    my $view_mode = $self->desktop->view_mode;

    $view_mode = defined $VIEWS_TREE_PURE{$view_mode} || defined $VIEWS_TREEFIND{$view_mode}
        ? 0
        : 2;

    $table->setCellAttr($row, 1, 'class="t2"')
        if $vendor;

    if ($view_mode)
    {
        $table->setCellAttr($row, $vendor + 1, 'class="f"');
        $table->setCellAttr($row, $vendor + 2, 'class="t2"');
    }

    $table->setCellAttr($row, $view_mode + $vendor + 1, 'class="f"');
    $table->setCellAttr($row, $view_mode + $vendor + 2, qq|class="ts| . $status . qq|"|);
    $table->setCellAttr($row, $view_mode + $vendor + 3, 'class="t2"');

    $table->setCellAttr($row, $view_mode + $vendor + 4, 'class="f"');
    $table->setCellAttr($row, $view_mode + $vendor + 5, $status > _ST_OK && $status < _ST_UNKNOWN ? 'class="g"' : 'class="g10"');

    $table->setCellAttr($row, $view_mode + $vendor + 6, 'class="f"');
    if (ref($entity->data))
    {
        $last_status ne 'n/a' && time - $entity->data->{last_check} > $OldLastCheckAlarm
            ? $table->setCellAttr($row, $view_mode + $vendor + 7, 'class="g"')
            : $table->setCellAttr($row, $view_mode + $vendor + 7, 'class="f"');
    }
    $table->setCellAttr($row, $view_mode + $vendor + 8, 'class="m"');
}

sub history_row_style
{
    my $self = shift;
    my $table = shift;
    my $row = shift;
    my $h = shift;
    my $style = shift;

    $table->setCellAttr($row, 1, 'class="g2"');
    $table->setCellAttr($row, 2, 'class="g2"');
    $table->setCellAttr($row, 3, 'class="t2"');
    $table->setCellAttr($row, 4, 'class="f"');
    $table->setCellAttr($row, 5, 'class="t2"');
    $table->setCellAttr($row, 6, 'class="f"');
    $table->setCellAttr($row, 7, qq|class="ts| . $h->{status_old} . qq|"|);
    $table->setCellAttr($row, 8, qq|class="ts| . $h->{status_new} . qq|"|);
    $table->setCellAttr($row, 9, 'class="f"');
    $table->setCellAttr($row, 10, 'class="m"');
    $table->setCellAttr($row, 11, $h->{err_approved_by} ? 'class="g2"' : 'class="m"');

    $table->setRowAttr($row, sprintf(qq|class="tr_%d"|, $style));
}

sub history_row
{
    my $self = shift;
    my $table = shift;
    my $h = shift;
    my $resolution = shift;

    my $cfg = $ProbesMapRev;

    my @row;

    my $node = $self->tree->get_node( $h->{id_parent} );

    next
        unless defined $node;

    push @row, $h->{'id'};
    push @row, $h->{'time'};
    push @row, $self->image_function( $node );
    push @row, $self->a_popup(
    {
        id => $h->{id_parent}, 
        probe => $cfg->{$node->id_probe_type}, 
        name => $node->name,
    });

    my $probe = $self->probes->{ $ProbesMapRev->{ $h->{id_probe_type} } };
    push @row, $self->image_function($self->tree->get_node( $h->{id_entity}));
    push @row, $self->a_popup(
    {
        id => $h->{id_entity}, 
        probe => $cfg->{$h->{id_probe_type}}, 
        name => $h->{name} ? "<b>$h->{name}</b>" : "<b>unknown, id: $h->{id_entity}</b>",
    });

    push @row, status_name($h->{status_old});
    push @row, status_name($h->{status_new});

    push @row, $h->{errmsg};

    my ($begin, $end, $middle) =
    (
        strftime("%H:%M %m/%d/%Y", localtime($h->{timest} - $resolution)),
        strftime("%H:%M %m/%d/%Y", localtime($h->{timest} + $resolution)),
        $h->{timest},
    );

    push @row, $probe->menu_stat
        ? sprintf(qq|<a href="%s"><img src=/img/chart.gif></a>|, 
            url_get({id_entity => $h->{id_entity}, section => 'stat', 
            begin => $begin, end => $end,
            history_alarm_time => $middle,
            history_alarm_err => $h->{errmsg},
            }, $self->url_params))
        : '';

    push @row, $h->{err_approved_by}
        ? 'after ' . duration_row($h->{err_approved_at}) . ' by ' 
            . (defined $self->users->{$h->{err_approved_by}} ? $self->users->{$h->{err_approved_by}}->username : 'unknown' )
            . ' (' . $h->{err_approved_ip} . ')'
        : '';

    push @row, $h->{flap};
  
    $table->addRow(@row);
}

sub stat
{
    my $self = shift;
    my $content = shift;

    my $entity = $self->entity;
    my $url_params = $self->url_params;
    my $desktop = $self->desktop;
    my $items = $self->tree->items;
    my $tree = $self->tree;
    my $view_mode = $desktop->view_mode;

    my $probe;

    return
        unless defined $entity && $entity->id_entity && $entity->monitor;

    $probe = $self->probes->{ $ProbesMapRev->{ $entity->id_probe_type } };

    return
        unless defined $probe;

    my $options = session_get_param($self->session, '_GRAPH_OPTIONS');
    if (defined $options && ref($options) eq 'HASH')
    {
        $url_params->{$_} = $options->{$_}
            for (keys %$options);
    }

    my $show_collected_info = session_get_param($self->session, '_STAT_SHOW_COLLECTED_INFO');
    my $show_node_info = session_get_param($self->session, '_STAT_SHOW_NODE_INFO');

    if ($probe->menu_stat($entity) eq '1' && $desktop->matrix($url_params->{section}, $items->{$entity->id_entity}))
    {
        $self->entity_general($content)
            if $show_collected_info;
        my $probe_name = $ProbesMapRev->{ $entity->id_probe_type };
        if (-e sprintf(qq|%s/%s.%s|, CFG->{Probe}->{RRDDir}, 
            $probe_name eq 'icmp_monitor' ? $entity->params('nic_ip') : $entity->id_entity, $probe_name ) )
        {
            $probe->stat($content, $entity, $url_params);
            $probe->stat_delta($content, $entity, $url_params)
                if CFG->{Web}->{Stat}->{ShowDeltaTest};
        }
        else
        {
            $content->addRow('no statistic information available');
        }
    }
    if ($probe->menu_stat($entity) eq '2' && $desktop->matrix($url_params->{section}, $items->{$entity->id_entity}))
    {

        my $children;
        
        if (defined $VIEWS_ALLFIND{$view_mode})
        {
            my $opt = $self->session->param('_FIND') || {};
            $children = $tree->get_node_down_family($entity->id_entity, defined $opt->{id_probe_type} ? $opt->{id_probe_type} : "");
        }
        else
        {
            $children = $tree->get_node_down_family($entity->id_entity);
        }

        my $ent;
        my $table;
        my $dbh = $self->dbh;
        my ($status, $last_check, $rowc, $probe_name);

        my $hide_not_monitored = $url_params->{hide_not_monitored};

        if ($show_node_info)
        {

            $self->entity_general($content);

        if ($entity->params('snmp_community_ro') || $entity->params('snmp_user'))
        {
            $table = table_begin('node', 6);

            if ($show_collected_info)
            {
                ($status, $last_check) = $self->entity_row($table, $entity, 0);
                $self->entity_row_style($table, $table->getTableRows, $status, $entity, $last_check, 0);
                $table->setRowClass($table->getTableRows, qq|tr_0|);
            }

            $rowc = $table->getTableRows;
            if ($entity->monitor && -e sprintf(qq|%s/%s.%s|, CFG->{Probe}->{RRDDir}, $entity->id_entity, 'node'))
            {   
                $probe->stat($table, $entity, $url_params, 'default');
            }
            else
            {
                $table->addRow('no statistic information available');
            }
            if ($show_collected_info)
            {   
                $table->setCellColSpan($_, 1, 7)
                    for ($rowc+1 .. $table->getTableRows);
                $table->setCellAttr($_, 1, 'class="k"')
                    for ($rowc+1 .. $table->getTableRows-1);
                $table->setCellAttr($table->getTableRows, 1, 'class="l"');
            }
        }

        }

#services
        $table = table_begin('services', 6, $table);

        for my $id (sort 
            { 
                $children->{$a}->id_probe_type cmp $children->{$b}->id_probe_type
                || $children->{$a}->name cmp $children->{$b}->name
            } keys %$children )
        {
            next
                unless $children->{$id}->id_probe_type > 1;
            next
                if $hide_not_monitored && ! $children->{$id}->monitor;
            next
                unless $desktop->matrix($url_params->{section}, $items->{$id});

        try
        {
            $ent = Entity->new( $dbh, $id);
        }
        catch  EEntityDoesNotExists with
        {
        }
        except
        {
        };

            $probe_name = $ProbesMapRev->{ $ent->id_probe_type };
            $probe = $self->probes->{ $probe_name };

            next
                if $probe->menu_stat_no_default;

            $url_params->{id_entity} = $id;

            next
                unless $ent->monitor 
                    && -e sprintf(qq|%s/%s.%s|, CFG->{Probe}->{RRDDir}, 
                        $probe_name eq 'icmp_monitor' ? $ent->params('nic_ip') : $ent->id_entity, $probe_name );

            if ($show_collected_info)
            {
                $url_params->{probe} = $probe_name;
                $url_params->{probe_specific} = '';
                ($status, $last_check) = $self->entity_row($table, $ent, 0);
                $self->entity_row_style($table, $table->getTableRows, $status, $ent, $last_check, 0);
                $table->setRowClass($table->getTableRows, qq|tr_0|);
            }

            $rowc = $table->getTableRows;

            $probe->stat($table, $ent, $url_params, 'default');

            if ($show_collected_info)
            {
                $table->setCellColSpan($_, 1, 7)
                    for ($rowc+1 .. $table->getTableRows);
                $table->setCellAttr($_, 1, 'class="k"')
                    for ($rowc+1 .. $table->getTableRows-1);
                $table->setCellAttr($table->getTableRows, 1, 'class="l"');
            }
        }
        $url_params->{id_entity} = $entity->id_entity;

        $content->addRow( scalar $table )
            if $table->getTableRows;
    }
}

sub stat_view
{
    my $self = shift;
    my $content = shift;

    my $entities = $self->entity_get_view;

    return
        unless @$entities;

    my $url_params = $self->url_params;

    my $options = session_get_param($self->session, '_GRAPH_OPTIONS');
    if (defined $options && ref($options) eq 'HASH')
    {
        $url_params->{$_} = $options->{$_}
            for (keys %$options);
    }

    my $table = table_begin('', 6);
    my ($status, $last_check, $rowc, $probe);
    my $tmp_id = $url_params->{id_entity};

    my $show_collected_info = session_get_param($self->session, '_STAT_SHOW_COLLECTED_INFO');
    my $show_node_info = session_get_param($self->session, '_STAT_SHOW_NODE_INFO');

    if (defined $VIEWS_TREEFIND{$self->desktop->view_mode} && $show_node_info)
    {
        $self->entity_general($content);
    }

    for my $ent (@$entities)
    {
        $probe = $self->probes->{ $ProbesMapRev->{ $ent->id_probe_type } };
        $url_params->{id_entity} = $ent->id_entity;

        if ($show_collected_info)
        {
            ($status, $last_check) = $self->entity_row($table, $ent, 1);
            $self->entity_row_style($table, $table->getTableRows, $status, $ent, $last_check, 1);
            $table->setRowClass($table->getTableRows, qq|tr_0|);
        }

        $rowc = $table->getTableRows;

        if ($ent->monitor && -e sprintf(qq|%s/%s.%s|, CFG->{Probe}->{RRDDir}, $ent->id_entity, $ProbesMapRev->{ $ent->id_probe_type } ) )
        {
            $probe->stat($table, $ent, $url_params, 'default');
        }
        else
        {
            $table->addRow('no statistic information available');
        }


        if ($show_collected_info)
        {
            $table->setCellColSpan($_, 1, 10)
                 for ($rowc+1 .. $table->getTableRows);
            $table->setCellAttr($_, 1, 'class="k"')
                 for ($rowc+1 .. $table->getTableRows-1);
            $table->setCellAttr($table->getTableRows, 1, 'class="l"');
        }
    }

    $url_params->{id_entity} = $tmp_id;

    $content->addRow( scalar $table )
        if $table->getTableRows;
}

sub form_graph_options
{
    my $self = shift;

    my $cont;

    my $form = $self->url_params;
    my $cgi = $self->cgi;

    $cont->{form_name} = 'form_graph_options';
    $cont->{form_title} = '';
    $cont->{id_entity} = defined $self->entity ? $self->entity->id_entity : 0;

    push @{ $cont->{buttons} }, { caption => "OK", url => "javascript:document.forms['form_graph_options'].submit()" };

    my $options = session_get_param($self->session, '_GRAPH_OPTIONS');

    push @{ $cont->{rows} }, 
    [
        'begin',
        $cgi->textfield({size => 4, -name =>'begin', class => "textfield", value => defined $options->{begin} ?  $options->{begin} : '' }),
        '',
        'width',
        $cgi->textfield({ size => 4, -name =>'width', class => "textfield", value => defined $options->{width} ?  $options->{width} : '' }),
        '',
        '<nobr>no x-grid</nobr>',
        $cgi->checkbox({name => "no_x_grid", label => "", checked => defined $options->{no_x_grid} && $options->{no_x_grid} eq 'on' ? 'checked' : ''}),
        '',
        '<nobr>no legend</nobr>',
        $cgi->checkbox({name => "no_legend", label => "", checked => defined $options->{no_legend} && $options->{no_legend} eq 'on' ? 'checked' : ''}),
        'zoom',
        $cgi->textfield({size => 4, -name =>'zoom', class => "textfield", value => defined $options->{zoom} ?  $options->{zoom} : '' }),
        'scale',
        $cgi->textfield({size => 4, -name =>'scale', class => "textfield", value => defined $options->{scale} ?  $options->{scale} : '' }),
    ];
    push @{ $cont->{rows} }, 
    [
        'end',
        $cgi->textfield({size => 4, -name =>'end', class => "textfield", value => defined $options->{end} ?  $options->{end} : '' }),
        '',
        'height',
        $cgi->textfield({ size => 4, -name =>'height', class => "textfield", value => defined $options->{height} ?  $options->{height} : '' }),
        '',
        '<nobr>no y-grid</nobr>',
        $cgi->checkbox({name => "no_y_grid", label => "", checked => defined $options->{no_y_grid} && $options->{no_y_grid} eq 'on' ? 'checked' : ''}),
        '',
        '<nobr>only graph</nobr>',
        $cgi->checkbox({name => "only_graph", label => "", checked => defined $options->{only_graph} && $options->{only_graph} eq 'on' ? 'checked' : ''}),
        '<nobr>no title</nobr>',
        $cgi->checkbox({name => "no_title", label => "", checked => defined $options->{no_title} && $options->{no_title} eq 'on' ? 'checked' : ''}),
        '<nobr>force scale</nobr>',
        $cgi->checkbox({name => "force_scale", label => "", checked => defined $options->{force_scale} && $options->{force_scale} eq 'on' ? 'checked' : ''}),
    ];

    push @{ $cont->{cellRowSpans} }, [2, 3, 2];
    push @{ $cont->{cellRowSpans} }, [2, 6, 2];
    push @{ $cont->{cellRowSpans} }, [2, 9, 2];

    push @{ $cont->{class} }, [2, 3, 'g5'];
    push @{ $cont->{class} }, [2, 6, 'g5'];
    push @{ $cont->{class} }, [2, 9, 'g5'];

    return form_create($cont);
}

sub form_history_filter
{
    my $self = shift;

    my $cont;

    my $form = $self->url_params;
    my $cgi = $self->cgi;

    $cont->{form_name} = 'form_history_filter';
    $cont->{form_title} = '',
    $cont->{id_entity} = defined $self->entity ? $self->entity->id_entity : 0;

        #parent => 'parent name', - zablokowane ze wzg na brak info z bazy danych w pojedynczym req
    my $items =
    {
        '' => '-- select --',
        name => 'name',
        status_old => 'status old',
        status_new => 'status new',
        errmsg => 'error',
        'id_probe_type' => 'probe',
    };

    my $cond = 
    {
        '' => '-- select --',
        'not_equal' => 'not equal',
        'equal' => 'equal to',
        'greater' => 'greater then',
        'lower' => 'lower then',
        'contain' => 'contain',
        'not_contain' => 'not contain',
    };

    push @{ $cont->{buttons} }, { caption => "update conditions", url => "javascript:document.forms['form_history_filter'].submit()" };

    my $conditions = session_get_param($self->session, '_HISTORY_CONDITIONS');
    if (defined $conditions && ref($conditions) eq 'HASH')
    {
        for (sort keys %$conditions)
        {
            push @{ $cont->{rows} },
            [
                sprintf(qq|<b>%s</b> %s %s <b>%s</b>|, 
                    $items->{$conditions->{$_}->{field}},
                    $cond->{$conditions->{$_}->{cond}},
                    $conditions->{$_}->{value} ne '' ? 'value: ' : 'field: ',
                    $conditions->{$_}->{value} ne '' ? $conditions->{$_}->{value} : $items->{$conditions->{$_}->{value_field}}
                ),
                '',
                '',
                $cgi->checkbox({name => "delete_$_", label => ""}) . "&nbsp;<img src=/img/trash.gif>",
            ];
            push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} }, 1, 3];
        }
        push @{ $cont->{rows} }, ['', '', '', ''];
        push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} }, 1, 4];
    }

    push @{ $cont->{rows} },
    [ 
        'filter field:<br>' . $cgi->popup_menu(-name=>'field', -values=>[ sort { uc $items->{$a} cmp uc $items->{$b} } keys %$items], -labels=> $items, -default => '', -class => 'textfield'),
        'by condition:<br>' . $cgi->popup_menu(-name=>'cond', -values=>[ sort { uc $cond->{$a} cmp uc $cond->{$b} } keys %$cond], -labels=> $cond, -default => '', -class => 'textfield'),
        'in field:<br>' . $cgi->popup_menu(-name=>'value_field', -values=>[ sort { uc $items->{$a} cmp uc $items->{$b} } keys %$items], -labels=> $items, -default => '', -class => 'textfield'),
        'or in value:<br>' .
        $cgi->textfield({-name =>'value', -value => '', class => "textfield"}),
    ];

    return form_create($cont);
}

sub history_conditions_dispatch
{
    my $self = shift;
    my $cond = shift;
    my @result = ();

    my $c;
    for (keys %$cond)
    {
        $_ = $cond->{$_};
        $c = '';

        if ($_->{field} eq 'parent')
        {
            $c = "links.id_parent in (SELECT id_entity FROM entities WHERE name ";

            if ($_->{value} eq '')
            {
                $c = '';
            }
            elsif ($_->{cond} eq 'contain')
            {
                $c .= sprintf(qq|like '%%%s%%')|, $_->{value});
            }
            elsif ($_->{cond} eq 'not_contain')
            {
                $c .= sprintf(qq|not like '%%%s%%')|, $_->{value});
            }
            elsif ($_->{cond} eq 'not_equal')
            {
                    $c .= ' <> ';
                    $c .= sprintf(qq|'%s')|, $_->{value});
            }
            elsif ($_->{cond} eq 'equal')
            {
                    $c .= ' = ';
                    $c .= sprintf(qq|'%s')|, $_->{value});
            }   
            elsif ($_->{cond} eq 'greater')
            {
                    $c = '';
            }
            elsif ($_->{cond} eq 'lower')
            {
                    $c = '';
            }
        }
        else
        {
            if ($_->{field} eq 'errmsg')
            {
                $c = "history24.$_->{field}";
            }
            else
            {
                $c .= $_->{field};
            }

            if ($_->{cond} eq 'contain')
            {
                $c .= sprintf(qq| like '%%%s%%'|, $_->{value});
            }
            elsif ($_->{cond} eq 'not_contain')
            {
                $c .= sprintf(qq| not like '%%%s%%'|, $_->{value});
            }
            else
            {
                if ($_->{cond} eq 'not_equal')
                {
                    $c .= ' <> ';
                }
                elsif ($_->{cond} eq 'equal')
                {
                    $c .= ' = ';
                }
                elsif ($_->{cond} eq 'greater')
                {
                    $c .= ' > ';
                }
                elsif ($_->{cond} eq 'lower')
                {
                    $c .= ' < ';
                }

                if ($_->{value} ne '')
                {
                    if ($_->{field} eq 'status_old' || $_->{field} eq 'status_new')
                    {
                        $c .= status_number($_->{value});
                    }
                    elsif ($_->{field} eq 'id_probe_type')
                    {
                        if (defined CFG->{ProbesMap}->{ $_->{value} })
                        {
                            $c .= CFG->{ProbesMap}->{ $_->{value} };
                        }
                        else
                        {
                            $c = '';
                        }
                    }
                    else
                    {
                        $c .= sprintf(qq|'%s'|, $_->{value});
                    }
                }
                else
                {
	            $c .= $_->{value_field};
                }
            }
        }
        push @result, $c
            if $c;
    }

    return @result
        ? sprintf(qq| AND (%s)|, join(" AND ", @result))
        : "";
}

sub history
{
    my $self = shift;

    my $view_mode = $self->desktop->view_mode;

    return ['', 0]
        if (defined $VIEWS_ALLVIEWS{$view_mode}) && ! $self->desktop->views->id_view;

    my $root = defined $self->entity && ! defined $VIEWS_ALLVIEWS{$view_mode}
        ? $self->entity->id_entity
        : 0;

    my $url_params = $self->url_params;

    my $limit = $url_params->{limit} || CFG->{Web}->{History}->{DefaultLimit};
    my $offset = $url_params->{offset} || 0;

    my $window = '1 DAY';
    my $window_number = $url_params->{base} || 0;
    my $window_base = time - $window_number * 86400;
    my $job = [];

    my $counter = 0;

    my $view_entities = {};
    if (defined $VIEWS_ALLVIEWS{$view_mode})
    {
        $view_entities = $self->desktop->views->view_entities;
    }
    elsif (defined $VIEWS_ALLFIND{$view_mode})
    {
        $view_entities = $self->desktop->find->view_entities;
    }

    $job = history_get_job( $self->dbh, $root, $view_mode, $view_entities );

    return ['', 0]
        unless @$job || ! $root;

    return ['', 0]
        if ! @$job && (defined $VIEWS_ALLVIEWS{$view_mode} || defined $VIEWS_ALLFIND{$view_mode});

    my $statement;
    my $req;
    my $conditions = session_get_param($self->session, '_HISTORY_CONDITIONS');
    $conditions = defined $conditions && ref($conditions) eq 'HASH'
        ? $self->history_conditions_dispatch($conditions)
        : '';

#warn "#$conditions#";


    $statement = qq|SELECT COUNT(id) as total FROM history24,entities WHERE history24.id_entity=entities.id_entity|;
    if ($root || defined $VIEWS_ALLVIEWS{$view_mode} || defined $VIEWS_ALLFIND{$view_mode})
    {
        $statement .= qq| AND history24.id_entity in (|;
        $statement .= join(',', @$job);
        $statement .= qq|)|;
    }
    $statement .= qq| AND time > (FROM_UNIXTIME($window_base) - INTERVAL $window) AND time < FROM_UNIXTIME($window_base)|
        if @$job != 1;
    $statement .= $conditions;

#warn "#$statement#";

    $req = $self->dbh->exec( $statement );
    $req  = $req->fetchrow_hashref;
#use Data::Dumper; warn Dumper($req);
    my $total = $req->{total};
    $url_params->{total} = $total;

    if ($offset > $total)
    {
        $url_params->{offset} = 0;
        $offset = 0;
    }

    $statement = qq|SELECT id, entities.id_entity,entities.name,id_probe_type,status_old,
        status_new,history24.errmsg,time,UNIX_TIMESTAMP(time) as timest, history24.err_approved_by,
        history24.err_approved_at, history24.err_approved_ip, history24.flap
        FROM history24,entities
        WHERE history24.id_entity=entities.id_entity|;
    if ($root || defined $VIEWS_ALLVIEWS{$view_mode} || defined $VIEWS_ALLFIND{$view_mode})
    {
        $statement .= qq| AND history24.id_entity in (|;
        $statement .= join(',', @$job);
        $statement .= qq|)|;
    }
    $statement .= qq| AND time > (FROM_UNIXTIME($window_base) - INTERVAL $window) AND time < FROM_UNIXTIME($window_base)|
        if @$job != 1;
    $statement .= $conditions;

    $statement .= sprintf(qq| ORDER BY id DESC LIMIT %s OFFSET %s|, $limit, $offset);

#warn "#$statement#";

    my $color = 0;
    $req = $self->dbh->exec( $statement );

    my $navi1 = $self->history_navi1($limit, $offset, $total, $window_number);
    my $navi2 = $self->history_navi2($window_number, $window_base, $job);
        
    my $table = table_begin();

    $table->addRow( "<b>$navi2</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>$navi1</b>" );
    $table->setCellColSpan($table->getTableRows, 1, 11);
    $table->setCellAttr($table->getTableRows, 1, 'class="g6"');
    $table->addRow( "" );
    $table->setCellColSpan($table->getTableRows, 1, 11);
    $table->setRowAttr($table->getTableRows, qq|class="tr_0"|);

    $self->history_row_title($table);
    $self->history_row_title_style($table, 3);

    my $resolution = CFG->{Web}->{History}->{StatResolution} || 3600;

    my $items = $self->tree->items;
    my $rel = $self->tree->relations;

    while( my $h = $req->fetchrow_hashref )
    {
        $h->{id_parent} = $rel->{ $h->{id_entity} };
        next
            unless defined $items->{ $h->{id_entity} }
                && $items->{ $h->{id_parent} }->get_right($self->tree->id_user, _R_VIE);
        $self->history_row($table, $h, $resolution);
        $self->history_row_style($table, $table->getTableRows, $h, $color);
        $color = ! $color;
        ++$counter;
    }

    $table->addRow( "" );
    $table->setCellColSpan($table->getTableRows, 1, 11);
    $table->setRowAttr($table->getTableRows, qq|class="tr_0"|);
    $table->addRow( "<b>$navi2</b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>$navi1</b>" );
    $table->setCellColSpan($table->getTableRows, 1, 11);
    $table->setCellAttr($table->getTableRows, 1, 'class="g6"');

    return $counter
        ? [scalar $table, 1]
        : [$navi2, 0];
}

sub history_navi1
{
    my $self = shift;
    my $limit = shift;
    my $offset = shift;
    my $total = shift;
    my $window_number = shift;

    my $cgi = $self->cgi;
    my $url_params = $self->url_params;

    my $page = $offset/$limit;
    my $page_total = $total/$limit;

    my ($start, $stop);
    my $tot = 6;

    $start = $page >= $tot
        ? $page - $tot
        : 0;

    $stop = $page < $tot
        ? $tot
        : $page + $tot;

    if ($stop - $start < $tot*2)
    {
        $stop = $tot*2;
    }

    if ($stop > $page_total)
    {
        $start -= $stop - int($page_total);
        $start = 0
            if $start < 0;
        $stop = int($page_total);
    }

    my @res;

    if ($start != $page)
    {
        push @res, $cgi->a({ href => url_get({ base => $window_number, limit => $limit, offset => 0}, $self->url_params), class=> 's' }, '&lt&lt'); 
    }
  
    if ($start != $page)
    { 
        push @res, $cgi->a({ href => url_get({ base => $window_number, limit => $limit, offset => $offset-$limit}, $self->url_params), class=> 's' }, '&lt'); 
    }

    for ($start .. $stop)
    {
        if ($_ == $page)
        {
            push @res, $_+1;
        }
        else
        {
            push @res, $cgi->a({ href => url_get({ base => $window_number, limit => $limit, offset => $limit*$_}, $self->url_params), class=> 's' }, $_+1); 
        }
    }

    if ($stop != $page)
    {
        push @res, $cgi->a({ href => url_get({ base => $window_number, limit => $limit, offset => $offset+$limit}, $self->url_params), class=> 's' }, '&gt'); 
    }
    if ($stop != $page)
    {
        push @res, $cgi->a({ href => url_get({ base => $window_number, limit => $limit, offset => $limit*int($page_total)}, $self->url_params), class=> 's' }, '&gt&gt'); 
    }

    return '<span class="g1">page: </span>' . join(' | ', @res);
}


sub history_navi2
{
    my $self = shift;
    my $window_number = shift;
    my $window_base = shift;
    my $job = shift;

    return
        if @$job == 1;

    my $cgi = $self->cgi;
    my $url_params = $self->url_params;

    my @res;

    push @res, $cgi->a({ href => url_get({ base => 0, offset => 0}, $self->url_params), class=> 's' }, '&lt&lt')
        if $window_number > 1;
    push @res, $cgi->a({ href => url_get({ base => $window_number - 1, offset => 0}, $self->url_params), class=> 's' }, '&lt')
        if $window_number;

    push @res, sprintf('<span class="g1">%s - %s</span>', scalar localtime($window_base), scalar localtime($window_base - 86400));

    push @res, $cgi->a({ href => url_get({ base => $window_number + 1, offset => 0}, $self->url_params), class=> 's' }, '&gt');

    return join(' | ', @res);
}
    
sub history_row_title_style
{       
    my $self = shift;
    my $table = shift;
    my $row = shift;
    
    $table->setCellAttr($row, 1, 'class="g4"');
    $table->setCellAttr($row, 2, 'class="g4"');
    $table->setCellAttr($row, 4, 'class="g4"');
    $table->setCellAttr($row, 6, 'class="g4"');
    $table->setCellAttr($row, 7, 'class="g4"');
    $table->setCellAttr($row, 8, 'class="g4"');
    $table->setCellAttr($row, 9, 'class="g4"');
    $table->setCellAttr($row, 11, 'class="g4"');
}

sub history_row_title
{
    my $self = shift;
    $_[0]->addRow(
         "id",
         "timestamp",
         "",
         "parent",
         "",
         "name",
         "status old",
         "status new",
         "message",
         "",
         "approval",
    );
}

sub entity_add
{
    my $self = shift;

    my $content = shift;
    my $node = shift;

    my $url_params = $self->url_params;
    my $what = $url_params->{what};

    if ($what eq '1'
        && $self->desktop->matrix('form_group_add', $node))
    {
        $self->form_group_add($content);
    }
    if ($what eq '2'
        && $self->desktop->matrix('form_node_add', $node))
    {
        $self->form_node_add($content);
    }
    if ($what eq '3'
        && $self->desktop->matrix('form_service_add', $node)
        && $self->desktop->matrix('form_probe_select', $node))
    {
        my $options = session_get_param($self->session, '_GENERAL_OPTIONS');
        if (defined $options && ref($options) eq 'HASH')
        {   
            $url_params->{$_} = $options->{$_}
                for (keys %$options);
        }
        my $table = table_begin('add service');
        $self->form_probe_select($table);
        $self->form_service_add($table)
            if $url_params->{id_probe_type};
        $content->addRow('<br>' . $table);
    }
}

sub form_entity_discover
{
    my $self = shift;
    my $content = shift;

    my $entity = $self->entity;

    return
        unless defined $entity;

    my $cgi = $self->cgi;

    my $ProbesMap = CFG->{ProbesMap};
    my $Probes = CFG->{Discover}->{Probes}; 

    my $pr = {};

    for (keys %$ProbesMap)
    {
        $pr->{ $ProbesMap->{ $_ } } = $_
            if $self->probes->{$_}->discover_mode;
    }

    my $cont;
    $cont->{form_name} = 'form_entity_discover';
    $cont->{form_title} = 'discover';
    $cont->{id_entity} = $self->url_params->{id_entity};

    my $db = $self->dbh;
    my $req = $db->exec( sprintf(qq|SELECT *,UNIX_TIMESTAMP(timestamp) as time FROM discover WHERE id_entity=%s|, 
        $cont->{id_entity}) )->fetchall_hashref('id_probe_type');

    if (keys %$req)
    {
        my $users = $self->users;
        for (sort { uc($ProbesMapRev->{$a}) cmp uc($ProbesMapRev->{$b})} keys %$req)
        {
            push @{ $cont->{rows} }, 
            [
                sprintf(qq|<b>%s</b> in progress since <b>%s</b> by <b>%s</b> (%s)|, 
                    $ProbesMapRev->{ $_ }, 
                    duration($req->{$_}->{time}) || 'now',
                    defined $users->{$req->{$_}->{id_user}} 
                        ? $users->{$req->{$_}->{id_user}}->username
                        : 'unknown',
                    $req->{$_}->{ip},
                )
            ];
            push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} } + 1, 1, 2];
            delete $pr->{$_};
        }
    }
    else
    {
        $pr->{0} = 'all probes';
        push @{ $cont->{rows} }, [ qq|no pending discover requests. that's OK.| ];
        push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} } + 1, 1, 2];
    }


    if (keys %$pr)
    {
        push @{ $cont->{rows} }, 
        [
            'select probe',
            $cgi->popup_menu(-name=>'id_probe_type',
                -values=>[ sort { uc $pr->{$a} cmp uc $pr->{$b} } keys %$pr],
                -default=> 0,
                -labels=> $pr,
                -class => 'textfield')
        ];
        push @{ $cont->{buttons} },
            { caption => "process", url => "javascript:document.forms['form_entity_discover'].submit()" };
    }
    push @{ $cont->{buttons} }, { caption => "cancel", url => url_get({what_op => 0}, $self->url_params) };

    $content->addRow( form_create($cont) );
    $content->addRow( sprintf
    (
        qq|configured discover process period: %ss. if there are discover reqest pending longer then %ss it seems there is something wrong with the discover process. some of the discover processes (e.g. tcp_generic, ssl_generic) against firewalls or hosts behind firewall may take a few minutes and that is normal.|, 
        CFG->{Discover}->{Period}, 
        5*CFG->{Discover}->{Period}
    ));
}

sub form_entity_test
{
    my $self = shift;
    my $content = shift;

    my $entity = $self->entity;

    return
        unless defined $entity;

    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_entity_test';
    $cont->{form_title} = 'force test';
    $cont->{id_entity} = $self->url_params->{id_entity};

    my $db = $self->dbh;
    my $req = $db->exec( sprintf(qq|SELECT *,UNIX_TIMESTAMP(timestamp) as time FROM force_test WHERE id_entity=%s|,
        $cont->{id_entity}) )->fetchrow_hashref;

    if (keys %$req)
    {
        my $users = $self->users;
        push @{ $cont->{rows} },
        [
                sprintf(qq|force test in progress since <b>%s</b> by <b>%s</b> (%s)|,
                    duration($req->{time}) || 'now',
                    defined $users->{$req->{id_user}}
                        ? $users->{$req->{id_user}}->username
                        : 'unknown',
                    $req->{ip},
                )
        ];
        push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} } + 1, 1, 2];
    }
    else
    {
        push @{ $cont->{rows} }, [ qq|are you sure you would like to request force test for current entity?| ];
        push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} } + 1, 1, 2];
        push @{ $cont->{buttons} },
            { caption => "test", url => "javascript:document.forms['form_entity_test'].submit()" };
    }


    push @{ $cont->{buttons} }, { caption => "cancel", url => url_get({what => 0}, $self->url_params) };

    $content->addRow( form_create($cont) );
}

sub form_group_add
{
    my $self = shift;
    my $content = shift;
    my $name = $self->entity;
    $name = defined $name ? $name->name : 'root';
    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_group_add';
    $cont->{form_title} = 'add group';
    $cont->{id_entity} = $self->url_params->{id_entity};
    push @{ $cont->{buttons} }, { caption => "add group", url => "javascript:document.forms['form_group_add'].submit()" };
    push @{ $cont->{buttons} }, { caption => "cancel", url => url_get({what=> 0}, $self->url_params) };

    push @{ $cont->{rows} }, ['name', $cgi->textfield({ name => 'name', value => '', class => "textfield",})];
    push @{ $cont->{rows} }, ['image', build_img_chooser($cgi, 'form_group_add', 'function', '', $cont), 'optional'];
    push @{ $cont->{rows} }, ['parent', $self->entity_get_parents_list_group_add('group', $cont->{id_entity}) ];


    $content->addRow( form_create($cont) );
}

sub form_node_add
{
    my $self = shift;
    my $content = shift;
    my $name = $self->entity;
    $name = defined $name ? $name->name : 'root';
    my $cgi = $self->cgi;

    if ($name eq 'root')
    {
        $content->addRow('root can contain only group entities');
        return;
    }

    my $cont;
    $cont->{form_name} = 'form_node_add';
    $cont->{form_title} = 'add node';
    $cont->{id_entity} = $self->url_params->{id_entity};
    push @{ $cont->{buttons} }, { caption => "add node", url => "javascript:document.forms['form_node_add'].submit()" };
    push @{ $cont->{buttons} }, { caption => "cancel", url => url_get({what=> 0}, $self->url_params) };

    push @{ $cont->{rows} }, ['ip address', $cgi->textfield({ name => 'ip', value => '', class => "textfield",})];
    push @{ $cont->{rows} }, ['name', $cgi->textfield({ name => 'name', value => '', class => "textfield",})];
    push @{ $cont->{rows} }, ['parent', $self->entity_get_parents_list('node', $cont->{id_entity}) ];
    push @{ $cont->{rows} }, 
        ['SNMP version', 
        $cgi->textfield({ name => 'snmp_version', value => '', class => "textfield",}), '1 | 2 | 3; default 2; if 3, authNoPriv require user and password fields, authPriv require user, password, encryption'];
    push @{ $cont->{rows} }, 
        ['SNMP port',
        $cgi->textfield({ name => 'snmp_port', value => '', class => "textfield",}), 'default 161'];
    push @{ $cont->{rows} }, 
        ['SNMP community RO string', 
        $cgi->textfield({ name => 'snmp_community_ro', value => CFG->{SNMPCommunityRODefault}, class => "textfield",}), 'version 1 & 2c'];

    push @{ $cont->{rows} }, 
        ['SNMP user', 
        $cgi->textfield({ name => 'snmp_user', value => CFG->{SNMPUserDefault}, class => "textfield",}), 'version 3'];
    push @{ $cont->{rows} }, 
        ['SNMP password', 
        $cgi->textfield({ name => 'snmp_authpassword', value => CFG->{SNMPPasswordDefault}, class => "textfield",}), 'version 3'];
    push @{ $cont->{rows} }, 
        ['SNMP protocol', 
        $cgi->textfield({ name => 'snmp_authprotocol', value => CFG->{SNMPProtocolDefault}, class => "textfield",}), '<nobr>version 3; md5 | sha; default md5</nobr>'];
    push @{ $cont->{rows} }, 
        ['SNMP encription', 
        $cgi->textfield({ name => 'snmp_privprotocol', value => CFG->{SNMPEncriptionDefault}, class => "textfield",}), '<nobr>version 3; des | 3desede | aescfb128 | aescfb192 | aescfb256</nobr>'];
    push @{ $cont->{rows} }, 
        ['SNMP encryption password', 
        $cgi->textfield({ name => 'snmp_privpassword', value => CFG->{SNMPEncriptionPasswordDefault}, class => "textfield",}), '<nobr>version 3; if not set, SNMP password is used</nobr>'];
    push @{ $cont->{rows} }, 
        ['don\'t discover', 
        $cgi->textfield({ name => 'dont_discover', value => '', class => "textfield",}), 'leave empty; value 1 means host will not be discovered'];

    push @{ $cont->{rows} }, 
        ['bulk parameters configure', 
        $cgi->textarea({-name =>'bulk', class => "textfield", value => '', rows => 6, columns => 40 }),
        'syntax:<br>parameter1=value1<br>parameter2=value2<br>etc...',
        ];

    push @{ $cont->{rows} }, 
        ['',
          $cgi->checkbox({name => "check_snmp", label => "check SNMP configuration before add", -checked=>'checked' })
        ];
    for (1,3) { push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 2 , $_ , 'm']; }

    $content->addRow( form_create($cont) );
}

sub form_probe_select
{ 
    my $self = shift;
    my $table = shift;
    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_probe_select';
    $cont->{form_title} = '';
    $cont->{no_border} = 1;

    my $us;

    my $probes = $self->probes;
    my $ProbesMap = CFG->{ProbesMap};

    for (keys %$probes)
    {   
        $us->{ $ProbesMap->{ $_ } } = $_
           if $probes->{$_}->manual; 
    }

    $us->{'0'} = '-- select (mandatory) --';

    push @{ $cont->{rows} },
    [   
        'probe type',
        $cgi->popup_menu(
            -name=>'id_probe_type',
            -values=>[ sort { uc $us->{$a} cmp uc $us->{$b} } keys %$us],
            -default=> $self->url_params->{id_probe_type} || 0,
            -onChange => "javascript:document.forms['form_probe_select'].submit()",
            -labels=> $us,
            -class => 'textfield'),
    ];

    $table->addRow( form_create($cont) );
}

sub form_service_add
{
    my $self = shift;
    my $table = shift;
    my $name = $self->entity;
    $name = defined $name ? $name->name : 'root';
    my $cgi = $self->cgi;
    my $url_params = $self->url_params;

    my $cont;

    $cont->{form_name} = 'form_service_add';
    $cont->{form_title} = '';
    $cont->{id_entity} = $self->url_params->{id_entity};
    push @{ $cont->{buttons} }, { caption => "add service", url => "javascript:document.forms['form_service_add'].submit()" };
    push @{ $cont->{buttons} }, { caption => "cancel", url => url_get({what=> 0}, $self->url_params) };

    push @{ $cont->{rows} }, [ 'parent', $name || 'parent id ' . $cont->{id_entity} ];

    push @{ $cont->{rows} }, [ 'name', $cgi->textfield({ name => 'name' , class => "textfield",}), ];

    my $probe_name = $ProbesMapRev->{$url_params->{id_probe_type}};
    my $mandatory = $self->probes->{$probe_name}->mandatory_fields;
    my $mf = {};
    if (defined $mandatory)
    {
        for (@$mandatory) 
        {
            $mf->{$_} = 1;
        }
    }

    my $params = parameter_get_list( $self->dbh );
    if (@$params)
    {
         for (sort @$params)
         {
             next
                 unless $_ =~ /^${probe_name}_/ || defined $mf->{$_};
             push @{ $cont->{rows} },
             [
                 $_,
                 $cgi->textfield({ name => $_ , class => "textfield",}),
             ];
         }
    }

    push @{ $cont->{rows} },
        ['bulk parameters configure',
        $cgi->textarea({-name =>'bulk', class => "textfield", value => '', rows => 6, columns => 40 }),
        'syntax:<br>parameter1=value1<br>parameter2=value2<br>etc...',
        ];

    $table->addRow( form_create($cont) );
}

sub utilities
{
    my $self = shift;

    return
        unless $self->entity;
  
    my $content = shift;

    $content->addRow( qq|<iframe frameborder=0 width=100% height=500 name="ifr_utils" src="/iframe.html"></iframe>| );
    $content->setWidth('100%');
}

sub entity_rights
{
    my $self = shift;

    return
        unless $self->entity;
  
    my $content = shift;

    $content->addRow( $self->entity_info );

    my $table = table_begin('rights', 9);

    $table->addRow ('group name', 'vi', 'vo', 'co', 'cm', 'ac', 'md', 'cr', 'de',);

    my $row = $table->getTableRows;
    $table->setCellAttr($row, 1, 'class="g4"');
    $table->setCellAttr($row, 2, 'class="g4"');
    $table->setCellAttr($row, 3, 'class="g4"');
    $table->setCellAttr($row, 4, 'class="g4"');
    $table->setCellAttr($row, 5, 'class="g4"');
    $table->setCellAttr($row, 6, 'class="g4"');
    $table->setCellAttr($row, 7, 'class="g4"');
    $table->setCellAttr($row, 8, 'class="g4"');
    $table->setCellAttr($row, 9, 'class="g4"');

    $self->entity_my_rights($table);

    $content->addRow ('<br>'.scalar $table.'<br>')
        if $table->getTableRows;
}

sub entity_my_rights
{
    my $self = shift;
    my $table = shift;
    my $session = $self->session;
    my $users = $self->users;
    my $rights_names = CFG->{Web}->{RightsNames};
    my $id_user = $session->param('_LOGGED');

    my $dbh = $self->dbh;
    my @groups = map $_->[0], 
        @{ $dbh->exec( sprintf(qq|SELECT id_group FROM users_2_groups WHERE id_user=%s|,$id_user) )->fetchall_arrayref};

    my $id_entity = $self->entity;
    $id_entity = defined $id_entity
        ? $id_entity->id_entity
        : 0;

    my $tree = $self->tree;
    my $path = $tree->get_node_path($id_entity);

    my @row;
    push @row, $users->{$id_user}->username, $id_user;

    my $req .= 'SELECT * FROM rights,groups WHERE rights.id_group=groups.id_group AND (';
    $req .= join(" OR ", map("groups.id_group=$_", @groups));
    $req .= ' ) AND (';
    $req .= join(" OR ", map("id_entity=$_", @$path));
    $req .= ' ) AND disabled=0';

    $req = $dbh->dbh->prepare($req);
    $req->execute() or die $dbh->dbh->errstr;

    my $r;
    my $h;

    while ($h = $req->fetchrow_hashref)
    {   
        $r->{ $h->{id_entity} }->{ $h->{id_group} } = $h;
    }   

    my $node = $tree->get_node($id_entity);

    $table->addRow(
        '<b>effective rights</b>',
        rng($node->get_right($id_user, _R_VIE)),
        rng($node->get_right($id_user, _R_VIO)),
        rng($node->get_right($id_user, _R_COM)),
        rng($node->get_right($id_user, _R_CMO)),
        rng($node->get_right($id_user, _R_ACK)),
        rng($node->get_right($id_user, _R_MDY)),
        rng($node->get_right($id_user, _R_CRE)),
        rng($node->get_right($id_user, _R_DEL)),
    );  
    $table->setRowAttr($table->getTableRows, qq|class="tr_0"|);
     
    if (defined $r->{ $node->id })
    {
        $self->rights_row($r->{ $node->id }, $table);
    }
    else
    {
        my $rel = $tree->relations;
        my $items  = $tree->items;
        while (defined $rel->{ $node->id })
        {
            $node = $items->{ $rel->{ $node->id } };
            if (defined $r->{ $node->id })
            {
                $self->rights_row($r->{ $node->id }, $table);
                last;
            }
        }
    }
}

sub comments_img
{
    my $self = shift;
    my $id_entity = shift;
    my $no_inherited = shift || 0;
    my $path = $self->comments_are_there($id_entity, $no_inherited);
    return ''
        unless $path;
    return sprintf(qq|<a href="javascript:nw('/comments/%s',600,800);"><img src="/img/comments_on.gif"></a>|,
        $no_inherited ? $id_entity : join(',',@$path) );
}

sub contacts_img
{
    my $self = shift;
    my $id_entity = shift;
    my $no_inherited = shift || 0;
    my $path = $self->contacts_are_there($id_entity, $no_inherited);
    return ''
        unless $path;
    return sprintf(qq|<a href="javascript:nw('/contacts/%s,%s', 300, 600);"><img alt="contacts information" src="/img/contacts.gif"></a>|,$id_entity, join(',',@$path) );
}

sub contacts_are_there
{
    my $self = shift;
    my $id_entity = shift;
    my $no_inherited = shift || 0;

    return 0
        unless $id_entity;

    my $tree = $self->tree;
    my $items = $tree->items;

    return 0
        if $no_inherited && ! scalar keys %{ $items->{ $id_entity }->cgroups };

    my $path = $tree->get_node_path($id_entity);

    my $result = [];

    for (@$path)
    {
        next
            if $_ eq '0';
        push @$result, $_
            if scalar keys %{ $items->{ $_ }->cgroups };
    }
    return @$result ? $result : 0;
}

sub comments_are_there
{
    my $self = shift;
    my $id_entity = shift;
    my $no_inherited = shift || 0;

    return 0
        unless $id_entity;

    my $tree = $self->tree;
    my $items = $tree->items;

    return 0
        if $no_inherited && ! $items->{ $id_entity }->comments;

    my $path = $tree->get_node_path($id_entity);

    my $result = [];

    for (@$path)
    {   
        next
            if $_ eq '0';
        push @$result, $_
            if $items->{ $_ }->comments;
    }
    return @$result ? $result : 0;
}

sub rights_row
{
    my $self = shift;

    my $rs = shift;
    return
        unless defined $rs;

    my $table = shift;

    my $color = 1;
    for my $r (keys %$rs)
    {
        $r = $rs->{$r};
        $table->addRow
        (
            $r->{name},
            rng($r->{vie}),
            rng($r->{vio}),
            rng($r->{com}),
            rng($r->{cmo}),
            rng($r->{ack}),
            rng($r->{mdy}),
            rng($r->{cre}),
            rng($r->{del})
        );
        $table->setRowAttr($table->getTableRows, sprintf(qq|class="tr_%d"|, $color)); 
        $color = ! $color;
    }
}

sub rng #right name get
{
    return $_[0] ? '<img src=/img/checkmark.gif>' : '<img src=/img/blank.gif>';
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;
