package FormProcessor::form_parameters_modify;

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
  
    eval
    {
        $db = DB->new();
        $entity = Entity->new($db, $url_params->{form}->{id_entity});
    };

    return [1, "internal: cannot load entity"]
        unless $entity;


    my $probe =  CFG->{ProbesMapRev}->{ $entity->id_probe_type };

    eval "require Probe::$probe; \$probe = Probe::${probe}->new();"
        or return [1, $@];

    eval {
       my $p = {};
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
                   unless defined $parameters->{$s[0]};
               die qq|cannot delete parameter ip|
                   if $s[0] eq 'ip' && $s[1] eq '%%DELETE%%';
               $s[1] =~ s/^\s+//;
               $p->{$s[0]} = $s[1];
           }
       }

        for (@{ $probe->mandatory_fields })
        {
            if (defined $p->{$_} && $p->{$_} eq '%%DELETE%%')
            {
                die "cannot delete mandatory parameters: $_";
            }
        }

       for my $name (keys %$p)
       {
           if ($p->{$name} eq '%%DELETE%%')
           {
               if (! defined $entity->params_own->{$name})
               {
                   if ($entity->params($name))
                   {
                       die sprintf(qq|parameter %s is inherited from parent. cannot be deleted on the child.\n|, $name);
                   }
                   die sprintf(qq|parameter %s is not set. cannot be deleted.\n|, $name);
               }
               $entity->params_delete($name, 0);
               if ($name eq 'tcp_generic_script')
               {
                   $entity->params_delete('function', 0);
               }
               elsif ($name eq  'ssl_generic_script')
               {
                   $entity->params_delete('function', 0);
               }
           }
           else
           {
               $entity->params($name, $p->{$name}, 0);
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
