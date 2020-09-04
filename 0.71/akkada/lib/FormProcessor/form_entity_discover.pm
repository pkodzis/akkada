package FormProcessor::form_entity_discover;

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
use Data::Dumper;
use Common;

our $Probes = {};
our $ProbesMap = CFG->{ProbesMap};
our $ProbesMapRev = CFG->{ProbesMapRev};

sub load_probes
{
    for my $probe ( keys %$ProbesMap )
    {   
        eval "require Probe::$probe; \$Probes->{\$probe} = Probe::${probe}->new();";
    }
}

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $id = $url_params->{form}->{id_entity};
    return [1, 'unknown entity']
        unless $id;
    return [1, 'unknown entity']
        if $id =~ /\D/;

    my $id_probe_type = $url_params->{form}->{id_probe_type};
    return [1, 'unknown probe']
        unless defined $id_probe_type;
    return [1, 'unknown probe id']
        if $id_probe_type =~ /\D/;

    my $db = DB->new();
    my $session = session_get();
    my $vm = session_get_param($session, '_VIEW_MODE');
    if ($vm != _VM_TREE && $vm != _VM_TREE_LIGHT)
    {
         session_set_param($db, $session, '_VIEW_MODE', _VM_TREE);
    }

    my $pr = {};

    for (keys %$ProbesMap)
    {  
       $pr->{ $ProbesMap->{ $_ } } = $_;
    }

    my @pr_list;
    if ($id_probe_type)
    {
        return [1, 'unknown discover probe']
            unless defined $pr->{$id_probe_type};
        push @pr_list, $id_probe_type;
    }
    else
    {
        @pr_list = keys %$pr;
    }

    load_probes();

    my $errors;

    eval
    {   
        my $session = session_get;

        my $db = DB->new();

        my $entity = Entity->new($db, $url_params->{form}->{id_entity});
        die "internal: cannot load entity"
            unless $entity;

        my $req = $db->exec( sprintf(qq|SELECT * FROM discover WHERE id_entity=%s AND (%s)|,
            $id, join(' OR ', map {"id_probe_type=$_"} @pr_list) ) )->fetchall_hashref('id_probe_type');

        if (keys %$req)
        {
            die "discover already in progress for probes: " 
                . join(", ", map { $ProbesMapRev->{$_} } keys %$req) 
                . ". please try again later!";
        }

        my $mp;        
        my $param;
        my $ok;
        for my $id_probe_type (@pr_list)
        {
            $mp = $Probes->{ $ProbesMapRev->{$id_probe_type} }->discover_mandatory_parameters;
            for $param (@$mp)
            {
                $ok = 0; 

                $ok = 1
                    if ! ref($param) && defined $entity->params($param);

                if (ref($param))
                {
                    for (@$param)
                    {
                        $ok = 1
                            if defined $entity->params($_);
                    }
                }

                $errors .= "probe $ProbesMapRev->{$id_probe_type} will not be discovered because of missing mandatory parameters. mandatory parameters which should be defined no host are: "
                    . join(", ", @$mp) . ".<p>"
                    unless $ok;
            }
            $db->exec( sprintf(qq|INSERT INTO discover VALUES(%s, %s, NOW(), %s, '%s')|,
                $id_probe_type, $id, $session->param('_LOGGED'), $session->param('_SESSION_REMOTE_ADDR')) )
                if $ok;
        }
    };
    return [1, $@]
        if $@;

    return [0, $errors];
}

1;
