package FormProcessor::form_test;

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

    my $dbh = DB->new();

    my $entity;

    $entity = Entity->new(DB->new(), $url_params->{id_entity});

    my $probe = CFG->{ProbesMapRev}->{ $entity->id_probe_type };
    eval "require Probe::$probe; \$probe = Probe::${probe}->new();" or return [1, 'B:' . $@];

    $probe->entity_test($entity);
    $entity->db_update_entity;
sleep 5;
    $probe->entity_test($entity);
    $entity->db_update_entity;

    return [0];
}

1;
