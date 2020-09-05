package WSBase;

use strict;

use HTML::Template;

use Common;
use Configuration;
use Constants;
use Log;
use WSURLRewriter;
use Data::Dumper;

our $VERSION = "2.0";

our $LogEnabled = CFG->{LogEnabled};
our $WCFG = CFG->{Web};
our $TMPL = CFG->{Web}->{Templates};

my $SESSION_DONT_STORE =
{
    form => 1,
    wskey => 1,
};

use constant
{
    DBH => 0,
    CGI => 1,
    COOKIES => 2,
    SESSION => 3,
    URL_PARAMS => 4,
    USERS => 5,
};

sub version { return $VERSION; }
sub copyright { return 'copyright &copy 2005-2009 Piotr Kodzis' }

sub new 
{
    my $class = shift;

    my $self = [];
    bless $self, $class;

    $self->[DBH] = shift;
    $self->[CGI] = CGI::Compress::Gzip->new();
    $self->[URL_PARAMS] = url_dispatch();
    $self->session_initialize;
    $self->[USERS] = users_init($self->dbh);
    $self->[COOKIES] = {};

    return $self;
}

sub dbh { return $_[0]->[DBH]; }
sub cgi { return $_[0]->[CGI]; }
sub cookies { return $_[0]->[COOKIES]; }
sub session { return $_[0]->[SESSION]; }
sub session_undef { $_[0]->[SESSION] = undef; }
sub url_params { return $_[0]->[URL_PARAMS]; }
sub users { return $_[0]->[USERS]; }


sub session_initialize
{
    my $self = shift;
    my $url_params = $self->url_params;

    $self->[SESSION] = session_get();

    $self->session_load_context
        unless $url_params->{context};
    $self->session_save
        unless $WCFG->{SectionDefinitions}->{ $url_params->{section} }->[0] > 999;
}

sub session_save
{
    my $self = shift;
    my $url_params = $self->url_params;

    return
        if $url_params->{section} eq 'login';

    my $session = $self->session;

    my $context = '';

    for ($session->param)
    { 
        $session->clear([$_])
            unless $_ =~ /^_/;
    }

    for (keys %$url_params)
    {
        next
            if defined $SESSION_DONT_STORE->{$_};
        $context .= '&'
            if $context;
        $context .= "$_=$url_params->{$_}";
    }
    session_set_param($self->dbh, $session, $0, $context);
}

sub session_load_context
{
    my $self = shift;
    my $url_params = $self->url_params;
    my $session = $self->session;

    return 0
        unless defined $session->param("_CONTEXT");
    return 0
        unless defined $session->param("_CONTEXT")->{$0};

    my @s = split(/\&/, $session->param("_CONTEXT")->{$0});

    my @t;
    for ( @s ) 
    {
        @t = split /\=/, $_;
        $url_params->{$t[0]} = $t[1]
            unless defined $SESSION_DONT_STORE->{$_};
    }
}

sub send_cookie
{
    my $self = shift;
    my $params = shift;
    $self->cookies->{ $params->{name} } = $self->cgi->cookie(
        -name => $params->{name},
        -value => $params->{value},
        -expires => $params->{expires});
}

sub send_cookie_with_header
{
    my $self = shift;
    my $params = shift;
    $self->send_cookie({name => $params->{name}, value => $params->{value}, expires => $params->{expires}});
    $self->cgi->header( -cookie => [ values %{$self->cookies} ]);
}

sub header
{
    my $self = shift;
    $self->cgi->header();
}

sub is_logged
{
    my $self = shift;
    my $session = $self->session;

    return 
        ! defined $session
            ||! $session->param('_LOGGED') 
            || (! CFG->{Web}->{Session}->{AllowSessionPersistance} && ! $self->session->expire())
        ? 0
        : 1;
}

sub bad_request
{
    my $self = shift;
    my $tmpl = HTML::Template->new(filename => "$TMPL/bad_request.tmpl");
    $tmpl->param(version => $self->version);
    $self->header;
    return $tmpl->output;
}

sub not_logged
{
    my $self = shift;
    my $tmpl = HTML::Template->new(filename => "$TMPL/not_logged.tmpl");
    $self->header;
    return $tmpl->output;
}

1;
