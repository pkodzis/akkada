package Window;

use vars qw($VERSION $AUTOLOAD %ok_field %ro_field);

$VERSION = 1.1;

use overload '""' => \&get, fallback => undef;

#test

use Carp;
use strict;
use HTML::Table;
use Window::StatusBar;
use Window::Tab;
use Window::Buttons;

for my $attr (qw( 
                  tab  
                  title
                  caption
                  content
                  buttons
                  status_bar
             )) { $ok_field{$attr}++; } 

for my $attr (qw( 
                  tab
                  status_bar
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
                TAB => Window::Tab->new(),
                TITLE => defined $param->{title} ? $param->{title} :  undef,
                CAPTION => defined $param->{caption} ? $param->{caption} :  undef,
                BUTTONS => Window::Buttons->new(),
                CONTENT => defined $param->{content} ? $param->{content} :  undef,
                CONTENT_INFO => defined $param->{content_info} ? $param->{content_info} :  undef,
                CONTENT_ERROR => defined $param->{content_error} ? $param->{content_error} :  undef,
                STATUS_BAR => Window::StatusBar->new(),
             };
  bless $self, $class;
  return $self;
}

sub content_info
{
   my $self = shift;
   push @{$self->{CONTENT_INFO}}, shift if @_;
   return $self->{CONTENT_INFO};
}

sub content_error
{
   my $self = shift;
   push @{$self->{CONTENT_ERROR}}, shift if @_;
   return $self->{CONTENT_ERROR};
}

sub table_content_info
{
  my $self = shift;
  my $table = HTML::Table->new();
  $table->setAlign("CENTER");
  $table->setCaption("<b><font color=blue>information</font></b>");
  $table->addRow($_) foreach (@{ $self->content_info });
  return $table->getTableRows ? $table : '';
}

sub table_content_error
{
  my $self = shift;
  my $table = HTML::Table->new();
  $table->setAlign("CENTER");
  $table->setCaption("<b><font color=red>error</font></b>");
  $table->addRow($_) foreach (@{ $self->content_error });
  return $table->getTableRows ? $table : '';
}

sub get
{
  my $self = shift;
  my $tab = $self->tab;
  my $title = $self->title;
  my $caption = $self->caption;
  my $buttons = $self->buttons;
  my $status_bar = $self->status_bar;
  my $content = $self->content;

  if (ref($self->content_info) eq 'ARRAY' && @{ $self->content_info }) {
    $content = $self->table_content_info() . "<br>" . (defined $content ? $content : '');
  }
  if (ref($self->content_error) eq 'ARRAY' && @{ $self->content_error }) {
    $content = $self->table_content_error() . "<br>" . (defined $content ? $content : '');
  }
  
  my $i;
  my $count = defined $tab ? $tab->count : 0;
  my $table = HTML::Table->new(-spacing=>0, -width=>'100%',);
  $table->setAlign("CENTER");
  $table->setAttr('class="9"');
  $table->addRow($caption)
      if $caption;

  if ($count) {
    $table->addRow("&nbsp;");
    $table->setCellAttr($table->getTableRows, 1, 'class="c5"');
    $table->setCellColSpan($table->getTableRows, 1, 4);

    my $tn = HTML::Table->new(-spacing=>0);
    $tn->setAlign("LEFT");
    $tn->setAttr('class="9"');
    $tn->addRow( @{$tab->get} );

    for $i (1..$count) {
      $tn->setCellAttr(1, $i,
                          $tab->active_item == $i
                            ? 'class="dj"'
                            : $tab->active_item == $i
                              ? 'class="dh"'
                              : 'class="di"'
                         );
    }
    $table->addRow( "&nbsp;", $tn->getTable(), "&nbsp;", "&nbsp;");
    $table->setCellAttr($table->getTableRows, 1, 'class="c8"');
    $table->setCellAttr($table->getTableRows, 2, 'class="c7"');
    $table->setCellAttr($table->getTableRows, 3, 'class="c7"');
    $table->setCellAttr($table->getTableRows, 4, 'class="c6"');

    $table->addRow( "&nbsp;", $buttons, "&nbsp;", "&nbsp;");
    $table->setCellColSpan($table->getTableRows, 2, 2);
    $table->setCellAttr($table->getTableRows, 1, $content ? 'class="d6"' : 'class="d2"');
    $table->setCellAttr($table->getTableRows, 2, 'class="d7"');
    $table->setCellAttr($table->getTableRows, 4, $content ? 'class="d5"' : 'class="d1"');

  } elsif ($buttons || $content) {
    $table->addRow( "&nbsp;", $buttons, "&nbsp;");
    $table->setCellColSpan($table->getTableRows, 2, 1);
    $table->setCellAttr($table->getTableRows, 1, $content ? 'class="d6"' : 'class="d4"');
    $table->setCellAttr($table->getTableRows, 2, 'class="d7"');
    $table->setCellAttr($table->getTableRows, 3, $content ? 'class="d5"' : 'class="d3"');
  }

  if ($content) {
    $table->addRow("&nbsp;", $content, "&nbsp;", "&nbsp;");
    $table->setCellColSpan($table->getTableRows, 2, 2);
    $table->setCellAttr($table->getTableRows, 1, 'class="d8"');
    $table->setCellAttr($table->getTableRows, 2, 'class="t3"');
    $table->setCellAttr($table->getTableRows, 4, 'class="d9"');

    $table->addRow("&nbsp;", $status_bar->count ? $status_bar : "&nbsp;", "&nbsp;", "&nbsp;");
    $table->setCellColSpan($table->getTableRows, 2, 2);
    $table->setCellAttr($table->getTableRows, 1, 'class="de"');
    $table->setCellAttr($table->getTableRows, 2, 'class="df"');
    $table->setCellAttr($table->getTableRows, 4, 'class="dd"');
  } elsif ($status_bar) {
    $table->addRow("&nbsp;", $status_bar->count ? $status_bar : "&nbsp;", "&nbsp;");
    $table->setCellAttr($table->getTableRows, 1, 'class="db"');
    $table->setCellAttr($table->getTableRows, 2, 'class="df"');
    $table->setCellAttr($table->getTableRows, 3, 'class="dc"');
  }
  if ($caption)
  {
      $table->setCellColSpan(1, 1, $table->getTableCols);
      $table->setCellAttr(1, 1, 'class="c9"');
  }
  return $table->getTableRows ? $table : '';
}

1;

