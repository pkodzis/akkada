package StatusTree;

# drzewo sklada sie tylko z NODEow
# serwisow w nim nie ma
# po zmianie statusu wszystkich affected nodes, selectami zmieniane sa dzieciaki


use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;          
use MyException qw(:try);

use Entity;
use Configuration;
use Log;
use Constants;
use DB;
use Common;
use StatusTree::Node;

use constant
{
    DBH => 0,
    ROOT => 1,
    IPS => 2,
    NODES_OK => 3,
    NODES_UNAV => 4,
};

our $LogEnabled = CFG->{LogEnabled};

our $Nodes;
our $Ips;

sub new
{
    my $class = shift;

    my $self = [];

    $self->[DBH] = DB->new();
    $self->[NODES_OK] = {};
    $self->[NODES_UNAV] = {};

    bless $self, $class;

    $self->[ROOT] = StatusTree::Node->new({id_entity => 0, status => '0', tree => $self});
    $self->load;

#use Data::Dumper; print Dumper($self->root->children->{2381}->nodes); die;
#use Data::Dumper; print Dumper( [keys %{$self->root->children->{2381}->nodes}] ); die;

    return $self;
}

sub load
{
    my $self = shift;

    $self->[IPS] = {};

    my $statment = qq|SELECT * FROM entities_2_parameters,parameters 
        WHERE entities_2_parameters.id_parameter = parameters.id_parameter 
        AND parameters.name='ip'
        AND id_entity NOT IN (SELECT id_entity FROM entities_2_parameters,parameters
        WHERE parameters.id_parameter=entities_2_parameters.id_parameter
        AND parameters.name='availability_check_disable')|;
    $Ips = $self->dbh->exec( $statment )->fetchall_hashref('id_entity');

    $statment = qq|SELECT * FROM links|;
    my $links = $self->dbh->exec( $statment )->fetchall_hashref('id_child');

    $statment = qq|SELECT id_entity,status,name,id_probe_type FROM entities,links WHERE monitor<>0 AND id_entity=id_parent|;
    $Nodes = $self->dbh->exec( $statment )->fetchall_hashref('id_entity');

    for (keys %$Nodes)
    {
        if (defined $Ips->{$_} && defined $Ips->{$_}->{value})
        {
            $Nodes->{$_}->{ip} = $Ips->{$_}->{value};
        }
        $Nodes->{$_}->{id_parent} = defined $links->{$_}
            ? $links->{$_}->{id_parent}
            : 0;
    }

    $self->build_tree($self->root);

#for (keys %{$self->ips}) { log_debug("$_: ". $self->ips->{$_}->name, _LOG_ERROR); }

    $self->load_unreachable($self->root);
    $self->leafs_set_unknown();
    # ustawia _ST_UNREACHABLE tylko na hoscie niedostepnym
    # pozostale przestawia na UNKNOWN
    # ale w swoje strukturze buduje wszystkim podrzednym hostom
    # stan UNREACHBLE i flagi UNREACHABLE
    # tabela statuses jest ignorowana
    # Available dziala tylko i WYLACZNIE na statusach WLASNYCH entity

    $Ips = undef;
    $Nodes = undef;
}

sub build_tree
{
    my $self = shift;
    my $cur = shift;

    my $id_parent = $cur->id_entity;

    if (defined $Ips->{$id_parent})
    {
        $self->[IPS]->{ $Ips->{$id_parent}->{value} } = $cur
             unless defined $self->[IPS]->{ $Ips->{$id_parent}->{value} }
                 && ! $self->[IPS]->{ $Ips->{$id_parent}->{value} }->id_probe_type;
    }

    for (keys %$Nodes)
    {
        next 
            unless $Nodes->{$_}->{id_parent} eq $id_parent;
        $Nodes->{$_}->{tree} = $self;
        $self->build_tree($cur->add($Nodes->{$_}));
    }
}

sub load_unreachable
{
    my $self = shift;
    my $cur = shift;

    if ($cur->status == _ST_UNREACHABLE)
    {
        $cur->set_unreachable;
    }
    else
    {
        my $children = $cur->children;
        for (keys %$children)
        {
            $self->load_unreachable($children->{$_});
        }
    }
}

sub leafs_set_unknown
{
    my $self = shift;

    my @unav = keys %{$self->nodes_unav};
    
    return
        unless @unav;

    my $statment = sprintf(qq|UPDATE entities SET status=%d, status_last_change=NOW() WHERE status<>%d 
        AND monitor<>0 AND id_entity in (
        SELECT id_child FROM links WHERE id_child NOT IN (SELECT id_parent FROM links)
        AND id_parent=%s)|, _ST_UNKNOWN, _ST_UNKNOWN, join(" OR id_parent=", @unav));

    $self->dbh->exec($statment);
}

sub ips 
{
    return $_[0]->[IPS];
}

sub nodes_ok
{
    return $_[0]->[NODES_OK];
}

sub nodes_unav
{
    return $_[0]->[NODES_UNAV];
}

sub dbh
{
    return $_[0]->[DBH];
}

sub root
{
    return $_[0]->[ROOT];
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}


1;
