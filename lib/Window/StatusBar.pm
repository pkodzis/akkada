package Window::StatusBar;

use vars qw($VERSION $AUTOLOAD %ok_field %ro_field);

$VERSION = 1.0;

use overload '""' => \&get, fallback => undef;

use Carp;
use strict;
use HTML::Table;

for my $attr (qw( 
                  items
             )) { $ok_field{$attr}++; } 

for my $attr (qw( 
                  items
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
               NAME => '',
               ITEMS => [],
             };
  bless $self, $class;
  return $self;
}

sub name
{
  my $self = shift;
  $self->{NAME} = shift if @_;
  return $self->{NAME};
}

sub count 
{
  my $self = shift;
  my @a = @{ $self->{ITEMS} };
  return $#a+1;
}

sub add
{
  my $self = shift;
  my $h = @_ ? shift : croak("missing argument");
  if (ref($h) eq 'HASH') {
    croak("missing argument caption") unless defined $h->{caption};
    $h->{align} = 'left' unless defined $h->{align};
    if (! defined $h->{class}) {
      if (defined $h->{border} && $h->{border} == 0) {
        $h->{class} = '';
      }
    }
    push @{ $self->{ITEMS} }, $h;
  } else {
    push @{ $self->{ITEMS} }, { caption => $h, align => 'left' };
  }
}

sub get
{
  my $self = shift;
  return '' unless @{ $self->items };

  my $table = HTML::Table->new(-spacing=>1, -width=>'100%');
  $table->setAttr( ($self->name ? ( 'id="' . $self->name . '"' ) : '' ) . ' class="w"');
  $table->addRow();
  foreach (@{ $self->items } ) {
    if ($_->{align} eq 'left') {
      $table->setCell($table->getTableRows, $table->getTableCols+1, $_->{caption});
      $table->setCellAttr($table->getTableRows, $table->getTableCols, defined $_->{class} ? qq|class="$_->{class}"| : 'class="sb"');
      $table->setCell($table->getTableRows, $table->getTableCols+1, "");
    }
  }

  my $align_right_first = 1;
  foreach (@{ $self->items } ) {
    if ($_->{align} eq 'right') {
      if ($align_right_first) {
        $align_right_first = 0;
        $table->setCell($table->getTableRows, $table->getTableCols+1, "");
        $table->setCellAttr($table->getTableRows, $table->getTableCols, 'class="c1"');
      }
      $table->setCell($table->getTableRows, $table->getTableCols+1, "");
      $table->setCell($table->getTableRows, $table->getTableCols+1, $_->{caption});
      $table->setCellAttr($table->getTableRows, $table->getTableCols, defined $_->{class} ? qq|class="$_->{class}"| : 'class="sb"');
    }
  }

  if ($align_right_first) {
    $table->setCell($table->getTableRows, $table->getTableCols+1, "&nbsp;");
    $table->setCellAttr($table->getTableRows, $table->getTableCols, 'class="c2"');
  }

  return $table->getTableRows ? $table : '';
}

1;

