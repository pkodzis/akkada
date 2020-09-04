package FormProcessor::form_right_add;

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

    my $id_parent = $url_params->{form}->{id_parent};
    return [1, 'select parent']
        unless defined $id_parent;
    return [1, 'unknown parent']
        if $id_parent =~ /\D/;

    my $id_group = $url_params->{form}->{id_group};
    return [1, 'select group']
        unless defined $id_group;
    return [1, 'unknown group']
        if $id_group=~ /\D/;

    eval
    {
        my $db = DB->new();

        $db->exec(sprintf(qq|INSERT INTO rights(id_entity,id_group,vie,vio,com,cmo,ack,mdy,cre,del,disabled)
            VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,0)|,
            $url_params->{form}->{id_child} ? $url_params->{form}->{id_child} : $id_parent,
            $id_group,
            $url_params->{form}->{vie} ? 1 : 0,
            $url_params->{form}->{vio} ? 1 : 0,
            $url_params->{form}->{com} ? 1 : 0,
            $url_params->{form}->{cmo} ? 1 : 0,
            $url_params->{form}->{ack} ? 1 : 0,
            $url_params->{form}->{mdy} ? 1 : 0,
            $url_params->{form}->{cre} ? 1 : 0,
            $url_params->{form}->{del} ? 1 : 0,
        ));

        flag_files_create($TreeCacheDir, "rights_init");

        my $session = session_get;

        my $options = $session->param('_PERMITIONS') || {};
        delete $options->{id_parent};
        $session->param('_PERMITIONS', $options);

    };
    return [1, $@]
        if $@;

    return [0];
}

1;
