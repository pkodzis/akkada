package Window::Tab;

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
               ITEMS => [],
             };
  bless $self, $class;
  return $self;
}

sub add_item
{
  my $self = shift;
  @_ ? push @{ $self->{ITEMS} }, shift : croak("missing argument");
}

sub get
{
  my $self = shift;
  return '' unless @{ $self->items };
  my $table = HTML::Table->new(-spacing=>1, -width=>'100%');
  $table->setAttr('class="w"');
  $table->addRow();
  foreach (@{ $self->items } ) {
    $table->setCell($table->getTableRows, $table->getTableCols+1, $_);
    $table->setCellAttr($table->getTableRows, $table->getTableCols, 'class="sb"');
    $table->setCell($table->getTableRows, $table->getTableCols+1, "");
  }
  $table->setCell($table->getTableRows, $table->getTableCols+1, "&nbsp;");
  $table->setCellAttr($table->getTableRows, $table->getTableCols, 'class="c2"');
  return $table->getTableRows ? $table : '';
}
1;

