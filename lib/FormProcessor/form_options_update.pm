package FormProcessor::form_options_update;

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

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};


our $CMDMode = 0;

sub process
{
    my $url_params = shift;

    if (! $CMDMode)
    {
        $url_params = url_dispatch();
    }

    my $entity;
    my $db;
  
    eval
    {
        $db = DB->new();
        $entity = Entity->new($db, $url_params->{form}->{id_entity});
    };

    return [1, "internal: cannot load entity"]
        unless $entity;

    eval {
        for my $param (keys %{ $url_params->{form} })
        {
            next
                if $param eq 'form_name';
            next
                if $param eq 'id_entity';

            if ($param =~ /^delete_/)
            {
                $param =~ s/^delete_//g;
                $entity->params_delete($param, 0);
                delete $url_params->{form}->{$param};
                if ($param eq 'tcp_generic_script')
                {
                    $entity->params_delete('function', 0);
                    delete $url_params->{form}->{function};
                }
                elsif ($param eq  'ssl_generic_script')
                {
                    $entity->params_delete('function', 0);
                    delete $url_params->{form}->{function};
                }
            }
            else
            {
                $entity->params($param, $url_params->{form}->{$param}, 0);
            }
        }
        flag_files_create($TreeCacheDir, "master_hold");
        my $tree = Tree->new({db => $db, with_rights => 0});
        $tree->reload_node( $entity->id_entity, 1 );
        $tree->cache_save;
        flag_file_check($TreeCacheDir, "master_hold", 1);
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
