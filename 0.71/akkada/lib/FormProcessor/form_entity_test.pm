package FormProcessor::form_entity_test;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Entity;
use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Configuration;
use Common;


our $FlagsControlDir = CFG->{FlagsControlDir};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $id = $url_params->{form}->{id_entity};
    #my $id = $url_params->{id_entity};
    return [1, 'unknown entity']
        unless $id;
    return [1, 'unknown entity']
        if $id =~ /\D/;

    eval
    {   
        my $session = session_get;

        my $db = DB->new();
        my $req = $db->exec( sprintf(qq|SELECT * FROM force_test WHERE id_entity=%s|, $id) )->fetchall_hashref('id_entity');

        if (keys %$req)
        {
            die "force test already in progress. please try again later!";
        }
        
        $db->exec( sprintf(qq|INSERT INTO force_test VALUES(%s, NOW(), %s, '%s')|,
            $id, $session->param('_LOGGED'), $session->param('_SESSION_REMOTE_ADDR')) );

        flag_files_create($FlagsControlDir, 'force_test.' . $id);

#        my $entity;
#        
#        eval
#        {   
#            $entity = Entity->new($db, $id);
#        };    
#        $entity->status_calc_flag_create($id);
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
