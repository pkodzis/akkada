package FormProcessor::form_cgroup_delete;

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
        $db->exec( sprintf(qq|DELETE FROM entities_2_cgroups WHERE id_cgroup=%s|, $id_cgroup) );
        $db->exec( sprintf(qq|DELETE FROM contacts_2_cgroups WHERE id_cgroup=%s|, $id_cgroup) );
        $db->exec( sprintf(qq|DELETE FROM cgroups WHERE id_cgroup=%s|, $id_cgroup) );
    };
    return [1, $@]
        if $@;

    flag_files_create($FlagsControlDir, "ActionsExecutor.contacts_load");

    return [0, 'tree_cache module should be restarted to see changes.'];
}

1;
