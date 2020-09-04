package FormProcessor::form_rights_existing_update;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Entity;
use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;
use Configuration;

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $form = $url_params->{form};
    delete $form->{id_entity};
    delete $form->{form_name};

    my $idx = {};
    my @tmp = map { (split(/_/,$_))[0] } keys %$form;
    for (@tmp)
    {
        $idx->{$_} = [ split(/-/, $_) ];
    }

    for (keys %$idx)
    {
        $tmp[0] = $_ . "_update";
        delete $idx->{$_}
            unless defined $form->{$tmp[0]};
    }

    return [1, 'select rights you would like to update/delete']
        unless keys %$idx;

    eval
    {
        my $db = DB->new();

        for my $i (keys %$idx)
        {
            $tmp[0] = $i . "_delete";
            if ($form->{$tmp[0]})
            {
                 $db->exec(sprintf(qq|DELETE FROM rights WHERE id_entity=%s AND id_group=%s|, $idx->{$i}->[0], $idx->{$i}->[1]));
            }
            else 
            {
                 $db->exec(sprintf(qq|UPDATE rights SET vie=%s,vio=%s,com=%s,cmo=%s,ack=%s,mdy=%s,cre=%s,del=%s,disabled=%s
                     WHERE id_entity=%s AND id_group=%s|,
                     $form->{ sprintf(qq|%s_%s|, $i, 'vie') } ? 1 : 0,
                     $form->{ sprintf(qq|%s_%s|, $i, 'vio') } ? 1 : 0,
                     $form->{ sprintf(qq|%s_%s|, $i, 'com') } ? 1 : 0,
                     $form->{ sprintf(qq|%s_%s|, $i, 'cmo') } ? 1 : 0,
                     $form->{ sprintf(qq|%s_%s|, $i, 'ack') } ? 1 : 0,
                     $form->{ sprintf(qq|%s_%s|, $i, 'mdy') } ? 1 : 0,
                     $form->{ sprintf(qq|%s_%s|, $i, 'cre') } ? 1 : 0,
                     $form->{ sprintf(qq|%s_%s|, $i, 'del') } ? 1 : 0,
                     $form->{ sprintf(qq|%s_%s|, $i, 'disabled') } ? 1 : 0,
                     $idx->{$i}->[0], $idx->{$i}->[1]));
            }
        }

        flag_files_create($TreeCacheDir, "rights_init");

    };
    return [1, $@]
        if $@;

    return [0];
}

1;
