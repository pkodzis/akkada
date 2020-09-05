package Comments;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION );

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( comments );
%EXPORT_TAGS = ( default => [qw( comments )] );

use strict;         
use MyException qw(:try);
use Configuration;
use Constants;
use Common;
use POSIX;
use URLRewriter;
use HTML::Table;
use Forms;

sub comments
{
    my $content = shift;
    my $id_entity = shift;
    my $entity_cgi = shift;
    my $is_permited_del = shift;
    my $is_permited_add = shift;
    my $subtitle = shift || '';
    my $left = shift || 0;

    my $req = sprintf(qq|SELECT * FROM comments,users 
        WHERE id_entity=%d 
        AND comments.id_user = users.id_user
        ORDER BY id_comment|, $id_entity);
    $req = $entity_cgi->dbh->exec( $req );

    my $table = table_begin($subtitle ? 'comments for' : 'comments',1, undef, $subtitle );
    $table->setAlign('LEFT')
        if $left;

    my $h;
    my $s;
    while ( $h = $req->fetchrow_hashref )  
    {
        $s = sprintf(qq|posted by <b>%s</b> at %s|, $h->{username}, $h->{timestamp});
        $s = $entity_cgi->cgi->a({
            href => url_get({}, $entity_cgi->url_params) . '?form_name=form_comment_delete&id_comment=' . $h->{id_comment} . "&id_entity=$id_entity",
            class => 's'}, '<img src=/img/trash.gif>') . $s
            if $is_permited_del;
        $table->addRow( $s );
        $table->setCellAttr($table->getTableRows, 1, 'class="x"');
        $table->addRow( "<pre>$h->{msg}</pre>" );
    }

    if ($is_permited_add)
    {
        if ($table->getTableRows)
        {
            $table->addRow('');
            $table->setCellAttr($table->getTableRows, 1, 'class="x"');
        }
        $table->addRow( form_comment($entity_cgi) )
    }

    $content->addRow( "<br>" . scalar $table )
        if $table->getTableRows > 1;
 }

sub form_comment
{
    my $entity_cgi = shift;

    my $cont;

    my $form = $entity_cgi->url_params;
    my $cgi = $entity_cgi->cgi;

    $cont->{form_name} = 'form_comment';
    $cont->{form_title} = '';
    $cont->{id_entity} = defined $entity_cgi->entity ? $entity_cgi->entity->id_entity : 0;

    push @{ $cont->{buttons} }, { caption => "add comment", url => "javascript:document.forms['form_comment'].submit()" };

    push @{ $cont->{rows} },
    [   
        $cgi->textarea({-name =>'comment', class => "textfield", value => '', rows => 10, columns => 50 }),
    ];

    return form_create($cont);
}


1;
