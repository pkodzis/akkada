package Tree::Node;

use vars qw($VERSION);

$VERSION = 1.0;

use Carp;
use Common;
use Constants;
use Configuration;
use strict;
use Bit::Vector;

use constant
{
    ID => 0,
    IS_NODE => 1,
    RIGHTS => 2,

    IMAGE_FUNCTION => 5,
    IMAGE_VENDOR => 6,
    ERR_APPROVED_BY => 7,
    NAME => 8,
    MONITOR => 9,
    IP => 10,
    ID_PROBE_TYPE => 11,
    STATE => 12,
    STATE_WEIGHT => 13,
    STATE_LAST_CHANGE => 14,
    STATUS => 16,
    STATUS_WEIGHT => 17,
    STATUS_LAST_CHANGE => 18,
    ERRMSG => 20,
    FLAP => 22,
    FLAP_COUNT => 23,
    CGROUPS => 24,
    COMMENTS => 25,
    SNMPGDEF => 26,
};

our $StatusRecoveredDeltaTime = CFG->{Web}->{StatusRecoveredDeltaTime} || 60;

sub id { return $_[0]->[ID]; } 

sub image_vendor {$_[0]->[IMAGE_VENDOR] = $_[1] if @_ == 2; return $_[0]->[IMAGE_VENDOR]; }
sub name {$_[0]->[NAME] = $_[1] if @_ == 2; return $_[0]->[NAME]; }
sub monitor {$_[0]->[MONITOR] = $_[1] if @_ == 2; return $_[0]->[MONITOR]; }
sub ip {$_[0]->[IP] = $_[1] if @_ == 2; return $_[0]->[IP]; }
sub id_probe_type {$_[0]->[ID_PROBE_TYPE] = $_[1] if @_ == 2; return $_[0]->[ID_PROBE_TYPE]; }
sub state {$_[0]->[STATE] = $_[1] if @_ == 2; return $_[0]->[STATE]; }
sub state_weight {$_[0]->[STATE_WEIGHT] = $_[1] if @_ == 2; return $_[0]->[STATE_WEIGHT]; }
sub state_last_change {$_[0]->[STATE_LAST_CHANGE] = $_[1] if @_ == 2; return $_[0]->[STATE_LAST_CHANGE]; }
sub status {$_[0]->[STATUS] = $_[1] if @_ == 2; return $_[0]->[STATUS]; }
sub status_weight {$_[0]->[STATUS_WEIGHT] = $_[1] if @_ == 2; return $_[0]->[STATUS_WEIGHT]; }
sub status_last_change {$_[0]->[STATUS_LAST_CHANGE] = $_[1] if @_ == 2; return $_[0]->[STATUS_LAST_CHANGE]; }
sub errmsg { if (@_ == 2) { $_[0]->[ERRMSG] = $_[1]; } $_[0]->[ERRMSG] =~ s/\|/\<br\>/g; return $_[0]->[ERRMSG]; }
sub err_approved_by {$_[0]->[ERR_APPROVED_BY] = $_[1] if @_ == 2; return $_[0]->[ERR_APPROVED_BY]; }
sub flap {$_[0]->[FLAP] = $_[1] if @_ == 2; return $_[0]->[FLAP]; }
sub flap_count {$_[0]->[FLAP_COUNT] = $_[1] if @_ == 2; return $_[0]->[FLAP_COUNT]; }
sub cgroups {$_[0]->[CGROUPS] = $_[1] if @_ == 2; return $_[0]->[CGROUPS]; }
sub comments {$_[0]->[COMMENTS] = $_[1] if @_ == 2; return $_[0]->[COMMENTS]; }
sub snmpgdef {$_[0]->[SNMPGDEF] = $_[1] if @_ == 2; return $_[0]->[SNMPGDEF]; }


sub new 
{
  my $class = shift;
  my $param = shift;

  my $self = [];

  $self->[ID] = $param->{id};
  $self->[IMAGE_FUNCTION] = defined $param->{image_function} ? $param->{image_function} : '';
  $self->[IMAGE_VENDOR] = defined $param->{image_vendor} ? $param->{image_vendor} : '';
  $self->[IP] = defined $param->{ip} ? $param->{ip} : '';
  $self->[NAME] = $param->{name};
  $self->[STATE] = $param->{state};
  $self->[STATE_WEIGHT] = $param->{state_weight};
  $self->[STATE_LAST_CHANGE] = defined $param->{state_last_change} ? $param->{state_last_change} : undef;
  $self->[STATUS] = $param->{status};
  $self->[STATUS_WEIGHT] = $param->{status_weight};
  $self->[STATUS_LAST_CHANGE] = defined $param->{status_last_change} ? $param->{status_last_change} : undef;
  $self->[ID_PROBE_TYPE] = defined $param->{id_probe_type} ? $param->{id_probe_type} : '0';
  $self->[MONITOR] = $param->{monitor};
  $self->[ERR_APPROVED_BY] = defined $param->{err_approved_by} ? $param->{err_approved_by} : '';
  $self->[RIGHTS] = {};
  $self->[FLAP] = $param->{flap};
  $self->[FLAP_COUNT] = $param->{flap_count};
  $self->[CGROUPS] = $param->{cgroups};
  $self->[COMMENTS] = $param->{comments};
  $self->[SNMPGDEF] = $param->{snmpgdef};
  $self->[IS_NODE] = 0;

  bless $self, $class;

  $self->errmsg(defined $param->{errmsg} ? $param->{errmsg} : '');

  return $self;
}

sub rights
{
    my $self = shift;

    my $id_user = shift
        or die "missing id_user";
    if (@_)
    {   
        my $r = shift;
        $self->[RIGHTS]->{$id_user} = defined $r && $r =~ /^[01]{8}$/
            ? $r
            : '00000000';
    }
    return defined $self->[RIGHTS]->{$id_user}
        ? $self->[RIGHTS]->{$id_user} 
        : '00000000';
}

sub get_right
{
    my $self = shift;
    my $id_user = shift
        or die "missing id_user";
    my $bit = shift;
    return right_bit_test($self->rights($id_user), $bit);
}

sub get_calculated_status
{
    my $self = shift;
   
    my $cs;

    return _ST_NOSTATUS
        unless $self->monitor;
 
    if ($self->id_probe_type < 2)
    {
        $cs = merge_statuses($self->status, $self->state);
    }
    else
    {
        $cs = defined $self->status 
            ? $self->status 
            : _ST_UNKNOWN;
    }

    my $t = time;

    $cs = _ST_RECOVERED
        if $cs == _ST_OK && $self->is_node && ($t - $self->state_last_change) < $StatusRecoveredDeltaTime;

    $cs = _ST_RECOVERED
        if $cs == _ST_OK && ($t - $self->status_last_change) < $StatusRecoveredDeltaTime;

    return $cs;

}

sub image_function
{
    my $self = shift;
    return $self->[IMAGE_FUNCTION]
        if $self->[IMAGE_FUNCTION];

    return ! $self->id_probe_type
        ? 'folder'
        : ''
}

sub is_node
{
    $_[0]->[IS_NODE] = $_[1]
        if @_ > 1;
    return $_[0]->[IS_NODE];
}

1;

