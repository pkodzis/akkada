package Forms;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION );

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( form_create );
%EXPORT_TAGS = ( default => [qw( form_create )] );

use strict;
use CGI;
use HTML::Table;
use Window::Buttons;


sub form_create
{
    my $cont = shift;
    my $cgi = CGI->new();

    my $table = HTML::Table->new(-width => '100%');
    $table->setAttr('class="w"') 
        if $cont->{no_border};

    $table->addRow(sprintf(qq|<form name="%s" method="POST"><input type=hidden name="form_name" value="%s"><input type=hidden name="id_entity" value="%d">|, $cont->{form_name}, $cont->{form_name}, defined $cont->{id_entity} ? $cont->{id_entity} : 0));

    my $form_title = 0;
    if ($cont->{form_title})
    {   
        $table->addRow( sprintf(qq|<span class="z">&nbsp;%s:&nbsp;</b>|, $cont->{form_title}));
        $form_title = 1;
    }

    my $title_row = 0;
    if ($cont->{title_row})
    {
        for ( @{$cont->{title_row}} )
        {
            $_ =~ s/_/ /g;
        }
        $table->addRow( @{$cont->{title_row}} );
        $title_row = 1;
        for my $i ( 1 .. $table->getTableCols )
        {
            $table->setCellAttr($table->getTableRows, $i, 'class="g4"');
        }
    }

    for (@{ $cont->{rows} })
    {
        $table->addRow(@$_, '');
    }

    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    for (@{ $cont->{buttons} })
    {
        $buttons->add({ caption => $_->{caption} , url => $_->{url}, img => $_->{img}, });
    }

    my $color = 0;
    for my $i ( 2+$form_title+$title_row .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $table->setCellClass($i, 1, 'f');
        $table->setCellClass($i, $table->getTableCols, 'e2');
        $color = ! $color;
    }

    $table->addRow( $buttons->get . $cgi->end_form() );

    $table->setCellColSpan(1, 1, $table->getTableCols);
    $table->setCellColSpan(2, 1, $table->getTableCols)
        if $form_title;
    #$table->setCellColSpan($table->getTableRows-1, 1, $table->getTableCols);
    $table->setCellColSpan($table->getTableRows, 1, $table->getTableCols);
    #$table->setRowClass($table->getTableRows, sprintf(qq|tr_0|, $color));

    for (@{ $cont->{class} })
    {
        $table->setCellClass($_->[0], $_->[1], $_->[2]);
    }

    for (@{ $cont->{cellColSpans} })
    {
        $table->setCellColSpan($_->[0] + 1, $_->[1], $_->[2]);
    }

    for (@{ $cont->{cellRowSpans} })
    {
        $table->setCellRowSpan($_->[0], $_->[1], $_->[2]);
    }

    return $table->getTableRows
        ? scalar $table
        : '';
}

1;
