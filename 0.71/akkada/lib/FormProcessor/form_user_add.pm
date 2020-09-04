package FormProcessor::form_user_add;

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

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $id = $url_params->{form}->{id_entity};
    return [1, 'unknown user']
        unless $id;
    return [1, 'unknown user']
        if $id =~ /\D/;

    my $id_group = $url_params->{form}->{id_group};
    return [1, 'select group']
        unless $id_group;
    return [1, 'unknown group']
        if $id_group=~ /\D/;

    eval
    {
        my $db = DB->new();

        die 'username empty'
            unless $url_params->{form}->{username};
        die 'password empty'
            unless $url_params->{form}->{password};
        die 'password not match'
            unless $url_params->{form}->{password} eq $url_params->{form}->{password_confirm};

        $db->exec(sprintf(qq|INSERT INTO users(id_user,username,password,locked) VALUES(%s,'%s','%s',%s)|,
            $id,
            $url_params->{form}->{username},
            crypt_pass($url_params->{form}->{password}),
            $url_params->{form}->{locked} ? 1 : 0,
        ));
        $db->exec(sprintf(qq|INSERT INTO users_2_groups VALUES(%s,%s)|, $id, $id_group));
        flag_files_create($TreeCacheDir, "rights_init");
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
