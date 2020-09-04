package Window::Buttons;

use vars qw($VERSION $AUTOLOAD %ok_field %ro_field);

$VERSION = 1.0;

use overload '""' => \&get, fallback => undef;

use Carp;
use strict;
use HTML::Table;
use CGI;

for my $attr (qw( 
                  count
                  count_right
                  items
                  items_right
                  button_refresh
                  button_back
                  button_close
                  button_ref
                  button_ref_flag
                  vertical
             )) { $ok_field{$attr}++; } 

for my $attr (qw( 
                  count
                  count_right
                  items
                  items_right
             )) { $ro_field{$attr}++; } 

my $CAPTION_NAVI = 0;

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
               COUNT => 0,
               COUNT_RIGHT => 0,
               ITEMS => {},
               ITEMS_RIGHT => {},
               BUTTON_REFRESH => 1,
               BUTTON_REF => 0,
               BUTTON_REF_FLAG => 0,
               BUTTON_BACK => 1,
               BUTTON_CLOSE => 0,
               VERTICAL => 0,
             };
  bless $self, $class;
  $CAPTION_NAVI= 0;
  return $self;
}

sub add
{
  my $self = shift;
  croak("missing argument") unless @_;
  my $item = shift;
  croak("argument must be hash reference") unless ref($item) eq 'HASH';
  croak("caption must be defined") unless defined $item->{caption};
  croak("url must be defined") unless defined $item->{url};
  my $but;
  $but->{caption} = $item->{caption};
  $but->{url} = $item->{url};
  $but->{img} = defined $item->{img} ? $item->{img} : undef;
  $but->{target} = defined $item->{target} ? $item->{target} : undef;
  $but->{class} = defined $item->{class} ? $item->{class} : '';
  $but->{alt} = defined $item->{alt} ? $item->{alt} : '';
  $but->{right_side} = defined $item->{right_side} ? $item->{right_side} : 0;
  if (defined $but->{right_side} && $but->{right_side}) {
    ++$self->{COUNT_RIGHT};
    $self->items_right->{ $self->count_right } = $but;
  } else {
    ++$self->{COUNT};
    $CAPTION_NAVI = $self->count
        if defined $item->{captionnavi};
    $self->items->{ $self->count } = $but;
  }
  $but->{on_mouse_over} = $item->{on_mouse_over};
  $but->{on_mouse_out} = $item->{on_mouse_out};
  $but->{on_click} = $item->{on_click};
}

sub move_caption_navi
{
    my $self = shift;

    my $count = $self->count;
    return
        if $count == $CAPTION_NAVI;

    my $items = $self->items;
    my $b_nv = $items->{$CAPTION_NAVI};
    
    for my $i ($CAPTION_NAVI .. $count - 1)
    {
        $items->{$i} = $items->{$i+1};
    }
    $items->{$count} = $b_nv;
    $CAPTION_NAVI = $count;
}

sub build_button
{
    my $self = shift;
    croak("missing argument") unless @_;
    my $b = shift;
    my $q = CGI->new();

    return $b->{url}
        ? $q->a(
            {-href=>$b->{url}, -class=> $b->{class} || "b5", -target=> defined $b->{target} ? $b->{target} : '', 
             -onMouseOver => defined $b->{on_mouse_over} ? $b->{on_mouse_over} : qq|window.status='$b->{alt}';return true;|, 
             -onMouseOut => defined $b->{on_mouse_out} ? $b->{on_mouse_out} : qq|window.status='';return true;|,
             -onClick => defined $b->{on_click} ? $b->{on_click} : '',
            },
            defined $b->{img}
                ? $q->img({ -src=>$b->{img}, -class=>"b1", -alt=>$b->{alt} })
                : ''
            . "&nbsp;" . $b->{caption} . "&nbsp;"
            )
        : $b->{caption};
}

sub get
{
  my $self = shift;
  my $table_l;
  my $table_r;
  my $i;
  my $j;
  my $q = CGI->new();

  if ($self->button_refresh) {
    $self->add({ caption => '', img => '/img/refresh.gif', alt => 'refresh', url => 'javascript:location.reload()', });
    $self->button_refresh(0);
  }
  if ($self->button_back) {
    $self->add({ caption => '', img => '/img/go_back.gif', alt => 'back', url => 'javascript:history.back()', });
    $self->button_back(0);
  }
  if ($self->button_close) {
    $self->add({ caption => 'close', url => 'javascript:window.close()', });
    $self->button_close(0);
  }
  if ($self->button_ref) {
    $self->add({ caption => 'refresh every:', url => 'javascript:button_ref()', right_side => 1});
    $self->button_ref(0);
    $self->button_ref_flag(1);
  }
  return '' unless $self->count || $self->count_right;

  if ($self->vertical) {
    if ($self->count) {
      $table_l = HTML::Table->new(-spacing=>0, -padding=>1);
      $table_l->setAttr('class="w"');
      foreach( sort {$a<=>$b} keys %{ $self->items }) {
        if ($self->items->{$_}->{caption} ne "<hr>") {
        $table_l->addRow($self->items->{$_}->{img} ? $q->img({ -src=> sprintf(qq|/img/%s.gif|, $self->items->{$_}->{img}), -class=>"b1", -alt=>$b->{alt} }) : "&nbsp;", $self->items->{$_}->{caption}, "&nbsp;");

        $table_l->setCellAttr($table_l->getTableRows, 2, qq|class="ba"|);
        $table_l->setCellAttr($table_l->getTableRows, 1, qq|class="b8"|);

        $table_l->setRowAttr($table_l->getTableRows,
                   qq|class="b2" onMouseOver="this.className='b3'" onMouseOut="this.className='b2'" onMouseUp="| . $self->items->{$_}->{url} . qq|"| );
        $table_l->setCellAttr($table_l->getTableRows, 2, qq|class="ba"|);
        $table_l->setCellAttr($table_l->getTableRows, 1, qq|class="b8"|);
        $table_l->setCellAttr($table_l->getTableRows, 3, qq|class="b8"|);
        } else {
          $table_l->addRow(qq|<table class="w" cellspacing=0 cellpadding=0 width=100%><tr><td style="border-bottom: solid ButtonShadow 1px; font-size: 1px; height: 4px;" >&nbsp</td></tr><tr><td style="border-top: solid ButtonHighlight 1px; font-size: 1px; height: 4px;" >&nbsp;</td></tr></table>|);
          $table_l->setCellColSpan($table_l->getTableRows, 1, 3);
          $table_l->setRowAttr($table_l->getTableRows, qq|class="b9"|);
          $table_l->setCellAttr($table_l->getTableRows, 1, qq|class="b9"|);
        }
      }
      return $table_l->getTableRows ? $table_l : '';
    }
  } else {

    if ($CAPTION_NAVI)
    {
        $self->move_caption_navi;
    }
  
    if ($self->count) {
      $table_l = HTML::Table->new(-spacing=>0, -padding=>1);
      $table_l->setAttr('class="w"');
      $table_l->addRow( map { $self->build_button($self->items->{$_}) } sort {$a<=>$b} keys %{ $self->items });
      for $i ( 1 .. $self->count ) {
        $table_l->setCellAttr
                  ($table_l->getTableRows, $i,
                   qq|class="b4" onMouseOver="this.className='b7'" onMouseOut="this.className='b4'"
                             onMouseDown="this.className='b6'" onMouseUp = "this.className='b7'"|
                  )
          unless $i == $CAPTION_NAVI;
      }
    }
    if ($self->count_right) {
      $table_r = HTML::Table->new(-spacing=>0, -padding=>1);
      $table_r->setAttr('class="w"');
      $table_r->addRow( map { $self->build_button($self->items_right->{$_}) } sort {$a<=>$b} keys %{ $self->items_right });

      $j = $self->count_right;

      if ($self->button_ref_flag)
      {
          $table_r->setCell(1, $table_r->getTableCols+1, $q->textfield({ id => 'button_ref', name => 'button_ref', override => 1, size => 2, class => 'textfield', }));
          $table_r->setCell(1, $table_r->getTableCols+1, 
              qq|<input type=checkbox name="button_ref_enable" id="button_ref_enable" label="" |
              . (CGI::cookie("AKKADA_PAGE_REFRESH") eq 'on' ? 'checked' : '')
              . qq| onClick="javascript:button_ref_enable_click()">|);
      }

      for $i (1 .. $j) {
        $table_r->setCellAttr
                  (
                    $table_r->getTableRows, $i,
                    qq|class="b4" onMouseOver="this.className='b7'" onMouseOut="this.className='b4'"
                    onMouseDown="this.className='b6'" onMouseUp = "this.className='b7'"|
                  );
      }
    }
    my $table = HTML::Table->new(-spacing=>0, -padding=>0);
    $table->setAttr('class="w"');

    $table->addRow($table_l ? $table_l : '', '&nbsp;', $table_r ? $table_r : '',);
    $table->setCellAttr(1, 2, 'style="width: 100%;"');
    $table->setCellAttr(1, 3, 'style="text-align: right;"');
    $table = $table->getTableRows ? $table : '';
    return $table;
  }
}

1;
