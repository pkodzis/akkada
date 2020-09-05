package FormProcessor::form_time_period_delete;

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

        my @tmp;
        my $req = $db->exec("SELECT name FROM entities_2_actions,entities where entities.id_entity=entities_2_actions.id_entity AND id_time_period=" . $id_time_period);
        while( my $h = $req->fetchrow_hashref )
        {
            push @tmp, $h->{name};
        }
        die sprintf(qq|time period is binded to the following entities: %s. first change or delete those bindings.|, join(", ", @tmp))
            if @tmp;

        $db->exec( sprintf(qq|DELETE FROM time_periods WHERE id_time_period=%s|, $id_time_period) );
    };

    flag_files_create($FlagsControlDir, "actions_load");

    return [1, $@]
        if $@;

    return [0];
}

1;
