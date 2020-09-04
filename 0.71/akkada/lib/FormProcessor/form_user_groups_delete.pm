package FormProcessor::form_user_groups_delete;

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

    eval
    {   
        my $db = DB->new();
        my $user = $db->exec("select * from users where id_user=" . $id)->fetchrow_hashref;

        my $change = 0;

        for my $param (keys %{ $url_params->{form} })
        {
            next
                if $param eq 'form_name';
            next
                if $param eq 'id_entity';

            if ($param =~ /^delete_/)
            {
                $param =~ s/^delete_//g;
                $db->exec( sprintf(qq|DELETE FROM users_2_groups WHERE id_group=%s AND id_user=%s|, $param, $id) );
                ++$change;
            }
        }
        flag_files_create($TreeCacheDir, "rights_init")
            if $change;
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
