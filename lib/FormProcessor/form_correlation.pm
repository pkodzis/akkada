package FormProcessor::form_correlation;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

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

    return [1, 'missing disable parameter']
        unless defined $url_params->{form}->{disable};
    return [1, 'disable can be 0 or 1']
        unless $url_params->{form}->{disable} =~ /^0$|^1$/;


    my $session = session_get;

    eval
    {
        session_set_param(DB->new(), $session, '_CORRELATION', $url_params->{form}->{disable});
    };

    return [1, $@]
        if $@;

    return [0];
}

1;
