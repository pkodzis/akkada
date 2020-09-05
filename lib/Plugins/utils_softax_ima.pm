package Plugins::utils_softax_ima;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;

our $FormDispatcher =
{
    1 => \&chat,
};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $id = $url_params->{form_id};
    return [1, 'unknown form']
        unless $id;
    return [1, 'unknown form']
        if $id =~ /\D/;

    return [0, $FormDispatcher->{$id}($url_params)];

}

sub chat
{
    my $url_params = shift;
    our $DataDir = CFG->{Probe}->{DataDir};

    my @result;

    open F, sprintf(qq|%s/%s.chat|, $DataDir, $url_params->{id_entity}) || return 'no result available';
    push @result, <F>;
    close F;

    return @result
        ? join('', qq|<textarea NAME="txt" ROWS=20 COLS=75 WRAP=VIRTUAL>|, @result, '</textarea>')
        : 'no result available';
}

1;
