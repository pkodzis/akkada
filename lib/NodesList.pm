package NodesList;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;         
use Common;

use constant 
{
    FORM => 0,
    FIELD_NAME => 1,
    ON_CHANGE_FORM_NAME => 2,
    DEFAULT_ID => 3,
    TREE => 4,
    DBH => 5,
    CGI => 6,
    TITLE => 7,
    GROUPS => 8,
    ENTITIES_2_GROUPS => 9,
    WITH_CONTACTS_GROUPS => 10,
    WITH_ACTIONS_BINDS => 11,
    ENTITIES_2_ACTIONS => 12,
};

sub new
{       
    my $class = shift;

    my $self;

    my $params = shift;
    $self->[FORM] = $params->{form};
    $self->[FIELD_NAME] = $params->{field_name} || 'id_parent';
    $self->[ON_CHANGE_FORM_NAME] = $params->{on_change_form_name} || undef;
    $self->[DEFAULT_ID] = $params->{default_id} || '';
    $self->[TREE] = $params->{tree};
    $self->[DBH] = $params->{dbh};
    $self->[CGI] = $params->{cgi};
    $self->[TITLE] = $params->{title} || 'select parent';
    $self->[WITH_CONTACTS_GROUPS] = $params->{with_contacts_groups} || 0;
    $self->[WITH_ACTIONS_BINDS] = $params->{with_actions_binds} || 0;

    bless $self, $class;

    if ($self->with_contacts_groups)
    {
        $self->groups_load;
        $self->entities_2_groups_load;
    } 
    elsif ($self->with_actions_binds)
    {
        $self->entities_2_actions_load;
    } 

    $self->make_nodes_list();
  
    return $self;
}

sub groups_load
{
    my $self = shift;
    $self->[GROUPS] = $self->dbh->dbh->selectall_hashref("SELECT * FROM cgroups", "id_cgroup");
}

sub entities_2_groups_load
{
    my $self = shift;
    my $req = $self->dbh->exec("SELECT * FROM entities_2_cgroups");
    while( my $h = $req->fetchrow_hashref )
    {
        $self->[ENTITIES_2_GROUPS]->{ $h->{id_entity} }->{ $h->{id_cgroup} } = 1;
    }
}

sub entities_2_actions_load
{
    my $self = shift;
    my $req = $self->dbh->exec("SELECT * FROM entities_2_actions");
    while( my $h = $req->fetchrow_hashref )
    {
        $self->[ENTITIES_2_ACTIONS]->{ $h->{id_entity} }->{ $h->{id_e2a} } = 1;
    }
}

sub with_actions_binds
{
    return $_[0]->[WITH_ACTIONS_BINDS];
}


sub with_contacts_groups
{
    return $_[0]->[WITH_CONTACTS_GROUPS];
}

sub groups
{
    return $_[0]->[GROUPS];
}

sub entities_2_groups
{
    return $_[0]->[ENTITIES_2_GROUPS];
}

sub entities_2_actions
{
    return $_[0]->[ENTITIES_2_ACTIONS];
}

sub title
{
    return $_[0]->[TITLE];
}

sub default_id
{
    return $_[0]->[DEFAULT_ID];
}

sub field_name
{
    return $_[0]->[FIELD_NAME];
}

sub form
{
    return $_[0]->[FORM];
}

sub on_change_form_name
{
    return $_[0]->[ON_CHANGE_FORM_NAME];
}

sub tree
{
    return $_[0]->[TREE];
}

sub dbh
{
    return $_[0]->[DBH];
}

sub cgi
{
    return $_[0]->[CGI];
}

sub bind_get_values
{
    my $self = shift;
    my $nodes = shift;
    my $tree = $self->tree;
    my $items = $tree->items;
    my $path;
    for my $id_node (keys %$nodes)
    {
        $path = $tree->get_node_path($id_node);
        $nodes->{$id_node}->{path} = $self->merge_node_names($path, $items);
        $nodes->{$id_node}->{fname} = join('::', @{$nodes->{$id_node}->{path} });
        $nodes->{$id_node}->{vname} = ('- ' x (@{$nodes->{$id_node}->{path} }-1)) . ' ' . $nodes->{$id_node}->{name};

        if ($self->with_contacts_groups)
        {
            my $entities_2_groups = $self->entities_2_groups;
            my $groups = $self->groups;
            if (defined $entities_2_groups->{ $id_node })
            {
                $nodes->{$id_node}->{vname} .= " => " 
                    . join(", ", sort { uc $a cmp uc $b } map { $groups->{$_}->{name} } 
                    keys %{ $entities_2_groups->{ $id_node } });
            }
        }
        elsif ($self->with_actions_binds)
        {
            my $entities_2_actions = $self->entities_2_actions;
            if (defined $entities_2_actions->{ $id_node })
            {
                $nodes->{$id_node}->{vname} .= ' (a) ';
            }
        }
    }
}

sub merge_node_names
{
    my $self = shift;
    my $path = shift;
    my $items = shift;

    $#$path = $#$path - 1;

    my @p;

    while(@$path)
    {
        push @p, $path->[$#$path];
        $#$path = $#$path - 1;
    }

    return [map { $items->{$_}->name } @p];
}

sub make_nodes_list
{
    my $self = shift;


    my $req = qq|SELECT id_entity,name FROM entities, links WHERE id_parent=id_entity|;
    my $nodes = $self->dbh->exec( $req )->fetchall_hashref('id_entity');

    $self->bind_get_values($nodes);
    $nodes->{ '' }->{fname} = '';
    $nodes->{ '' }->{vname} = '--- select ---';

    my $lab = {};
    for (keys %$nodes)
    {
        $lab->{ $_ } = $nodes->{$_}->{vname};
    }

    push @{ $self->form->{rows} },
    [   
        $self->title,
        $self->cgi->popup_menu(
            -name=> $self->field_name,
            -values=> [ sort { uc $nodes->{$a}->{fname} cmp uc $nodes->{$b}->{fname} } keys %$nodes],
            -labels => $lab,
            -onChange => defined $self->on_change_form_name
                ? sprintf(qq|javascript:document.forms['%s'].submit()|, $self->on_change_form_name)
                : '',
            -default=> $self->default_id,
            -class => 'textfield'),
    ];
}

1;
