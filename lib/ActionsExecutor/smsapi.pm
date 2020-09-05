package ActionsExecutor::smsapi;

#
# this modules is dedicated to work with the commercial www.smsapi.pl SMS interface (Polish company)
#

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use MyException qw(:try);
use Common;
use Data::Dumper;
use LWP::UserAgent;
use Log;

our $LogEnabled = CFG->{LogEnabled};
our $C = CFG->{ActionsExecutor}->{Modules}->{smsapi};
our $LowLevelDebug = $C->{LowLevelDebug};

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
        log_debug('smsapi: bad data format', _LOG_ERROR)
            if $LogEnabled;
        return;
    }
    elsif (! defined $data->{command} || $data->{command} eq '')
    {
        log_debug('smsapi: missing command definition', _LOG_ERROR)
            if $LogEnabled;
        return;
    }


    my $command = $data->{command};
    eval "\$command={$command}";

    if (ref($command) ne 'HASH')
    {
        log_debug('smsapi: bad command format', _LOG_ERROR)
            if $LogEnabled;
        return;
    }
    elsif (! defined $command->{to} || $command->{to} eq '')
    {
        my @to;
        for ( map { $contacts->{$_}->{phone} } keys %$contacts)
        {
            push @to, $_
                if $_;
        }

        $command->{to} = join(',', @to);

        if ($command->{to} eq '')
        {
            log_debug('smsapi: missing cell phone of members of contact group', _LOG_ERROR)
                if $LogEnabled;
            return;
        }
    }


    $data->{command} = $command;

    $data = $self->prepare($data);
   
    $self->smsapi_send($data);
}

sub prepare
{
    my $self = shift;
    my $data = shift;

    my $res;

    $res->{username} = $data->{command}->{username} ? $data->{command}->{username} : $C->{Defaults}->{username};
    $res->{password} = $data->{command}->{password} ? $data->{command}->{password} : $C->{Defaults}->{password};
    $res->{from} = $data->{command}->{from} ? $data->{command}->{from} : $C->{Defaults}->{from};
    $res->{url} = $data->{command}->{url} ? $data->{command}->{url} : $C->{Defaults}->{url};
    $res->{to} = $data->{command}->{to};
    $res->{timeout} = $data->{command}->{timeout} ? $data->{command}->{timeout} : $C->{Defaults}->{timeout};

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

\@Previous:
status: $data->{tmp_st_old}
status duration: $data->{lsd}
error: $data->{errmsg_old}

EOF

    $res->{body} = urlencode($res->{body});
    $res->{password} = crypt_pass($res->{password});

    return $res;
}

sub smsapi_send
{
    my $self = shift;
    my $data = shift;

    if (! $data->{username})
    {
        log_debug("missing SMSAPI.PL sender username. check etc/conf.d/ActionsExecutor/smsapi.conf file", _LOG_ERROR);
        return;
    }
    elsif (! $data->{password})
    {
        log_debug("missing SMSAPI.PL sender password. check etc/conf.d/ActionsExecutor/smsapi.conf file", _LOG_ERROR);
        return;
    }

    my $ua = LWP::UserAgent->new();
    $ua->timeout($data->{timeout});

    log_debug(Dumper($data), _LOG_ERROR)
        if $LowLevelDebug;

    my $url = sprintf(qq|%s?username=%s&password=%s&from=%s&to=%s&message=%s|,
        $data->{url},
        $data->{username},
        $data->{password},
        $data->{from},
        $data->{to},
        $data->{body});

    log_debug(Dumper($url), _LOG_ERROR)
        if $LowLevelDebug;

    my $response = $ua->get($url);

    log_debug(Dumper($response), _LOG_ERROR)
        if $LowLevelDebug;

    my $result = $response->content;

    if ($result =~ /^OK:/)
    {
        log_debug(sprintf(qq|smsapi: %s|, $result), _LOG_DEBUG)
            if $LogEnabled;
    }
    elsif ($result =~ /^ERROR:/)
    {
        $result =~ s/^ERROR://;
        log_debug(qq|smsapi: error:| . (defined $C->{Errors}->{$result} ? $C->{Errors}->{$result} : $response->content), _LOG_ERROR)
            if $LogEnabled;
    }
    else
    {
        log_debug(qq|smsapi: other error; http code: | . $response->code, _LOG_ERROR)
            if $LogEnabled;
    }
}

1;
