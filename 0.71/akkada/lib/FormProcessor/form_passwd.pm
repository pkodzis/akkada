package FormProcessor::form_passwd;

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

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $session = session_get;

    my $id = $session->param('_LOGGED');
    return [1, 'unknown user']
        unless $id;

    eval
    {
        my $db = DB->new();
        my $user = $db->exec("select * from users where id_user=" . $id)->fetchrow_hashref;

        die 'bad old password'
            unless crypt_pass($url_params->{form}->{password_old}) eq $user->{password};
        die 'password cannot be empty'
            unless $url_params->{form}->{password_new};
        die 'password not match'
            unless $url_params->{form}->{password_new} eq $url_params->{form}->{password_new_confirm};
        $db->exec( sprintf(qq|UPDATE users SET password='%s' 
            WHERE id_user=%s|, crypt_pass($url_params->{form}->{password_new}), $id));
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
