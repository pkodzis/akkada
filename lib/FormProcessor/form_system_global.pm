package FormProcessor::form_system_global;

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

    my $action = $url_params->{form}->{action};

    return [1, "select action"]
        unless $action;

    eval
    {   
        for (qw| start stop restart |)
        {
            die "action flag: $_ exists. try again later."
                if flag_file_check( $FlagsControlDir, 'manager.' . $_);
        }
        flag_files_create($FlagsControlDir, 'manager.' . $action);
    };

    return [1, $@]
        if $@;

    return [0];
}

1;
