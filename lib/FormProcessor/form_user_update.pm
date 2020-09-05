package FormProcessor::form_user_update;

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
use Configuration;

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $id = $url_params->{form}->{id_entity};
    return [1, 'unknown user']
        unless $id;
    return [1, 'unknown user']
        if $id =~ /\D/;

    eval
    {
        my $db = DB->new();
        my $user = $db->exec("select * from users where id_user=" . $id)->fetchrow_hashref;

        if ($url_params->{form}->{locked} ne $user->{locked})
        {
            $db->exec( sprintf(qq|UPDATE users SET locked=%s 
                WHERE id_user=%s|, $url_params->{form}->{locked} ? 1 : 0, $id));
        }
        if ($url_params->{form}->{password})
        {
            die 'password not match'
                unless $url_params->{form}->{password} eq $url_params->{form}->{password_confirm};
            $db->exec( sprintf(qq|UPDATE users SET password='%s' 
                WHERE id_user=%s|, crypt_pass($url_params->{form}->{password}), $id));
        }
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
