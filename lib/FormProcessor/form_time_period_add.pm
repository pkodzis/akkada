package FormProcessor::form_time_period_add;

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

    my $id_time_period = $url_params->{form}->{id_time_period};
    return [1, 'unknown time period']
        unless $id_time_period;
    return [1, 'unknown time period']
        if $id_time_period =~ /\D/;

    eval
    {
        my $db = DB->new();

        die 'name empty'
            unless $url_params->{form}->{name};

        $db->exec(sprintf(qq|INSERT INTO time_periods(id_time_period,name,monday,tuesday,wednesday,thursday,friday,saturday,sunday) VALUES(%s,'%s','%s','%s','%s','%s','%s','%s','%s')|,
            $id_time_period,
            $url_params->{form}->{name},
            $url_params->{form}->{monday},
            $url_params->{form}->{tuesday},
            $url_params->{form}->{wednesday},
            $url_params->{form}->{thursday},
            $url_params->{form}->{friday},
            $url_params->{form}->{saturday},
            $url_params->{form}->{sunday},
        ));

        my $session = session_get;
        my $options = $session->param('_ACTIONS') || {};
        $options->{ id_time_period} = $id_time_period;
        $session->param('_ACTIONS', $options);

    };

    flag_files_create($FlagsControlDir, "actions_load");
    
    return [1, $@]
        if $@;

    return [0];
}

1;
