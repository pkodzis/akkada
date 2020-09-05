package IP;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION );

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( get_collected_ip_addresses get_entities_in_the_same_ip_network find_mac_address get_entities_ips);
%EXPORT_TAGS = ( default => [qw( get_collected_ip_addresses get_entities_in_the_same_ip_network find_mac_address get_entities_ips)] );

use strict;
use MyException qw(:try);
use Constants;
use Configuration;
use Log;
use Data::Dumper;
use NetAddr::IP;
use DB;
use Entity;
use Common;

our $LogEnabled = CFG->{LogEnabled};
our $DataDir = CFG->{Probe}->{DataDir};
our $GrepBin = CFG->{GrepBin};

sub get_entities_ips
{
    my $dbh = shift;
    my $req = $dbh->exec(qq|SELECT entities.id_entity, value FROM entities,entities_2_parameters,parameters
        WHERE entities_2_parameters.id_parameter=parameters.id_parameter
        AND (parameters.name="ip" OR parameters.name="nic_ip")
        AND entities_2_parameters.id_entity=entities.id_entity|)->fetchall_arrayref();

    return {}
        unless @$req;

    my %result;

    @result{ map  { $_->[0] } @$req } = map { $_->[1] } @$req;

    return \%result;
}


sub get_entities_in_the_same_ip_network
{
    my $ips = shift;
    my @ip = split /\./, shift;

    my $i = $ip[0];
    my $j;

    my @tmp = grep {/^$i/} keys %$ips;

    return {}
        unless @tmp;

    for (1..3)
    {
        @tmp = grep {/^$i\.$ip[$_]/} keys %$ips;
        last
            unless @tmp;
        $j = $i;
        $i .= ".$ip[$_]";
    }

    my $nip = NetAddr::IP->new(join(".", @ip));

    for ( grep { /^$j/ } keys %$ips )
    {
        return $ips->{$_}->{ids}
            if $ips->{$_}->{obj}->contains($nip);
    }

    return {};
}

sub get_collected_ip_addresses
{
    my $db = shift;

    my @tmp = ();
    my @ip = ();
    my $res = {};
    my $res2 ={};
    my $res3 ={};
    my $id;
    my $ip;

    open(F, sprintf(qq|cd %s; %s -E "ipAddrEntry\|ipForwarding" *\| %s -v -E "\\\|\$" \||, $DataDir, $GrepBin, $GrepBin));
    while (<F>)
    {
        s/\n//g;
        s/$DataDir\///g;
        @tmp = split /:/, $_, 2;
        $id = $tmp[0];

        if (/ipAddrEntry/)
        {
	    $tmp[1] =~ s/ipAddrEntry\|//g;
            @tmp = split /#/, $tmp[1];
            for (@tmp)
            {
                @ip = split /:/, $_;
                $res->{$id}->{ips}->{$ip[0]} = $ip[1];
            }
        }
        if (/ipForwarding/)
        {
	    $tmp[1] =~ s/ipForwarding\|//g;
            $res3->{$id} = $tmp[1];
        }
    }
    closedir(F);

    my $links = $db->dbh->selectall_hashref("SELECT * FROM links", "id_child");

    for $id (keys %$res)
    {
        for (keys %{$res->{$id}->{ips}})
        {
            $ip = NetAddr::IP->new($_, $res->{$id}->{ips}->{$_});
            $res2->{$ip->network}->{ids}->{$id}->{ip} = $ip;
            $res2->{$ip->network}->{obj} = $ip;
            $res2->{$ip->network}->{ids}->{$id}->{fwd} = defined $links->{$id} && defined $res3->{$links->{$id}->{id_parent}}
                ? $res3->{$links->{$id}->{id_parent}}
                : "unknown";
            $res2->{$ip->network}->{ids}->{$id}->{pid} = defined $links->{$id} && defined $res3->{$links->{$id}->{id_parent}}
                ? $links->{$id}->{id_parent}
                : 0;
        }
    }

    return $res2;
}


sub find_mac_address
{
    my $ip = shift;

    return ['not found', undef, undef , undef, undef, undef]
        unless $ip;

    my $db = DB->new();

    my ($session, $error, $result, $entity, $oid, $flag, $count);

    my $ips_all = get_collected_ip_addresses($db);
    my $ips = get_entities_in_the_same_ip_network($ips_all, $ip);
    my $list = [];
    #for my $id_entity (keys %$ips)
    for my $id_entity (sort {$ips->{$a}->{fwd} cmp $ips->{$b}->{fwd}} keys %$ips)
    {
        next
            unless $ips->{$id_entity}->{pid};

        ++$count;
        $flag = 0;

        try
        {
            $entity = Entity->new($db, $ips->{$id_entity}->{pid});
        }
        catch  EEntityDoesNotExists with
        {
            $flag = 1;
        }
        except
        {
        };

        next
            if $flag;

        ($session, $error) = snmp_session($entity->params('ip'), $entity);

        next
            if ! $session || $error;

        push @$list, [ $entity->name, $entity->params('ip') ];

#print "checking entity ", $entity->name, "...\n";

        $session->max_msg_size(8128);
        $session->translate(['-null']);

        $result = $session->get_table(-baseoid => '.1.3.6.1.2.1.4.22.1.2');
        $error = $session->error();
        $session->close;

        next
            if $error;
        next
            unless defined $result;

        for (keys %$result)
        {
            $oid = $_;
            s/^\.1\.3\.6\.1\.2\.1\.4\.22\.1\.2//g;
            s/^\.\d+\.//g;
            return [decode_mac($result->{$oid}), $entity->id_entity, $entity->name, $entity->params('ip'), $count, $list]
                if /^$ip$/;
        }
    }
    return ['not found', undef, undef , undef, $count, $list];
}

1;
