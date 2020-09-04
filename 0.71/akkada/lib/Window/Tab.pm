package Window::Tab;

use vars qw($VERSION $AUTOLOAD %ok_field %ro_field);

$VERSION = 1.0;

use overload '""' => \&get, fallback => undef;

use Carp;
use strict;
use CGI;

for my $attr (qw( 
                  items
                  count
                  active_item
                  auto_active_item
             )) { $ok_field{$attr}++; } 

for my $attr (qw( 
                  items
                  count
                  active_item
             )) { $ro_field{$attr}++; } 

sub AUTOLOAD
{
  my $self = shift;
  my $attr = $AUTOLOAD;
  $attr =~ s/.*:://;
  return unless $attr =~ /[^A-Z]/; 
  croak "invalid attribute method: ->$attr()" unless $ok_field{$attr};
  croak "ro attribute method: ->$attr()" if $ro_field{$attr} && @_;
  $self->{uc $attr} = shift if @_;
  return $self->{uc $attr};
}

sub new 
{
  my $class = shift;
  my $param = shift;
  my $self = {
               ACTIVE_ITEM => undef,
               COUNT => 0,
               ITEMS => {},
               AUTO_ACTIVE_ITEM => 1,
             };
  bless $self, $class;
  return $self;
}

sub add
{
  my $self = shift;
  croak("missing argument") unless @_;
  my $item = shift;
  croak("must be a hash reference") unless ref($item) eq 'HASH';
  my $caption = defined $item->{caption} ? $item->{caption} : croak("missing caption field");
  my $url = defined $item->{url} ? $item->{url} : undef;
  $url = undef unless $url;
  ++$self->{COUNT};
  $self->{ACTIVE_ITEM} = $self->count if defined $item->{active} && $item->{active} eq $item->{active_value};
  $self->{ITEMS}->{ $self->count }  = { caption => $caption, url => $url, class => defined $item->{class} ? $item->{class} : ''};
}

sub _set_active
{
  my $self = shift;
  $self->{ACTIVE_ITEM} = 1;
}

sub build_item
{
  my $self = shift;
  my $index = @_ ? shift : croak("missing argument");
  my $item = $self->items->{$index};
  my $q = CGI->new();
  if ($self->auto_active_item) {
    $self->_set_active unless defined $self->active_item;
  }
    return sprintf(qq|&nbsp;%s&nbsp;|, $index == $self->active_item && $item->{caption} !~ /span/i
        ?  $item->{caption}
        :  ( defined $item->{url} 
               ? $q->a({
                         -href=> $item->{url},
                         -class=> $item->{class} ? $item->{class} : 'r',
                       }, $item->{caption} )
               : $item->{caption} )
        );
}


sub get 
{
  my $self = shift;
  my $a;
  my $i;
  return $a unless $self->count;
  for $i ( 1..$self->count ) {
    push @$a, $self->build_item($i);
  }
  push @$a, "";

  return $a;
}

1;
