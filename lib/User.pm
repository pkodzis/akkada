package User;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;         
use MyException qw(:try);
use Configuration;

use constant ID_USER => 0;
use constant USERNAME => 1;
use constant LOCKED => 2;
use constant GROUPS => 3;

sub new
{       
    my $class = shift;
    my $param = shift;

    my $self = [];
    $self->[ID_USER] = $param->{id_user};
    $self->[GROUPS] = $param->{groups} || [];
    $self->[USERNAME] = $param->{username};
    $self->[LOCKED] = $param->{locked};
    bless $self, $class;
    return $self;
}

sub id_user
{
    my $self = shift;
    $self->[ID_USER] = shift
        if @_;
    return $self->[ID_USER];
}

sub groups
{
    my $self = shift;
    $self->[GROUPS] = shift
        if @_;
    return $self->[GROUPS];
}

sub username
{
    my $self = shift;
    $self->[USERNAME] = shift
        if @_;
    return $self->[USERNAME];
}

sub locked
{
    my $self = shift;
    $self->[LOCKED] = shift
        if @_;
    return $self->[LOCKED];
}

1;
