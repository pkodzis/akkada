package FormProcessor::form_groups_add;

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

    return [1, 'missing group name']
        unless $url_params->{form}->{name};

    eval
    {
        my $dbh = DB->new();
        $dbh->exec( sprintf(qq|INSERT INTO groups(name) VALUES('%s')|, $url_params->{form}->{name}) );
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
