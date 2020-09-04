package Plugins::utils_node::ping;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;
use Entity;

sub available
{
    return "ping";
}

sub get
{
    my $url_params = shift;

    my $entity = Entity->new(DB->new(), $url_params->{id_entity});
    
    return "unknown entity"
        unless $entity;

    log_audit($entity, sprintf(qq|plugin %s executed|, (split /::/, __PACKAGE__,2)[1]));

    my $ip = $entity->params('ip');
    my @res;

    open F, "/bin/ping -c 8 $ip |";
    push @res, <F>;
    close F;

    return sprintf(qq|<pre>%s</pre>|, join("", @res));
}

1;
