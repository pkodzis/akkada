package FormProcessor::form_command_delete;

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

        my @tmp;
        my $req = $db->exec("SELECT * FROM actions where id_command=" . $id_command);
        while( my $h = $req->fetchrow_hashref )
        {
            push @tmp, $h->{name};
        }
        die sprintf(qq|command used in following actions: %s. first change or delete those actions|, join(", ", @tmp))
            if @tmp;

        $db->exec( sprintf(qq|DELETE FROM commands WHERE id_command=%s|, $id_command) );
        flag_files_create($FlagsControlDir, "actions_load");
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
