package FormProcessor::form_history_clear_log;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;
use Views;
use CGI;


sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    $url_params = url_dispatch( $url_params );

    my $root = $url_params->{form}->{id_entity};

    return [1, 'unknown entity']
        if $root =~ /\D/;

    my $session = session_get;

    my $view_mode = session_get_param($session, '_VIEW_MODE') || _VM_TREE;

    my $job;

    eval 
    {
        my $dbh = DB->new();
        my $views = Views->new($dbh, $session, CGI->new(), $url_params);

        $job = history_get_job( $dbh, $root, $view_mode, $views->view_entities);

        my $days = $url_params->{form}->{days};
        $days = 0
            unless defined $days && $days !~ /\D/;

        if ($job && ref($job) eq 'ARRAY' && @$job)
        {
            $job = join(" OR id_entity=", @$job);
            $job = $days
                ? sprintf(qq|DELETE FROM history24 WHERE (to_days(now()) - to_days(time) > %s) AND (id_entity=%s)|, $days, $job)
                : sprintf(qq|DELETE FROM history24 WHERE id_entity=%s|, $job);
            $dbh->exec($job);
        }
        elsif (! $root)
        {
            $job = $days
                ? sprintf(qq|DELETE FROM history24 WHERE (to_days(now()) - to_days(time) > %s)|, $days)
                : qq|DELETE FROM history24|;
            $dbh->exec($job);
        }

    };

    return [1, $@]
        if $@;
    return [0];
}

1;
