package FormProcessor::form_action_add;

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

        die 'name empty'
            unless $url_params->{form}->{name};

        $db->exec(sprintf(qq|INSERT INTO actions(id_action,name,active,id_command,notify_recovery,notification_interval,notification_start,notification_stop,service_type,error_messages_like,statuses,calc,inherit) VALUES(%s,'%s','%s','%s',%s,'%s','%s','%s','%s','%s','%s', %s, %s)|,
            $id_action,
            $url_params->{form}->{name},
            $url_params->{form}->{active} ? 1 : 0,
            $url_params->{form}->{id_command},
            $url_params->{form}->{notify_recovery} ? 1 : 0,
            $url_params->{form}->{notification_interval},
            $url_params->{form}->{notification_start},
            $url_params->{form}->{notification_stop},
            $url_params->{form}->{service_type},
            $url_params->{form}->{error_messages_like},
            $url_params->{form}->{statuses},
            $url_params->{form}->{calc} ? 1 : 0,
            $url_params->{form}->{inherit} ? 1 : 0,
        ));

        my $session = session_get;
        my $options = $session->param('_ACTIONS') || {};
        $options->{ id_action} = $id_action;
        $session->param('_ACTIONS', $options);

    };
    flag_files_create($FlagsControlDir, "actions_load");

    return [1, $@]
        if $@;

    return [0];
}

1;
