package FormProcessor::form_command_update;

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
            unless $url_params->{form}->{uname};
        die 'module not selected'
            unless $url_params->{form}->{umodule};

        $db->exec( sprintf(qq|UPDATE commands SET name='%s',command='%s',module='%s' WHERE id_command=%s|,  
             $url_params->{form}->{uname},
             $url_params->{form}->{ucommand},
             $url_params->{form}->{umodule},
             $id_command));
        flag_files_create($FlagsControlDir, "actions_load");
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
