package FormProcessor::form_options_add;

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

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $entity;
    my $db;
 
#use Data::Dumper; return "<pre>" . Dumper($url_params) . "</pre>"; 

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
            if ($param =~ /^add_/)
            {
                if ($param eq 'add_name' && $url_params->{form}->{add_name} && $url_params->{form}->{add_value} )
                {
                    $entity->params($url_params->{form}->{add_name}, $url_params->{form}->{add_value});
                    if ($url_params->{form}->{add_name} eq 'tcp_generic_script')
                    {
                        $entity->params('function', 'tcp_generic_script');
                    }
                    elsif ($url_params->{form}->{add_name} eq 'ssl_generic_script')
                    {
                        $entity->params('function', 'ssl_generic_script');
                    }
                    elsif ($url_params->{form}->{add_name} eq 'flaps_disable_monitor')
                    {
                        $entity->flaps_clear;
                    }
                    delete $url_params->{form}->{add_name};
                    delete $url_params->{form}->{add_value};
                }
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
