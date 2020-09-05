package Actions;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;         
use Configuration;
use Constants;
use Common;
use URLRewriter;
use Forms;
use NodesList;
use Log;

use constant 
{
    DESKTOP => 0,
    COMMANDS => 2,
    GROUPS => 3,
    ACTIONS => 4,
    TIME_PERIODS => 5,
    ENTITIES_2_ACTIONS => 6,
};

sub new
{       
    my $class = shift;

    my $self;

    $self->[DESKTOP] = shift;

    bless $self, $class;

    $self->commands_load;
    $self->groups_load;
    $self->actions_load;
    $self->time_periods_load;
    $self->entities_2_actions_load;

    return $self;
}

sub desktop
{
    return $_[0]->[DESKTOP];
}

sub session
{
    return $_[0]->desktop->session;
}

sub actions
{
    return $_[0]->[ACTIONS];
}

sub time_periods
{
    return $_[0]->[TIME_PERIODS];
}

sub commands
{
    return $_[0]->[COMMANDS];
}

sub url_params
{
    return $_[0]->desktop->url_params;
}

sub db
{
    return $_[0]->desktop->dbh;
}

sub cgi
{
    return $_[0]->desktop->cgi;
}

sub groups
{
    return $_[0]->[GROUPS];
}

sub entities_2_actions
{
    return $_[0]->[ENTITIES_2_ACTIONS];
}

sub groups_load
{
    my $self = shift;
    $self->[GROUPS] = $self->db->dbh->selectall_hashref("SELECT * FROM cgroups", "id_cgroup");
}

sub time_periods_load
{
    my $self = shift;
    $self->[TIME_PERIODS] = $self->db->dbh->selectall_hashref("SELECT * FROM time_periods", "id_time_period");
}

sub actions_load
{
    my $self = shift;
    $self->[ACTIONS] = $self->db->dbh->selectall_hashref("SELECT * FROM actions", "id_action");
}

sub commands_load
{
    my $self = shift;
    $self->[COMMANDS] = $self->db->dbh->selectall_hashref("SELECT * FROM commands", "id_command");
}

sub entities_2_actions_load
{
    my $self = shift;
    my $req = $self->db->exec("SELECT * FROM entities_2_actions");
    while( my $h = $req->fetchrow_hashref )
    {   
        $self->[ENTITIES_2_ACTIONS]->{ $h->{id_entity} } = []
            unless ref($self->[ENTITIES_2_ACTIONS]->{ $h->{id_entity} });
        push @{$self->[ENTITIES_2_ACTIONS]->{ $h->{id_entity} }}, [ $h->{id_action}, $h->{id_cgroup}, $h->{id_time_period} ];
    }
}

sub bindings_table
{
    my $self = shift;
    my $url_params = $self->url_params;
    my $result;

    my $options = $self->session->param('_ACTIONS');
    if (defined $options && ref($options) eq 'HASH')
    {   
        $url_params->{$_} = $options->{$_}
            for (keys %$options);
    }

    my $table= HTML::Table->new(-width=> '100%');
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');

    $table->addRow
    (
        '<span class="z">&nbsp;select entity:&nbsp;</span>',
    );
    $table->setCellAttr($table->getTableRows, $table->getTableCols, qq|width="100%" bgcolor=WINDOW|);
    $table->setCellColSpan($table->getTableRows, 1, 5);

    $result = $self->form_actions_bind_select_entity();
    $table->addRow( $result->[0] );

    $table->setCellAttr($table->getTableRows, 1, qq|class='e1'|);

    return "<br>" . scalar $table . "<br>"
        if ! $result->[1];

    $table->addRow('<hr>');
    $table->setCellColSpan($table->getTableRows, 1, 5);
    $table->addRow(sprintf(qq|<span class="z">&nbsp;bindings for entity:&nbsp;</span>&nbsp%s|, $result->[1]));
    $table->setCellColSpan($table->getTableRows, 1, 5);
    $table->addRow('&nbsp;');

    $table->addRow
    (
        '<span class="z">&nbsp;new bind:&nbsp;</span>',
        '&nbsp;&nbsp;','','&nbsp;&nbsp;',
        '<span class="z">&nbsp;update bind:&nbsp;</span>',
    );

    $table->setCellAttr($table->getTableRows, 2, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, 3, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, 4, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, $table->getTableCols, qq|width="100%" bgcolor=WINDOW|);


    $table->addRow
    (
        $self->form_actions_bind_create,
        '', '', '',
        $self->form_actions_bind_update . $self->actions_bind_inherited,
    );

    $table->setCellAttr($table->getTableRows, 1, qq|class='e1'|);
    $table->setCellAttr($table->getTableRows, 5, qq|class='e1'|);
    $table->setCellRowSpan(6,3,3);

    return "<br>" . scalar $table . "<br>";

}

sub bindings_table_pure
{
    my $self = shift;
    my $url_params = $self->url_params;
    my $result;

    my $options = $self->session->param('_ACTIONS');
    if (defined $options && ref($options) eq 'HASH')
    {
        $url_params->{$_} = $options->{$_}
            for (keys %$options);
    }
    $options->{id_current} = shift;
    $self->session->param('_ACTIONS', $options);
    $self->desktop->session_save;

    my $table= HTML::Table->new(-width=> '100%');
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');

    $table->addRow
    (
        '<span class="z">&nbsp;new bind:&nbsp;</span>',
        '&nbsp;&nbsp;','','&nbsp;&nbsp;',
        '<span class="z">&nbsp;update bind:&nbsp;</span>',
    );

    $table->setCellAttr($table->getTableRows, 2, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, 3, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, 4, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, $table->getTableCols, qq|width="100%" bgcolor=WINDOW|);


    $table->addRow
    (
        $self->form_actions_bind_create,
        '', '', '',
        $self->form_actions_bind_update . $self->actions_bind_inherited,
    );

    $table->setCellAttr($table->getTableRows, 1, qq|class='e1'|);
    $table->setCellAttr($table->getTableRows, 5, qq|class='e1'|);
    $table->setCellRowSpan(1,3,3);

    return "<br>" . scalar $table . "<br>";

}

sub actions_bind_inherited
{
    my $self = shift;
    my $options = $self->session->param('_ACTIONS');

    return ""
        unless defined $options->{id_current};

    my $id_entity = $options->{id_current};

    my $e2a = $self->entities_2_actions;
    my $path = $self->desktop->tree->get_node_path($id_entity);
    my $id;

    my $groups = $self->get_hash($self->groups, 'name');    
    my $actions_table = $self->actions;
    my $actions = $self->get_hash($actions_table, 'name');    
    my $time_periods = $self->get_hash($self->time_periods, 'name');

    my $cont = {};

    $cont->{form_name} = 'actions_bind_inherited';
    $cont->{form_title} = 'inherited binds';
    $cont->{no_border} = 1;
    $cont->{title_row} = [ 'source', 'action', 'time&nbsp;period', 'contacts&nbsp;group'];
    $cont->{rows} = [];

    my $i = 3;
    my $j = 0;
    while ($j<2)
    {
        $j++;
        $id = shift @$path;
        next
            unless defined $e2a->{$id};
        next
            if $id == $id_entity;
        for (@{$e2a->{$id}})
        {
            next
                if $actions_table->{$_->[0]}->{inherit} == 0;
            ++$i;
            push @{$cont->{rows}}, 
            [
                get_entity_fqdn($id, $self->desktop->tree, 1),
                $actions->{$_->[0]},
                $time_periods->{$_->[2]},
                $groups->{$_->[1]},
            ];
            push @{$cont->{class}}, [$i, 1, 'ba'];
            push @{$cont->{class}}, [$i, 2, 'ba'];
            push @{$cont->{class}}, [$i, 3, 'ba'];
            push @{$cont->{class}}, [$i, 4, 'ba'];
        }
    }
    return @{$cont->{rows}} ? ('<p>' . form_create($cont)) : '';
}

sub form_actions_bind_update
{
    my $self = shift;
    my $cgi = $self->cgi;

    my $options = $self->session->param('_ACTIONS');

    return "no entity selected"
        unless defined $options->{id_current};

    my $id_entity = $options->{id_current};

    my $e2a = $self->entities_2_actions;

    return "no binds defined"
        unless defined $e2a->{$id_entity};

    $e2a = $e2a->{$id_entity};

    my $items = $self->desktop->tree->items;
    my $groups = $self->get_hash($self->groups, 'name');    
    my $actions = $self->get_hash($self->actions, 'name');    
    my $time_periods = $self->get_hash($self->time_periods, 'name');

    my $cont = {};

    $cont->{form_name} = 'form_actions_bind_update';
    $cont->{id_entity} = $id_entity;
    $cont->{no_border} = 1;
    $cont->{title_row} = [ '', 'action', 'time&nbsp;period', 'contacts&nbsp;group', '<img src=/img/trash.gif>'];

    my $i = 0;
    my $key;

    for (@$e2a)
    {
        ++$i;
        $key = sprintf(qq|%s.%s.%s.%s|,$id_entity, $_->[0], $_->[1], $_->[2]);

        push @{ $cont->{rows} },
        [
        "$i.",
        $cgi->popup_menu(
            -name=>"id_action.$key",
            -values=>[ sort { uc $actions->{$a} cmp uc $actions->{$b} } keys %$actions],
            -labels=> $actions,
            -default=> $_->[0],
            -class => 'textfield'),
        $cgi->popup_menu(
            -name=>"id_time_period.$key",
            -values=>[ sort { uc $time_periods->{$a} cmp uc $time_periods->{$b} } keys %$time_periods],
            -labels=> $time_periods,
            -default=> $_->[2],
            -class => 'textfield'),
        $cgi->popup_menu(
            -name=>"id_cgroup.$key",
            -values=>[ sort { uc $groups->{$a} cmp uc $groups->{$b} } keys %$groups],
            -labels=> $groups,
            -default=> $_->[1],
            -class => 'textfield'),
        $cgi->checkbox({name => "delete.$key", label => ""}),
        ];  

    }
            
    push @{ $cont->{buttons} }, { caption => "update", url => "javascript:document.forms['form_actions_bind_update'].submit()" };

    return form_create($cont);
}

sub form_actions_bind_select_entity
{
    my $self = shift;
    my $cgi = $self->cgi;

    my $id_parent = '';
    my $id_child = '';

    my $options = $self->session->param('_ACTIONS');
    if (defined $options && ref($options) eq 'HASH')
    {   
        $id_parent = defined $options->{id_parent}
            ? $options->{id_parent}
            : '';
        $id_child = defined $options->{id_child}
            ? $options->{id_child}
            : '';
        $options->{id_current} = $id_child ? $id_child : $id_parent;
        $self->session->param('_ACTIONS', $options);
        $self->desktop->session_save;
    }

    my $cont;
    $cont->{form_name} = 'form_actions_bind_node_select';
    $cont->{no_border} = 1;
    my $nodeslist = NodesList->new({
        form => $cont,
        field_name => 'id_parent',
        on_change_form_name => 'form_actions_bind_node_select',
        default_id => $id_parent,
        tree => $self->desktop->tree,
        dbh => $self->desktop->dbh,
        cgi => $self->desktop->cgi,
        with_actions_binds => 1,
    });

    my $result = form_create($cont);

    return [$result, 0]
        if $id_parent eq '';

    my $dbh = $self->db;

    my $req = $id_parent
        ? sprintf(qq|SELECT id_entity,name FROM entities, links WHERE id_parent=%s AND id_entity=id_child|, $id_parent)
        : qq|SELECT id_entity,name FROM entities WHERE id_entity NOT IN (SELECT id_child FROM links)|;
    my $nodes = $dbh->exec( $req )->fetchall_hashref('id_entity');
    die unless $nodes;

    $cont = {};

    $cont->{form_name} = 'form_actions_bind_child_select';
    $cont->{no_border} = 1;

    my $entities_2_actions = $self->entities_2_actions;
    @$nodes{ keys %$nodes} = map { $nodes->{$_}->{name} } keys %$nodes;
    for (keys %$nodes)
    {
        $nodes->{$_} .= ' (a) '
            if defined $entities_2_actions->{ $_ };
    }

    $nodes->{ '' } = '--- select (optional) ---';
    push @{ $cont->{rows} },
    [
        'select child',
        $cgi->popup_menu(
            -name=>'id_child',
            -values=>[ sort { uc $nodes->{$a} cmp uc $nodes->{$b} } keys %$nodes],
            -labels=> $nodes,
            -onChange => "javascript:document.forms['form_actions_bind_child_select'].submit()",
            -default=> $id_child,
            -class => 'textfield'),
    ];

    $result .= form_create($cont);

    return [$result, get_entity_fqdn($id_child && defined $nodes->{$id_child} ? $id_child : $id_parent, $self->desktop->tree, 1)];
        #: $self->desktop->tree->items->{$id_parent}->name 
}


sub form_actions_bind_create
{
    my $self = shift;
    my $cgi = $self->cgi;

    my $options = $self->session->param('_ACTIONS');

    return "no entity selected"
        unless defined $options->{id_current};

    my $id_entity = $options->{id_current};

    my $cont;
    $cont->{form_name} = 'form_actions_bind_create';

    $cont->{no_border} = 1;
    $cont->{id_entity} = $id_entity;

    push @{ $cont->{buttons} }, { caption => "add", url => "javascript:document.forms['form_actions_bind_create'].submit()" };

    my $data = $self->get_hash($self->actions, 'name');
    push @{ $cont->{rows} },
    [
        'action',
        $cgi->popup_menu(
            -name=>'id_action',
            -values=>[ sort { uc $data->{$a} cmp uc $data->{$b} } keys %$data],
            -labels=> $data,
            -class => 'textfield'),
    ];

    $data = $self->get_hash($self->time_periods, 'name');
    push @{ $cont->{rows} },
    [
        'time period',
        $cgi->popup_menu(
            -name=>'id_time_period',
            -values=>[ sort { uc $data->{$a} cmp uc $data->{$b} } keys %$data],
            -labels=> $data,
            -class => 'textfield'),
    ];

    $data = $self->get_hash($self->groups, 'name');
    push @{ $cont->{rows} },
    [
        'contacts group',
        $cgi->popup_menu(
            -name=>'id_cgroup',
            -values=>[ sort { uc $data->{$a} cmp uc $data->{$b} } keys %$data],
            -labels=> $data,
            -class => 'textfield'),
    ];


    return form_create($cont);
}


sub actions_table
{
    my $self = shift;
    my $url_params = $self->url_params;

    my $options = $self->session->param('_ACTIONS');

    if (defined $options && ref($options) eq 'HASH')
    {   
        $url_params->{$_} = $options->{$_}
            for (keys %$options);
    }

    if (! $url_params->{id_action} || ! defined $self->actions->{ $url_params->{id_action} })
    {
        $options->{id_action} = (sort keys %{ $self->actions })[0];
        $url_params->{id_action} = $options->{id_action};
        $url_params->{form}->{id_action} = $options->{id_action};
    }
    elsif ($url_params->{id_action} ne $url_params->{form}->{id_action})
    {
        $url_params->{form}->{id_action} = $url_params->{id_action};
    }
    if (! $url_params->{id_cgroup} || ! defined $self->groups->{ $url_params->{id_cgroup} })
    {   
        $options->{id_cgroup} = (sort keys %{ $self->groups })[0];
        $url_params->{id_cgroup} = $options->{id_cgroup};
        $url_params->{form}->{id_cgroup} = $options->{id_cgroup};
    }
    elsif ($url_params->{id_cgroup} ne $url_params->{form}->{id_cgroup})
    {   
        $url_params->{form}->{id_cgroup} = $url_params->{id_cgroup};
    }
    $self->session->param('_ACTIONS', $options);
    $self->desktop->session_save;


    my $table= HTML::Table->new(-width=> '100%');
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');

    $table->addRow
    (
        '<span class="z">&nbsp;new action:&nbsp;</span>',
        '&nbsp;&nbsp;','','&nbsp;&nbsp;',
        '<span class="z">&nbsp;update action&nbsp;</span>',
    );

    $table->setCellAttr($table->getTableRows, 2, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, 3, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, 4, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, $table->getTableCols, qq|width="100%" bgcolor=WINDOW|);


    my $s_actions = $url_params->{id_action} 
        ? ($self->form_action_select() . $self->form_action_update() . $self->form_action_delete())
        : 'no actions defined';

    $table->addRow
    (
        $self->form_action_add,
        '', '', '',
        $s_actions,
    );

#        $self->form_bind_actions(),

    $table->setCellAttr($table->getTableRows, 1, qq|class='e1'|);
    $table->setCellAttr($table->getTableRows, 5, qq|class='e1'|);
    $table->setCellRowSpan(1,3,3);

    return "<br>" . scalar $table . "<br>";
}

sub commands_table
{
    my $self = shift;
    my $url_params = $self->url_params;
        
    my $options = $self->session->param('_ACTIONS');
        
    if (defined $options && ref($options) eq 'HASH')
    {
        $url_params->{$_} = $options->{$_}
            for (keys %$options);
    }
    
    if (! $url_params->{id_command} || ! defined $self->commands->{ $url_params->{id_command} })
    {
        $options->{id_command} = (sort keys %{ $self->commands })[0];
        $url_params->{id_command} = $options->{id_command};
        $url_params->{form}->{id_command} = $options->{id_command};
    }
    elsif ($url_params->{id_command} ne $url_params->{form}->{id_command})
    {
        $url_params->{form}->{id_command} = $url_params->{id_command};
    }
    
    $self->session->param('_ACTIONS', $options);
    $self->desktop->session_save;


    my $table= HTML::Table->new(-width=> '100%');
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');

    $table->addRow
    (
        '<span class="z">&nbsp;new command:&nbsp;</span>',
        '&nbsp;&nbsp;','','&nbsp;&nbsp;',
        '<span class="z">&nbsp;update commands&nbsp;</span>',
    );

    $table->setCellAttr($table->getTableRows, 2, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, 3, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, 4, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, $table->getTableCols, qq|width="100%" bgcolor=WINDOW|);


    my $s_command = $url_params->{id_command}
        ? ($self->form_command_select() . $self->form_command_update() . $self->form_command_delete())
        : 'no commands defined';

    $table->addRow
    (
        $self->form_command_add,
        '', '', '',
        $s_command,
    );

    $table->setCellAttr($table->getTableRows, 1, qq|class='e1'|);
    $table->setCellAttr($table->getTableRows, 5, qq|class='e1'|);
    $table->setCellRowSpan(1,3,3);

    return "<br>" . scalar $table . "<br>";
}


sub time_periods_table
{
    my $self = shift;
    my $url_params = $self->url_params;
        
    my $options = $self->session->param('_ACTIONS');
        
    if (defined $options && ref($options) eq 'HASH')
    {
        $url_params->{$_} = $options->{$_}
            for (keys %$options);
    }       
    
    if (! $url_params->{id_time_period} || ! defined $self->time_periods->{ $url_params->{id_time_period} })
    {
        $options->{id_time_period} = (sort keys %{ $self->time_periods })[0];
        $url_params->{id_time_period} = $options->{id_time_period};
        $url_params->{form}->{id_time_period} = $options->{id_time_period};
    }   
    elsif ($url_params->{id_time_period} ne $url_params->{form}->{id_time_period})
    {
        $url_params->{form}->{id_time_period} = $url_params->{id_time_period};
    }   
    
    $self->session->param('_ACTIONS', $options);
    $self->desktop->session_save;
    

    my $table= HTML::Table->new(-width=> '100%');
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');
    
    $table->addRow
    (
        '<span class="z">&nbsp;new time period:&nbsp;</span>',
        '&nbsp;&nbsp;','','&nbsp;&nbsp;',
        '<span class="z">&nbsp;update time period&nbsp;</span>',
    );

    $table->setCellAttr($table->getTableRows, 2, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, 3, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, 4, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, $table->getTableCols, qq|width="100%" bgcolor=WINDOW|);


    my $s_time_period = $url_params->{id_time_period}
        ? ($self->form_time_period_select() . $self->form_time_period_update() . $self->form_time_period_delete())
        : 'no time periods defined';

    $table->addRow
    (
        $self->form_time_period_add,
        '', '', '',
        $s_time_period,
    );

    $table->setCellAttr($table->getTableRows, 1, qq|class='e1'|);
    $table->setCellAttr($table->getTableRows, 5, qq|class='e1'|);
    $table->setCellRowSpan(1,3,3);

    return "<br>" . scalar $table . "<br>";
}

sub form_time_period_add
{
    my $self = shift;
    my $cgi = $self->cgi;

    my @time_periods = sort { $b <=> $a } keys %{ $self->time_periods };

    my $cont;
    $cont->{form_name} = 'form_time_period_add';

    $cont->{no_border} = 1;
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_time_period" value="%s"  />|, $time_periods[0]+1) ]; # bez CGI!
    push @{ $cont->{buttons} }, { caption => "add time period", url => "javascript:document.forms['form_time_period_add'].submit()" };

    push @{ $cont->{rows} },
    [
        'name',
        $cgi->textfield({ name => 'name', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'monday',
        $cgi->textfield({ name => 'monday', value => '0-23', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'tuesday',
        $cgi->textfield({ name => 'tuesday', value => '0-23', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'wednesday',
        $cgi->textfield({ name => 'wednesday', value => '0-23', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'thursday',
        $cgi->textfield({ name => 'thursday', value => '0-23', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'friday',
        $cgi->textfield({ name => 'friday', value => '0-23', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'saturday',
        $cgi->textfield({ name => 'saturday', value => '0-23', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'sunday',
        $cgi->textfield({ name => 'sunday', value => '0-23', class => "textfield",}),
    ];

    return form_create($cont);
}

sub form_time_period_update
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $id_time_period = $self->url_params->{id_time_period};

    my $time_period = $self->time_periods->{ $id_time_period };

    my $cont;
    $cont->{form_name} = 'form_time_period_update';
    $cont->{no_border} = 1;
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_time_period" value="%s"  />|, $id_time_period) ];
    push @{ $cont->{buttons} }, { caption => "update time period", url => "javascript:document.forms['form_time_period_update'].submit()" };
    push @{ $cont->{buttons} }, { caption => "delete time period", url => "javascript:document.forms['form_time_period_delete'].submit()" };

    push @{ $cont->{rows} },
    [
        'name',
        $cgi->textfield({ name => 'uname', value => $time_period->{name}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'monday',
        $cgi->textfield({ name => 'umonday', value => $time_period->{monday}, class => "textfield",}),
    ];  
    push @{ $cont->{rows} },
    [
        'tuesday',
        $cgi->textfield({ name => 'utuesday', value => $time_period->{tuesday}, class => "textfield",}),
    ];  
    push @{ $cont->{rows} },
    [
        'wednesday',
        $cgi->textfield({ name => 'uwednesday', value => $time_period->{wednesday}, class => "textfield",}),
    ];  
    push @{ $cont->{rows} },
    [
        'thursday',
        $cgi->textfield({ name => 'uthursday', value => $time_period->{thursday}, class => "textfield",}),
    ];  
    push @{ $cont->{rows} },
    [
        'friday',
        $cgi->textfield({ name => 'ufriday', value => $time_period->{friday}, class => "textfield",}),
    ];  
    push @{ $cont->{rows} },
    [
        'saturday',
        $cgi->textfield({ name => 'usaturday', value => $time_period->{saturday}, class => "textfield",}),
    ];  
    push @{ $cont->{rows} },
    [
        'sunday',
        $cgi->textfield({ name => 'usunday', value => $time_period->{sunday}, class => "textfield",}),
    ];

    return form_create($cont);
}

sub form_time_period_delete
{   
    my $self = shift;
    my $cgi = $self->cgi; 
    my $id_time_period = $self->url_params->{id_time_period};
        
    my $cont;
    $cont->{form_name} = 'form_time_period_delete';
    
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_time_period" value="%s"  />|, $id_time_period) ];
    $cont->{no_border} = 1;
        
    return form_create($cont);
}
    
sub form_time_period_select 
{
    my $self = shift;
    my $cgi = $self->cgi;
    
    my $cont; 
    $cont->{form_name} = 'form_time_period_select';
    $cont->{form_title} = '';
    $cont->{no_border} = 1;

    my $us;
    for (keys %{ $self->time_periods})
    {
        $us->{$_} = $self->time_periods->{$_}->{name};
    }
    
    my $id_time_period = $self->url_params->{id_time_period};
    
    my $s = qq|<select name="id_time_period" tabindex="1" onchange="javascript:document.forms['form_time_period_select'].submit()" class="te
xt      
field">|;
    for (sort { uc $us->{$a} cmp uc $us->{$b} } keys %$us)
    {
        $s .= sprintf(qq|<option %s value="%s">%s</option>|, ($_ == $id_time_period ? 'selected="selected"' : ''), $_, $us->{$_});
    }
    $s .= '</select>';

    push @{ $cont->{rows} }, [  'time period', $s ]; #nie robic tego na CGI!

    return form_create($cont);
}

sub get_command_modules
{
    my $self = shift;
    my $name = shift;
    my $current = shift;
    my $cgi = $self->cgi;

    opendir(DIR, CFG->{LibDir} . "/ActionsExecutor")
        or log_debug("directory probems: $!", _LOG_ERROR);
    my @m = grep { /\.pm$/ } readdir(DIR);
    closedir DIR;

    if (@m)
    {
        $m[$_] =~  s/\.pm$//g
            for (0..$#m);
    }

    my %h;
    @h{@m} = @m;
    $h{''} = "--- select ---";

    return $cgi->popup_menu(-name=>$name, -values=>[ sort { uc $h{$a} cmp uc $h{$b} } keys %h], -labels=> \%h, -default => $current ? $current : '', -class => 'textfield'),

}

sub form_command_add
{
    my $self = shift;
    my $cgi = $self->cgi;

    my @commands = sort { $b <=> $a } keys %{ $self->commands };

    my $cont;
    $cont->{form_name} = 'form_command_add';

    $cont->{no_border} = 1;
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_command" value="%s"  />|, $commands[0]+1) ]; # bez CGI!
    push @{ $cont->{buttons} }, { caption => "add command", url => "javascript:document.forms['form_command_add'].submit()" };

    push @{ $cont->{rows} },
    [
        'name',
        $cgi->textfield({ name => 'name', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'module',
        $self->get_command_modules("module", ""),
    ];
    push @{ $cont->{rows} },
    [
        'command',
        $cgi->textfield({ name => 'command', value => '', class => "textfield",}),
    ];

    return form_create($cont);
}

sub form_command_update
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $id_command = $self->url_params->{id_command};

    my $command = $self->commands->{ $id_command };

    my $cont;
    $cont->{form_name} = 'form_command_update';
    $cont->{no_border} = 1;
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_command" value="%s"  />|, $id_command) ];
    push @{ $cont->{buttons} }, { caption => "update command", url => "javascript:document.forms['form_command_update'].submit()" };
    push @{ $cont->{buttons} }, { caption => "delete command", url => "javascript:document.forms['form_command_delete'].submit()" };

    push @{ $cont->{rows} },
    [
        'name',
        $cgi->textfield({ name => 'uname', value => $command->{name}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'module',
        $self->get_command_modules("umodule", $command->{module}),
    ];
    push @{ $cont->{rows} },
    [
        'command',
        $cgi->textfield({ name => 'ucommand', value => $command->{command} , class => "textfield",}),
    ];

    return form_create($cont);
}

sub form_command_delete
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $id_command = $self->url_params->{id_command};

    my $cont;
    $cont->{form_name} = 'form_command_delete';

    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_command" value="%s"  />|, $id_command) ];
    $cont->{no_border} = 1;

    return form_create($cont);
}

sub form_command_select 
{
    my $self = shift;
    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_command_select';
    $cont->{form_title} = '';
    $cont->{no_border} = 1;

    my $us;
    for (keys %{ $self->commands})
    {
        $us->{$_} = $self->commands->{$_}->{name};
    }

    my $id_command = $self->url_params->{id_command};

    my $s = qq|<select name="id_command" tabindex="1" onchange="javascript:document.forms['form_command_select'].submit()" class="text
field">|;
    for (sort { uc $us->{$a} cmp uc $us->{$b} } keys %$us)
    {
        $s .= sprintf(qq|<option %s value="%s">%s</option>|, ($_ == $id_command ? 'selected="selected"' : ''), $_, $us->{$_});
    }
    $s .= '</select>';

    push @{ $cont->{rows} }, [  'command', $s ]; #nie robic tego na CGI!

    return form_create($cont);
}

sub form_action_add
{
    my $self = shift;
    my $cgi = $self->cgi;

    my @actions = sort { $b <=> $a } keys %{ $self->actions };

    my $cont;
    $cont->{form_name} = 'form_action_add';

    $cont->{no_border} = 1;
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_action" value="%s"  />|, $actions[0]+1) ]; # bez CGI!
    push @{ $cont->{buttons} }, { caption => "add action", url => "javascript:document.forms['form_action_add'].submit()" };

    push @{ $cont->{rows} },
    [
        'name',
        $cgi->textfield({ name => 'name', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'notifications interval',
        $cgi->textfield({ name => 'notification_interval', value => '1800', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'notifications start after',
        $cgi->textfield({ name => 'notification_start', value => '120', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'notifications count',
        $cgi->textfield({ name => 'notification_stop', value => '4', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'notify recovery',
        $cgi->checkbox({name => "notify_recovery", label => "", checked => 'on'}),
    ];
    push @{ $cont->{rows} },
    [
        'service type',
        $cgi->textfield({ name => 'service_type', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'error messages like',
        $cgi->textfield({ name => 'error_messages_like', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'statuses',
        $cgi->textfield({ name => 'statuses', value => '1-6', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'ignore calculated status changes',
        $cgi->checkbox({name => "calc", label => "", checked => 'on'}),
    ];
    push @{ $cont->{rows} },
    [
        'inherit to children',
        $cgi->checkbox({name => "inherit", label => "", checked => 'on'}),
    ];

    my $commands = $self->get_hash($self->commands, 'name');

    push @{ $cont->{rows} },
    [
        'command',
        $cgi->popup_menu(
            -name=>'id_command',
            -values=>[ sort { uc $commands->{$a} cmp uc $commands->{$b} } keys %$commands],
            -labels=> $commands,
            -class => 'textfield'),
    ];

    push @{ $cont->{rows} },
    [
        'active',
        $cgi->checkbox({name => "active", label => "", checked => 'on'}),
    ];

    return form_create($cont);
}

sub get_hash
{
    my $self = shift;
    my $data = shift;
    my $field = shift;
    my $noselect = @_ ? shift : 0;
    my $result = {};

    for (keys %$data)
    {
        $result->{$_} = $data->{$_}->{$field};
    }

    $result->{0} = '--- select ---'
        unless $noselect;

    return $result;
}

sub form_action_update
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $id_action = $self->url_params->{id_action};

    my $action = $self->actions->{ $id_action };

    my $cont;
    $cont->{form_name} = 'form_action_update';
    $cont->{no_border} = 1;
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_action" value="%s"  />|, $id_action) ];
    push @{ $cont->{buttons} }, { caption => "update action", url => "javascript:document.forms['form_action_update'].submit()" };
    push @{ $cont->{buttons} }, { caption => "delete action", url => "javascript:document.forms['form_action_delete'].submit()" };

    push @{ $cont->{rows} },
    [
        'name', 
        $cgi->textfield({ name => 'uname', value => $action->{name}, class => "textfield",}),
    ];

    push @{ $cont->{rows} },
    [
        'notifications interval',
        $cgi->textfield({ name => 'unotification_interval', value => $action->{notification_interval} , class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'notifications start after',
        $cgi->textfield({ name => 'unotification_start', value => $action->{notification_start}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'notifications count',
        $cgi->textfield({ name => 'unotification_stop', value => $action->{notification_stop}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'notify recovery', 
        $cgi->checkbox({name => "unotify_recovery", label => "", checked => $action->{notify_recovery} ? 'on' : ''}),
    ];

    push @{ $cont->{rows} },
    [
        'service type',
        $cgi->textfield({ name => 'uservice_type', value => $action->{service_type}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'error messages like',
        $cgi->textfield({ name => 'uerror_messages_like', value => $action->{error_messages_like}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'statuses',
        $cgi->textfield({ name => 'ustatuses', value => $action->{statuses}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'ignore calculated status changes',
        $cgi->checkbox({name => "ucalc", label => "", checked => $action->{calc} ? 'on' : ''}),
    ];
    push @{ $cont->{rows} },
    [
        'inherit to children',
        $cgi->checkbox({name => "uinherit", label => "", checked => $action->{inherit} ? 'on' : ''}),
    ];

    my $commands = $self->get_hash($self->commands, 'name');

    push @{ $cont->{rows} },
    [
        'command',
        $cgi->popup_menu(
            -name=>'uid_command',
            -values=>[ sort { uc $commands->{$a} cmp uc $commands->{$b} } keys %$commands],
            -default => $action->{id_command},
            -labels=> $commands,
            -class => 'textfield'),
    ];

    push @{ $cont->{rows} },
    [
        'active', 
        $cgi->checkbox({name => "uactive", label => "", checked => $action->{active} ? 'on' : ''}),
    ];

    return form_create($cont);
}


sub form_action_delete
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $id_action = $self->url_params->{id_action};

    my $cont;
    $cont->{form_name} = 'form_action_delete';

    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_action" value="%s"  />|, $id_action) ];
    $cont->{no_border} = 1;

    return form_create($cont);
}

sub form_action_select 
{  
    my $self = shift;
    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_action_select';
    $cont->{form_title} = '';
    $cont->{no_border} = 1;
    my $actions = $self->actions;

    my $us;
    for (keys %{ $self->actions})
    {
        $us->{$_} = $actions->{$_}->{name};
    }

    my $id_action = $self->url_params->{id_action};
    my $action = $self->actions;

    my $s = qq|<select name="id_action" tabindex="1" onchange="javascript:document.forms['form_action_select'].submit()" class="textfield">|;
    for (sort { uc $us->{$a} cmp uc $us->{$b} } keys %$us)
    {
        $s .= sprintf(qq|<option %s value="%s">%s</option>|, ($_ == $id_action ? 'selected="selected"' : ''), $_, $us->{$_});
    }
    $s .= '</select>';

    push @{ $cont->{rows} }, [  'action', $s ]; #nie robic tego na CGI!

    return form_create($cont);
}


sub select_binds
{
    my $self = shift;
    my $id_entity = @_ ? shift : $self->url_params->{id_child};
    my $noselect = 0; #shift || 0;
    my $groups = $self->groups;
    my $entities_2_groups = $self->entities_2_groups;

    my $s = qq|<select name="entities_2_cgroups" tabindex="1" multiple size="8" class="textfield">\n|;
    for (sort { uc $groups->{$a}->{name} cmp uc $groups->{$b}->{name} } keys %$groups)
    {   
        $s .= sprintf(qq|<option %s value="%s">%s</option>\n|,
          (defined $entities_2_groups->{$id_entity}->{$_} && ! $noselect ? 'selected="selected"' : ''), $_, $groups->{$_}->{name});
    }
    $s .= '</select>';

    return $s;
}

1;
