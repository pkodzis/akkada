package ActionsExecutor::gg;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use MyException qw(:try);
use Common;
use Data::Dumper;
use Log;
use Net::Gadu;

our $LogEnabled = CFG->{LogEnabled};
our $C = CFG->{ActionsExecutor}->{Modules}->{gg};

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
        log_debug('gadu-gadu: bad data format', _LOG_ERROR)
            if $LogEnabled;
        return;
    }
    elsif (! defined $data->{command} || $data->{command} eq '')
    {
        log_debug('gadu-gadu: missing command definition', _LOG_ERROR)
            if $LogEnabled;
        return;
    }


    my $command = $data->{command};
    eval "\$command={$command}";

    if (ref($command) ne 'HASH')
    {
        log_debug('gadu-gadu: bad command format', _LOG_ERROR)
            if $LogEnabled;
        return;
    }

    $data->{command} = $command;

    my @to;
    
    @to = grep { /^gg\:/ } map { $contacts->{$_}->{other} } keys %$contacts;

    if (! @to)
    {
        log_debug('gadu-gadu: missing gg IDs of members of contact group', _LOG_ERROR)
                if $LogEnabled;
        return;
    }

    $data = $self->prepare($data);
   
    $self->gg_send($data, $_)
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

EOF

    return $res;
}

sub gg_send
{
    my $self = shift;
    my $data = shift;
    my $to = shift;

    if (! $data->{username})
    {
        log_debug("missing Gadu-Gadu sender ID. check etc/conf.d/ActionsExecutor/gadu-gadu.conf file", _LOG_ERROR);
        return;
    }
    elsif (! $data->{password})
    {
        log_debug("missing Gadu-Gadu sender password. check etc/conf.d/ActionsExecutor/gadu-gadu.conf file", _LOG_ERROR);
        return;
    }

    $to =~ s/^gg\://;


    my $g = new Net::Gadu(async=>0, server=>"");
    if (!$g->login($data->{username},$data->{password}) )
    {
        log_debug(qq|gadu-gadu: login error|, _LOG_ERROR)
            if $LogEnabled;
    };
    $g->send_message($to, $data->{body});

    log_debug(qq|gadu-gadu: message sent OK|, _LOG_DEBUG)
        if $LogEnabled;
}

1;
