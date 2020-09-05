package Permitions;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;         
use Configuration;
use Constants;
use Common;
use URLRewriter;
use Forms;

use constant 
{
    DB => 0,
    SESSION => 1,
    USERS => 2,
    GROUPS => 3,
    CGI => 5,
    URL_PARAMS => 6,
    TREE => 6,
};

sub new
{       
    my $class = shift;

    my $self;

    $self->[DB] = shift;
    $self->[SESSION] = shift;
    $self->[USERS] = shift;
    $self->[CGI] = shift;
    $self->[URL_PARAMS] = shift;
    $self->[TREE] = shift || undef;

    bless $self, $class;

    $self->groups_load;

    return $self;
}

sub session
{
    return $_[0]->[SESSION];
}

sub users
{
    return $_[0]->[USERS];
}

sub url_params
{
    return $_[0]->[URL_PARAMS];
}

sub tree
{
    return $_[0]->[TREE];
}

sub db
{
    return $_[0]->[DB];
}

sub cgi
{
    return $_[0]->[CGI];
}

sub groups
{
    return $_[0]->[GROUPS];
}

sub groups_load
{
    my $self = shift;
    $self->[GROUPS] = $self->db->dbh->selectall_hashref("SELECT * FROM groups", "id_group");
    @{ $self->[GROUPS] }{ keys %{ $self->[GROUPS] }} = map { $self->[GROUPS]->{$_}->{name} } keys %{ $self->[GROUPS] };
}

sub rights_table
{
    my $self = shift;
    my $url_params = $self->url_params;

    my $options = $self->session->param('_PERMITIONS');
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
        '<span class="z">&nbsp;add right:&nbsp;</span>',
        '&nbsp;&nbsp;','','&nbsp;&nbsp;',
        '<span class="z"><nobr>&nbsp;existing rights:&nbsp;</span>',
        ''
    );
    $table->setCellAttr($table->getTableRows, 2, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, 3, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, 4, qq|bgcolor=WINDOW|);

    #$table->setRowAttr($table->getTableRows, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, $table->getTableCols, qq|width="100%" bgcolor=WINDOW|);

    $table->addRow
    (
        $self->form_right_add(),

        "","","",

        $self->form_rights_existing_update(),

    );

    $table->setCellAttr($table->getTableRows, 1, qq|class='e1'|);
    $table->setCellAttr($table->getTableRows, 5, qq|class='e1'|);
    $table->setCellRowSpan(1,3,3);

    return "<br>" . scalar $table . "<br>";
}

sub form_right_add
{
    my $self = shift;
    my $cgi = $self->cgi;

    my $id_parent = '';

    my $options = $self->session->param('_PERMITIONS');
    if (defined $options && ref($options) eq 'HASH')
    {   
        $id_parent = defined $options->{id_parent}
            ? $options->{id_parent}
            : '';
    }

    my $dbh = $self->db;

    my $req = qq|SELECT id_entity,name FROM entities, links WHERE id_parent=id_entity|;
    my $nodes = $dbh->exec( $req )->fetchall_hashref('id_entity');
    die unless $nodes;

    @$nodes{ keys %$nodes} = map { $nodes->{$_}->{name} ? $nodes->{$_}->{name} : $_ } keys %$nodes;
    $nodes->{ '' } = '--- select ---';
    $nodes->{ 0 } = 'root';

    my $cont;
    $cont->{form_name} = 'form_right_add_node_select';
    $cont->{no_border} = 1;
    push @{ $cont->{rows} },
    [   
        'parent',
        $cgi->popup_menu(
            -name=>'id_parent',
            -values=>[ sort { uc $nodes->{$a} cmp uc $nodes->{$b} } keys %$nodes],
            -labels=> $nodes,
            -onChange => "javascript:document.forms['form_right_add_node_select'].submit()",
            -default=>$id_parent,
            -class => 'textfield'),
    ];

    my $result = form_create($cont) . '<br>';

    return $result
        if $id_parent eq '';

    $cont = {};
    $cont->{form_name} = 'form_right_add';
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "add right", url => "javascript:document.forms['form_right_add'].submit()" };

    $req = $id_parent
        ? sprintf(qq|SELECT id_entity,name FROM entities, links WHERE id_parent=%s AND id_entity=id_child|, $id_parent)
        : qq|SELECT id_entity,name FROM entities WHERE id_entity NOT IN (SELECT id_child FROM links)|;
    $nodes = $dbh->exec( $req )->fetchall_hashref('id_entity');
    die unless $nodes;

    @$nodes{ keys %$nodes} = map { $nodes->{$_}->{name} } keys %$nodes;
    $nodes->{ '' } = '--- select (optional) ---';
    push @{ $cont->{rows} },
    [   
        'child',
        $cgi->popup_menu(
            -name=>'id_child',
            -values=>[ sort { uc $nodes->{$a} cmp uc $nodes->{$b} } keys %$nodes],
            -labels=> $nodes,
            -default=>'',
            -class => 'textfield'),
    ];

    my %gr = %{ $self->groups };
    $gr{''} = '--- select (mandatory) ---';

    push @{ $cont->{rows} },
    [   
        'group',
        $cgi->popup_menu(
            -name=>'id_group',
            -values=>[ sort { uc $gr{$a} cmp uc $gr{$b} } keys %gr],
            -labels=> \%gr,
            -default=>'',
            -class => 'textfield'),
    ];

    push @{ $cont->{rows} },
    [   
        '&nbsp;rights&nbsp;',
        'vi',
        'vo',
        'co',
        'cm',
        'ac',
        'md',
        'cr',
        'de',
    ];

    push @{ $cont->{class} }, [4, 2, 'g4'];
    push @{ $cont->{class} }, [4, 3, 'g4'];
    push @{ $cont->{class} }, [4, 4, 'g4'];
    push @{ $cont->{class} }, [4, 5, 'g4'];
    push @{ $cont->{class} }, [4, 6, 'g4'];
    push @{ $cont->{class} }, [4, 7, 'g4'];
    push @{ $cont->{class} }, [4, 8, 'g4'];
    push @{ $cont->{class} }, [4, 9, 'g4'];

    push @{ $cont->{rows} },
    [   
        '',
        $cgi->checkbox({name => "vie", label => ""}),
        $cgi->checkbox({name => "vio", label => ""}),
        $cgi->checkbox({name => "com", label => ""}),
        $cgi->checkbox({name => "cmo", label => ""}),
        $cgi->checkbox({name => "ack", label => ""}),
        $cgi->checkbox({name => "mdy", label => ""}),
        $cgi->checkbox({name => "cre", label => ""}),
        $cgi->checkbox({name => "del", label => ""}),
    ];

    push @{ $cont->{cellColSpans} }, [1, 2, 8];
    push @{ $cont->{cellColSpans} }, [2, 2, 8];
    push @{ $cont->{cellRowSpans} }, [4, 1, 2];

    push @{ $cont->{rows} }, [ $cgi->hidden({ name => 'id_parent', value => $id_parent }), ];
    push @{ $cont->{cellColSpans} }, [5, 1, 9];

    $result .= form_create($cont);
    return $result;
}
    
sub form_rights_existing_update
{
    my $self = shift;
    my $cgi = $self->cgi;
    
    my $dbh = $self->db->dbh;

    my $req = qq|SELECT id_entity,groups.id_group,groups.name, vie,mdy,cre,del,com,vio,cmo,ack,disabled
        FROM rights,groups WHERE rights.id_group=groups.id_group|;
    $req = $dbh->prepare($req);
    $req->execute() or die $dbh->errstr;

    my $h;
    my $r;

    while ($h = $req->fetchrow_hashref)
    {      
        $r->{ $h->{id_entity} }->{rights}->{ $h->{id_group} } = $h;
    }      

    $req = join(" OR ", map { "id_entity=$_" } keys %$r);

    $req = qq|SELECT id_entity,id_probe_type,name FROM entities WHERE $req|;
    $req = $dbh->prepare($req);
    $req->execute() or die $dbh->errstr;

    while ($h = $req->fetchrow_hashref)
    {   
        $r->{ $h->{id_entity} }->{entity} = $h;
    }

    my $cont;
    $cont->{form_name} = 'form_rights_existing_update';
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "update selected", url => "javascript:document.forms['form_rights_existing_update'].submit()" };

    push @{ $cont->{title_row} },
    (
        'entity',
        '&nbsp;',
        'group',
        '&nbsp;',
        'vi',
        'vo',
        'co',
        'cm',
        'ac',
        'md',
        'cr',
        'de',
        '&nbsp;',
        'disabled',
        '&nbsp;',
        'delete',
        'update',
    );

    my $count = 0;
    my $idx;
    for my $entity (keys %$r)
    {
        $h = 0;
        $entity = $r->{$entity};
        for my $group ( keys %{ $entity->{rights} })
        {
            $group = $entity->{rights}->{$group};
            ++$h;
            ++$count;
            $idx = sprintf(qq|%s-%s|, $entity->{entity}->{id_entity} || 0, $group->{id_group});
            push @{ $cont->{rows} },
            [
                get_entity_fqdn($entity->{entity}->{id_entity}, $self->tree),
                #$entity->{entity}->{name} || 'root',
                '',
                $group->{name},
                '',
                $cgi->checkbox({name => $idx . "_vie", label => "", checked => $group->{vie} ? 'on' : ''}),
                $cgi->checkbox({name => $idx . "_vio", label => "", checked => $group->{vio} ? 'on' : ''}),
                $cgi->checkbox({name => $idx . "_com", label => "", checked => $group->{com} ? 'on' : ''}),
                $cgi->checkbox({name => $idx . "_cmo", label => "", checked => $group->{cmo} ? 'on' : ''}),
                $cgi->checkbox({name => $idx . "_ack", label => "", checked => $group->{ack} ? 'on' : ''}),
                $cgi->checkbox({name => $idx . "_mdy", label => "", checked => $group->{mdy} ? 'on' : ''}),
                $cgi->checkbox({name => $idx . "_cre", label => "", checked => $group->{cre} ? 'on' : ''}),
                $cgi->checkbox({name => $idx . "_del", label => "", checked => $group->{del} ? 'on' : ''}),
                '',
                $cgi->checkbox({name => $idx . "_disabled", label => "", checked => $group->{disabled} ? 'on' : ''}),
                '',
                $cgi->checkbox({name => $idx . "_delete", label => ""}),
                $cgi->checkbox({name => $idx . "_update", label => ""}),
            ];
        }
    }
    push @{ $cont->{cellRowSpans} }, [2, 2, $count+2];
    push @{ $cont->{cellRowSpans} }, [2, 4, $count+2];
    push @{ $cont->{cellRowSpans} }, [2, 13, $count+2];
    push @{ $cont->{cellRowSpans} }, [2, 15, $count+2];

    return form_create($cont);
}

sub users_and_groups_table
{
    my $self = shift;
    my $url_params = $self->url_params;

    my $options = $self->session->param('_PERMITIONS');
    if (defined $options && ref($options) eq 'HASH')
    {   
        $url_params->{$_} = $options->{$_}
            for (keys %$options);
    }

    $url_params->{id} = (keys %{ $self->users })[0]
        unless $url_params->{id} && defined $self->users->{ $url_params->{id} };

    my $table= HTML::Table->new(-width=> '100%');
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');

    $table->addRow
    (
        '<span class="z">&nbsp;existing user settings:&nbsp;</span>',
        '&nbsp;&nbsp;','','&nbsp;&nbsp;',
        '<span class="z">&nbsp;add user:&nbsp;</span>',
        '&nbsp;&nbsp;','','&nbsp;&nbsp;',
        '<span class="z">&nbsp;groups settings:&nbsp;</span>',
        ''
    );
    $table->setCellAttr($table->getTableRows, 2, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, 3, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, 4, qq|bgcolor=WINDOW|);

    $table->setCellAttr($table->getTableRows, 6, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, 7, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, 8, qq|bgcolor=WINDOW|);

    #$table->setRowAttr($table->getTableRows, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, $table->getTableCols, qq|width="100%" bgcolor=WINDOW|);

    $table->addRow
    (
        $self->form_users_select()
        . $self->form_user_update()
        . $self->form_user_groups_delete()
        . $self->form_user_groups_add(),

        "","","",

        $self->form_user_add(),

        "","","",

        $self->form_groups_update()
        . $self->form_groups_add() 
    );

    $table->setCellAttr($table->getTableRows, 1, qq|class='e1'|);
    $table->setCellAttr($table->getTableRows, 5, qq|class='e1'|);
    $table->setCellAttr($table->getTableRows, 9, qq|class='e1'|);
    $table->setCellRowSpan(1,3,3);
    $table->setCellRowSpan(1,7,3);

    return "<br>" . scalar $table . "<br>";
}

sub form_user_add
{
    my $self = shift;
    my $cgi = $self->cgi;
    my @users = sort { $b <=> $a } keys %{ $self->users };

    my $gr = $self->groups;

    my $cont;
    $cont->{form_name} = 'form_user_add';
    $cont->{id_entity} = $users[0] + 1;

    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "add user", url => "javascript:document.forms['form_user_add'].submit()" };

    push @{ $cont->{rows} },
    [
        'user name',
        $cgi->textfield({ name => 'username', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'password',
        $cgi->password_field({ name => 'password', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'password confirm',
        $cgi->password_field({ name => 'password_confirm', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'disabled',
        $cgi->checkbox({name => "locked", label => ""}),
    ];
    push @{ $cont->{rows} },
    [
        'group',
        $cgi->popup_menu(
            -name=>'id_group',
            -values=>[ sort { uc $gr->{$a} cmp uc $gr->{$b} } keys %$gr],
            -labels=> $gr,
            -class => 'textfield'),
    ];  

    return form_create($cont);
}

sub form_user_update
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $user = $self->users->{ $self->url_params->{id} };
    my $id = $self->url_params->{id};

    my $cont;
    $cont->{form_name} = 'form_user_update';
    $cont->{form_title} = 'general';
    $cont->{id_entity} = $id;
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "update user", url => "javascript:document.forms['form_user_update'].submit()" };
    push @{ $cont->{buttons} }, { caption => "delete user", url => "javascript:document.forms['form_user_delete'].submit()" };
    push @{ $cont->{rows} },
    [
        'user', 
        $cgi->b( $user->username ),
    ];
    push @{ $cont->{rows} },
    [
        'password', 
        $cgi->password_field({ name => 'password', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'password confirm', 
        $cgi->password_field({ name => 'password_confirm', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'disabled', 
        $cgi->checkbox({name => "locked", label => "", checked => $user->locked ? 'on' : ''}),
    ];

    my $cont1;
    $cont1->{form_name} = 'form_user_delete';
    $cont1->{id_entity} = $id;
    $cont1->{no_border} = 1;

    return form_create($cont) . form_create($cont1);
}

sub form_passwd
{
    my $self = shift;
    my $cgi = $self->cgi;

    my $id_user = $self->session->param('_LOGGED');
    my $user_name = $self->session->param('_LOGGED_USERNAME');

    die 
        unless $id_user;

    my $cont;
    $cont->{form_name} = 'form_passwd';
    $cont->{id_entity} = $id_user;
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "change password", url => "javascript:document.forms['form_passwd'].submit()" };
    push @{ $cont->{rows} },
    [   
        'user',
        $cgi->b( $user_name ),
    ];
    push @{ $cont->{rows} },
    [   
        'old password',
        $cgi->password_field({ name => 'password_old', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [   
        'new password',
        $cgi->password_field({ name => 'password_new', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'new password confirm',
        $cgi->password_field({ name => 'password_new_confirm', value => '', class => "textfield",}),
    ];

    return form_create($cont);
}

sub form_users_select 
{  
    my $self = shift;
    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_users_select';
    $cont->{form_title} = '';
    $cont->{no_border} = 1;
    #push @{ $cont->{buttons} }, { caption => "select", url => "javascript:document.forms['form_users_select'].submit()" };

    my $us;
    for (keys %{ $self->users })
    {
        $us->{$_} = $self->users->{$_}->username;
    }

    push @{ $cont->{rows} },
    [  
        'user',
        $cgi->popup_menu(
            -name=>'id',
            -values=>[ sort { uc $us->{$a} cmp uc $us->{$b} } keys %$us],
            -default=> $self->url_params->{id},
            -onChange => "javascript:document.forms['form_users_select'].submit()",
            -labels=> $us,
            -class => 'textfield'),
    ];

    return form_create($cont);
}

sub form_user_groups_delete
{
    my $self = shift;
    my $id = $self->url_params->{id};
    my $cgi = $self->cgi;

    my $groups = $self->groups;
    my $gr = $self->db->dbh->selectall_hashref(sprintf(qq|SELECT * FROM users_2_groups WHERE id_user=%s|, $id), "id_group");

    return
        unless keys %$gr;

    @{ $gr }{ keys %$gr } = map { $groups->{$_} } keys %$gr;

    my $cont;
    $cont->{form_name} = 'form_user_groups_delete';
    $cont->{form_title} = 'group membership';
    $cont->{id_entity} = $id;
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "delete from group", url => "javascript:document.forms['form_user_groups_delete'].submit()" };

    for (sort keys %$gr)
    {
        push @{ $cont->{rows} },
        [
            $gr->{$_},
            $cgi->checkbox({name => "delete_" . $_, label => ""}) . "&nbsp;<img src=/img/trash.gif>",
        ];
    }

    return form_create($cont);
}


sub form_user_groups_add
{  
    my $self = shift;
    my $cgi = $self->cgi;
    my $id = $self->url_params->{id};

    my $groups = $self->groups;
    my $gr = $self->db->dbh->selectall_hashref(sprintf(qq|
        SELECT * FROM groups WHERE id_group NOT IN 
        (SELECT id_group FROM users_2_groups WHERE id_user=%s);|, $id), "id_group");

    return
        unless keys %$gr;

    @{ $gr }{ keys %$gr } = map { $groups->{$_} } keys %$gr;

    my $cont;
    $cont->{form_name} = 'form_user_groups_add';
    $cont->{form_title} = '';
    $cont->{id_entity} = $id;
    $cont->{no_border} = 1;

    push @{ $cont->{buttons} }, { caption => "add to group", url => "javascript:document.forms['form_user_groups_add'].submit()" };

    $gr->{''} = '';

    push @{ $cont->{rows} },
    [   
        $cgi->popup_menu(
            -name=>'id_group',
            -values=>[ sort { uc $gr->{$a} cmp uc $gr->{$b} } keys %$gr],
            -labels=> $gr,
            -default=>'',
            -class => 'textfield'),
    ];

    return form_create($cont);
}

sub form_groups_update
{
    my $self = shift;
    my $gr = $self->groups;
    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_groups_update';
    $cont->{form_title} = '';
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "update groups", url => "javascript:document.forms['form_groups_update'].submit()" };

    for (sort keys %$gr)
    {
        if ($gr->{$_} eq 'master' || $gr->{$_} eq 'everyone' || $gr->{$_} eq 'operators')
        {
            push @{ $cont->{rows} },
            [
                $gr->{$_}, 'n/a',
            ];
        }
        else
        {
            push @{ $cont->{rows} },
            [
                $cgi->textfield({ name => $gr->{$_}, value => $gr->{$_}, class => "textfield",}),
                $cgi->checkbox({name => "delete_" . $gr->{$_}, label => ""}) . "&nbsp;<img src=/img/trash.gif>",
            ];
        }
    }

    return form_create($cont);
}


sub form_groups_add
{   
    my $self = shift;
    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_groups_add';
    $cont->{form_title} = '';
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "add group", url => "javascript:document.forms['form_groups_add'].submit()" };

    push @{ $cont->{rows} },
    [   
        $cgi->textfield({ name => "name", value => "", class => "textfield",}),
    ];

    return form_create($cont);
}


1;
