package StatusTree::Node;

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

use constant
{
    ID_ENTITY => 0,
    STATUS => 1,
    PARENT => 2,
    CHILDREN => 3,
    TREE  => 4,
    NAME => 5,
    CHILDREN_ALL => 6,
    STATUS_INH => 7,
    ID_PROBE_TYPE => 8,
};

our $LogEnabled = CFG->{LogEnabled};
our $FlagsUnreachableDir = CFG->{FlagsUnreachableDir};
our $ErrMsg = CFG->{Available}->{ErrMsg};
our $Probes = CFG->{Probes};
our $ProbesMapRev = CFG->{ProbesMapRev};

sub new
{
    my $class = shift;

    my $self = [];
    
    my $param = shift;

    $self->[ID_ENTITY] = $param->{id_entity};
    $self->[STATUS] = $param->{status};
    $self->[PARENT] = $param->{parent};
    $self->[NAME] = $param->{name};
    $self->[ID_PROBE_TYPE] = $param->{id_probe_type};
    $self->[CHILDREN] = {};
    $self->[CHILDREN_ALL] = {};
    $self->[TREE] = $param->{tree};
    $self->[STATUS_INH] = 0;

    if ( $param->{parent} )
    {
        $param = $param->{parent};
    }
#print $self->[ID_ENTITY] , ": ", $self->[STATUS],"\n";
    bless $self, $class;

    return $self;
}

sub status_inh
{
    return $_[0]->[STATUS_INH];
}

sub name
{
    return $_[0]->[NAME];
}

sub tree
{
    return $_[0]->[TREE];
}

sub parent
{
    return $_[0]->[PARENT];
}

sub id_probe_type
{
    return $_[0]->[ID_PROBE_TYPE];
}

sub children
{
    return $_[0]->[CHILDREN];
}

sub children_all
{
    return $_[0]->[CHILDREN_ALL];
}

sub add
{
    my ($self, $param) = @_;

    $param->{parent} = $self;

    my $node = StatusTree::Node->new($param);

    $self->children->{ $param->{id_entity} } = $node;

    $self->children_all_add($node);

    $param->{status} == _ST_UNREACHABLE
        ? $self->tree->nodes_unav->{ $param->{id_entity} } = $node
        : $self->tree->nodes_ok->{ $param->{id_entity} } = $node;

    return $node;
}

sub children_all_add
{
    my $self = shift;
    my $node = shift;
    $self->children_all->{ $node->id_entity } = $node;
    $self->parent->children_all_add($node)
        if $self->parent;
}

sub id_entity
{
    return $_[0]->[ID_ENTITY];
}

sub status 
{
    my $self = shift;
    my $id_entity = $self->id_entity;

#print sprintf(qq|%s: %d => %d\n|, $id_entity, $self->[STATUS], $_[0]) if @_;
    if (@_)
    {
        my $st_n = shift;
        my $st_o = $self->[STATUS];

        my $inh = shift || 0;

        if ($st_o == $st_n)
        {
            if ($st_o == _ST_UNKNOWN)
            {
                if (flag_file_check($FlagsUnreachableDir, $id_entity, 1))
                {
                    flag_files_create_ow($FlagsUnreachableDir, sprintf(qq|%s.last|, $id_entity));
                    log_debug(sprintf(qq|unexpected entity %s unreachable flag deleted!|, $id_entity), _LOG_INFO);
                }
            }
            if ($st_o == _ST_UNREACHABLE)
            {
                if (flag_files_create($FlagsUnreachableDir, $id_entity))
                {
                    log_debug(sprintf(qq|unexpected entity %s unreachable flag created!|, $id_entity), _LOG_INFO);
                }
            }
        }
        elsif ($st_n == _ST_UNKNOWN && $st_o == _ST_UNREACHABLE)
        {
            $self->[STATUS_INH] = $inh;
            $self->set_unknown;
            $self->tree->nodes_ok->{$id_entity} = $self;
            delete $self->tree->nodes_unav->{$id_entity};
        }
        elsif ($st_n == _ST_UNREACHABLE)
        {
            $self->[STATUS_INH] = $inh;
            $self->set_unreachable;
            $self->tree->nodes_unav->{$id_entity} = $self;
            delete $self->tree->nodes_ok->{$id_entity};
        }
    }
    return $self->[STATUS];
}

sub set_unreachable
{
    my $self = shift;
    my $id_entity = $self->id_entity;

    my $entity = $self->entity_get( $id_entity );

    my $errmsg = '';
    $errmsg = sprintf("%s; %s dependent nodes affected", $ErrMsg, scalar keys %{$self->children_all})
        unless $self->status_inh;

    $entity->set_status( $self->status_inh ? _ST_UNKNOWN : _ST_UNREACHABLE, $errmsg);

    if ($entity->params('ip'))
    {
        log_debug(sprintf(qq|entity %s unreachable flag created!|, $id_entity), _LOG_INFO)
            if flag_files_create($FlagsUnreachableDir, $id_entity);
    }

    node_set_status($self->tree->dbh, $id_entity, _ST_UNKNOWN);

#    return
#        if $self->status_inh;

    my $children = $self->children;
    for (keys %$children)
    {
        $children->{$_}->status(_ST_UNREACHABLE, 1);
    }

    $self->[STATUS] = _ST_UNREACHABLE;

}

sub set_unknown
{
    my $self = shift;
    my $id_entity = $self->id_entity;
#print "set_unknown\n";
    my $entity = $self->entity_get( $id_entity );
    if (defined $Probes->{ $ProbesMapRev->{ $entity->id_probe_type } }->{not_tested})
    {
        $entity->set_status(_ST_OK, '');
#print "_ST_OK\n";
    }
    else
    {
#print "_ST_UNKNOWN\n";
        $entity->set_status(_ST_UNKNOWN, '');
    }

    if (flag_file_check($FlagsUnreachableDir, $id_entity, 1))
    {
        flag_files_create_ow($FlagsUnreachableDir, sprintf(qq|%s.last|, $id_entity));
        log_debug(sprintf(qq|entity %s unreachable flag deleted!|, $id_entity), _LOG_INFO);
    }

    $self->[STATUS] = _ST_UNKNOWN;

    my $children = $self->children;
    for (keys %$children)
    {
        $children->{$_}->status(_ST_UNKNOWN);
    }

}

sub entity_get
{   
    my $tree = $_[0]->tree;
    return Entity->new($tree->dbh, $_[1]);
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;
