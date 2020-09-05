package ActionsExecutor::mail;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use MyException qw(:try);
use Common;
use Data::Dumper;
use Log;
use Mail::Sender;

our $LogEnabled = CFG->{LogEnabled};
our $C = CFG->{ActionsExecutor}->{Modules}->{mail};
our $AddFooter = CFG->{ActionsBroker}->{AddFooter};
our $Footer = CFG->{ActionsBroker}->{Footer};

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
        log_debug('mail: bad data format', _LOG_ERROR)
            if $LogEnabled;
        return;
    }
    elsif (! defined $data->{command} || $data->{command} eq '')
    {
        log_debug('mail: missing command definition', _LOG_ERROR)
            if $LogEnabled;
        return;
    }

    if ((! defined $data->{smtp} || $data->{smtp} eq '') && (! defined $C->{SMTP} || $C->{SMTP} eq ''))
    {
        log_debug('mail: missing SMTP definition', _LOG_ERROR)
            if $LogEnabled;
        return;
    }

    my $command = $data->{command};
    eval "\$command={$command}";

    if (ref($command) ne 'HASH')
    {
        log_debug('mail: bad command format', _LOG_ERROR)
            if $LogEnabled;
        return;
    }
    elsif (! defined $command->{to} || $command->{to} eq '')
    {
        $command->{to} = join(",", map { $contacts->{$_}->{email} } keys %$contacts);

        if ($command->{to} eq '')
        {
            log_debug('mail: bad command, missing "to" e-mail address', _LOG_ERROR)
                if $LogEnabled;
            return;
        }
    }
    $data->{command} = $command;
   
    $self->mail_send( $self->mail_prepare($data) ); 
}

sub mail_prepare
{
    my $self = shift;
    my $data = shift;

    my $res;

    $res->{smtp} = $data->{command}->{smtp} ? $data->{command}->{smtp} : $C->{SMTP};
    $res->{from} = $data->{command}->{from} ? $data->{command}->{from} : $C->{Defaults}->{from};
    $res->{to} = $data->{command}->{to};
    $res->{cc} = $data->{command}->{cc} ? $data->{command}->{cc} : '';
    $res->{bcc} = $data->{command}->{bcc} ? $data->{command}->{bcc} : '';

    $data = action_data_normalize($data);

    $res->{subject} = action_subject_normalize
    (
        $data->{command}->{subject} ? $data->{command}->{subject} : $C->{Defaults}->{subject},
        $data
    );

    $data->{name} = sprintf(qq|%s (%s)|, $data->{name}, $data->{entity_ip})
        if defined $data->{entity_ip} && $data->{entity_ip};
    $data->{parent_name} = sprintf(qq|%s (%s)|, $data->{parent_name}, $data->{parent_ip})
        if defined $data->{parent_ip} && $data->{parent_ip};

    $res->{body} = <<EOF;
Entity:				$data->{name}
Entity parent:			$data->{parent_name}
Status:				$data->{tmp_st}
Error:				$data->{errmsg}
Date:				$data->{status_last_change}
Flap detected:			$data->{flap}
Duration:			$data->{duration}

Description:			$data->{description}

Previous status:		$data->{tmp_st_old}
Previous status duration:	$data->{lsd}
Previous error:			$data->{errmsg_old}

$data->{footer}

EOF

    $res->{body} .= $Footer
        if $AddFooter;

    return $res;
}

sub mail_send
{
    my $self = shift;
    my $data = shift;

    my $sender;
    my $errmsg;

    eval {
       $sender = new Mail::Sender ({ smtp => $data->{smtp} });
        $sender->OpenMultipart({
            from => $data->{from},
            to => $data->{to},
            cc => $data->{cc},
            bcc => $data->{bcc},
            replyto => '',
            subject => $data->{subject},
            multipart => 'related',
        });

        $sender->Part({ctype => 'multipart/alternative'});
        $sender->Part({
            ctype => 'text/plain; charset=ISO-8859-2;', 
            disposition => 'NONE', 
            msg => $data->{body},
            encoding => 'quoted-printable' 
        });
        $sender->EndPart("multipart/alternative");
    } or $errmsg = $Mail::Sender::Error;

    $sender->Close()
        if ref($sender) eq 'Mail::Sender';

    if (defined $errmsg && $errmsg ne 'ok') 
    {
        log_debug(sprintf(qq|mail: sending mail error: %s|, $errmsg), _LOG_ERROR)
            if $LogEnabled;
        return;
    }
}

1;
