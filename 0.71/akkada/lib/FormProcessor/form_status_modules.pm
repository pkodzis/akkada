package FormProcessor::form_status_modules;

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

    delete $url_params->{form}->{form_name};
    delete $url_params->{form}->{id_entity};

    my $act = $url_params->{form};
    my $action;

    eval
    {   
        for my $module ( %$act )
        {
            $action = $act->{$module};

            next
                unless $action;

            $module =~ s/^action_//g;

            for (qw| start stop restart |)
            {
                die "action flag: $_ exists. try again later."
                    if flag_file_check( $FlagsControlDir, sprintf(qq|manager.process.Modules.%s.%s|, $module, $_));
            }
            flag_files_create($FlagsControlDir, sprintf(qq|manager.process.Modules.%s.%s|, $module, $action));
        }
    };

    return [1, $@]
        if $@;

    return [0];
}

1;
