package FormProcessor::form_contact_update;

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

our $FlagsControlDir = CFG->{FlagsControlDir};

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
        my $contact = $db->exec("select * from contacts where id_contact=" . $id_contact)->fetchrow_hashref;

        my $c2g = {};
        my $nc2g = {};

        my $req = $db->exec("SELECT * FROM contacts_2_cgroups where id_contact=" . $id_contact);
        while( my $h = $req->fetchrow_hashref )
        {
            $c2g->{ $h->{id_cgroup} } = 1;
        }
        $url_params->{form}->{contacts_2_cgroups} = [ $url_params->{form}->{contacts_2_cgroups} ]
             unless ref($url_params->{form}->{contacts_2_cgroups}) eq 'ARRAY';

        for (@{ $url_params->{form}->{contacts_2_cgroups} })
        {
            $nc2g->{$_} = 1;
        }
        for (keys %$nc2g)
        {
            next
                if defined $c2g->{$_} || $_ eq '';
            $db->exec(sprintf("INSERT INTO contacts_2_cgroups VALUES(%s,%s)", $id_contact, $_));
        }
        for (keys %$c2g)
        {
            next
                if defined $nc2g->{$_} || $_ eq '';
            $db->exec(sprintf("DELETE FROM contacts_2_cgroups WHERE id_contact=%s AND id_cgroup=%s", $id_contact, $_));
        }

        if ($url_params->{form}->{uactive} ne $contact->{active})
        {
            $db->exec( sprintf(qq|UPDATE contacts SET active=%s 
                WHERE id_contact=%s|, $url_params->{form}->{uactive} ? 1 : 0, $id_contact));
        }
        $db->exec( sprintf(qq|UPDATE contacts SET name='%s',email='%s',phone='%s',company='%s',alias='%s',other='%s'
             WHERE id_contact=%s|,  
             $url_params->{form}->{uname}, 
             $url_params->{form}->{uemail}, 
             $url_params->{form}->{uphone}, 
             $url_params->{form}->{ucompany}, 
             $url_params->{form}->{ualias}, 
             $url_params->{form}->{uother}, 
             $id_contact));
    };
    return [1, $@]
        if $@;

    flag_files_create($FlagsControlDir, "ActionsExecutor.contacts_load");

    return [0];
}

1;
