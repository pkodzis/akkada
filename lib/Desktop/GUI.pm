package Desktop::GUI;
use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.34;

use base qw(Desktop);
use strict;

use Tree;
use Configuration;
use Entity;
use CGIEntity;
use URLRewriter;
use Log;
use Constants;
use MyException qw(:try);
use Comments;
use Permitions;
use Contacts;
use Actions;
use Common;
use System;
use Views;
use Tools;
use Find;
use CGIContacts;
use Dashboard;
use Top;

use Bit::Vector;

our $LogEnabled = CFG->{LogEnabled};

sub version
{
    return "0.75";
}

sub tree_init
{
#log_debug("start tree_init", _LOG_ERROR);
    my $self = shift;
    my $url_params = $self->url_params;
    my $id_user = $self->session->param('_LOGGED');
 
    if (! $id_user)
    {
        warn "internal akk\@da error: unknown user";
        exit;
    }

    my $root_only = 
        ! defined $url_params->{section}
        || $url_params->{section} eq 'general'
        || $url_params->{section} eq 'alarms'
        || $url_params->{section} eq 'history'
        || $url_params->{section} eq 'entity_options'
        || $url_params->{section} eq 'services_options'
        || $url_params->{section} eq 'stat'
        || $url_params->{section} eq 'rights'
        || $url_params->{section} eq 'contactsen'
        || $url_params->{section} eq 'actionsen'
        || $url_params->{section} eq 'utils'
        || $url_params->{section} eq 'tool'
        ? 0
        : 1;
    
    $self->{TREE} = Tree->new({url_params => $url_params, id_user => $id_user,
        view => $self->views->view_entities, db => $self->dbh, root_only => $root_only });

#log_debug("end tree_init", _LOG_ERROR);
    if (! keys %{ $self->tree->items })
    {
        print sprintf(qq|<html><head><meta http-equiv="Refresh" content="60 url="></head><body><h2>internal akk\@da error: entities cache unavailable. probably it is stopped.</h2><bgsound SRC="%s" loop=1></body></html>|, 
            CFG->{Web}->{SoundAlarmFile}->{6});
        exit;
    };
}

sub tree
{
    my $self = shift;

    $self->tree_init()
        unless defined $self->{TREE};
    return $self->{TREE};
}

sub view_mode
{
    my $self = shift;
    $self->view_mode_init()
        unless defined $self->{VIEW_MODE};
    return $self->{VIEW_MODE};
}

sub view_mode_init
{
    my $self = shift;
    $self->{VIEW_MODE} = session_get_param($self->session, '_VIEW_MODE');
    $self->{VIEW_MODE} = _VM_TREE
        unless defined $self->{VIEW_MODE};
}

sub views
{
    my $self = shift;
    $self->views_init()
        unless defined $self->{VIEWS};
    return $self->{VIEWS};
}

sub find
{
    my $self = shift;
    $self->find_init()
        unless defined $self->{FIND};
    return $self->{FIND};
}

sub tools
{
    my $self = shift;
    $self->tools_init()
        unless defined $self->{TOOLS};
    return $self->{TOOLS};
}

sub prepare_left
{
    my $self = shift;
    my $left = $self->left;
    my $url_params = $self->url_params;

    $left->buttons->button_refresh(0);
    $left->buttons->button_back(0);

    if ($url_params->{section} eq 'utils'
        || $url_params->{section} eq 'dashboard'
        || $url_params->{section} eq 'tool')
    {   
        return;
    }

    if ($url_params->{section} eq 'permissions'
        || $url_params->{section} eq 'contacts'
        || $url_params->{section} eq 'about'
        || $url_params->{section} eq 'actions'
        || $url_params->{section} eq 'passwd')
    {
        return;
    }
    elsif ($url_params->{section} eq 'tools')
    {
        $self->prepare_left_tools;
        return;
    }

    $left->buttons->add({ caption => "", url => "javascript:treeShowHide(false)", img => "/img/tree_close.gif", alt => 'hide tree',
        right_side => 0, });

    my $tree = $self->tree;
    my $view_mode = $self->view_mode;


    if (defined $VIEWS_ALLTREES{$view_mode})
    {
        $left->buttons->add({ caption => "", url => "javascript:d.openAll()", img => "/img/tree_expand_b.gif", alt => 'expand tree'});
        $left->buttons->add({ caption => "", url => "javascript:d.closeAll()", img => "/img/tree_colaps_b.gif", alt => 'collapse tree'});

        $left->buttons->add({ caption => CGI::cookie("AKKADA_HIDE_IP") eq 'true' ? 'show ip' : 'hide ip',
                              url => "javascript:d.ipShowHide()", });
  
        $left->buttons->add({ caption => CGI::cookie("AKKADA_HIDE_STATUS") eq 'true' ? 'show status' : 'hide status',
                              url => "javascript:d.statusShowHide()", });
  
        $left->buttons->add({ caption => CGI::cookie("AKKADA_TREE_SORT") eq 'true' ? 'sort by type' : 'sort by name',
                              url => "javascript:d.treeSort()", });
  
        $tree->selected_item($url_params->{id_entity});
        log_debug("building tree html", _LOG_INTERNAL)
            if $LogEnabled;
        $left->content( $tree->html($view_mode, $url_params->{hide_not_monitored}) );
        log_debug("tree html ready", _LOG_INTERNAL)
            if $LogEnabled;
    }
    elsif (defined $VIEWS_VIEWS{$view_mode})
    {
        $left->content( $self->views->get() . $tree->html($view_mode, $url_params->{hide_not_monitored}) );
    }
    elsif (defined $VIEWS_FIND{$view_mode})
    {
        $left->content( $self->find->form_entity_find($self->views) );
    }
    else
    {
        return;
    }


    $left->tab->add(
    {   
        caption => "tree",
        active => $view_mode,
        active_value => _VM_TREE,
        url => sprintf(qq|%s?%s&nvm=%d|, url_get({}, $url_params), 'form_name=form_view_mode_change', _VM_TREE),
    }); 

    $left->tab->add(
    {   
        caption => "views",
        active => $view_mode,
        active_value => _VM_VIEWS,
        url => sprintf(qq|%s?%s&nvm=%d|, url_get({}, $url_params), 'form_name=form_view_mode_change', _VM_VIEWS),
    });

    $left->tab->add(
    {   
        caption => "find",
        active => $view_mode,
        active_value => _VM_FIND,
        url => sprintf(qq|%s?%s&nvm=%d|, url_get({}, $url_params), 'form_name=form_view_mode_change', _VM_FIND),
    });

    $left->status_bar->name("status_tree");
    $left->status_bar->add($self->server_time);
}

sub server_time
{
    return sprintf("server\'s time: %s %s", scalar localtime, tz() );
}

sub prepare_left_tools
{
    my $self = shift;
    my $left = $self->left;
    my $url_params = $self->url_params;

    $left->buttons->button_refresh(0);
    $left->buttons->button_back(0);

    $left->buttons->add({ caption => "", url => "javascript:treeShowHide(false)", img => "/img/tree_close.gif", alt => 'hide tree',
        right_side => 0, });

    $left->status_bar->name("status_tree");
    $left->status_bar->add($self->server_time);

    $left->tab->add(
    {
        caption => "tools list",
        active => 1,
        active_value => 1,
        url => url_get({}, $url_params),
    });

    $left->content( $self->tools->get_left() );

}

=pod
sub prepare_right_system
{
    my ($self, $right, $url_params) = @_;

    my $node = $self->tree->root;

    return
        unless $self->matrix('system', $node);

    $url_params->{system_mode} = 1
        unless $url_params->{system_mode};

    $right->tab->add(
    {   
        caption => "status",
        active => $url_params->{system_mode},
        active_value => 1,
        url => url_get({system_mode => 1}, $url_params),
    })  
        if $self->matrix('system', $node);

    $right->tab->add(
    {   
        caption => "manage",
        active => $url_params->{system_mode},
        active_value => 2,
        url => url_get({system_mode => 2}, $url_params),
    })
        if $self->matrix('system_manage', $node);

    $right->tab->add(
    {   
        caption => "configuration",
        active => $url_params->{system_mode},
        active_value => 3,
        url => url_get({system_mode => 3}, $url_params),
    })
        if $self->matrix('system_configuration', $node) && 0;

    $right->buttons->add({ caption => '', img => '/img/refresh.gif', alt => 'reload page', url => url_get({}, $url_params ), });

    $right->buttons->button_refresh(0);

    my $sys = System->new($self->dbh, $self->session, $self->cgi, $url_params);

    if ($url_params->{system_mode} == 1)
    {
        $right->content( $sys->status() );
    }
    elsif ($url_params->{system_mode} == 2)
    {
        $right->content( $sys->manage() );
    }
    elsif ($url_params->{system_mode} == 3 && 0)
    {
        $right->content( $sys->configuration() );
    }
}
=cut

sub prepare_right_contacts
{
    my ($self, $right, $url_params) = @_;

    my $node = $self->tree->root;

    return
        unless $self->matrix('contacts', $node);

    $right->tab->add(
    {
        caption => "contacts",
        active => 1,
        active_value => 1,
        url => url_get({mode => 1}, $url_params),
    })
        if $self->matrix('contacts', $node);


    my $view_mode = $self->view_mode;

    my $but = $right->buttons;
    $but->button_ref(0);
    $but->button_back(0);


    if (defined $VIEWS_LIGHT{$view_mode})
    {
        $but->add({ caption => "", alt => 'full skin', img => '/img/dockicon.gif', right_side => 1,
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});
    }
    else
    {
        $but->add({ caption => "", alt => 'teeny skin', img => '/img/dockicon.gif', right_side => 1,
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});
    }

    my $contacts = Contacts->new($self);

    my $content = $contacts->contacts_cgroups_table();

    if (defined $VIEWS_LIGHT{$view_mode})
    {

        my $entity_cgi = CGIEntity->new(
            $self->users, $self->session, $self->dbh, undef, $self->cgi, $self->tree, $self->url_params, $self);

        $content .= $entity_cgi->probes->{'group'}->popup_menu_teeny({view_mode => $view_mode});

        $but->add({ caption => $self->get_caption(undef, $entity_cgi, 'with_section'),
            class => 'p2', url => "", captionnavi=> 1});

        $right->content(qq|<table width="100%" cellspacing="0" cellpadding="0" class="w"><tr><td>|
            . $but->get() . qq|</td></tr><tr><td>|
            . scalar $content . qq|<p>&nbsp;<p></td></tr><tr><td class="dz">|
            . $self->logo(1) . '&nbsp;&nbsp;'
            . $self->logged_as . ',&nbsp;&nbsp;'
            . $self->server_time . qq|<p>&nbsp;</td></tr></table>|);
    }
    else
    {
        $right->content( $content );
        $right->buttons($but);
    }

}

sub prepare_right_actions
{
    my ($self, $right, $url_params) = @_;

    my $node = $self->tree->root;

    return
        unless $self->matrix('actions', $node);

    $right->tab->add(
    {
        caption => "bindings",
        active => $url_params->{mode},
        active_value => 1,
        url => url_get({mode => 1}, $url_params),
    })
        if $self->matrix('actions', $node);

    $right->tab->add(
    {
        caption => "actions",
        active => $url_params->{mode},
        active_value => 2,
        url => url_get({mode => 2}, $url_params),
    })
        if $self->matrix('actions', $node);

    $right->tab->add(
    {
        caption => "commands",
        active => $url_params->{mode},
        active_value => 3,
        url => url_get({mode => 3}, $url_params),
    })
        if $self->matrix('actions', $node);

    $right->tab->add(
    {
        caption => "time periods",
        active => $url_params->{mode},
        active_value => 4,
        url => url_get({mode => 4}, $url_params),
    })
        if $self->matrix('actions', $node);


    my $view_mode = $self->view_mode;

    my $but = $right->buttons;
    $but->button_ref(0);
    $but->button_back(0);


    if (defined $VIEWS_LIGHT{$view_mode})
    {
        $but->add({ caption => "", alt => 'full skin', img => '/img/dockicon.gif', right_side => 1,
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});
    }
    else
    {
        $but->add({ caption => "", alt => 'teeny skin', img => '/img/dockicon.gif', right_side => 1,
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});
    }

    my $actions = Actions->new($self);

    my $content;

    if ($url_params->{mode} == 2)
    {
        $content = $actions->actions_table();
    }
    elsif ($url_params->{mode} == 3)
    {
        $content = $actions->commands_table();
    }
    elsif ($url_params->{mode} == 4)
    {
        $content = $actions->time_periods_table();
    }
    else
    {
        $content = $actions->bindings_table();
    }


    if (defined $VIEWS_LIGHT{$view_mode})
    {
        my $entity_cgi = CGIEntity->new(
            $self->users, $self->session, $self->dbh, undef, $self->cgi, $self->tree, $self->url_params, $self);

        $content .= $entity_cgi->probes->{'group'}->popup_menu_actions({view_mode => $view_mode});

        $but->add({ caption => $self->get_caption(undef, $entity_cgi, 'with_section'),
            class => 'p2', url => "", captionnavi=> 1});

        $right->content(qq|<table width="100%" cellspacing="0" cellpadding="0" class="w"><tr><td>|
            . $but->get() . qq|</td></tr><tr><td>|
            . scalar $content . qq|<p>&nbsp;<p></td></tr><tr><td class="dz">|
            . $self->logo(1) . '&nbsp;&nbsp;'
            . $self->logged_as . ',&nbsp;&nbsp;'
            . $self->server_time . qq|<p>&nbsp;</td></tr></table>|);
    }
    else
    {
        $right->content( $content );
        $right->buttons($but);
    }
}

sub prepare_right_permissions
{
    my ($self, $right, $url_params) = @_;

    my $node = $self->tree->root;
    
    return
        unless $self->matrix('permissions', $node);
    
    $url_params->{mode} = 1
        unless $url_params->{mode};

    $right->tab->add(
    {
        caption => "users & groups", 
        active => $url_params->{mode}, 
        active_value => 1,
        url => url_get({mode => 1}, $url_params), 
    })
        if $self->matrix('permissions', $node);

    $right->tab->add(
    {
        caption => "rights", 
        active => $url_params->{mode}, 
        active_value => 2,
        url => url_get({mode => 2}, $url_params), 
    })
        if $self->matrix('permissions', $node);

    my $view_mode = $self->view_mode;
    
    my $but = $right->buttons;
    $but->button_ref(0);
    $but->button_back(0);


    if (defined $VIEWS_LIGHT{$view_mode})
    {
        $but->add({ caption => "", alt => 'full skin', img => '/img/dockicon.gif', right_side => 1,
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});
    }
    else
    {
        $but->add({ caption => "", alt => 'teeny skin', img => '/img/dockicon.gif', right_side => 1,
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});
    }


    my $perm = Permitions->new($self->dbh, $self->session, $self->users, $self->cgi, $url_params, $self->tree);

    my $content;

    if ($url_params->{mode} == 1)
    {
        $content = $perm->users_and_groups_table();
    }
    elsif ($url_params->{mode} == 2)
    {
        $content = $perm->rights_table();
    }


    if (defined $VIEWS_LIGHT{$view_mode})
    {

        my $entity_cgi = CGIEntity->new(
            $self->users, $self->session, $self->dbh, undef, $self->cgi, $self->tree, $self->url_params, $self);

        $content .= $entity_cgi->probes->{'group'}->popup_menu_permissions({view_mode => $view_mode});

        $but->add({ caption => $self->get_caption(undef, $entity_cgi, 'with_section'),
            class => 'p2', url => "", captionnavi=> 1});

        $right->content(qq|<table width="100%" cellspacing="0" cellpadding="0" class="w"><tr><td>|
            . $but->get() . qq|</td></tr><tr><td>|
            . scalar $content . qq|<p>&nbsp;<p></td></tr><tr><td class="dz">|
            . $self->logo(1) . '&nbsp;&nbsp;'
            . $self->logged_as . ',&nbsp;&nbsp;'
            . $self->server_time . qq|<p>&nbsp;</td></tr></table>|);
    }
    else
    {
        $right->content( $content );
        $right->buttons($but);
    }
}

sub prepare_right_tools
{
    my ($self, $right, $url_params) = @_;

    $right->tab->add({ caption => "general", active => 1, active_value => 1, url => url_get({}, $url_params), });
    $right->buttons->button_refresh(0);
    $right->buttons->button_back(0);

    $right->caption($self->get_caption_tools());
   
    my $content = HTML::Table->new();
    $content->setAlign("LEFT");
    $content->setAttr('class="w"');
    $content->addRow( qq|<iframe frameborder=0 width=100% height=500 name="ifr_tool" src="/iframe.html"></iframe>| );
    $content->setWidth('100%');
    $right->content( scalar $content );
}

sub tool_get
{
    my $self = shift;
    my $url_params = $self->url_params;

    my $but = $self->right->buttons;
    $but->button_refresh(0);
    $but->button_back(0);

    my $tool_name = $url_params->{tool_name};

    if (! $tool_name)
    {
        $self->alter('missing tool name');
        return;
    }

    my $is_permited = $self->matrix(sprintf(qq|Tools::%s|, $tool_name), $self->tree->items->{$url_params->{id_entity}});

    if (! $is_permited)
    {
        $self->alter(sprintf(qq|tool <b>%s</b> access denied|, $tool_name));
        return;
    }

    my $result;
    eval qq|require Tools::$tool_name;|;
 
    if ($@)
    {
        $self->alter(sprintf(qq|tool <b>%s</b> error: %s|, $tool_name, $@));
        return;
    }

    if ((! defined $url_params->{start} || ! $url_params->{start}) && (! defined $url_params->{form} || ! keys %{$url_params->{form}}))
    {
        eval qq|\$result = Tools::${tool_name}::desc();
            \$result .= Tools::${tool_name}::button_start("$ENV{REQUEST_URI}");
            |;
        if ($@)
        {
            $self->alter(sprintf(qq|tool <b>%s</b> error: %s|, $tool_name, $@));
            return;
        }
        $self->alter($result);
        return;
    }
    
    eval qq|\$result = Tools::${tool_name}::run("$ENV{REQUEST_URI}");|;

    if (ref($result) ne 'ARRAY')
    {
        $self->alter(sprintf(qq|tool <b>%s</b> error: %s|, $tool_name, $@));
        return;
    }

    if ($result->[0])
    {
        $self->alter(sprintf(qq|tool <b>%s</b> error: %s|, $tool_name, $result->[1] ? $result->[1] : 'unknown error'));
    }
    else
    {
        $self->alter($result->[1] ? $result->[1] : 'unknown result');
    }
}

sub prepare_passwd
{
    my ($self, $right, $url_params) = @_;
   
    $right->tab->add({ caption => "change password", active => 1, active_value => 1, url => url_get({}, $url_params), });
    $right->buttons->add({ caption => '', alt => 'reload page', img => '/img/refresh.gif', url => url_get({}, $url_params ), });
    $right->buttons->button_refresh(0);

    my $perm = Permitions->new($self->dbh, $self->session, $self->users, $self->cgi, $url_params);

    $right->content( $perm->form_passwd() );
}


sub prepare_right_dashboard
{
    my ($self, $right, $url_params) = @_;

    my $node = $self->tree->root;

    my $view_mode = $self->view_mode;

    my $enabled = CFG->{System}->{Modules}->{sysstat};
    my $top10 = CFG->{System}->{Modules}->{top};

    $url_params->{settings} = 3
        if ! $enabled 
        && $url_params->{settings} != 3 
        && $url_params->{settings} != 4
        && $url_params->{settings} != 5;


    $right->tab->add(
    {
        caption => "general",
        active => $url_params->{settings},
        active_value => 0,
        url => url_get({settings => 0}, $url_params),
    })
        if $enabled;

    $right->tab->add(
    {
        caption => "histograms",
        active => $url_params->{settings},
        active_value => 2,
        url => url_get({settings => 2}, $url_params),
    })
        if $enabled;

    $right->tab->add(
    {
        caption => "top 10",
        active => $url_params->{settings},
        active_value => 5,
        url => url_get({settings => 5}, $url_params),
    })
        if $self->matrix('top', $node) && $top10;

    $right->tab->add(
    {
        caption => "system status",
        active => $url_params->{settings},
        active_value => 3,
        url => url_get({settings => 3}, $url_params),
    })
        if $self->matrix('system', $node);

    $right->tab->add(
    {
        caption => "manage system",
        active => $url_params->{settings},
        active_value => 4,
        url => url_get({settings => 4}, $url_params),
    })
        if $self->matrix('system_manage', $node);

    $right->tab->add(
    {
        caption => "settings",
        active => $url_params->{settings},
        active_value => 1,
        url => url_get({settings => 1}, $url_params),
    })
        if $enabled;

    my $but = $right->buttons;
    $but->button_ref(1);
    $but->button_back(0);

    if (defined $VIEWS_LIGHT{$view_mode})
    {
        $but->add({ caption => "", alt => 'full skin', img => '/img/dockicon.gif', right_side => 1,
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});
    }
    else
    {
        $but->add({ caption => "", alt => 'teeny skin', img => '/img/dockicon.gif', right_side => 1,
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});
    }

    $but->add({caption => 'restore defaults', alt => '', class => 'p2',  
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_dashboard_manage&id_form=0&col=1&action=rst'), })
        unless $url_params->{settings} == 2;


    my $dashboard = Dashboard->new($self);

    my $content;
    if (! $url_params->{settings})
    {
        $content = $dashboard->get();
    }
    elsif ($url_params->{settings} == 1)
    {
        $content = $dashboard->settings_get();
    }
    elsif ($url_params->{settings} == 2)
    {
        $content = $dashboard->histograms_get();
    }
    elsif ($url_params->{settings} == 3)
    {
        my $sys = System->new($self->dbh, $self->session, $self->cgi, $url_params);
        $content = $sys->status();
    }
    elsif ($url_params->{settings} == 4)
    {
        my $sys = System->new($self->dbh, $self->session, $self->cgi, $url_params);
        $content = $sys->manage();
    }
    elsif ($url_params->{settings} == 5)
    {
        my $entity_cgi = CGIEntity->new(
            $self->users, $self->session, $self->dbh, undef, $self->cgi, $self->tree, $self->url_params, $self);
        my $top = Top->new();
        $content = $top->get($url_params, $entity_cgi);

        $content .= $entity_cgi->probes->{$_}->popup_menu({view_mode => $view_mode})
            for ('node', 'cpu', 'hdd', 'nic', 'ram');
    }


    if (defined $VIEWS_LIGHT{$view_mode})
    {
        my $entity_cgi = CGIEntity->new(
            $self->users, $self->session, $self->dbh, undef, $self->cgi, $self->tree, $self->url_params, $self);

        $content .= $entity_cgi->probes->{'group'}->popup_menu_dashboard({view_mode => $view_mode});

        $but->add({ caption => $self->get_caption(undef, $entity_cgi, 'with_section'),
            class => 'p2', url => "", captionnavi=> 1});

        $right->content(qq|<table width="100%" cellspacing="0" cellpadding="0" class="w"><tr><td>|
            . $but->get() . qq|</td></tr><tr><td>|
            . scalar $content . qq|<p>&nbsp;<p></td></tr><tr><td class="dz">|
            . $self->logo(1) . '&nbsp;&nbsp;'
            . $self->logged_as . ',&nbsp;&nbsp;'
            . $self->server_time . qq|<p>&nbsp;</td></tr></table>|);
    }
    else
    {
        $right->content( scalar $content );
        $right->buttons($but);
    }

}


sub fix_section
{
    my ($self, $id_entity, $entity_cgi, $probe, $node, $probe_name, $entity) = @_;
    my $url_params = $self->url_params;
    my $cfg = CFG->{Web}->{SectionDefinitions};
  
    $url_params->{section} = 'general'
        unless defined $cfg->{$url_params->{section}}->[0];

    my $view_mode = $self->view_mode;

    if (defined $VIEWS_ALLVIEWS{$view_mode})
    {
        $url_params->{section} = 'general'
            unless $url_params->{section} eq 'general'
            || $url_params->{section} eq 'history'
            || $url_params->{section} eq 'alarms'
	    || $url_params->{section} eq 'stat'
	    || $url_params->{section} eq 'utils';
    } 
    elsif (defined $VIEWS_ALLFIND{$view_mode})
    {
        $url_params->{section} = 'general'
            unless $url_params->{section} eq 'general'
            || $url_params->{section} eq 'history'
	    || $url_params->{section} eq 'stat'
            || $url_params->{section} eq 'alarms'
	    || $url_params->{section} eq 'utils';
    }
    elsif (! $id_entity )
    {
        $url_params->{section} = 'general'
            unless $url_params->{section} eq 'general'
            || $url_params->{section} eq 'history'
            || $url_params->{section} eq 'alarms';
    }

    if ($url_params->{section} eq 'stat' && ! defined $VIEWS_ALLVIEWS{$view_mode} && ! defined $VIEWS_FIND{$view_mode})
    {   
        if (! $id_entity)
        {
            $url_params->{section} = 'general';
        }
        elsif ($id_entity && ! $probe->menu_stat($entity))
        {
            $url_params->{section} = 'general';
        }
    }
    elsif ($url_params->{section} eq 'services_options')
    {   
        if (! $id_entity || $probe_name ne 'node')
        {
            $url_params->{section} = 'general';
        } 
        elsif ($id_entity && ! $node->is_node )
        {
            $url_params->{section} = 'general';
        } 
    }
    elsif ($url_params->{section} eq 'utilities')
    {   
        $url_params->{section} = 'general'
            unless $probe_name eq 'node';
    }
    
    $url_params->{section} = 'general'
        unless $self->matrix($url_params->{section}, $node);

    if ($url_params->{section} eq 'general' && $url_params->{what} && $url_params->{what} ne '5' && $url_params->{what} ne '6')
    {
        if ($probe_name eq 'group')
        {
            $url_params->{what} = ''
                if $url_params->{what} ne '1'
                    && $url_params->{what} ne '2';
        }
        elsif ($probe_name eq 'node')
        {
            $url_params->{what} = ''
                if $url_params->{what} ne '3'
                    && $url_params->{what} ne '4';
        }
        else
        {
            $url_params->{what} = ''
                if $url_params->{what} ne '4';
        }
    }
}

sub view_menu
{
    my $self = shift;

    my $url_params = shift;
    my $section = CFG->{Web}->{SectionDefinitions}->{ $url_params->{section} }->[0];
    my $id_probe_type = shift;
    my $view_mode = shift;

    my $buttons = Window::Buttons->new();
    $buttons->vertical(1);
    $buttons->button_refresh(0);
    $buttons->button_back(0);

    if ($id_probe_type == 1 && ! defined $VIEWS_ALLVIEWS{$view_mode} && ! defined $VIEWS_ALLFIND{$view_mode})
    {
        $buttons->add({ caption => "list", 
            url => "javascript:open_location($section,'?form_name=form_general_view&vmn=0&id_entity=', 'current' , 'view_menu');", 
            img => 'view_list'});
        $buttons->add({ caption => "detailed", 
            url => "javascript:open_location($section,'?form_name=form_general_view&vmn=1&id_entity=', 'current', 'view_menu');", 
            img => 'view_detailed'});
        $buttons->add({ caption => "bouquet list", 
            url => "javascript:open_location($section,'?form_name=form_general_view&vmn=2&id_entity=', 'current', 'view_menu');", 
            img => 'view_bouquet_list'});
        $buttons->add({ caption => "bouquet detailed", 
            url => "javascript:open_location($section,'?form_name=form_general_view&vmn=3&id_entity=', 'current', 'view_menu');", 
            img => 'view_bouquet_detailed'});
    }
    else
    {
        $buttons->add({ caption => "list", 
            url => "javascript:open_location($section,'?form_name=form_general_view&vm=0&id_entity=', 'current' , 'view_menu');", 
            img => 'view_list'});
        $buttons->add({ caption => "detailed", 
            url => "javascript:open_location($section,'?form_name=form_general_view&vm=1&id_entity=', 'current', 'view_menu');", 
            img => 'view_detailed'});
    }

    my $result = qq|
        <style type="text/css">#flyout_view_menu{position:absolute;top:100px;left:353px;display:none;z-index:100}</style>
        <div id="flyout_view_menu"><table class="y" cellpadding=0 cellspacing=0><tr><td>|;
    $result .= qq|<table cellspacing="0" class="u"><tr><td>|;
    $result .= $buttons;
    $result .= qq|</td></tr></table>|;
    $result .= qq|</td></tr></table></div>|;
}

sub prepare_right_entity
{
    my ($self, $right, $url_params, $entity) = @_;
    my $id_entity = $url_params->{id_entity};
    my $tree = $self->tree;
    my $items = $tree->items;

    my $node = $items->{$id_entity};
    my $cfg = CFG->{Web}->{SectionDefinitions};
    my $entity_cgi = CGIEntity->new($self->users, $self->session, $self->dbh, $entity, $self->cgi, $tree, $url_params, $self);
    my $probe_name = CFG->{ProbesMapRev}->{ $items->{ $id_entity }->id_probe_type };
    my $probe = $entity_cgi->probes->{ $probe_name };
    
    my $view_mode = $self->view_mode;

    my @opts;

    $self->fix_section($id_entity, $entity_cgi, $probe, $node, $probe_name, $entity);

    if ($url_params->{section} eq 'utils'
        || $url_params->{section} eq 'tool')
    {
        $right->buttons->button_refresh(0);
        $right->buttons->button_back(0);
        $self->utils();
        return;
    }

    my $tab = $right->tab;
    my $but = $right->buttons;

    if (! defined $VIEWS_ALLVIEWS{$view_mode} && ! defined $VIEWS_ALLFIND{$view_mode})
    {
        $right->status_bar->name("rights");
        my $vec = Bit::Vector->new(8);
        $vec->from_Bin($items->{$id_entity}->rights($tree->id_user));
        $vec->Reverse($vec);
        $vec = $vec->to_Bin();
        $vec =~ s/1/\+/g;
        $vec =~ s/0/\-/g;
        $right->status_bar->add(sprintf("your rights to the current entity: %s", $vec));
    }
    $right->status_bar->add(sprintf("db entities count: %s (%s); cached entities count: %s",
        $tree->total_m, $tree->total, (scalar keys %{ $tree->items }) - 1));
    $right->status_bar->add({caption=>$self->copyrights, align=>'right'});

    $right->caption($self->get_caption($entity, $entity_cgi));


    if (! keys %$items && ! defined $VIEWS_ALLVIEWS{$view_mode} && ! defined $VIEWS_ALLFIND{$view_mode})
    {
        $right->content_info("no entities defined");
        #return;
    }

    $url_params->{hide_not_monitored} = session_get_param($self->session, '_HIDE_NOT_MONITORED');
    $url_params->{hide_not_monitored} = CFG->{Web}->{HideNotMonitored}
        if CFG->{Web}->{HideNotMonitored} && $url_params->{hide_not_monitored} eq '';

    $tab->add(
    { 
        caption => "general" . tip(9),
        class => 'v',
        active => $url_params->{section},
        active_value => 'general',
        url => url_get({id_entity => $id_entity, section => 'general' }, $url_params),
    })
        if defined $cfg->{general}->[0]
            && $self->matrix('general', $node);

    $tab->add(
    { 
        caption => "alarms" . tip(10),
        class => 'v',
        active => $url_params->{section}, 
        active_value => 'alarms',
        url => url_get({id_entity => $id_entity, section => 'alarms', }, $url_params), 
    })
        if defined $cfg->{alarms}->[0] 
            && $self->matrix('alarms', $node);

    $tab->add(
    { 
        caption => "stat" . tip(15),
        class => 'v',
        active => $url_params->{section},
        active_value => 'stat',
        url => url_get({id_entity => $id_entity, section => 'stat', }, $url_params),
    })
        if defined $cfg->{stat}->[0]
            && (($id_entity && $probe->menu_stat($entity) 
               || defined $VIEWS_ALLVIEWS{$view_mode} 
               || defined $VIEWS_ALLFIND{$view_mode}))
            && $self->matrix('stat', $node);

    $tab->add(
    {
        caption => "log" . tip(11),
        class => 'v',
        active => $url_params->{section},
        active_value => 'history',
        url => url_get({id_entity => $id_entity, section => 'history', }, $url_params), 
    })
        if defined $cfg->{history}->[0]
            && $self->matrix('history', $node);

    $tab->add(
    { 
        caption => "options" . tip(12),
        class => 'v',
        active => $url_params->{section},
        active_value => 'entity_options',
        url => url_get({id_entity => $id_entity, section => 'entity_options',}, $url_params), 
    })
        if defined $cfg->{entity_options}->[0]
            && $self->matrix('entity_options', $node)
            && $id_entity
            && defined $VIEWS_TREE_PURE{$view_mode};

    $tab->add(
    { 
        caption => "service options" . tip(13), 
        class => 'v', 
        active => $url_params->{section}, 
        active_value => 'services_options',
        url => url_get({id_entity => $id_entity, section => 'services_options',}, $url_params), 
    })
        if defined $cfg->{services_options}->[0]
            && $self->matrix('services_options', $node)
            && $probe_name eq 'node'
            && $node->is_node
            && $id_entity
            && defined $VIEWS_TREE_PURE{$view_mode};

    $tab->add(
    {
        caption => "utilities",
        class => 'v',
        active => $url_params->{section},
        active_value => 'utilities',
        url => url_get({id_entity => $id_entity, section => 'utilities',}, $url_params),
    })  
        if defined $cfg->{utilities}->[0]
            && $self->matrix('utilities', $node)
            && $probe_name eq 'node'
            && $id_entity
            && defined $VIEWS_TREE_PURE{$view_mode};

    $tab->add(
    {
        caption => "contacts",
        class => 'v',
        active => $url_params->{section},
        active_value => 'contactsen',
        url => url_get({id_entity => $id_entity, section => 'contactsen',}, $url_params),
    })
        if defined $cfg->{contactsen}->[0]
            && $self->matrix('contactsen', $node)
            && $id_entity
            && defined $VIEWS_TREE_PURE{$view_mode};

    $tab->add(
    {
        caption => "actions",
        class => 'v',
        active => $url_params->{section},
        active_value => 'actionsen',
        url => url_get({id_entity => $id_entity, section => 'actionsen',}, $url_params),
    })
        if defined $cfg->{actionsen}->[0]
            && $self->matrix('actionsen', $node)
            && $id_entity
            && defined $VIEWS_TREE_PURE{$view_mode};

    $tab->add(
    {
        caption => "rights" . tip(14),
        class => 'v',
        active => $url_params->{section},
        active_value => 'rights',
        url => url_get({id_entity => $id_entity, section => 'rights',}, $url_params), 
    })
        if $id_entity
            && defined $cfg->{rights}->[0]
            && $self->matrix('rights', $node)
            && defined $VIEWS_TREE_PURE{$view_mode};

    if (defined $entity && defined $VIEWS_TREE_PURE{$view_mode})
    {
        $but->add({ caption => "", alt => 'level up', img => '/img/level_up.gif', url => url_get( {id_entity => $entity->id_parent,}, $url_params )})
            if $url_params->{section} ne 'utilities';
    }

    $but->add({ caption => '', alt => 'reload page', img => '/img/refresh.gif', url => url_get({ id_entity => $id_entity}, $url_params ), })
        if $url_params->{section} ne 'utilities';

    $but->button_refresh(0);

    my $content = HTML::Table->new();

    $content->setAlign("LEFT");
    $content->setAttr('class="w"');

    if (defined $VIEWS_LIGHT{$view_mode})
    {
        $but->add({ caption => "", alt => 'full skin', img => '/img/dockicon.gif', right_side => 1,
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});
    }
    else
    {
        $but->add({ caption => "", alt => 'teeny skin', img => '/img/dockicon.gif', right_side => 1,
        url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});
    }


    if ( $url_params->{section} eq 'general'
       || $url_params->{section} eq 'entity_options'
       || $url_params->{section} eq 'contactsen'
       || $url_params->{section} eq 'actionsen'
       || $url_params->{section} eq 'history')
    {
            $url_params->{view} = session_get_param($self->session, '_GENERAL_VIEW');
            $url_params->{view} = CFG->{Web}->{DefaultTableView}
                if CFG->{Web}->{DefaultTableView} && $url_params->{view} eq '';
            $url_params->{view} = 0
                if $url_params->{view} > 1;

            $url_params->{view_node} = session_get_param($self->session, '_GENERAL_VIEW_NODE');
            $url_params->{view_node} = $url_params->{view}
                if $url_params->{view_node} eq '' || $url_params->{view_node} > 3;


            if ($node->is_node && $node->id_probe_type == 1 && ! defined $VIEWS_ALLVIEWS{$view_mode} && ! defined $VIEWS_ALLFIND{$view_mode})
            {
                if ($url_params->{view_node} == 0)
                {
                    $but->add( { caption => '', alt => '', img => '/img/view_list.gif',
                        class => 'p2', url => '#', on_mouse_over => qq|set_OBJ($id_entity, 'view_menu', 1)|, 
                        on_mouse_out =>qq|clear_OBJ()|, on_click =>qq|open_flyout()| });
                }
                elsif ($url_params->{view_node} == 1)
                {
                    $but->add({ caption => '' . tip(4), alt => '', img => '/img/view_detailed.gif',
                        class => 'p2', url => '#', on_mouse_over => qq|set_OBJ($id_entity, 'view_menu', 1)|, 
                        on_mouse_out =>qq|clear_OBJ()|, on_click =>qq|open_flyout()| });
                }
                elsif ($url_params->{view_node} == 2)
                {
                    $but->add({ caption => '' , alt => '', img => '/img/view_bouquet_list.gif',
                        class => 'p2', url => '#', on_mouse_over => qq|set_OBJ($id_entity, 'view_menu', 1)|, 
                        on_mouse_out =>qq|clear_OBJ()|, on_click =>qq|open_flyout()| });
                }
                elsif ($url_params->{view_node} == 3)
                {
                    $but->add({ caption => '' , alt => '', img => '/img/view_bouquet_detailed.gif',
                        class => 'p2', url => '#', on_mouse_over => qq|set_OBJ($id_entity, 'view_menu', 1)|, 
                        on_mouse_out =>qq|clear_OBJ()|, on_click =>qq|open_flyout()| });
                }
            }
            elsif ($node->is_node)
            {
                if ($url_params->{view} == 0)
                {
                    $but->add( { caption => '', alt => '', img => '/img/view_list.gif',
                        class => 'p2', url => '#', on_mouse_over => qq|set_OBJ($id_entity, 'view_menu', 1)|, 
                        on_mouse_out =>qq|clear_OBJ()|, on_click =>qq|open_flyout()| });
                }
                elsif ($url_params->{view} == 1)
                {
                    $but->add({ caption => '', alt => '', img => '/img/view_detailed.gif',
                        class => 'p2', url => '#', on_mouse_over => qq|set_OBJ($id_entity, 'view_menu', 1)|, 
                        on_mouse_out =>qq|clear_OBJ()|, on_click =>qq|open_flyout()| });
                }

            }

        #}

    }
    elsif ( $url_params->{section} eq 'alarms') 
    {
        $url_params->{hide_approved} = session_get_param($self->session, '_HIDE_APPROVED');
        $url_params->{hide_approved} 
            ? $but->add({ 
                caption => '' . tip(2), alt => 'show approved', img => '/img/approved_on.gif',
                class => 'p2',  url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_hide_approved'), })
            : $but->add({ 
                caption => '' . tip(1), alt => 'hide approved', img => '/img/approved_off.gif',
                class => 'p2', url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_hide_approved'), })
            if $self->matrix('form_hide_approved', $node);

        $url_params->{alarms_sound_off} = session_get_param($self->session, '_ALARMS_SOUND_OFF');
        $url_params->{alarms_sound_off} 
            ? $but->add({ 
                caption => '', alt => 'sound on', img => '/img/alarms_sound_on.gif',
                class => 'p2',  url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_alarms_sound_off'), })
            : $but->add({ 
                caption => '', alt => 'sound off', img => '/img/alarms_sound_off.gif',
                class => 'p2', url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_alarms_sound_off'), })
            if $self->matrix('form_alarms_sound_off', $node);

        $url_params->{correlation} = session_get_param($self->session, '_CORRELATION');
        $url_params->{correlation} 
            ? $but->add({ 
                caption => '' , alt => 'enable correlation', img => '/img/correlation_on.gif',
                class => 'p2',  url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_correlation&disable=0'), })
            : $but->add({ 
                caption => '', alt => 'disable correlation', img => '/img/correlation_off.gif',
                class => 'p2', url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_correlation&disable=1'), })
            if $self->matrix('form_correlation', $node);

=pod
        $but->add({ caption => 'p2', url => url_get({ id_entity => $id_entity, alarms_mode => 0, }, $url_params ), });
        $but->add({ caption => '1', url => url_get({ id_entity => $id_entity, alarms_mode => 1, }, $url_params ), });
        $but->add({ caption => '2', url => url_get({ id_entity => $id_entity, alarms_mode => 2, }, $url_params ), });
=cut
    }

    if (($url_params->{section} eq 'general' || $url_params->{section} eq 'stat') 
        && defined $VIEWS_TREE_PURE{$view_mode})
    {
        session_get_param($self->session, '_GENERAL_SHOW_PARAMETERS')
            ? $but->add( { caption => '', img => '/img/params_off.gif', alt => 'hide parameters',
                class => 'p2', url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_parameters_view'), })
            : $but->add({ caption => '', img => '/img/params_on.gif', alt => 'show parameters',
                class => 'p2', url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_parameters_view'), });
    }
    if ($url_params->{section} eq 'general' && defined $entity
        && defined $VIEWS_TREE_PURE{$view_mode})
    {
        $but->add({ caption => 'clear flap', 
            class => 'p2', url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_flaps_clear'), })
            if $entity->flap_monitor =~ /1/;
    }

    if (( ! defined $url_params->{section} || $url_params->{section} eq 'general' ) 
        && $self->matrix('general', $node)
        && defined $VIEWS_ALLVIEWS{$view_mode}
       )
    {
        $but->add( { caption => '', img => '/img/delete.gif', alt => 'delete view', class => 'p2', 
            url => sprintf(qq|javascript:make_sure('%s','%s?form_name=form_view_delete')|, 
                msgs(2), url_get({}, $url_params)),})
            if $self->matrix('form_view_delete', $node)
            && $self->views->id_view;
    }
    elsif (( ! defined $url_params->{section} || $url_params->{section} eq 'general' ) 
        && $self->matrix('general', $node)
        && (defined $VIEWS_TREE_PURE{$view_mode}
        || defined $VIEWS_TREEFIND{$view_mode}))
    {

        $content->addRow($self->views->form_existing_views($node->id))
            if $url_params->{what} eq '6' 
                && $node->id
                && $self->matrix('form_view_select', $node);

        $entity_cgi->form_entity_test($content)
            if $url_params->{what} eq '4'
                && $self->matrix('form_entity_test', $node);

        $entity_cgi->entity_general($content);
       
        $but->add(
        {   
            caption => '' . tip(21), img => '/img/add_group.gif', alt => 'add group',
            class => 'p2',
            url => url_get({ id_entity => $id_entity, 'what' => 1}, $url_params ),
        })  
            if $probe_name eq 'group'
                && $self->matrix('form_group_add', $node);

        $but->add(
        {   
            caption => '' . tip(24), img => '/img/force_test.gif', alt => 'force test',
            class => 'p2',
            #url => "javascript:document.forms['form_entity_test'].submit()",
            url => url_get({ id_entity => $id_entity, 'what' => 4}, $url_params ),
        })  
            if $probe_name ne 'group'
                && $self->matrix('form_entity_test', $node);

        $but->add(
        {   
            caption => '' . tip(22), img => '/img/add_node.gif', alt => 'add node',
            class => 'p2',
            url => url_get({ id_entity => $id_entity, 'what' => 2}, $url_params ),
        })  
            if $probe_name eq 'group' && $id_entity
                && $self->matrix('form_node_add', $node);

        $but->add(
        {   
            caption => '' . tip(25) , alt => 'add service', img => '/img/add_service.gif',
            class => 'p2',
            url => url_get({ id_entity => $id_entity, 'what' => 3}, $url_params ),
        })  
            if $probe_name eq 'node'
                && $self->matrix('form_service_add', $node);

        $but->add(
        {   
            caption => '' . tip(26), img => '/img/delete.gif', alt => 'delete',
            class => 'p2',
            #url => url_get({what => 5}, $url_params )
            url => sprintf(qq|javascript:make_sure('%s','%s?form_name=form_entity_delete&id_entity=%s')|,
                msgs(3), url_get({}, $url_params), $id_entity),
        })  
            if $id_entity
                && $self->matrix('form_entity_delete', $node);

        $entity_cgi->entity_add($content, $node)
            if $url_params->{what};
    }
    elsif ($url_params->{section} eq 'contactsen' 
        && $self->matrix('contactsen', $node)
        && defined $VIEWS_TREE_PURE{$view_mode})
    {
        my $cur_contacts = $entity_cgi->contacts_are_there($id_entity);
        $content->addRow( CGIContacts::get_contacts( $cur_contacts, 0 ) )
            if $cur_contacts;
        my $contacts = Contacts->new($self);
        my $t = table_begin('', 1, undef, '');
        $t->addRow($contacts->form_bind_contacts_pure($id_entity));
        $t->setAlign("LEFT");
        $content->addRow($t);

    }
    elsif ($url_params->{section} eq 'actionsen'
        && $self->matrix('actionsen', $node)
        && defined $VIEWS_TREE_PURE{$view_mode})
    {

        my $actions = Actions->new($self);
        my $t = table_begin('', 1, undef, '');
        $t->addRow($actions->bindings_table_pure($id_entity));
        $t->setAlign("LEFT");
        $content->addRow($t);

    }
    elsif ( $url_params->{section} eq 'alarms' && $self->matrix('alarms', $node))
    {
        if ($self->matrix('form_alarms_filter', $node))
        {
            my $cond = session_get_param($self->session, '_ALARMS_CONDITIONS');

            $but->add(
            {
                caption => 'WARNING: alarms you see are filtered', 
                alt => 'clear alarms filter', img => '/img/log_filter_clear.gif',
                class => 'p2',
                url => url_get({ id_entity => $id_entity, 'clear_alarms_filter' => 1, }, $url_params ),
            })
                if $cond;

            push @opts, make_popup_form($entity_cgi->form_alarms_filter(), 'section_form_alarms_filter', 'filter alarms')
                if $self->matrix('form_alarms_filter', $node);

        }

        my $s = $entity_cgi->alarms($view_mode);
        $s
            ? $content->addRow($s)
            : $right->content_info('alarms not found');
    }
    elsif ( $url_params->{section} eq 'history' && $self->matrix('history', $node))
    {
        if ($self->matrix('form_history_filter', $node))
        {
	    my $cond = session_get_param($self->session, '_HISTORY_CONDITIONS');

            $but->add(
            {
                caption => 'WARNING: log you see is filtered', 
                alt => 'clear history filter', img => '/img/log_filter_clear.gif',
                class => 'p2', 
                url => url_get({ id_entity => $id_entity, 'clear_history_filter' => 1, }, $url_params ), 
            })
                if $cond;

            push @opts, make_popup_form($entity_cgi->form_history_filter(), 'section_form_history_filter', 'filter history' )
                if $self->matrix('form_history_filter', $node);
        }
   
        if ($self->matrix('form_history_clear_log', $node))
        {
            $but->add(
            {
                caption => 'clear all log' , alt => 'clear all history log', 
                class => 'p2', 
                url => sprintf(qq|javascript:make_sure('%s','%s?form_name=form_history_clear_log&id_entity=%d')|, 
                    msgs(1), url_get({}, $url_params), $id_entity),
            });

            $but->add(
            {
                caption => 'keep last week' , alt => 'clear all history log older then a week', 
                class => 'p2', 
                url => sprintf(qq|javascript:make_sure('%s','%s?form_name=form_history_clear_log&id_entity=%d&days=7')|, 
                    msgs(4), url_get({}, $url_params), $id_entity),
            });

            $but->add(
            {
                caption => 'keep last month' , alt => 'clear all history log older then a 30 days', 
                class => 'p2', 
                url => sprintf(qq|javascript:make_sure('%s','%s?form_name=form_history_clear_log&id_entity=%d&days=30')|, 
                    msgs(5), url_get({}, $url_params), $id_entity),
            })
        }

        my $s = $entity_cgi->history();

        if ($s->[1])
        {
            $content->addRow($s->[0]);
        }
        else
        {
            $content->addRow($s->[0] . "<p>no log records found in selected time period</p>&nbsp;"); 
        }
    }
    elsif ( $url_params->{section} eq 'utilities' && $self->matrix('utilities', $node))
    {
        $entity_cgi->utilities($content);
    }
    elsif ( $url_params->{section} eq 'rights' && $self->matrix('rights', $node))
    {
        $entity_cgi->entity_rights($content);
    }
    elsif ( $url_params->{section} eq 'entity_options' && $self->matrix('entity_options', $node))
    {
        my $local_permission = $self->matrix('form_entity_discover', $node);

        $local_permission = 0
            unless $probe_name eq 'node';

        $but->add(
        {    
            caption => 'discover' . tip(23),
            class => 'p2',
            url => url_get({ id_entity => $id_entity, 'what_op' => 1}, $url_params ),
        })
            if $local_permission;

        if ($url_params->{what_op} eq '1' && $local_permission)
        {
            $entity_cgi->form_entity_discover($content);
        }
        else
        {
            $entity_cgi->entity_options($content,'short');
        }
    }
    elsif ( $url_params->{section} eq 'services_options' && $self->matrix('services_options', $node) && $probe_name eq 'node')
    {
        $entity_cgi->services_options($content);
    }
    elsif ( $url_params->{section} eq 'stat' && $self->matrix('stat', $node))
    {
        ! session_get_param($self->session, '_STAT_SHOW_COLLECTED_INFO')
            ? $but->add(
            {
                caption => '', alt => 'show collected information', img => '/img/general_on.gif',
                url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_stat_show_collected_info'), 
            })
            : $but->add(
            {
                caption => '', alt => 'hide collected information', img => '/img/general_off.gif',
                url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_stat_show_collected_info'), 
            })
            if $self->matrix('form_stat_show_collected_info', $node);

        if ($node->id_probe_type eq '1' && ! defined $VIEWS_FIND{$view_mode})
        {
            ! session_get_param($self->session, '_STAT_SHOW_NODE_INFO')
                ? $but->add(
                {
                    caption => '', alt => 'show node information', img => '/img/node_info_on.gif',
                    url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_stat_show_node_info'), 
                })
                : $but->add(
                {
                    caption => '', alt => 'hide node information', img => '/img/node_info_off.gif',
                    url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_stat_show_node_info'), 
                })
                if $self->matrix('form_stat_show_node_info', $node);
        }

        $but->add(
        {
            caption => 'reset options', 
            url => url_get({ id_entity => $id_entity, 'clear_graph_options' => 1, }, $url_params ), 
        })
            if $self->matrix('form_graph_options', $node)
                && session_get_param($self->session, '_GRAPH_OPTIONS');

        push @opts, make_popup_form($entity_cgi->form_graph_options(), 'section_form_graph_options', 'graph options' )
            if $self->matrix('form_graph_options', $node);


        if (defined $VIEWS_ALLVIEWS{$view_mode})
        {
            $entity_cgi->stat_view($content);
        }
        elsif (defined $VIEWS_ALLFIND{$view_mode})
        {
            $entity_cgi->stat_view($content);
        }
        else
        {
            $entity_cgi->stat($content);
        }

    }

    if ( defined $url_params->{section} 
        && $url_params->{section} ne 'alarms' 
        && $url_params->{section} ne 'utilities' 
        && ! defined $VIEWS_ALLVIEWS{$view_mode}
        && ! defined $VIEWS_ALLFIND{$view_mode}
        && ( $url_params->{what_op} ne '1' ) 
        && $self->matrix($url_params->{section}, $node)) 
    {
        my $with_leafs = 1;
        if ($url_params->{section} eq 'services_options'
            || $url_params->{section} eq 'stat')
        {
            $with_leafs = 0;
        }

        my $s;
        if ($node->id_probe_type == 1 && ! defined $VIEWS_TREEFIND{$view_mode})
        {
            if ($url_params->{view_node} == 0)
            {
                $s = $entity_cgi->entity_children_very_short_get($with_leafs);
            }
            elsif ($url_params->{view_node} == 1)
            {
                $s = $entity_cgi->entity_children_long_get($with_leafs);
            }
            elsif ($url_params->{view_node} == 2)
            {
                $s = $entity_cgi->entity_children_very_short_bouquet_get($content);
            }
            elsif ($url_params->{view_node} == 3)
            {
                $s = $entity_cgi->entity_children_long_bouquet_get($content);
            }
        }
        else
        {
            if ($url_params->{view} == 0)
            {
                $s = $entity_cgi->entity_children_very_short_get($with_leafs);
            }
            elsif ($url_params->{view} == 1)
            {
                $s = $entity_cgi->entity_children_long_get($with_leafs);
            }
        }

        $content->addRow($s)
            if $s;

        my $show_comments = session_get_param($self->session, '_GENERAL_SHOW_COMMENTS');
        $show_comments
            ? $but->add( { caption => '', img => '/img/comments_off.gif', alt => 'hide comments',
                class => 'p2', url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_comments_view'), })
            : $but->add({ caption => '', img => '/img/comments_on.gif', alt => 'show comments',
                class => 'p2', url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_comments_view'), });

        if (defined $entity && $id_entity && $entity->status == _ST_BAD_CONF)
        {
            $but->add( { caption => 'try to fix bad configuration', alt => '',
                class => 'p2', url => sprintf(qq|%s?%s&id_entity=%s|, 
                url_get({}, $url_params), 'form_name=form_entity_recheck', $id_entity) })
        }

        comments($content, $id_entity, $entity_cgi, $self->matrix('form_comment_delete', $items->{$id_entity}), $self->matrix('form_comment', $items->{$id_entity}))
            if $id_entity
            && $show_comments;
    }
    elsif ( defined $url_params->{section} 
        && ( $url_params->{section} ne 'alarms' ) 
        && ( $url_params->{section} ne 'stat' ) 
        && ( $url_params->{section} ne 'history' ) 
        && ( $url_params->{section} ne 'utilities' ) 
        && ( $url_params->{what_op} ne '1' ) 
        && (defined $VIEWS_ALLVIEWS{$view_mode} || defined $VIEWS_ALLFIND{$view_mode})
        && $self->matrix($url_params->{section}, $node)) 
    {
        my $s;

        if ($url_params->{view} == 0)
        {
             $s = $entity_cgi->entity_view_very_short_get();
        }
        elsif ($url_params->{view} == 1)
        {
             $s = $entity_cgi->entity_view_long_get()
        }
        elsif ($url_params->{view} == 2)
        {
             $s = $entity_cgi->entity_view_very_short_get();
        }
        elsif ($url_params->{view} == 3)
        {
             $s = $entity_cgi->entity_view_long_get()
        }

        $content->addRow($s)
            if $s;
    }

    if ( ($url_params->{section} eq 'general'
       || $url_params->{section} eq 'entity_options'
       || $url_params->{section} eq 'stat'
       || $url_params->{section} eq 'history'
       || $url_params->{section} eq 'services_options')
       ) #&& $node->is_node)
    {   

        $url_params->{hide_not_monitored}
            ? $but->add( { caption => '', alt => 'show not monitored services', img => '/img/hide_not_monitored_off.gif',
                class => 'p2', url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_hide_not_monitored'), })      
            : $but->add({ caption => '', alt => 'hide not monitored services', img => '/img/hide_not_monitored_on.gif',
                class => 'p2', url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_hide_not_monitored'), })      
            if $node->is_node;
    }

    if ( $url_params->{section} eq 'utilities' && $node->id_probe_type == 1)
    {

        my $result;
        eval qq|require Plugins::utils_node;
           \$result = Plugins::utils_node::get_list($id_entity)
           |;

        for (sort keys %$result)
        {
            $but->add({ caption => $result->{$_}->{name}, target => "ifr_utils",
                url => url_get({ id_entity => $entity->id_entity, section => 'utils', 
                id_probe_type => 1, form_id => $result->{$_}->{form_id} }, $url_params)});
        }
    }

    if ( $url_params->{section} ne 'stat')
    {
        $content->addRow($self->view_menu($url_params, $node->id_probe_type, $view_mode));
    }

    my $probes = $entity_cgi->probes;
    my $popups = '';
    for (keys %{$self->popups})
    {
        next
            unless defined $probes->{$_};
        $popups .= $probes->{$_}->popup_menu({section => $cfg->{$url_params->{section}}->[0], view_mode => $view_mode});
    };
    for (keys %{$self->popups_top})
    {
        next
            unless defined $probes->{$_};
        $popups .= $probes->{$_}->popup_menu({section => $cfg->{$url_params->{section}}->[0], 
            view_mode => $view_mode, top_level => 1});
    };

    if ($url_params->{section} eq 'stat')
    {
        $popups .= $probes->{'group'}->popup_menu_graphtime($url_params);
    }

    if (defined $VIEWS_ALLVIEWS{$view_mode} || defined $VIEWS_HARD{$view_mode})
    {
        $popups .= $probes->{'group'}->popup_menu_view({view_mode => $view_mode});
    }
    elsif (defined $VIEWS_FIND{$view_mode})
    {
        $popups .= $probes->{'group'}->popup_menu_find({view_mode => $view_mode});
    }

    if (defined $VIEWS_LIGHT{$view_mode})
    {
        $popups .= $probes->{'group'}->popup_menu_teeny({view_mode => $view_mode});
    }

    $content->addRow($popups);


    $but->button_ref(1)
         unless $url_params->{section} eq 'utils';

    if (defined $VIEWS_LIGHT{$view_mode})
    {
        push @opts, defined $VIEWS_ALLFIND{$view_mode}
            ? make_popup_form($self->find->form_entity_find, 'section_form_entity_find', 'search')
            : defined $VIEWS_ALLVIEWS{$view_mode}
            ? make_popup_form($self->views->get(), 'section_views_get', 'views options')
            : '';

        $content->addRow($_)
            for @opts;

        $but->button_back(0)
            if defined $VIEWS_ALLFIND{$view_mode} || defined $VIEWS_VIEWS{$view_mode};

        $but->add({ caption => $self->get_caption($entity, $entity_cgi, 'with_section'), 
            class => 'p2', url => "", captionnavi=> 1});

        $right->content(qq|<table width="100%" cellspacing="0" cellpadding="0" class="w"><tr><td>| 
            . $but->get() . qq|</td></tr><tr><td>| 
            . scalar $content . qq|<p>&nbsp;<p></td></tr><tr><td class="dz">|
            . $self->logo(1) . '&nbsp;&nbsp;' 
            . $self->logged_as . ',&nbsp;&nbsp;' 
            . $self->server_time . qq|<p>&nbsp;</td></tr></table>|);
    }
    else
    {
        $content->addRow(@opts);
        $right->content( scalar $content );
    }
}

sub prepare_form_processor
{
    my ($self, $url_params, $entity) = @_;

    my $id_entity = $url_params->{id_entity};

    my $id_parent = undef;

    my ($mode, $msg);

    my $tree = $self->tree;
    my $items = $tree->items;
    my $rel = $tree->relations;

    if ($url_params->{form} && $url_params->{form}->{form_name})
    {
        return ("info", "")
            if $url_params->{form}->{form_name} =~ /^fakeform_/;

        my $is_permited = $url_params->{form}->{form_name} eq 'form_alarm_approval'
            ? $self->matrix($url_params->{form}->{form_name}, $items->{$url_params->{form}->{id_entity}})
            : $self->matrix($url_params->{form}->{form_name}, $items->{$id_entity});
        if ( $is_permited && $url_params->{form}->{form_name} eq 'form_passwd'
             || $is_permited && $url_params->{form}->{form_name} =~ /_user_/ )
        {
            $is_permited = $self->matrix($url_params->{form}->{form_name}, $tree->root);
        }
        else
        {
            $is_permited = $self->matrix($url_params->{form}->{form_name}, $items->{$url_params->{form}->{id_entity}})
                if $is_permited 
                    && $url_params->{form}->{form_name} ne 'form_alarm_approval' 
                    && $url_params->{form}->{form_name} ne 'form_view_manage' 
                    && defined $url_params->{form}->{id_entity};
        }

        if (! $is_permited)
        {
            return ("error", "form access denied.");
        }

        if ($url_params->{form}->{form_name} eq 'form_entity_delete')
        {
            $id_parent = scalar $rel->{ $id_entity }
                if defined $rel->{ $id_entity };
        }

        my $form_result;
        $form_result = eval qq|require FormProcessor::$url_params->{form}->{form_name};
            FormProcessor::$url_params->{form}->{form_name}::process("$ENV{REQUEST_URI}");
            |;

        if (ref($form_result) ne 'ARRAY')
        {
            if (CFG->{Web}->{FormProcessorDebug})
            {
                return ("error", sprintf(qq|%s: %s|, "FormProcessor::$url_params->{form}->{form_name}::process", $@));
            }
            else
            {
                $@ =~ /^(.*) at [a-z,A-z,0-9,_,\/,\., ]* line [0-9]*/;
                return ("error", $@ . "#" . $1);
            }
        }
        else
        {
            if ($form_result->[0])
            {
                if (CFG->{Web}->{FormProcessorDebug})
                {
                    return ("error", sprintf(qq|%s: %s|, "FormProcessor::$url_params->{form}->{form_name}::process",
                        $form_result->[1] ? $form_result->[1] : 'unknown error'));
                }
                else
                {
                    $form_result->[1] =~ /^(.*) at [a-z,A-z,0-9,_,\/,\., ]* line [0-9]*/
                        if $form_result->[1];
                    return ("error", $form_result->[1] && $1 ? $1 : $form_result->[1] ? $form_result->[1] : 'unknown error');
                }
            }
            else
            {
                ($mode, $msg) = ("info", $form_result->[1] ? $form_result->[1] : 'update OK')
                    if $url_params->{form}->{form_name} ne 'form_group_add'
                    && $url_params->{form}->{form_name} ne 'form_alarm_approval'
                    && $url_params->{form}->{form_name} ne 'form_node_add'
                    && $url_params->{form}->{form_name} ne 'form_service_add'
                    && $url_params->{form}->{form_name} ne 'form_general_view'
                    && $url_params->{form}->{form_name} ne 'form_hide_not_monitored'
                    && $url_params->{form}->{form_name} ne 'form_parameters_view'
                    && $url_params->{form}->{form_name} ne 'form_comments_view'
                    && $url_params->{form}->{form_name} ne 'form_entity_delete'
                    && $url_params->{form}->{form_name} ne 'form_view_mode_change'
                    && $url_params->{form}->{form_name} ne 'form_bind_contacts_node_select'
                    && $url_params->{form}->{form_name} ne 'form_bind_contacts_child_select'
                    && $url_params->{form}->{form_name} ne 'form_actions_bind_node_select'
                    && $url_params->{form}->{form_name} ne 'form_actions_bind_child_select'
                    && $url_params->{form}->{form_name} ne 'form_contact_select'
                    && $url_params->{form}->{form_name} ne 'form_action_select'
                    && $url_params->{form}->{form_name} ne 'form_command_select'
                    && $url_params->{form}->{form_name} ne 'form_cgroup_select'
                    && $url_params->{form}->{form_name} ne 'form_view_select'
                    && $url_params->{form}->{form_name} ne 'form_entity_find'
                    && $url_params->{form}->{form_name} ne 'form_history_filter'
                    && $url_params->{form}->{form_name} ne 'form_alarms_filter'
                    && $url_params->{form}->{form_name} ne 'form_graph_options'
                    && $url_params->{form}->{form_name} ne 'form_stat_show_collected_info'
                    && $url_params->{form}->{form_name} ne 'form_dashboard_manage'
                    && $url_params->{form}->{form_name} ne 'form_stat_show_node_info';

                if ($url_params->{form}->{form_name} eq 'form_options_mandatory'
                    || $url_params->{form}->{form_name} eq 'form_alarm_approval'
                    || $url_params->{form}->{form_name} eq 'form_group_add'
                    || $url_params->{form}->{form_name} eq 'form_options_update'
                    || $url_params->{form}->{form_name} eq 'form_options_add'
                    || $url_params->{form}->{form_name} eq 'form_node_add'
                    || $url_params->{form}->{form_name} eq 'form_service_add'
                    || $url_params->{form}->{form_name} eq 'form_services_options'
                    || $url_params->{form}->{form_name} ne 'form_bind_contacts'
                    || $url_params->{form}->{form_name} ne 'form_unbind_contacts'
                    || $url_params->{form}->{form_name} ne 'form_bind_actions'
                    || $url_params->{form}->{form_name} ne 'form_unbind_actions'
                    || $url_params->{form}->{form_name} eq 'form_entity_delete')
                {
                    $self->tree_init();
                }
            }
        }

        if ($url_params->{form}->{form_name} eq 'form_entity_delete')
        {
            $id_entity = defined $id_parent ? $id_parent : 0;
            $url_params->{id_entity} = $id_entity;
            delete $url_params->{what};
            $self->tree_init();
        }
        elsif ($url_params->{form}->{form_name} eq 'form_entity_test')
        {
            delete $url_params->{what};
        }
        elsif ($url_params->{form}->{form_name} eq 'form_entity_find')
        {
            $self->session_initialize;
            $self->find_init();
        }
        elsif ($url_params->{form}->{form_name} =~ /user/)
        {
            $self->{USERS} = users_init($self->dbh);
        }

        $$entity = $id_entity
            ? Entity->new($self->dbh, $id_entity, 1)
            : undef;

        $self->session_initialize;

        if ($url_params->{form} && $url_params->{form}->{form_name} eq 'stat')
        {
            for (keys %{ $url_params->{form} })
            {
                $url_params->{$_} = $url_params->{form}->{$_}
                    unless $_ eq 'form_name';
            }
        }
    }
    if ($url_params->{form}->{form_name} eq 'form_view_select'
        || $url_params->{form}->{form_name} eq 'form_view_add'
        || $url_params->{form}->{form_name} eq 'form_view_mode_change'
        || $url_params->{form}->{form_name} eq 'form_entity_find'
        || $url_params->{form}->{form_name} eq 'form_view_delete'
        || $url_params->{form}->{form_name} eq 'form_view_manage')
    {
        $self->view_mode_init();
        $self->tree_init();
        $self->views_init();
        $self->find_init();
    }
    if ($url_params->{form}->{form_name} eq 'form_configuration_gui')
    {
        reload_cfg();
    }

    return ($mode, $msg);
}

sub utils
{
    my $self = shift;
    my $url_params = $self->url_params;
    my $right = $self->right;

    if (! $url_params->{id_probe_type} || $url_params->{id_probe_type} =~ /\D/)
    {   
        $self->alter('missing id_probe_type');
        return;
    }
    if (! $url_params->{form_id} || $url_params->{form_id} =~ /\D/)
    {   
        $self->alter('missing form_id');
        return;
    }
    if (! $url_params->{id_entity} || $url_params->{id_entity} =~ /\D/)
    {   
        $self->alter('missing id_entity');
        return;
    }

    my $probe_name = CFG->{ProbesMapRev}->{ $url_params->{id_probe_type} };
    my $is_permited = $self->matrix(sprintf(qq|Plugins::utils_%s.%s|, $probe_name, $url_params->{form_id}), 
        $self->tree->items->{$url_params->{id_entity}});

    if (! $is_permited)
    {
         $self->alter("form access denied.");
         return;
    }

    my $result;
    eval qq|require Plugins::utils_$probe_name;
        \$result = Plugins::utils_${probe_name}::process("$ENV{REQUEST_URI}");
        |;

    if (ref($result) ne 'ARRAY')
    {
        $self->alter(sprintf(qq|%s: %s|, "Plugins::utils_$probe_name", $@));
    }
    else
    {
        if ($result->[0])
        {
            $self->alter(sprintf(qq|%s: %s|,"Plugins::utils_$probe_name::process", $result->[1] ? $result->[1] : 'unknown error'));
        }
        else
        {
            $self->alter($result->[1] ? $result->[1] : 'unknown result')
        }
    }
}

sub views_init
{
    my $self = shift;
    $self->{VIEWS} = Views->new($self->dbh, $self->session, $self->cgi, $self->url_params);
    $self->views->vt_find_init($self->find)
        if $self->views->id_view_type == _VT_FIND && ! defined $VIEWS_ALLFIND{$self->view_mode};
}

sub tools_init
{
    my $self = shift;
    $self->{TOOLS} = Tools->new($self->dbh, $self->session, $self->cgi, $self->url_params, $self->tree);
}

sub find_init
{
    my $self = shift;
    $self->{FIND} = Find->new($self->cgi, $self->session, $self->dbh, $self->tree);
    $self->find->find_entities()
        if defined $VIEWS_ALLFIND{$self->view_mode};
}

sub get_caption
{
    my $self = shift;
    my $entity = shift;
    my $entity_cgi = shift;
    my $with_section = @_ ? shift : 0;

    my @result;

    my $last_probe_id;
    my $last_entity_id;
    my $url_params = $self->url_params;

    my $start = 1;

    my $view_mode = $self->view_mode;
    if (defined $VIEWS_LIGHT{$view_mode} && $url_params->{section} eq 'about') 
    {
        push @result, sprintf(qq|<font class="j"><b>%s</b></font>|, 
            $self->make_section_button($entity_cgi, 0, 'teeny', 0, 'about'));
    }
    elsif (defined $VIEWS_ALLFIND{$view_mode})
    {
        if (defined $VIEWS_LIGHT{$view_mode}) 
        {
            push @result, sprintf(qq|<font class="j"><b>%s</b></font>|, 
                $self->make_section_button($entity_cgi, 0, 'teeny', 0, 'find result'));
        }
        else
        {
            push @result, qq|<font class="j"><b>find result:</b></font>|;
        }
    }
    elsif (defined $VIEWS_ALLVIEWS{$view_mode})
    {
        my $v = $self->views;
        my $views = $v->views;
        my $id_view = $v->id_view;
        my $view_name = defined $views->{ $id_view } ? $views->{ $id_view }->{name} : 'n/a';
        if (defined $VIEWS_LIGHT{$view_mode}) 
        {
            push @result, sprintf(qq|<font class="j"><b>%s</b></font>|, 
                $self->make_section_button($entity_cgi, 0, 'teeny', 0, "view: $view_name"));
        }
        else
        {
            push @result, sprintf(qq|<font class="j"><b>view: %s</b></font>|, $view_name);
        }
    }
    elsif (defined $VIEWS_DASHBOARD{$view_mode})
    {
        if (defined $VIEWS_LIGHT{$view_mode})
        {
            push @result, sprintf(qq|<font class="j"><b>%s</b></font>|,
                $self->make_section_button($entity_cgi, 0, 'dashboard', 0, "dashboard"));
        }
        else
        {
            push @result, qq|<font class="j"><b>dashboard</b></font>|;
        }
    }
    elsif ($url_params->{section} eq 'permissions' && defined $VIEWS_LIGHT{$view_mode})
    {
        push @result, sprintf(qq|<font class="j"><b>%s</b></font>|,
            $self->make_section_button($entity_cgi, 0, 'permissions', 0, "permissions"));
    }
    elsif ($url_params->{section} eq 'actions' && defined $VIEWS_LIGHT{$view_mode})
    {
        push @result, sprintf(qq|<font class="j"><b>%s</b></font>|,
            $self->make_section_button($entity_cgi, 0, 'actions', 0, "actions"));
    }
    elsif ($url_params->{section} eq 'contacts' && defined $VIEWS_LIGHT{$view_mode})
    {
        push @result, sprintf(qq|<font class="j"><b>%s</b></font>|,
            $self->make_section_button($entity_cgi, 0, 'teeny', 0, "contacts"));
    }
    else
    {
        my @caption;
        my $items = $self->tree->items;
        my $rel = $self->tree->relations;

        if (! $entity)
        {
            push @caption, [0, 'locations'];
        }
        else
        {
            push @caption, [$entity->id_entity, $entity->name ];

            my $tmp = $items->{$entity->id_parent};
            if (defined $tmp)
            {
                push @caption, [$tmp->id, $tmp->name];
                $tmp = $items->{ $rel->{$tmp->id} };
                push @caption, [$tmp->id, $tmp->name]
                    if defined $tmp;
            }

            if (@caption == 3 && $caption[2]->[0])
            {
                push @caption, [0, '...'];
            }
            elsif (@caption < 3 && $caption[$#caption]->[0])
            {
                push @caption, [0, 'root'];
            }
        }

        if ($caption[$#caption]->[1] eq 'root')
        {
            $caption[$#caption]->[1] = 'location';
        }
        elsif (! $caption[$#caption]->[1])
        {
            $caption[$#caption]->[1] = 'unknown';
        }

        if (defined $VIEWS_LIGHT{$view_mode}) 
        {
            push @result, sprintf(qq|<font class="j"><b>%s</b></font>|, 
                $self->make_section_button($entity_cgi, 0, 'teeny', 0, $caption[$#caption]->[1]));
            --$start;

            --$#caption;
        }

        while (@caption)
        {
            $last_entity_id = $caption[$#caption]->[0];
            $last_probe_id = CFG->{ProbesMapRev}->{$items->{$caption[$#caption]->[0]}->id_probe_type};

            push @result, $entity_cgi->a_popup(
            {
                id => $last_entity_id,
                probe => $last_probe_id,
                name => $caption[$#caption]->[1],
                class => '',
                top_level => $start == 1 ? 1 : 0,
            });

            --$start;

            --$#caption;
        }
        $result[$#result] = "<b>$result[$#result]</b>"
            if ! defined $VIEWS_TREEFIND{$view_mode};
    }

    my $probe;
    my $probe_name_raw;
    my $id_parent;
    my $id_probe_type;
    if (defined $VIEWS_TREEFIND{$view_mode}) 
    {
       $id_probe_type = $self->session->param('_FIND') || {};
       $id_probe_type = defined $id_probe_type->{id_probe_type} ? $id_probe_type->{id_probe_type} : undef;

       if (defined $id_probe_type && $id_probe_type =~ /:/) {
           $probe = [split /:/, $id_probe_type, 2];
           $probe = $entity_cgi->probes->{snmp_generic}->name($probe->[1]);
       } elsif (defined $id_probe_type) {
           $probe = CFG->{ProbesMapRev}->{$id_probe_type};
           $probe = $entity_cgi->probes->{ $probe }->name
               if defined $probe;
       }

       $id_parent = $self->session->param('_FIND');
       $id_parent = $id_parent->{id_parent}
           if ref($id_parent);

       if ($probe && $id_parent) {
           $probe_name_raw = $id_parent . "_" . $id_probe_type;
           $probe_name_raw =~ s/:/_/g;

           $probe = $entity_cgi->a_popup_bqv({
               id => $id_parent,
               id_probe_type => $id_probe_type,
               probe => $probe_name_raw,
               name => $probe,
               class => 'v',
           });

           $result[$#result] .= '<font class="j">::<b>' . $probe . '</b></font>'
               . $entity_cgi->probes->{'group'}->popup_menu_bqv($id_parent, $id_probe_type, $probe_name_raw);
       }
    }


    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);

    $buttons->add({
        caption => "",
        url => "javascript:treeShowHide(true)",
        alt => 'show tree', 
        img => "/img/tree_open.gif",
        right_side => 1,
        });

    if (defined $VIEWS_TREEFIND{$view_mode} && defined $VIEWS_LIGHT{$view_mode} && $probe_name_raw) 
    {
        return 
            qq|<table class="w"><tr><td><div style="display:none" id="tree_closed">$buttons</div></td><td class="g2">|
            . "&nbsp;" 
            . join(" > ", @result) 
            . sprintf(qq|<font class="f"><b> :: %s</b></font>|, 
                $self->make_section_button_tree_find($entity_cgi, $id_parent, $id_probe_type, $probe_name_raw))
            . qq|</td></tr></table>|;
    }
    if (defined $VIEWS_LIGHT{$view_mode}) 
    {
        my $id;

        if ( defined $VIEWS_ALLVIEWS{$view_mode} )
        {
            $id = $self->views->id_view;
        }
        elsif ( defined $VIEWS_FIND{$view_mode} )
        {
            $id = 0;
        }
        else
        {
            $id = $last_entity_id;
        }

        my $section_def = CFG->{Web}->{SectionDefinitions}->{ $url_params->{section} };

        if ($url_params->{section} eq 'actions')
        {
            return 
            qq|<table class="w"><tr><td><div style="display:none" id="tree_closed">$buttons</div></td><td class="g2">|
                . "&nbsp;" 
                . join(" > ", @result) 
                . sprintf(qq|<font class="f"><b> :: %s</b></font>|, 
                    $self->make_section_button($entity_cgi, 0, 'actions', 0, 
                        $url_params->{mode} == 4
                            ? 'time periods'
                            : $url_params->{mode} == 3
                            ? 'commands'
                            : $url_params->{mode} == 2
                            ? 'actions'
                            : 'bindings'
                        ))
            . qq|</td></tr></table>|;
        }
        elsif ($url_params->{section} eq 'permissions')
        {
            return
            qq|<table class="w"><tr><td><div style="display:none" id="tree_closed">$buttons</div></td><td class="g2">|
                . "&nbsp;"
                . join(" > ", @result)
                . sprintf(qq|<font class="f"><b> :: %s</b></font>|,
                    $self->make_section_button($entity_cgi, 0, 'permissions', 0,
                        $url_params->{mode} == 2
                            ? 'rights'
                            : 'users & groups'
                        ))
            . qq|</td></tr></table>|;
        }
        elsif ($url_params->{section} eq 'about')
        {
            return
            qq|<table class="w"><tr><td><div style="display:none" id="tree_closed">$buttons</div></td><td class="g2">|
                . "&nbsp;"
                . join(" > ", @result)
            . qq|</td></tr></table>|;
        }
        elsif ($url_params->{section} eq 'dashboard')
        {
            return
            qq|<table class="w"><tr><td><div style="display:none" id="tree_closed">$buttons</div></td><td class="g2">|
                . "&nbsp;"
                . join(" > ", @result)
                . sprintf(qq|<font class="f"><b> :: %s</b></font>|,
                    $self->make_section_button($entity_cgi, 0, 'dashboard', 0,
                        $url_params->{settings} == 1
                            ? 'settings'
                            : $url_params->{settings} == 2
                                ? 'histograms'
                                : $url_params->{settings} == 3
                                    ? 'system status'
                                    : $url_params->{settings} == 4
                                        ? 'manage system'
                                        : $url_params->{settings} == 5
                                            ? 'top 10'
                                            : 'general'
                        ))
            . qq|</td></tr></table>|;
        }
        elsif ($url_params->{section} eq 'contacts')
        {
            return
            qq|<table class="w"><tr><td><div style="display:none" id="tree_closed">$buttons</div></td><td class="g2">|
                . "&nbsp;"
                . join(" > ", @result)
            . qq|</td></tr></table>|;
        }
        else
        {
            return 
            qq|<table class="w"><tr><td><div style="display:none" id="tree_closed">$buttons</div></td><td class="g2">|
            . "&nbsp;" 
            . join(" > ", @result) 
            . (defined $VIEWS_DASHBOARD{$view_mode}
                ? ""
                : sprintf(qq|<font class="f"><b> :: %s</b></font>|, 
                    $self->make_section_button($entity_cgi, $id, $last_probe_id, 
                        defined $VIEWS_TREEFIND{$view_mode} ? 1 : $start)))
            . qq|</td></tr></table>|;
        }
    }
    else
    {
        return 
            qq|<table class="w"><tr><td><div style="display:none" id="tree_closed">$buttons</div></td><td class="g2">|
            . "&nbsp;" 
            . join(" > ", @result) 
            . qq|</td></tr></table>|;
    }
}

sub get_caption_tools
{
    my $self = shift;
                
    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);

    $buttons->add({
        caption => "",
        url => "javascript:treeShowHide(true)",
        alt => 'show tree',
        img => "/img/tree_open.gif",
        right_side => 1,
        });

    return qq|<table class="w"><tr><td><div style="display:none" id="tree_closed">$buttons</div></td></tr></table>|;
}

sub make_section_button
{
    my $self = shift;
    my $entity_cgi = shift;
    my $last_entity_id = shift;
    my $last_probe_id = shift;
    my $top_level = $_[0] == 0 ? 1 : 0;
    my $section_caption = defined $_[1] ? $_[1] : CFG->{Web}->{SectionDefinitions}->{ $self->url_params->{section} }->[2];
    my $view_mode = $self->view_mode;

    my $probe;
    if ( defined $VIEWS_ALLVIEWS{$view_mode} && $last_probe_id ne 'teeny' )
    {
        $probe = 'view';
    }
    elsif ( defined $VIEWS_FIND{$view_mode} && $last_probe_id ne 'teeny')
    {
        $probe = 'find';
    }
    elsif (! defined $last_probe_id || $last_probe_id eq '')
    {
        $probe = 'group';
    }
    else
    {
        $probe = $last_probe_id;
    }

    return $entity_cgi->a_popup(
            {
                id => defined $last_entity_id && $last_entity_id ne '' ? $last_entity_id : 0,
                probe => $probe,
                name => $section_caption,
                class => '',
                top_level => $top_level,
                caption => 1,
            });

}

sub make_section_button_tree_find
{
    my $self = shift;
    my $entity_cgi = shift;
    my $id_parent = shift;
    my $id_probe_type = shift;
    my $probe_name_raw = shift;
    my $section_caption = CFG->{Web}->{SectionDefinitions}->{ $self->url_params->{section} }->[2];

=pod
    return $entity_cgi->a_onclick(
            {
                id => $id_parent,
                probe => $probe_name_raw,
                name => $section_caption,
                class => '',
                top_level => 0,
            });
=cut

    return $entity_cgi->a_popup(
            {
                id => $id_parent,
                probe => $probe_name_raw,
                name => $section_caption,
                class => '',
                top_level => 1,
                caption => 1,
            });
}

sub prepare_right
{
    my $self = shift;
    my $right = $self->right;

    my $entity = shift;

    my $mode = shift;
    my $msg = shift;

    if ($mode eq 'error')
    {
        $right->content_error($msg);
    }
    elsif ($msg)
    {
        $right->content_info($msg);
    }

    my $url_params = $self->url_params;

    if ($url_params->{clear_history_filter})
    {
        session_clear_param($self->dbh, $self->session, '_HISTORY_CONDITIONS');
        $url_params->{clear_history_filter} = 0;
    }
    elsif ($url_params->{clear_alarms_filter})
    {
        session_clear_param($self->dbh, $self->session, '_ALARMS_CONDITIONS');
        $url_params->{clear_alarms_filter} = 0;
    }
    elsif ($url_params->{clear_graph_options})
    {
        session_clear_param($self->dbh, $self->session, '_GRAPH_OPTIONS');
        $url_params->{clear_graph_options} = 0;
    }

    my $node = $self->tree->root;

    if ( ! defined $url_params->{section} 
        || $url_params->{section} eq 'general' 
        || $url_params->{section} eq 'alarms' 
        || $url_params->{section} eq 'history' 
        || $url_params->{section} eq 'entity_options' 
        || $url_params->{section} eq 'services_options' 
        || $url_params->{section} eq 'stat' 
        || $url_params->{section} eq 'rights' 
        || $url_params->{section} eq 'utils' 
        || $url_params->{section} eq 'utilities' 
        || $url_params->{section} eq 'contactsen' 
        || $url_params->{section} eq 'actionsen' 
        )
    {
        $self->prepare_right_entity($right, $url_params, $entity);
    }
    elsif ( $url_params->{section} eq 'tools')
    {
        $self->matrix('tools', $node)
            ? $self->prepare_right_tools($right, $url_params)
            : $right->content_info('jou, bicz! ;]');
    }
    elsif ( $url_params->{section} eq 'about')
    {
        $right->content( $self->about($right) );
    }
    elsif ( $url_params->{section} eq 'tool')
    {
        $self->matrix('tool', $node)
            ? $self->tool_get($right, $url_params)
            : $right->content_info('jou, bicz! ;]');
    }
=pod
    elsif ( $url_params->{section} eq 'system')
    {
        $self->matrix('system', $node)
            ? $self->prepare_right_system($right, $url_params)
            : $right->content_info('jou, bicz! ;]');
    }
=cut
    elsif ( $url_params->{section} eq 'contacts')
    {
        $self->matrix('contacts', $node)
            ? $self->prepare_right_contacts($right, $url_params)
            : $right->content_info('jou, bicz! ;]');
    }
    elsif ( $url_params->{section} eq 'actions')
    {
        $self->matrix('actions', $node)
            ? $self->prepare_right_actions($right, $url_params)
            : $right->content_info('jou, bicz! ;]');
    }
    elsif ( $url_params->{section} eq 'permissions')
    {
        $self->matrix('permissions', $node)
            ? $self->prepare_right_permissions($right, $url_params)
            : $right->content_info('jou, bicz! ;]');
    }
    elsif ( $url_params->{section} eq 'passwd' )
    {
        $self->matrix('passwd', $node)
            ? $self->prepare_passwd($right, $url_params)
            : $right->content_info('jou, bicz! ;]');
    }
    elsif ( $url_params->{section} eq 'dashboard' )
    {
        $self->matrix('dashboard', $node)
            ? $self->prepare_right_dashboard($right, $url_params)
            : $right->content_info('jou, bicz! ;]');
    }
    else
    {
        $right->content_info('access denied.');
    }
}

sub logo
{
    return $_[1] 
        ? "<img src=/img/logo_small.gif>"
        : "<img src=/img/logo_small.gif> ver. " . $_[0]->version;
}

sub copyrights
{
    return '&copy; 2005-2008 <a href="mailto:piotr.kodzis@yahoo.pl">k&#248;dz&#237;s</a>';
}

sub prepare_top
{
    my $self = shift;
    my $top = $self->top;
    my $url_params = $self->url_params;

    $top->buttons->button_refresh(0);
    $top->buttons->button_back(0);

    return
        if $url_params->{section} eq 'utils' || $url_params->{section} eq 'tool';

    $top->status_bar->add($self->logo);

    return
        if defined $VIEWS_LIGHT{$self->view_mode};

    $top->status_bar->name("status_bar");

    my $node = $self->tree->root;

    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);

    $buttons->add(
    {
        caption => ($url_params->{section} eq 'passwd' ? "<b>change password</b>" : "change password")  . tip(18),
        class => 'p2',
        url => url_get({ section => 'passwd' }, $url_params), 
        right_side => 1,
    })
        if $self->matrix('passwd', $node);

    $buttons->add(
    {
        caption => "logout"  . tip(19), 
        class => 'p2', 
        url => url_get({ section => 'login' }, $url_params), 
        right_side => 1,
    });

    $buttons->add(
    {
        caption => "about",
        class => 'p2', 
        url => url_get({ section => 'about' }, $url_params), 
        right_side => 1,
    });

    $buttons->add(
    {
        caption => ($url_params->{section} ne 'permissions' 
                    && $url_params->{section} ne 'contacts' 
                    && $url_params->{section} ne 'actions' 
                    && $url_params->{section} ne 'passwd' 
                    #&& $url_params->{section} ne 'system' 
                    && $url_params->{section} ne 'tools' 
                    && $url_params->{section} ne 'dashboard' 
                    ? "<b>network</b>" : "network"),
        class => 'p2',
        url => defined $VIEWS_NONBASE{$self->view_mode}
            ?  url_get({}, {}) . "?form_name=form_view_mode_change&nvm=0&id_entity=0"
            :  url_get({}, {}), 
    })
        if $self->matrix('network', $node);

    $buttons->add(
    {
        caption => ($url_params->{section} eq 'dashboard' ? "<b>dashboard</b>" : 'dashboard'),
        class => 'p2',
        url => url_get({ section => 'dashboard', }, {}), 
    })
        if $self->matrix('dashboard', $node);

    $buttons->add(
    {
        caption => ($url_params->{section} eq 'tools' ? "<b>tools</b>" : 'tools'),
        class => 'p2',
        url => url_get({ section => 'tools', }, {}), 
    })
        if $self->matrix('tools', $node);

    $buttons->add(
    {
        caption => ($url_params->{section} eq 'contacts' ? "<b>contacts</b>" : 'contacts'),
        class => 'p2',
        url => url_get({ section => 'contacts', }, {}), 
    })
        if $self->matrix('contacts', $node);

    $buttons->add(
    {
        caption => ($url_params->{section} eq 'actions' ? "<b>actions</b>" : 'actions'),
        class => 'p2',
        url => url_get({ section => 'actions', }, {}), 
    })
        if $self->matrix('actions', $node);

    $buttons->add(
    {
        caption => ($url_params->{section} eq 'permissions' ? "<b>permissions</b>" : 'permissions') . tip(17), 
        class => 'p2',
        url => url_get({ section => 'permissions', }, {}), 
    })
        if $self->matrix('permissions', $node);
=pod
    $buttons->add(
    {
        caption => ($url_params->{section} eq 'system' ? "<b>system</b>" : 'system') . tip(27), 
        class => 'p2',
        url => url_get({ section => 'system', }, {}), 
    })
        if $self->matrix('system', $node);
=cut

    $top->status_bar->add({ caption => $buttons, border => 0 });

    $top->status_bar->add({align => 'right', caption => '', });
    $top->status_bar->add({align => 'right', caption => $self->logged_as});

}

sub logged_as
{
    return sprintf('logged as: %s&nbsp;', $_[0]->session->param('_LOGGED_USERNAME'));
}

sub prepare_bottom
{
    my $self = shift;
    my $url_params = $self->url_params;

    my $bottom = $self->bottom;

    $bottom->buttons->button_refresh(0);
    $bottom->buttons->button_back(0);

    return 
        if $url_params->{section} eq 'utils' || $url_params->{section} eq 'tool';

    $bottom->status_bar->add("bottom cudownego systemu");

}

sub prepare
{
    my $self = shift;

    my $url_params = $self->url_params;

    my $entity = undef;

    if (! $url_params->{id_entity} && $VIEWS_TREEFIND{$self->view_mode})
    {
        my $find = $self->session->param('_FIND') || {};
        $url_params->{id_entity} = $find->{id_parent}
            if $find->{id_parent};
    }

    if ($url_params->{id_entity} != 0)
    {
        
        my $items = $self->tree->items;
        if (! defined $items->{ $url_params->{id_entity} } )
        {   
            $url_params->{id_entity} = 0;
        }
        elsif (! $items->{ $url_params->{id_entity} }->get_right($self->tree->id_user, _R_VIE))
        {   
            $url_params->{id_entity} = 0;
        }

        try
        {
            $entity = $url_params->{id_entity}
            ? Entity->new($self->dbh, $url_params->{id_entity}, 1)
            : undef;
        }
        catch EEntityDoesNotExists with
        {
            log_exception(shift, _LOG_WARNING);
            $entity = undef;
            $url_params->{id_entity} = 0;
        }
        except
        {
        };
    }

    my ($mode, $msg) = $self->prepare_form_processor($url_params, \$entity);
    log_debug("prepared form_processor", _LOG_INTERNAL)
        if $LogEnabled;

    $self->prepare_right($entity, $mode, $msg);
    log_debug("prepared right", _LOG_INTERNAL)
        if $LogEnabled;
    $self->prepare_left; #kolejnosc jest wazna! right czasem reinicjuje drzewo, wiec musi byc przed left
    log_debug("prepared left", _LOG_INTERNAL)
        if $LogEnabled;
    $self->prepare_bottom;
    $self->prepare_top;
    log_debug("prepared bottom and top", _LOG_INTERNAL)
        if $LogEnabled;
}

sub page_begin
{
    my $self = shift;
    my $result = $self->SUPER::page_begin(@_);
    my $url_params = $self->url_params;
    my $url = url_get({}, $url_params);
    $result .= <<EOF;

<SCRIPT LANGUAGE="javascript">

var me = '$url';

EOF
    $result .= qq|  var root = '|;

    $result .= CFG->{Web}->{AkkadaRoot};
    $result .= '/'
        unless $result =~ /\/$/;
    $result .= qq|';\n|;
    
    $result .= qq|</script></HEAD><BODY OnLoad="loadAkkada()">|;
    $result .= qq|<script language="javascript"> if (browser != "Internet Explorer" && browser != "Netscape Navigator") { document.location = "/bb.html"; } </script>|
        if CFG->{Web}->{ForceBrowser};

    return $result;
}

sub page_end
{
    my $self = shift;

    my $result;

    my $url_params = $self->url_params;

    if ($url_params->{section} eq 'permissions'
        || $url_params->{section} eq 'tool'
        || $url_params->{section} eq 'contacts'
        || $url_params->{section} eq 'actions'
        || $url_params->{section} eq 'tools'
        #|| $url_params->{section} eq 'system'
        || $url_params->{section} eq 'about'
        || $url_params->{section} eq 'utils'
        || $url_params->{section} eq 'ws'
        || $url_params->{section} eq 'passwd')
    {   
        $result = "</BODY>";
        $result .= $self->SUPER::page_end(@_);
        return $result;
    }


    my $id_entity = $url_params->{id_entity};
    my $view_mode = $self->view_mode;

    $result = <<EOF;
<SCRIPT language="javascript" type="text/javascript">

var vmode = $view_mode;

set_CUR($id_entity);

if (page_refresh == 'on') 
    refresh_start()
else
    refresh_stop();
EOF

    if (defined $VIEWS_HARD{$view_mode} && $url_params->{section} ne 'dashboard')
    {
        $result .= <<EOF;
var show_tree = getCookie("AKKADA_TREE_MENU");

if (show_tree == '')
  treeShowHide(true)
else
  treeShowHide( show_tree == 'true'?true:false );
EOF
    }

    $result .= "</SCRIPT></BODY>";
    $result .= $self->SUPER::page_end(@_);
    return $result;
}

sub about
{
    my $self = shift;
    my $right = shift;

    my $but = $right->buttons;
    $but->button_refresh(0);

    my $view_mode = $self->view_mode;
    my $url_params = $self->url_params;

    $right->tab->add({caption => "about", active => 1, active_value => 1, url => "#"});

    my $content = <<EOF;
<table class="w"><tr><td>&nbsp;</td><td>
&nbsp;<br>
<h2>AKK\@DA</h2>
<h4>&copy; 2005-2008 by Piotr Kodzis</h4>
<p>
This program is <a href="http://www.opensource.org">Open Source</a> software. You can redistribute it and/or modify it under the terms of the <a href="http://www.gnu.org">GNU</a> General Public License as published by the Free Software Foundation, either version 2 of the License or any later version.
</p>
<p>
ICMP graphs base on <a href=http://people.ee.ethz.ch/~oetiker/webtools/smokeping/>SmokePing</a> source code by <A HREF="mailto:oetiker\@ee.ethz.ch">&copy; Tobi Oetiker</A>
</p>
<p>
GUI tree menu base on version 1 of <a href=http://www.destroydrop.com/javascripts/tree/>dtree</a> JavaScript by <a href="mailto&#58;drop&#64;destroydrop&#46;com">&copy; Geir Landr&ouml;</a>
</p>
<p>
All used icons base on icons found on the Internet via <a href="http://images.google.com">Google</a> images search.
</p>
<p>
AKK\@DA home page is available at <a href="http://akkada.eu">http://akkada.eu/</a>.
</p>
&nbsp;</p>
</td><td>&nbsp;</td></tr></table>
EOF

    if (defined $VIEWS_LIGHT{$view_mode})
    {
        my $entity_cgi = CGIEntity->new(
            $self->users, $self->session, $self->dbh, undef, $self->cgi, $self->tree, $self->url_params, $self);

        $content .= $entity_cgi->probes->{'group'}->popup_menu_teeny({view_mode => $view_mode});

        $but->add({ caption => "", alt => 'full skin', img => '/img/dockicon.gif', right_side => 1,
            url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});

        $but->add({ caption => $self->get_caption(undef, $entity_cgi, 'with_section'),
            class => 'p2', url => "", captionnavi=> 1});

        $right->content(qq|<table width="100%" cellspacing="0" cellpadding="0" class="w"><tr><td>|
            . $but->get() . qq|</td></tr><tr><td>|
            . scalar $content . qq|<p>&nbsp;<p></td></tr><tr><td class="dz">|
            . $self->logo(1) . '&nbsp;&nbsp;'
            . $self->logged_as . ',&nbsp;&nbsp;'
            . $self->server_time . qq|<p>&nbsp;</td></tr></table>|);
    }
    else
    {
        $but->add({ caption => "", alt => 'teeny skin', img => '/img/dockicon.gif', right_side => 1,
            url => sprintf(qq|%s?%s|, url_get({}, $url_params), 'form_name=form_view_mode_change&switch=1')});

        $right->content( $content );
    }
}

1;
