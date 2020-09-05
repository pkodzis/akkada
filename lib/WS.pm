package WS;

use base qw(WSBase);
use strict;

use Common;
use Configuration;
use Constants;
use Log;
use Serializer;

use Data::Dumper;

our $LogEnabled = CFG->{LogEnabled};
our $TMPL = CFG->{Web}->{Templates};

sub get
{
    my $self = shift;
    my $url_params = $self->url_params;

    my $wskey = defined $url_params->{wskey} && $url_params->{wskey} ? $url_params->{wskey} : 'main';
    $wskey = "ext_$wskey";

    my $login_error = '';

    if (! $self->is_logged && $wskey eq 'ext_process_form_login')
    {
        return $self->ext_process_form_login;
    }
    elsif ($self->is_logged && $wskey ne 'ext_main')
    {
        return $self->ext_process_logout;
    }

    return $self->is_logged
        ? $self->main
        : $self->form_login;
}

sub form_login
{
    my $self = shift;
    my $login_error = shift;

    my $tmpl = HTML::Template->new(filename => "$TMPL/form_login.tmpl");

    $tmpl->param(version => $self->version);
    #$tmpl->param(copyright => $self->copyright);
    #$tmpl->param(action => '/ws/process_form_login');
    #$tmpl->param(login_error => $login_error);

    $self->header;

    return $tmpl->output;
}

sub ext_process_form_login
{
    my $self = shift;
    my $url_params = $self->url_params;
    my $session = $self->session;

    if ($url_params->{form} && $url_params->{form}->{password})
    {
        my $req = sprintf(qq|SELECT * FROM users WHERE username="%s" and password="%s" and locked=0|,
             $url_params->{form}->{username},
             crypt_pass($url_params->{form}->{password}));
        $req = $self->dbh->exec( $req )->fetchrow_hashref;

        if ($req)
        {
             log_debug("login successful: " . $url_params->{form}->{username}, _LOG_WARNING)
                 if $LogEnabled;

             $session->param("_LOGGED", $req->{id_user});
             $session->param("_LOGGED_USERNAME", $req->{username});
             $session->param("_CONTEXT", thaw( $req->{context} ) );

             if ($url_params->{form}->{remember} eq 'on' && CFG->{Web}->{Session}->{AllowSessionPersistance})
             {
                 $session->expire(0);
                 $self->send_cookie_with_header({name=>'AKKADA_SESSION_ID',value=>$self->session->id, expires=>'Fri, 01-Jan-2038 00:00:00 GMT'});
             }
             else
             {
                 $session->expire("_LOGGED", CFG->{Web}->{Session}->{Expire});
                 $session->expire("_LOGGED_USERNAME", CFG->{Web}->{Session}->{Expire});
                 $session->expire(CFG->{Web}->{Session}->{Expire});
                 $self->send_cookie_with_header({name=>'AKKADA_SESSION_ID',value=>$self->session->id, expires=>''});
             }

             delete $url_params->{form};

             $self->session_load_context;

             $url_params->{section} = 'general'
                 if $url_params->{section} eq 'login';

             return '{ success: true}';
        }
    }

    log_debug("login incorrect: " . $url_params->{form}->{username}, _LOG_WARNING)
        if $LogEnabled;

    return "{ success: false, errors: { reason: 'Login failed. Try again.' }}"
}

sub main
{
    my $self = shift;

    my $tmpl = HTML::Template->new(filename => "$TMPL/main.tmpl");

    $tmpl->param(version => $self->version);

    $self->header;

    return $tmpl->output;
}

sub ext_process_logout
{
    my $self = shift;

    $self->send_cookie({name=>'AKKADA_SESSION_ID',value=>'', expires=> 'now'});

    my $session = $self->session;
    $session->delete()
        if ref($session) =~ /CGI::Session/;
    $self->session_undef;
    
    return $self->form_login;
}

1;
