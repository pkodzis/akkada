package FormProcessor::form_action_update;

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

        $db->exec( sprintf(qq|UPDATE actions SET name='%s',active='%s',id_command='%s',notify_recovery='%s',notification_interval='%s',
             notification_start='%s',notification_stop='%s',service_type='%s',error_messages_like='%s',statuses='%s',calc=%s,inherit=%s
             WHERE id_action=%s|,  
             $url_params->{form}->{uname},
             $url_params->{form}->{uactive} ? 1 : 0,
             $url_params->{form}->{uid_command},
             $url_params->{form}->{unotify_recovery} ? 1 : 0,
             $url_params->{form}->{unotification_interval},
             $url_params->{form}->{unotification_start},
             $url_params->{form}->{unotification_stop},
             $url_params->{form}->{uservice_type},
             $url_params->{form}->{uerror_messages_like},
             $url_params->{form}->{ustatuses},
             $url_params->{form}->{ucalc} ? 1 : 0,
             $url_params->{form}->{uinherit} ? 1 : 0,
             $id_action));
    };

    flag_files_create($FlagsControlDir, "actions_load");

    return [1, $@]
        if $@;

    return [0];
}

1;
