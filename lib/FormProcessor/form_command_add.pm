package FormProcessor::form_command_add;

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

    my $id_command = $url_params->{form}->{id_command};
    return [1, 'unknown command']
        unless $id_command;
    return [1, 'unknown command']
        if $id_command =~ /\D/;

    eval
    {
        my $db = DB->new();

        die 'name empty'
            unless $url_params->{form}->{name};
        die 'module not selected'
            unless $url_params->{form}->{module};

        $db->exec(sprintf(qq|INSERT INTO commands(id_command,name,command,module) VALUES(%s,'%s','%s','%s')|,
            $id_command,
            $url_params->{form}->{name},
            $url_params->{form}->{command},
            $url_params->{form}->{module},
        ));

        my $session = session_get;
        my $options = $session->param('_ACTIONS') || {};
        $options->{ id_command} = $id_command;
        $session->param('_ACTIONS', $options);
        flag_files_create($FlagsControlDir, "actions_load");
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
