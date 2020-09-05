package FormProcessor::form_cgroup_update;

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

    my $id_cgroup = $url_params->{form}->{id_cgroup};
    return [1, 'unknown cgroup']
        unless $id_cgroup;
    return [1, 'unknown cgroup']
        if $id_cgroup =~ /\D/;

    eval
    {
        my $db = DB->new();
        my $cgroup = $db->exec("select * from cgroups where id_cgroup=" . $id_cgroup)->fetchrow_hashref;

        my $c2g = {};
        my $nc2g = {};

        my $req = $db->exec("SELECT * FROM contacts_2_cgroups where id_cgroup=" . $id_cgroup);
        while( my $h = $req->fetchrow_hashref )
        {   
            $c2g->{ $h->{id_contact} } = 1;
        }
        $url_params->{form}->{gcontacts_2_cgroups} = [ $url_params->{form}->{gcontacts_2_cgroups} ]
             unless ref($url_params->{form}->{gcontacts_2_cgroups}) eq 'ARRAY';

        for (@{ $url_params->{form}->{gcontacts_2_cgroups} })
        {   
            $nc2g->{$_} = 1;
        }
        for (keys %$nc2g)
        {   
            next
                if defined $c2g->{$_} || $_ eq '';
            $db->exec(sprintf("INSERT INTO contacts_2_cgroups VALUES(%s,%s)", $_, $id_cgroup));
        }
        for (keys %$c2g)
        {   
            next
                if defined $nc2g->{$_} || $_ eq '';
            $db->exec(sprintf("DELETE FROM contacts_2_cgroups WHERE id_contact=%s AND id_cgroup=%s", $_, $id_cgroup));
        }

        $db->exec( sprintf(qq|UPDATE cgroups SET name='%s'
             WHERE id_cgroup=%s|,  
             $url_params->{form}->{ugname}, 
             $id_cgroup));
    };
    return [1, $@]
        if $@;

    flag_files_create($FlagsControlDir, "ActionsExecutor.contacts_load");

    return [0];
}

1;
