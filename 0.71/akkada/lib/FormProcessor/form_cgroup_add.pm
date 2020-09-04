package FormProcessor::form_cgroup_add;

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

    my $id_cgroup = $url_params->{form}->{id_cgroup};
    return [1, 'unknown cgroup']
        unless $id_cgroup;
    return [1, 'unknown cgroup']
        if $id_cgroup =~ /\D/;

    eval
    {
        my $db = DB->new();

        die 'name empty'
            unless $url_params->{form}->{gname};

        $db->exec(sprintf(qq|INSERT INTO cgroups(id_cgroup,name) VALUES(%s,'%s')|,
            $id_cgroup,
            $url_params->{form}->{gname},
        ));

        my $nc2g = {};

        $url_params->{form}->{gcontacts_2_cgroups} = [ $url_params->{form}->{gcontacts_2_cgroups} ]
             unless ref($url_params->{form}->{gcontacts_2_cgroups}) eq 'ARRAY';

        for (@{ $url_params->{form}->{gcontacts_2_cgroups} })
        {   
            $nc2g->{$_} = 1;
        }
        for (keys %$nc2g)
        {   
            next
                if $_ eq '';
            $db->exec(sprintf("INSERT INTO contacts_2_cgroups VALUES(%s,%s)", $_, $id_cgroup));
        }

        my $session = session_get;
        my $options = $session->param('_CONTACTS') || {};
        $options->{ id_cgroup } = $id_cgroup;
        $session->param('_CONTACTS', $options);

    };
    return [1, $@]
        if $@;

    return [0];
}

1;
