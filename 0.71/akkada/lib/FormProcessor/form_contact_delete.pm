package FormProcessor::form_contact_delete;

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

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $id_contact = $url_params->{form}->{id_contact};
    return [1, 'unknown contact']
        unless $id_contact;
    return [1, 'unknown contact']
        if $id_contact =~ /\D/;

    eval
    {   
        my $db = DB->new();
        $db->exec( sprintf(qq|DELETE FROM contacts_2_cgroups WHERE id_contact=%s|, $id_contact) );
        $db->exec( sprintf(qq|DELETE FROM contacts WHERE id_contact=%s|, $id_contact) );
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
