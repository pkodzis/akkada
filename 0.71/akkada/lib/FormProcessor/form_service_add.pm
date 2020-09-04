package FormProcessor::form_service_add;

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
use Tree;

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $entity = {};
    my $probe;
    my $session;
    my $db;

    eval
    {
        delete $url_params->{form}->{form_name};
        $db = DB->new();
        my $parent = Entity->new($db, $url_params->{form}->{id_entity});

        die "internal: cannot load parent entity"
           unless $parent;

        my $session = session_get;
        my $options = session_get_param($session, '_GENERAL_OPTIONS');

        if (defined $options && ref($options) eq 'HASH')
        {   
            $url_params->{form}->{$_} = $options->{$_}
                for (keys %$options);
        }

        $entity->{id_parent} = $url_params->{form}->{id_entity};
        delete $url_params->{form}->{id_entity};

        die "missing id_probe_type"
            unless $url_params->{form}->{id_probe_type};
        $entity->{id_probe_type} = $url_params->{form}->{id_probe_type};
        delete $url_params->{form}->{id_probe_type};
        $entity->{probe_name} = CFG->{ProbesMapRev}->{ $entity->{id_probe_type} };

    };
    return [1, $@]
        if $@;

    $probe = $entity->{probe_name};

    eval "require Probe::$probe; \$probe = Probe::${probe}->new();"
        or return [1, $@];
 
    eval
    {
       if ($url_params->{form}->{bulk})
       {
           my $parameters = $db->exec( qq|SELECT name FROM parameters| )->fetchall_hashref("name");

           my @w = split /\n/, $url_params->{form}->{bulk};

           my @s;
           for (@w)
           {
               s/\s+$//;
               next
                   unless $_;
               die sprintf(qq|syntax error: %s. it should be "parameter=value"|, $_)
                   unless /[a-z,A-Z]*=/;
               @s = split /=/, $_;
               die sprintf(qq|unknown parameter: %s|, $s[0])
                   unless defined $parameters->{$s[0]} || $s[0] eq 'name';
               die sprintf(qq|parameter %s value %s not supported during entity add process|, $s[0], $s[1])
                   if $s[1] eq '%%DELETE%%';
               $s[1] =~ s/^\s+//;
               if ($s[0] eq 'name')
               { 
                   $entity->{name} = $s[1];
               }
               else
               {
                   $entity->{params}->{$s[0]} = $s[1];
               }
           }
       }

        die "missing name"
            unless $url_params->{form}->{name} || $entity->{name};
        if (! $entity->{name})
        {
            $entity->{name} = $url_params->{form}->{name};
            delete $url_params->{form}->{name};
        }


        for (@{ $probe->mandatory_fields })
        {
            if (defined $url_params->{form}->{$_} && $url_params->{form}->{$_} ne '')
            {
                $entity->{params}->{$_} = $url_params->{form}->{$_};
                delete $url_params->{form}->{$_};
            }
            elsif (! defined $entity->{params}->{$_})
            {
                die "missing mandatory value: $_";
            }
        }

        for (keys %{ $url_params->{form} })
        {
            $entity->{params}->{$_} = $url_params->{form}->{$_}
                if ! defined $entity->{params}->{$_};
            if ($_ eq 'tcp_generic_script' && $url_params->{form}->{$_})
            {   
                $entity->{params}->{'function'} = 'tcp_generic_script';
            }
            elsif ($_ eq 'ssl_generic_script' && $url_params->{form}->{$_})
            {
                $entity->{params}->{'function'} = 'ssl_generic_script';
            }
        }

        $entity = entity_add( $entity );

        flag_files_create($TreeCacheDir, "master_hold");
        my $tree = Tree->new({db => $db, with_rights => 0});
        $tree->load_node( $entity->id_entity);
        $tree->cache_save;
        flag_file_check($TreeCacheDir, "master_hold", 1);

        
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
