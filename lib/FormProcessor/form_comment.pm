package FormProcessor::form_comment;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    return [1, 'empty comments not permited ;>']
        unless $url_params->{form}->{comment};

    eval {
        my $session = session_get;
        my $id_user = $session->param('_LOGGED');
        my $msg = sql_fix_string($url_params->{form}->{comment});
        my $dbh = DB->new();

        my $statement = sprintf(qq|INSERT INTO comments(id_user,id_entity,msg) VALUES(%s,%s,'%s')|, 
            $id_user,
            $url_params->{form}->{'id_entity'},
            $msg);
        $dbh->exec($statement);
        flag_files_create($TreeCacheDir, "master_hold");
        my $tree = Tree->new({db => $dbh, with_rights => 0});
        $tree->reload_node( $url_params->{form}->{'id_entity'}, 3 );
        $tree->cache_save;
        flag_file_check($TreeCacheDir, "master_hold", 1);
    };

    return [1, $@]
        if $@;

    return [0];
}

1;
