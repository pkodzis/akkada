package Contacts;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;         
use Configuration;
use Constants;
use Common;
use URLRewriter;
use Forms;
use NodesList;

use constant 
{
    DESKTOP => 0,
    CONTACTS => 2,
    GROUPS => 3,
    CONTACTS_2_GROUPS => 4,
    ENTITIES_2_GROUPS => 5,
};

sub new
{       
    my $class = shift;

    my $self;

    $self->[DESKTOP] = shift;

    bless $self, $class;

    $self->groups_load;
    $self->contacts_load;
    $self->contacts_2_groups_load;
    $self->entities_2_groups_load;

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

sub contacts
{
    return $_[0]->[CONTACTS];
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

sub contacts_2_groups
{
    return $_[0]->[CONTACTS_2_GROUPS];
}

sub entities_2_groups
{
    return $_[0]->[ENTITIES_2_GROUPS];
}

sub groups_load
{
    my $self = shift;
    $self->[GROUPS] = $self->db->dbh->selectall_hashref("SELECT * FROM cgroups", "id_cgroup");
}

sub contacts_load
{
    my $self = shift;
    $self->[CONTACTS] = $self->db->dbh->selectall_hashref("SELECT * FROM contacts", "id_contact");
}

sub contacts_2_groups_load
{
    my $self = shift;
    my $req = $self->db->exec("SELECT * FROM contacts_2_cgroups");
    while( my $h = $req->fetchrow_hashref )
    {   
        $self->[CONTACTS_2_GROUPS]->{ $h->{id_contact}}->{ $h->{id_cgroup} } = 1;
    }
}

sub entities_2_groups_load
{
    my $self = shift;
    my $req = $self->db->exec("SELECT * FROM entities_2_cgroups");
    while( my $h = $req->fetchrow_hashref )
    {   
        $self->[ENTITIES_2_GROUPS]->{ $h->{id_entity} }->{ $h->{id_cgroup} } = 1;
    }
}

sub bindings
{
    my $self = shift;
    my $url_params = $self->url_params;

    my $options = $self->session->param('_CONTACTS');
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

    $table->addRow
    (
        $self->form_bind_contacts(),
    );

    $table->setCellAttr($table->getTableRows, 1, qq|class='e1'|);

    return "<br>" . scalar $table . "<br>";
}

sub form_bind_contacts
{
    my $self = shift;
    my $cgi = $self->cgi;

    my $id_parent = '';
    my $id_child = '';

    my $options = $self->session->param('_CONTACTS');
    if (defined $options && ref($options) eq 'HASH')
    {   
        $id_parent = defined $options->{id_parent}
            ? $options->{id_parent}
            : '';
        $id_child = defined $options->{id_child}
            ? $options->{id_child}
            : '';
    }

    my $cont;
    $cont->{form_name} = 'form_bind_contacts_node_select';
    $cont->{no_border} = 1;
    my $nodeslist = NodesList->new({
        form => $cont,
        field_name => 'id_parent',
        on_change_form_name => 'form_bind_contacts_node_select',
        default_id => $id_parent,
        tree => $self->desktop->tree,
        dbh => $self->desktop->dbh,
        cgi => $self->desktop->cgi,
        with_contacts_groups => 1,
    });

    my $result = form_create($cont);

    return $result
        if $id_parent eq '';

    my $dbh = $self->db;

    my $req = $id_parent
        ? sprintf(qq|SELECT id_entity,name FROM entities, links WHERE id_parent=%s AND id_entity=id_child|, $id_parent)
        : qq|SELECT id_entity,name FROM entities WHERE id_entity NOT IN (SELECT id_child FROM links)|;
    my $nodes = $dbh->exec( $req )->fetchall_hashref('id_entity');
    die unless $nodes;

    $cont = {};

    $cont->{form_name} = 'form_bind_contacts_child_select';
    $cont->{no_border} = 1;
    @$nodes{ keys %$nodes} = map { $nodes->{$_}->{name} } keys %$nodes;

    my $entities_2_groups = $self->entities_2_groups;
    my $groups = $self->groups;
    for my $id_node (keys %$nodes)
    {
        if (defined $entities_2_groups->{ $id_node })
        {
            $nodes->{$id_node} .= " => "
                . join(", ", sort { uc $a cmp uc $b } map { $groups->{$_}->{name} }
                    keys %{ $entities_2_groups->{ $id_node } });
        }
    }

    $nodes->{ '' } = '--- select (optional) ---';
    push @{ $cont->{rows} },
    [
        'select child',
        $cgi->popup_menu(
            -name=>'id_child',
            -values=>[ sort { uc $nodes->{$a} cmp uc $nodes->{$b} } keys %$nodes],
            -labels=> $nodes,
            -onChange => "javascript:document.forms['form_bind_contacts_child_select'].submit()",
            -default=> $id_child,
            -class => 'textfield'),
    ];
    $result .= form_create($cont) . '<br>';
    
    $cont = {};
    $cont->{form_name} = 'form_unbind_contacts';
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_child" value="%s"  />|, $id_child) ];
    $cont->{no_border} = 1;
    $result .= form_create($cont);

    $cont = {};
    $cont->{form_name} = 'form_bind_contacts';
    #$cont->{form_title} = '<nobr>binded contact groups</nobr>';
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "update", url => "javascript:document.forms['form_bind_contacts'].submit()" };
    push @{ $cont->{buttons} }, { caption => "unbind", url => "javascript:document.forms['form_unbind_contacts'].submit()" };
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_child" value="%s"  />|, $id_child) ];
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_parent" value="%s"  />|, $id_parent) ];
    push @{ $cont->{rows} },
    [   
        sprintf("bind contact groups for entity <b>%s</b>", $self->desktop->tree->items->{$id_child}->name),
    ];
    push @{ $cont->{rows} },
    [   
        $self->select_binds,
    ];


    $result .= form_create($cont)
        if $id_child;

    return $result;
}

sub form_bind_contacts_pure
{
    my $self = shift;
    my $id_child = shift;
    my $cgi = $self->cgi;

    my $result;

    my $cont = {};
    $cont->{form_name} = 'form_unbind_contacts';
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_child" value="%s"  />|, $id_child) ];
    $cont->{no_border} = 1;
    $result .= form_create($cont);

    $cont = {};
    $cont->{form_name} = 'form_bind_contacts';
    $cont->{form_title} = '<nobr>contact groups</nobr>';
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "update", url => "javascript:document.forms['form_bind_contacts'].submit()" };
    push @{ $cont->{buttons} }, { caption => "unbind", url => "javascript:document.forms['form_unbind_contacts'].submit()" };
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_child" value="%s"  />|, $id_child) ];
    push @{ $cont->{rows} },
    [
        sprintf("bind contact groups for entity <b>%s</b>", $self->desktop->tree->items->{$id_child}->name),
    ];
    push @{ $cont->{rows} },
    [
        $self->select_binds($id_child),
    ];


    $result .= form_create($cont)
        if $id_child;

    return $result;

}

sub contacts_cgroups_table
{
    my $self = shift;
    my $url_params = $self->url_params;

    my $options = $self->session->param('_CONTACTS');

    if (defined $options && ref($options) eq 'HASH')
    {   
        $url_params->{$_} = $options->{$_}
            for (keys %$options);
    }

    if (! $url_params->{id_contact} || ! defined $self->contacts->{ $url_params->{id_contact} })
    {
        $options->{id_contact} = (sort keys %{ $self->contacts })[0];
        $url_params->{id_contact} = $options->{id_contact};
        $url_params->{form}->{id_contact} = $options->{id_contact};
    }
    elsif ($url_params->{id_contact} ne $url_params->{form}->{id_contact})
    {
        $url_params->{form}->{id_contact} = $url_params->{id_contact};
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
    $self->session->param('_CONTACTS', $options);
    $self->desktop->session_save;


    my $table= HTML::Table->new(-width=> '100%');
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');

    $table->addRow
    (
        '<span class="z">&nbsp;contacts:&nbsp;</span>',
        '&nbsp;&nbsp;','','&nbsp;&nbsp;',
        '<span class="z">&nbsp;groups:&nbsp;</span>',
        '&nbsp;&nbsp;','','&nbsp;&nbsp;',
        '<span class="z">&nbsp;bindings&nbsp;</span>',
    );

    $table->setCellAttr($table->getTableRows, 2, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, 3, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, 4, qq|bgcolor=WINDOW|);

    $table->setCellAttr($table->getTableRows, 6, qq|bgcolor=WINDOW|);
    $table->setCellAttr($table->getTableRows, 7, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, 8, qq|bgcolor=WINDOW|);

    #$table->setRowAttr($table->getTableRows, qq|class="tr_0"|);
    $table->setCellAttr($table->getTableRows, $table->getTableCols, qq|width="100%" bgcolor=WINDOW|);


    my $s_contacts;
    $s_contacts .= $self->form_contact_select() . $self->form_contact_update() . $self->form_contact_delete(),
        if $url_params->{id_contact};
    $s_contacts .= $self->form_contact_add;

    my $s_cgroups;
    $s_cgroups .= $self->form_cgroup_select() . $self->form_cgroup_update() . $self->form_cgroup_delete(),
        if $url_params->{id_cgroup};
    $s_cgroups .= $self->form_cgroup_add;

    $table->addRow
    (
        $s_contacts,
        '', '', '',
        $s_cgroups,
        '', '', '',
        $self->form_bind_contacts(),
    );

    $table->setCellAttr($table->getTableRows, 1, qq|class='e1'|);
    $table->setCellAttr($table->getTableRows, 5, qq|class='e1'|);
    $table->setCellAttr($table->getTableRows, 9, qq|class='e1'|);
    $table->setCellRowSpan(1,3,3);
    $table->setCellRowSpan(1,7,3);

    return "<br>" . scalar $table . "<br>";
}


sub form_contact_add
{
    my $self = shift;
    my $cgi = $self->cgi;

    my @contacts = sort { $b <=> $a } keys %{ $self->contacts};

    my $cont;
    $cont->{form_name} = 'form_contact_add';

    $cont->{no_border} = 1;
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_contact" value="%s"  />|, $contacts[0]+1) ]; # bez CGI!
    push @{ $cont->{buttons} }, { caption => "add contact", url => "javascript:document.forms['form_contact_add'].submit()" };

    push @{ $cont->{rows} },
    [
        'alias',
        $cgi->textfield({ name => 'alias', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'name',
        $cgi->textfield({ name => 'name', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'company',
        $cgi->textfield({ name => 'company', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'e-mail',
        $cgi->textfield({ name => 'email', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'phone',
        $cgi->textfield({ name => 'phone', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'active',
        $cgi->checkbox({name => "active", label => "", checked => 'on'}),
    ];
    push @{ $cont->{rows} },
    [
        'member of groups',
        $self->select_groups(1),
    ];

    return form_create($cont);
}

sub form_contact_update
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $id_contact = $self->url_params->{id_contact};

    my $contact = $self->contacts->{ $id_contact };

    my $cont;
    $cont->{form_name} = 'form_contact_update';
    $cont->{no_border} = 1;
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_contact" value="%s"  />|, $id_contact) ];
    push @{ $cont->{buttons} }, { caption => "update contact", url => "javascript:document.forms['form_contact_update'].submit()" };
    push @{ $cont->{buttons} }, { caption => "delete contact", url => "javascript:document.forms['form_contact_delete'].submit()" };
    push @{ $cont->{rows} },
    [
        'alias', 
        $cgi->textfield({ name => 'ualias', value => $contact->{alias}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'name', 
        $cgi->textfield({ name => 'uname', value => $contact->{name}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'company',
        $cgi->textfield({ name => 'ucompany', value => $contact->{company}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'e-mail',
        $cgi->textfield({ name => 'uemail', value => $contact->{email}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'phone',
        $cgi->textfield({ name => 'uphone', value => $contact->{phone}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'active', 
        $cgi->checkbox({name => "uactive", label => "", checked => $contact->{active} ? 'on' : ''}),
    ];
    push @{ $cont->{rows} },
    [
        'member of groups',
        $self->select_groups,
    ];

    return form_create($cont);
}


sub form_contact_delete
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $id_contact= $self->url_params->{id_contact};

    my $cont;
    $cont->{form_name} = 'form_contact_delete';

    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_contact" value="%s"  />|, $id_contact) ];
    $cont->{no_border} = 1;

    return form_create($cont);
}

sub form_contact_select 
{  
    my $self = shift;
    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_contact_select';
    $cont->{form_title} = '';
    $cont->{no_border} = 1;

    my $us;
    for (keys %{ $self->contacts})
    {
        $us->{$_} = $self->contacts->{$_}->{name};
    }

    my $id_contact = $self->url_params->{id_contact};
    my $contact = $self->contacts;

    my $s = qq|<select name="id_contact" tabindex="1" onchange="javascript:document.forms['form_contact_select'].submit()" class="textfield">|;
    for (sort { uc $us->{$a} cmp uc $us->{$b} } keys %$us)
    {
        $s .= sprintf(qq|<option %s value="%s">%s</option>|, ($_ == $id_contact ? 'selected="selected"' : ''), $_, $us->{$_});
    }
    $s .= '</select>';

    push @{ $cont->{rows} }, [  'contact', $s ]; #nie robic tego na CGI!

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

sub select_groups
{
    my $self = shift;
    my $noselect = shift || 0;
    my $groups = $self->groups;
    my $contacts_2_groups = $self->contacts_2_groups;
    my $id_contact = $self->url_params->{id_contact};

    my $s = qq|<select name="contacts_2_cgroups" tabindex="1" multiple size="8" class="textfield">\n|;
    for (sort { uc $groups->{$a}->{name} cmp uc $groups->{$b}->{name} } keys %$groups)
    {   
        $s .= sprintf(qq|<option %s value="%s">%s</option>\n|, 
            (defined $contacts_2_groups->{$id_contact}->{$_} && ! $noselect ? 'selected="selected"' : ''), $_, $groups->{$_}->{name});
    }
    $s .= '</select>';

    return $s;
}

sub select_contacts
{
    my $self = shift;
    my $noselect = shift || 0;
    my $contacts = $self->contacts;
    my $contacts_2_groups = $self->contacts_2_groups;
    my $id_cgroup = $self->url_params->{id_cgroup};

    my $s = qq|<select name="gcontacts_2_cgroups" tabindex="1" multiple size="8" class="textfield">\n|;
    for (sort { uc $contacts->{$a}->{name} cmp uc $contacts->{$b}->{name} } keys %$contacts)
    {   
        $s .= sprintf(qq|<option %s value="%s">%s</option>\n|, 
            (defined $contacts_2_groups->{$_}->{$id_cgroup} && ! $noselect ? 'selected="selected"' : ''), $_, $contacts->{$_}->{name});
    }
    $s .= '</select>';

    return $s;
}

sub form_cgroup_add
{   
    my $self = shift;
    my $cgi = $self->cgi;
    
    my @cgroups = sort { $b <=> $a } keys %{ $self->groups};
    
    my $cont;
    $cont->{form_name} = 'form_cgroup_add';
    
    $cont->{no_border} = 1;
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_cgroup" value="%s"  />|, $cgroups[0]+1) ]; # bez CGI!
    push @{ $cont->{buttons} }, { caption => "add group", url => "javascript:document.forms['form_cgroup_add'].submit()" };
        
    push @{ $cont->{rows} },
    [
        'name',
        $cgi->textfield({ name => 'gname', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'select members',
        $self->select_contacts(1),
    ];

    return form_create($cont);
}


sub form_cgroup_update
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $id_cgroup = $self->url_params->{id_cgroup};

    my $cgroup = $self->groups->{ $id_cgroup };

    my $cont;
    $cont->{form_name} = 'form_cgroup_update';
    $cont->{no_border} = 1;
    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_cgroup" value="%s"  />|, $id_cgroup) ];
    push @{ $cont->{buttons} }, { caption => "update group", url => "javascript:document.forms['form_cgroup_update'].submit()" };
    push @{ $cont->{buttons} }, { caption => "delete group", url => "javascript:document.forms['form_cgroup_delete'].submit()" };
    push @{ $cont->{rows} },
    [   
        'name',
        $cgi->textfield({ name => 'ugname', value => $cgroup->{name}, class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'select members',
        $self->select_contacts,
    ];

    return form_create($cont);
}

sub form_cgroup_delete
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $id_cgroup = $self->url_params->{id_cgroup};

    my $cont;
    $cont->{form_name} = 'form_cgroup_delete';

    push @{ $cont->{rows} }, [ sprintf(qq|<input type="hidden" name="id_cgroup" value="%s"  />|, $id_cgroup) ];
    $cont->{no_border} = 1;

    return form_create($cont);
}

sub form_cgroup_select 
{       
    my $self = shift;
    my $cgi = $self->cgi;
        
    my $cont;
    $cont->{form_name} = 'form_cgroup_select';
    $cont->{form_title} = '';
    $cont->{no_border} = 1;
    
    my $us;
    for (keys %{ $self->groups})
    {
        $us->{$_} = $self->groups->{$_}->{name};
    }
    
    my $id_cgroup = $self->url_params->{id_cgroup};
    my $cgroups = $self->groups;
        
    my $s = qq|<select name="id_cgroup" tabindex="1" onchange="javascript:document.forms['form_cgroup_select'].submit()" class="textfield">|;
    for (sort { uc $us->{$a} cmp uc $us->{$b} } keys %$us)
    {
        $s .= sprintf(qq|<option %s value="%s">%s</option>|, ($_ == $id_cgroup ? 'selected="selected"' : ''), $_, $us->{$_});
    }
    $s .= '</select>';
    
    push @{ $cont->{rows} }, [  'select group', $s ]; #nie robic tego na CGI!

    return form_create($cont);
}

1;
