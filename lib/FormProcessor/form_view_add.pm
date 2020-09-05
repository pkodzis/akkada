package FormProcessor::form_view_add;

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

    eval
    {
        my $db = DB->new();

        die 'name empty'
            unless $url_params->{form}->{name};

        $db->exec(sprintf(qq|INSERT INTO views(name, function, id_view_type, data) VALUES('%s', '%s', %s, '%s')|, 
            $url_params->{form}->{name}, $url_params->{form}->{function}, $url_params->{form}->{id_view_type}, $url_params->{form}->{data}));

    };
    return [1, $@]
        if $@;

    return [0];
}

1;
