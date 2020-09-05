package ActionsExecutor::gtalk;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use MyException qw(:try);
use Common;
use Data::Dumper;
use Log;
use GTalk;

our $LogEnabled = CFG->{LogEnabled};
our $C = CFG->{ActionsExecutor}->{Modules}->{gtalk};

sub new
{
    my $this = shift;
    my $class = ref($this) || $this;

    my $self = {};

    bless $self, $class;

    return $self;
}


sub process
{
    my $self = shift;
    my $data = shift;
    my $contacts = shift;

    if (ref($data) ne 'HASH')
    {
        log_debug('gtalk: bad data format', _LOG_ERROR)
            if $LogEnabled;
        return;
    }
    elsif (! defined $data->{command} || $data->{command} eq '')
    {
        log_debug('gtalk: missing command definition', _LOG_ERROR)
            if $LogEnabled;
        return;
    }


    my $command = $data->{command};
    eval "\$command={$command}";

    if (ref($command) ne 'HASH')
    {
        log_debug('gtalk: bad command format', _LOG_ERROR)
            if $LogEnabled;
        return;
    }

    $data->{command} = $command;

    my @to;
    
    @to = grep { /^GTalk\:/ } map { $contacts->{$_}->{other} } keys %$contacts;

    if (! @to)
    {
        log_debug('gtalk: missing GTalk IDs of members of contact group', _LOG_ERROR)
                if $LogEnabled;
        return;
    }

    $data = $self->prepare($data);
   
    $self->gtalk_send($data, $_)
        for @to;
}

sub prepare
{
    my $self = shift;
    my $data = shift;

    my $res;

    $res->{username} = $data->{command}->{username} ? $data->{command}->{username} : $C->{Defaults}->{username};
    $res->{password} = $data->{command}->{password} ? $data->{command}->{password} : $C->{Defaults}->{password};

    $data = action_data_normalize($data);

    $data->{name} = sprintf(qq|%s (%s)|, $data->{name}, $data->{entity_ip})
        if defined $data->{entity_ip} && $data->{entity_ip};
    $data->{parent_name} = sprintf(qq|%s (%s)|, $data->{parent_name}, $data->{parent_ip})
        if defined $data->{parent_ip} && $data->{parent_ip};

    $res->{body} = <<EOF;
Entity: $data->{name}
Entity parent: $data->{parent_name}
Status: $data->{tmp_st}
Error: $data->{errmsg}
Date: $data->{status_last_change}
Flap detected: $data->{flap}
Duration: $data->{duration}

Description: $data->{description}

Previous status: $data->{tmp_st_old}
Previous status duration: $data->{lsd}
Previous error: $data->{errmsg_old}

$data->{footer}
=============================

EOF

    return $res;
}

sub gtalk_send
{
    my $self = shift;
    my $data = shift;
    my $to = shift;

    if (! $data->{username})
    {
        log_debug("missing GTalk sender ID. check etc/conf.d/ActionsExecutor/gtalk.conf file", _LOG_ERROR);
        return;
    }
    elsif (! $data->{password})
    {
        log_debug("missing GTalk sender password. check etc/conf.d/ActionsExecutor/gtalk.conf file", _LOG_ERROR);
        return;
    }

    $to =~ s/^GTalk\://;

    my $result = GTalk::GTalk(
        debuglevel=>1, debugfile=>'/tmp/Gtalk-log.txt',
        username => $data->{username}, 
        password => $data->{password},
        to => $to, 
        body => $data->{body});

    if ($result)
    {
        log_debug(sprintf(qq|gtalk: %s|, $result), _LOG_ERROR)
            if $LogEnabled;
    }
    else
    {
        log_debug(qq|gtalk: message sent OK|, _LOG_DEBUG)
            if $LogEnabled;
    }
}

1;
