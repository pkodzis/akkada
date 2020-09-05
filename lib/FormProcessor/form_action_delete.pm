package FormProcessor::form_action_delete;

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

    my $id_action = $url_params->{form}->{id_action};
    return [1, 'unknown action']
        unless $id_action;
    return [1, 'unknown action']
        if $id_action =~ /\D/;

    eval
    {   
        my $db = DB->new();

        my @tmp;
        my $req = $db->exec("SELECT name FROM entities_2_actions,entities where entities.id_entity=entities_2_actions.id_entity AND 
id_action=" . $id_action);
        while( my $h = $req->fetchrow_hashref )
        {
            push @tmp, $h->{name};
        }
        die sprintf(qq|action is binded to the following entities: %s. first change or delete those bindings.|, join(", ", @tmp
))
            if @tmp;

        $db->exec( sprintf(qq|DELETE FROM actions WHERE id_action=%s|, $id_action) );
    };

    flag_files_create($FlagsControlDir, "actions_load");

    return [1, $@]
        if $@;

    return [0];
}

1;
