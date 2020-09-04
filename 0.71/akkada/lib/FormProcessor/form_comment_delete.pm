package FormProcessor::form_comment_delete;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;
use CGI::Session;

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    eval {
        my $dbh = DB->new();

        return 'bad comment id'
            if $url_params->{form}->{'id_comment'} eq '' || $url_params->{form}->{'id_comment'} =~ /\D/;
        my $statement = sprintf(qq|DELETE FROM comments WHERE id_comment=%s|, $url_params->{form}->{'id_comment'});
        $dbh->exec($statement);

        flag_files_create($TreeCacheDir, "master_hold");
        my $tree = Tree->new({db => $dbh, with_rights => 0});
        $tree->reload_node( $url_params->{form}->{id_entity}, 3 );
        $tree->cache_save;
        flag_file_check($TreeCacheDir, "master_hold", 1);

    };

    return [1, $@]
        if $@;

    return [0];
}

1;
