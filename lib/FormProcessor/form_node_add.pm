package FormProcessor::form_node_add;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Entity;
use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Tree;
use Common;
use Socket;

our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

sub process
{
    my $url_params = shift;
    my $oparams = {};

    $url_params = url_dispatch( $url_params );

    eval {

       my $db = DB->new();

       my $entity = 
       {
           probe_name => 'node',
           name => $url_params->{form}->{name},
           id_parent => $url_params->{form}->{id_parent},
       };

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
               die sprintf(qq|parameter %s value %s not supported during entity add process|, $s[0], $s[1])
                   if $s[1] eq '%%DELETE%%';
               $s[1] =~ s/^\s+//;
               $entity->{params}->{$s[0]} = $s[1];
           }
       }

       die "missing ip address or DNS host name"
           unless $url_params->{form}->{ip} || $entity->{params}->{ip};

       $entity->{params}->{ip} = $url_params->{form}->{ip}
           if ! defined $entity->{params}->{ip};

       if ($entity->{params}->{ip} !~ /\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/)
       {
           #no ip address -> try to resolve DNS name;
           my $address = inet_aton($entity->{params}->{ip});
           if (defined $address)
           {
               $address = inet_ntoa($address);
               $address = undef
                   unless $address =~ /\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/;
           }

           if (! defined $address)
           {
               die "it's not possible to resolve a DNS name or ip address is not valid"
           }

           $entity->{params}->{ip} = $address;

       }

       if (my $tmp_name = check_node_duplicate($db, $entity->{params}->{ip}))
       {
           die "operation failed. node with ip address " . $entity->{params}->{ip} 
               . " already exists in AKK\@DA configuration. It's name is " . $tmp_name;
       }

       $entity->{params}->{snmp_port} = $url_params->{form}->{snmp_port}
           if ! defined $entity->{params}->{snmp_port} && $url_params->{form}->{snmp_port};

       $entity->{params}->{snmp_community_ro} = $url_params->{form}->{snmp_community_ro}
           if ! defined $entity->{params}->{snmp_community_ro} && $url_params->{form}->{snmp_community_ro};

       $entity->{params}->{snmp_user} = $url_params->{form}->{snmp_user}
           if ! defined $entity->{params}->{snmp_user} && $url_params->{form}->{snmp_user};

       $entity->{params}->{snmp_authpassword} = $url_params->{form}->{snmp_authpassword}
           if ! defined $entity->{params}->{snmp_authpassword} && $url_params->{form}->{snmp_authpassword};

       $entity->{params}->{snmp_authprotocol} = $url_params->{form}->{snmp_authprotocol}
           if ! defined $entity->{params}->{snmp_authprotocol} && $url_params->{form}->{snmp_authprotocol};

       $entity->{params}->{snmp_privpassword} = $url_params->{form}->{snmp_privpassword}
           if ! defined $entity->{params}->{snmp_privpassword} && $url_params->{form}->{snmp_privpassword};

       $entity->{params}->{snmp_privprotocol} = $url_params->{form}->{snmp_privprotocol}
           if ! defined $entity->{params}->{snmp_privprotocol} && $url_params->{form}->{snmp_privprotocol};

       $entity->{params}->{snmp_version} = $url_params->{form}->{snmp_version}
           if ! defined $entity->{params}->{snmp_version} && $url_params->{form}->{snmp_version};

       $entity->{params}->{dont_discover} = 1
           if ! defined $entity->{params}->{dont_discover} && $url_params->{form}->{dont_discover};

       $entity->{params}->{availability_check_disable} = 1
           if ! defined $entity->{params}->{availability_check_disable} && $url_params->{form}->{availability_check_disable};

       if (defined $url_params->{form}->{check_snmp} && $url_params->{form}->{check_snmp})
       {
           my $res = check_snmp($entity);
           die $res
               if $res;
       }

       $entity = entity_add( $entity );
       flag_files_create($TreeCacheDir, "master_hold");
       my $tree = Tree->new({db => $db, with_rights => 0});
       $tree->load_node( $entity->id_entity);
       flag_file_check($TreeCacheDir, "master_hold", 1);
    };
    return [1, $@]
        if $@;

    return [0];
}

sub check_snmp
{
    my $params = shift;
    my $entity;

    eval
    {
        $entity = Entity->new(DB->new(), $params->{id_parent});
    };

    return [1, "internal: cannot load entity"]
        unless $entity;

    for (keys %{$params->{params}})
    {
        $entity->param_set_temp($_, $params->{params}->{$_});
    }

    my $instances_count = get_param_instances_count($entity->params('snmp_version'));

    my ($session, $error, $res);
 
    for my $i (0..$instances_count)
    {
        $entity->param_set_temp('snmp_instance', $i);

        ($session, $error) = snmp_session($entity->params('ip'), $entity);

        if (! $error)
        {
            $res = $session->get_request( -varbindlist => ['1.3.6.1.2.1.1.2.0'] );
            $error = $session->error;

            if ($error)
            {
                 return sprintf(qq|snmp instance %s error: %s|, $i, $error);
            }
            elsif (! $res)
            {
                 return sprintf(qq|snmp instance %s host %s did not answer on SNMP request|, $i, $entity->params('ip'));
            }
        }
        else
        {
            return sprintf(qq|snmp instance %s error: %s|, $i, $error);
        }
    }

    return '';
}


1;
