package FormProcessor::form_contact_add;

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

        die 'name empty'
            unless $url_params->{form}->{name};

        $db->exec(sprintf(qq|INSERT INTO contacts(id_contact,name,email,phone,active,company,alias) VALUES(%s,'%s','%s','%s',%s,'%s','%s')|,
            $id_contact,
            $url_params->{form}->{name},
            $url_params->{form}->{email},
            $url_params->{form}->{phone},
            $url_params->{form}->{active} ? 1 : 0,
            $url_params->{form}->{company},
            $url_params->{form}->{alias},
        ));

        my $nc2g = {};
        $url_params->{form}->{contacts_2_cgroups} = [ $url_params->{form}->{contacts_2_cgroups} ]
             unless ref($url_params->{form}->{contacts_2_cgroups}) eq 'ARRAY';
        for (@{ $url_params->{form}->{contacts_2_cgroups} })
        {   
            $nc2g->{$_} = 1;
        }
        for (keys %$nc2g)
        {
            next
                if $_ eq '';
            $db->exec(sprintf("INSERT INTO contacts_2_cgroups VALUES(%s,%s)", $id_contact, $_));
        }


        my $session = session_get;
        my $options = $session->param('_CONTACTS') || {};
        $options->{ id_contact } = $id_contact;
        $session->param('_CONTACTS', $options);

    };
    return [1, $@]
        if $@;

    return [0];
}

1;
