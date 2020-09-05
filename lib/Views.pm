package Views;

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
    CGI => 2,
    URL_PARAMS => 3,
    ID_VIEW => 4,
    VIEWS => 5,
    VIEW_ENTITIES => 6,
    ENTITIES => 7,
    ID_VIEW_TYPE => 8,
    FIND => 9,
};

our %VIEW_TYPES = (
    0 => 'static',
    1 => 'find',
);

sub new
{       
    my $class = shift;

    my $self;

    $self->[DB] = shift;
    $self->[SESSION] = shift;
    $self->[CGI] = shift;
    $self->[URL_PARAMS] = shift;

    bless $self, $class;

    my $id_view = session_get_param($self->session,'_ID_VIEW');

    if ($id_view > 64020)
    {
        $id_view = $id_view - 64020;
    }

    $self->[ID_VIEW] = $id_view;
    $self->[VIEWS] = $self->db->exec( qq|SELECT * FROM views| )->fetchall_hashref('id_view');
    $self->[ID_VIEW_TYPE] = defined $id_view && $id_view ? $self->views->{$id_view}->{id_view_type} : undef;

    $self->[VIEW_ENTITIES] = [];
    $self->[ENTITIES] = {};
    if (defined $id_view && $id_view)
    {
        my $res = $self->db->exec( 
            sprintf(qq|SELECT entities.id_entity,entities.name,id_parent,view_order,monitor FROM entities,links,entities_2_views 
                WHERE entities.id_entity=entities_2_views.id_entity 
                AND entities.id_entity=links.id_child 
                AND id_view=%s ORDER BY view_order|, $id_view) 
            )->fetchall_arrayref;

        if (defined $res && ref($res) eq 'ARRAY' && @$res)
        {
            $self->[VIEW_ENTITIES] = [ map { $_->[0] } @$res ];
            for (@$res)
            {
                 $self->[ENTITIES]->{ $_->[0] }->{eid} = $_->[0];
                 $self->[ENTITIES]->{ $_->[0] }->{name} = $_->[1];
                 $self->[ENTITIES]->{ $_->[0] }->{pid} = $_->[2];
                 $self->[ENTITIES]->{ $_->[0] }->{view_order} = $_->[3];
                 $self->[ENTITIES]->{ $_->[0] }->{monitor} = $_->[4];
            }

            $res = $self->db->exec( 
                sprintf(qq|SELECT id_entity,name FROM entities,links
                    WHERE id_entity=%s|, join(' OR id_entity=', map { $_->[2] } @$res) )
                )->fetchall_hashref('id_entity');
            for (keys %{$self->[ENTITIES]})
            {
                $self->[ENTITIES]->{ $_ }->{pname} = $res->{ $self->[ENTITIES]->{ $_ }->{pid} }->{name};
            }
        }

    }

    return $self;
}

sub vt_find_init
{
    my $self = shift;
    my $find = shift;

    if (defined $self->id_view_type && $self->id_view_type && defined $self->id_view && $self->id_view)
    {
         my $options = {};
         my $data = $self->views->{$self->id_view}->{data};
         %$options = map { split /\=/, $_ && $_ } split /\&/, $data;
         $find->find_entities($options);
         $self->[VIEW_ENTITIES] = $find->view_entities;
    }
}

sub id_view
{
    return $_[0]->[ID_VIEW];
}

sub id_view_type
{
    return $_[0]->[ID_VIEW_TYPE];
}

sub entities
{
    return $_[0]->[ENTITIES];
}

sub view_entities
{
    return $_[0]->[VIEW_ENTITIES];
}

sub views
{
    return $_[0]->[VIEWS];
}

sub session
{
    return $_[0]->[SESSION];
}

sub url_params
{
    return $_[0]->[URL_PARAMS];
}

sub db
{
    return $_[0]->[DB];
}

sub cgi
{
    return $_[0]->[CGI];
}

sub get
{
    my $self = shift;
    my $url_params = $self->url_params;

    my $table= HTML::Table->new();
    #my $table= HTML::Table->new(-width=> '100%');
    #$table->setAlign("CENTER");
    $table->setAttr('class="w"');

    $self->existing_views($table);

    if ($self->id_view)
    {
        $table->addRow ( make_popup_form($self->form_view_manage, 'section_form_view_manage', 'settings') );

        #$table->addRow ( $self->form_view_manage() );
    }

    #$table->addRow ( $self->form_view_add() );
    $table->addRow ( make_popup_form($self->form_view_add, 'section_form_view_add', 'add') );

    return scalar $table 
        . qq|<form name="form_view_delete" method="POST"><input type=hidden name="form_name" value="form_view_delete"></form>|
        . "<br>";
}

sub existing_views
{
    my $self = shift;
    my $table = shift;

    my $views = $self->views();
    return 
        unless defined $views && keys %$views;

    $table->addRow ( $self->form_existing_views(0) );
}

sub form_view_manage
{
    my $self = shift;
    my $cgi = $self->cgi;
    my $entities = $self->entities();
    my $view_e = $self->view_entities();
    my $url_params = $self->url_params();
    my $id_view = $self->id_view;

    my $id_view_type = $self->id_view_type;

    my $cont;
    $cont->{form_name} = 'form_view_manage';
    $cont->{no_border} = 1;

if ($id_view_type == _VT_STATIC)
{
    my $i;
    for (@$view_e)
    {
        ++$i;
        push @{ $cont->{rows} },
        [
            sprintf("%s.", $i),
            $entities->{$_}->{pname},
            $entities->{$_}->{name},

            $i == 1 ? '' : $cgi->a
            (
        { -href => url_get({view_mode => _VM_VIEWS}, $url_params) . '?form_name=form_view_manage&action=up&id_entity=' . $_ . '&id_view=' . $id_view, },
                $cgi->img({ src=>'/img/r_up.gif', class => 'o', alt => "move up"})
            ),
            $i == @$view_e ? '' : $cgi->a
            (
        { -href => url_get({view_mode => _VM_VIEWS}, $url_params) . '?form_name=form_view_manage&action=down&id_entity=' . $_ . '&id_view=' . $id_view, },
                $cgi->img({ src=>'/img/r_down.gif', class => 'o', alt => "move down"})
            ),
            $cgi->a
            (
        { -href => url_get({view_mode => _VM_VIEWS}, $url_params) . '?form_name=form_view_manage&action=del&id_entity=' . $_ . '&id_view=' . $id_view, },
                $cgi->img({ src=>'/img/r_del.gif', class => 'o', alt => "delete"}),
            ),
        ];
        push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, 2, 'f'];
        push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, 3, 'f'];
        push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, 4, 'm'];
        push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, 5, 'm'];
        push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, 6, 'm'];
    }
}

    if ($id_view)
    {
        if ($id_view_type == _VT_FIND)
        {
            push @{ $cont->{rows} }, 
            [ 'definition', $cgi->textfield({ name => 'data', value => $self->views->{$id_view}->{data}, class => "textfield",}), ];
            for (4..6) { push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, $_, 'm']; }
        }

        push @{ $cont->{rows} }, [ '', $cgi->hidden({ name => 'update', value => $id_view}), '', '', '', ''];
        for (1..6) { push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, $_, 'm']; }

        push @{ $cont->{rows} }, 
            [ 'name', $cgi->textfield({ name => 'name', value => $self->views->{$id_view}->{name}, class => "textfield",}), ];
        for (4..6) { push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, $_, 'm']; }

        push @{ $cont->{rows} }, 
            ['image', build_img_chooser($cgi,'form_view_manage','function',$self->views->{$id_view}->{function},$cont),'optional'];
        for (4..6) { push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, $_, 'm']; }

        push @{ $cont->{rows} }, ['type', $VIEW_TYPES{$id_view_type}, '<nobr>read only</nobr>' ];
        for (4..6) { push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, $_, 'm']; }

        push @{ $cont->{buttons} }, { caption => "update view", url => "javascript:document.forms['form_view_manage'].submit()" };

    }

    return defined $cont->{rows}
        ? form_create($cont)
        : '';
}

sub form_existing_views
{
    my $self = shift;
    my $mode_add = @_ ? shift : 0;
    my %views = %{$self->views()};
    my $cgi = $self->cgi;

    if ($mode_add)
    {
        for (keys %views)
        {
            delete $views{$_}
                if $views{$_}->{id_view_type};
        }
    }

    @views{ keys %views} = map { $views{$_}->{name} } keys %views;
    $views{ '' } = '--- select ---';

    if ($mode_add)
    {
        my @tmp = map { $_->[0] } @{ $self->db->exec( 
            sprintf(qq|SELECT id_view FROM entities_2_views where id_entity=%s|, $mode_add)
            )->fetchall_arrayref };
        for (@tmp)
        {
            delete $views{ $_ };
        }
    }

    my $cont;
    $cont->{form_name} = 'form_view_select';
    $cont->{no_border} = 1;

    if (scalar keys %views > 1)
    {

    push @{ $cont->{rows} },
    [
        'view',
        $cgi->popup_menu(
            -name=>'id_view',
            -values=>[ sort { uc $views{$a} cmp uc $views{$b} } keys %views],
            -labels=> \%views,
            -onChange => ($mode_add ? '' : "javascript:document.forms['form_view_select'].submit()"),
            -default=> $self->id_view,
            -class => 'textfield') 
        . ($mode_add ? qq|<input type=hidden name="add" value="1">| : '')
    ];

    if ($mode_add)
    {
        $cont->{id_entity} = $mode_add;
        push @{ $cont->{buttons} }, 
            { caption => "add", url => "javascript:document.forms['form_view_select'].submit()" };
        push @{ $cont->{buttons} }, { caption => "cancel", url => url_get({what=> 0}, $self->url_params) };
    }

    }
    else
    {
         push @{ $cont->{rows} }, [ 'no views defined or entity exist in all defined views'];
    }

    return form_create($cont);
}

sub form_view_add
{
    my $self = shift;
    my $options = @_ ? shift : '';
    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_view_add';

    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "add new view", url => "javascript:document.forms['form_view_add'].submit()" };

    push @{ $cont->{rows} }, [ 'name', $cgi->textfield({ name => 'name', value => '', class => "textfield",}), ];

    if ($options)
    {
        push @{ $cont->{rows} }, ['image', build_img_chooser($cgi, 'form_view_add', 'function', '', $cont), 'optional'
            . $cgi->hidden({ name => 'data', value => $options})
            . $cgi->hidden({ name => 'id_view_type', value => _VT_FIND}) ];
    }
    else
    {
        push @{ $cont->{rows} }, ['image', build_img_chooser($cgi, 'form_view_add', 'function', '', $cont), 'optional'];
        push @{ $cont->{rows} }, [ 'definition', $cgi->textfield({ name => 'data', value => "", class => "textfield",}), 'optional' ];
        push @{ $cont->{rows} },
        [
            'type',
            $cgi->popup_menu(
                -name=>'id_view_type',
                -values=>[ sort { uc $VIEW_TYPES{$a} cmp uc $VIEW_TYPES{$b} } keys %VIEW_TYPES],
                -labels=> \%VIEW_TYPES,
                #-onChange => "javascript:document.forms['form_actions_bind_child_select'].submit()",
                -default => _VT_STATIC,
                -class => 'textfield'),
        ];
    }

    return form_create($cont);
}

1;
