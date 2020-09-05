package FormProcessor::form_dashboard_manage;

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
use CGI;
use Dashboard;

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $id = $url_params->{form}->{id_form};
    return [1, 'unknown form']
        unless defined $id;
    return [1, 'unknown form']
        if $id =~ /\D/;

    my $col = $url_params->{form}->{col};
    return [1, 'unknown column']
        unless defined $col;
    return [1, 'unknown column']
        if $col =~ /\D/;

    --$col;

    my $action = $url_params->{form}->{action};
    return [1, 'unknown action']
        unless defined $action ;
    return [1, 'unknown action']
        unless $action eq 'up'
        || $action eq 'down'
        || $action eq 'del'
        || $action eq 'rst'
        || $action eq 'gp'
        || $action eq 'add';

    my ($db, $cfg, $gp);

    eval
    {
        $db = DB->new();
        $cfg = Dashboard::config_init(undef, $db);
        $gp = Dashboard::graphs_period_init(undef, $db);
    };

    return [1, $@]
        if $@;

    if ($action eq 'del')
    {
        splice @{$cfg->[$col]}, get_index($cfg->[$col], $id), 1;
    }
    elsif ($action eq 'add')
    {
        push @{$cfg->[$col]}, $id;
    }
    elsif ($action eq 'up')
    {
        my $i = get_index($cfg->[$col], $id);
        my $tmp = $cfg->[$col]->[$i];
        $cfg->[$col]->[$i] = $cfg->[$col]->[$i-1];
        $cfg->[$col]->[$i-1] = $tmp;
    }
    elsif ($action eq 'down')
    {
        my $i = get_index($cfg->[$col], $id);
        my $tmp = $cfg->[$col]->[$i];
        $cfg->[$col]->[$i] = $cfg->[$col]->[$i+1];
        $cfg->[$col]->[$i+1] = $tmp;
    }
    elsif ($action eq 'gp')
    {
        my $period = $url_params->{form}->{period};
        return [1, 'unknown period']
            unless defined $period;
        $gp = $period;
    }
    elsif ($action eq 'rst')
    {
        $cfg = [];
        $gp = undef;
    }

    eval
    {
        Dashboard::config_save(undef, $db, $cfg, $gp);
    };

    return [1, $@]
        if $@;

    return [0];
}

sub get_index
{
    my $ar = shift;
    my $ele = shift;
    my $i = -1;

    for (@$ar)
    {
        ++$i;
        return $i
            if $_ == $ele;
    }

    return -1;
}

1;
