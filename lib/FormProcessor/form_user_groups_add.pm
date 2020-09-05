package FormProcessor::form_user_groups_add;

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
        $db->exec( sprintf(qq|INSERT INTO users_2_groups VALUES(%s,%s)|, $id, $url_params->{form}->{id_group}) );
        flag_files_create($TreeCacheDir, "rights_init");
    };

    return [1, $@]
        if $@;

    return [0];
}

1;
