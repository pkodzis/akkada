package Desktop;

use vars qw($VERSION $AUTOLOAD %ok_field %ro_field);

$VERSION = 0.31;

use strict;

use HTML::Table;
#use CGI qw(-nosticky :standard);
use CGI::Compress::Gzip;


use Window;
use Common;
use Constants;
use Configuration;
use URLRewriter;
use CGI::Session;
use Serializer;
use Data::Dumper; #!!! nie kasowac - jest uzywany!
use Log;

our $LogEnabled = CFG->{LogEnabled};
our $WCFG = CFG->{Web};

my $SESSION_DONT_STORE =
{
    form => 1,
};

for my $attr (qw( 
                  top
                  bottom
                  left
                  right
                  alter
                  cgi
                  cookies
                  popups
                  popups_top
                  session
                  dbh
                  url_params
                  users
                  mod_rights
             )) { $ok_field{$attr}++; } 

for my $attr (qw( 
                  top
                  bottom
                  left
                  right
                  cgi
                  session
                  dbh
             )) { $ro_field{$attr}++; } 

sub AUTOLOAD
{
    my $self = shift;
    my $attr = $AUTOLOAD;

    $attr =~ s/.*:://;
    return
        unless $attr =~ /[^A-Z]/; 

    warn "invalid attribute method: ->$attr()" 
        unless $ok_field{$attr};
    warn "ro attribute method: ->$attr()" 
        if $ro_field{$attr} && @_;

if (! $ok_field{$attr})
{
use Data::Dumper; warn Dumper([caller(0)]);
use Data::Dumper; warn Dumper([caller(1)]);
use Data::Dumper; warn Dumper([caller(2)]);
use Data::Dumper; warn Dumper([caller(3)]);
}

    die 
        unless $ok_field{$attr};
    die 
        if $ro_field{$attr} && @_;

    $self->{uc $attr} = shift
        if @_;

    return $self->{uc $attr};
}

sub version
{
    return $VERSION;
}

sub matrix
{
    my $self = shift;
    my $module = shift;
    my $node = shift;
    my $id_user = $self->tree->id_user;
    my $mod_rights = $self->mod_rights;
    return 0
        unless defined $mod_rights->{$module};
    return 0
        unless defined $node;
    return $node->get_right( $id_user, $mod_rights->{$module});
}

sub new 
{
  my $class = shift;

  my $self = {};
  bless $self, $class;

  $self->{DBH} = shift;

  $self->{CGI} = CGI::Compress::Gzip->new();
  $self->{'MOD_RIGHTS'} = CFG->{Web}->{Rights};

  $self->{URL_PARAMS} = url_dispatch();

  $self->session_initialize;

  $self->{USERS} = users_init($self->{DBH});

  $self->{TOP} = Window->new();
  $self->{BOTTOM} = Window->new();
  $self->{LEFT} = Window->new();
  $self->{RIGHT} = Window->new();
  $self->{ALTER} = '';
  $self->{COOKIES} = {};
  $self->{POPUPS} = {group => 1, node => 1};
  $self->{POPUPS_TOP} = {group => 1};

  return $self;
}

sub put_popup
{
    my $self = shift;
    my $popup = shift;
    $self->popups->{$popup}++;
}

sub put_popup_top
{
    my $self = shift;
    my $popup = shift;
    $self->popups_top->{$popup}++;
}

sub header
{
  my $self = shift;
  my $cookies = $self->cookies;

  # !!! uwaga: to sie nie printuje; CGI w przypadku mod_perla wysyla to metoda wlasna do mod_perla i nie nalezy sie tym interesowac
  # czy dociera do przegladarki widac w debugu na przegladarce na kliencie.
  $self->cgi->header( -cookie => [ values %$cookies ]);
}

sub session_initialize
{
    my $self = shift;
    my $url_params = $self->url_params;

    $self->{SESSION} = session_get;

    $self->session_load_context
        unless $url_params->{context};
    $self->session_save
        unless $WCFG->{SectionDefinitions}->{ $url_params->{section} }->[0] > 999;
}

sub prepare
{
   #potrzebne do logowania sie do akkady
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
#warn Dumper $url_params;
}

sub users
{
    return $_[0]->{USERS};
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

sub login_process
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
             $session->param("_LOGGED", $req->{id_user});
             $session->param("_LOGGED_USERNAME", $req->{username});
             $session->param("_CONTEXT", thaw( $req->{context} ) );

             if ($url_params->{form}->{remember} eq 'on' && CFG->{Web}->{Session}->{AllowSessionPersistance})
             {
                 $session->expire(0);
                 $self->send_cookie({name=>'AKKADA_SESSION_ID',value=>$self->session->id, expires=>'Fri, 01-Jan-2038 00:00:00 GMT'});
             }
             else
             {
                 $session->expire("_LOGGED", CFG->{Web}->{Session}->{Expire});
                 $session->expire("_LOGGED_USERNAME", CFG->{Web}->{Session}->{Expire});
                 $session->expire(CFG->{Web}->{Session}->{Expire});
                 $self->send_cookie({name=>'AKKADA_SESSION_ID',value=>$self->session->id, expires=>''});
             }

             delete $url_params->{form};

             $self->session_load_context;

             $url_params->{section} = 'general'
                 if $url_params->{section} eq 'login';

             return $req->{id_user};
        }
    }
    return 0;
}



sub page_begin
{
    my $charset = $WCFG->{CharSet} || "iso-8859-1";
#<META HTTP-EQUIV="Pragma" CONTENT="no-cache">
#<META HTTP-EQUIV="Expires" CONTENT="-1">
    return <<EOF;
<HTML>
<HEAD>
<TITLE>$0</TITLE>
<META HTTP-EQUIV="content-type" CONTENT="text/html; charset=$charset"> 
<LINK rel="StyleSheet" href="/css/akkada.css" type="text/css" />
<LINK rel="StyleSheet" href="/css/status.css" type="text/css" />
<LINK rel="StyleSheet" href="/dtree/dtree.css" type="text/css" />
<SCRIPT type="text/javascript" src="/dtree/dtree.js"></script>
<SCRIPT type="text/javascript" src="/common.js"></script>

EOF
}

sub page_end
{
    return "</HTML>";
}

sub login_page
{
    my $self = shift;

    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $buttons->add({ caption => 'login' , url => "javascript:document.forms['form_login'].submit()", });

    my $cgi = $self->cgi;

    my $table = HTML::Table->new();
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');

    $table->addRow(qq|<form name="form_login" method="POST"><input type=hidden name="form_name" value="form_login">|);
    $table->addRow( sprintf(qq|%s ver. %s&nbsp;|,
        $cgi->img({src => '/img/logo_small.gif'}), $self->version ));
    $table->setCellColSpan($table->getTableRows,1,2);
    $table->addRow( '&nbsp;' );
    $table->addRow(qq|username: <input type="text" name="username" value="" class="textfield" size=16 onKeyPress="send_submit(event,'form_login');">|);
    $table->addRow(qq|password: <input type="password" name="password" value="" class="textfield" size=18 onKeyPress="send_submit(event,'form_login');">|);
    $table->addRow(qq|<input type="checkbox" name="remember" value="on" onClick="javascript:msgExp();">&nbsp;remember my login|)
        if CFG->{Web}->{Session}->{AllowSessionPersistance};
    $table->addRow( '&nbsp;' );
    $table->addRow( $buttons->get . $cgi->end_form() );
    $table->addRow( '&nbsp;' );
    $table->addRow( '&nbsp;' );
    $table->addRow( sprintf(qq|<div id="msgexp">%s</div>|,CFG->{Web}->{Login}->{MsgExpire}) 
        . sprintf(qq|<div id="msgnoexp" style="display: none;">%s</div>|,CFG->{Web}->{Login}->{MsgNoExpire}) );
    $table->addRow( CFG->{Web}->{Login}->{Msg} );
    $table->setCellColSpan($table->getTableRows,1,2);

    if (-e "$ENV{AKKADA}/etc/login.html")
    {
        open F, "$ENV{AKKADA}/etc/login.html";
        $table->addRow( join('', <F>) );
        close F;
        $table->setCellColSpan($table->getTableRows,1,2);
    }

    return qq|<script>
        function msgExp()
        {
            tD.getElementById('msgexp').style.display = (tD.forms['form_login'].elements['remember'].checked==true)?"none":"block";
            tD.getElementById('msgnoexp').style.display = (tD.forms['form_login'].elements['remember'].checked)?"block":"none";
            return; 
        } 
    </script></head><body><br><br>$table</body></html>|;
}

sub session_delete
{
    my $self = shift;
    my $session = $self->session;
    $self->send_cookie({name=>'AKKADA_SESSION_ID',value=>'', expires=> 'now'});
    return
        unless ref($session) eq 'CGI::Session::File';
    $session->delete();
}

sub get
{
    my $self = shift;

    my $result;
    my $url_params = $self->url_params;
    if (! defined $self->session->param('_LOGGED') || $url_params->{section} eq 'login'
        || (! CFG->{Web}->{Session}->{AllowSessionPersistance} && ! $self->session->expire()))
    {
        if ($url_params->{section} eq 'login')
        {
            $self->session_delete();
            $self->session_initialize();
        }
        my $id_user = $self->login_process();
        if ($id_user)
        {
            $self->session_save
                unless $WCFG->{SectionDefinitions}->{ $url_params->{section}}->[0] > 999;
            $self->tree_init($id_user);
            $id_user = url_get({}, $url_params);
            $self->header;
            return qq|<html><head><meta http-equiv="Refresh" content="0 url=$id_user"></head></html>|;
        }
        else
        {
            $self->header;
            $url_params->{section} = 'login';
            $result = $self->page_begin;
            $result .= $self->login_page;
            return $result;
        }
    }

    #this is for AKK@DA web services

    log_debug("building desktop", _LOG_INTERNAL)
        if $LogEnabled;

    $self->header;
    $result = $self->page_begin;
    $self->prepare;

    if (defined $VIEWS_LIGHT{$self->view_mode})
    {
        $result .= $self->right->content;
        $result .= $self->alter;
        $result .= $self->page_end;
        return $result;
    }

    $result .= $self->top;


    my $table = HTML::Table->new(-spacing=>0, -padding=>0, -width=>'100%');

    $table->setAttr('class="w"');
    $table->addRow( sprintf(qq|<div style="display:block" id="tree_menu">%s</div>|, $self->left), $self->right);
    $table->setCellAttr($table->getTableRows, 1, 'class="e1"');
    $table->setCellAttr($table->getTableRows, 2, 'class="e3"');

    $result .= $table->getTableRows 
        ? $table 
        : '';

    #$result .= $self->bottom;

    $result .= $self->alter;
    $result .= $self->page_end;

    $result =~ s/\<\!\-\- spanned cell \-\-\>//g;

    log_debug(sprintf(qq|desktop ready; html code size: %s chars|, length($result)), _LOG_INTERNAL)
        if $LogEnabled;

    $result = conspiracy($result)
	if CFG->{Web}->{ConspiracyFile};

    return $result;
}

1;
