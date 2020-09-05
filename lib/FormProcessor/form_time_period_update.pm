package FormProcessor::form_time_period_update;

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

        $db->exec( sprintf(qq|UPDATE time_periods SET name='%s',
             monday='%s', tuesday='%s',wednesday='%s',thursday='%s',friday='%s',saturday='%s',sunday='%s'
             WHERE id_time_period=%s|,  
             $url_params->{form}->{uname},
             $url_params->{form}->{umonday},
             $url_params->{form}->{utuesday},
             $url_params->{form}->{uwednesday},
             $url_params->{form}->{uthursday},
             $url_params->{form}->{ufriday},
             $url_params->{form}->{usaturday},
             $url_params->{form}->{usunday},
             $id_time_period));
    };

    flag_files_create($FlagsControlDir, "actions_load");

    return [1, $@]
        if $@;

    return [0];
}

1;
