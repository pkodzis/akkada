package Plugins::utils_node::route_table;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;
use Net::SNMP qw(:snmp);
use Entity;

sub available
{
    return "route table";
}

our $ROUTE_OID = '1.3.6.1.2.1.4.21';
our $IF_OID = '1.3.6.1.2.1.2.2.1.2';
my $TAB = {};
my $IF = {};

my $_ipRoute =
{
    1 => 'ipRouteDest',
    2 => 'ipRouteIfIndex',
    3 => 'ipRouteMetric1',
    4 => 'ipRouteMetric2',
    5 => 'ipRouteMetric3',
    6 => 'ipRouteMetric4',
    7 => 'ipRouteNextHop',
    8 => 'ipRouteType',
    9 => 'ipRouteProto',
    10 => 'ipRouteAge',
    11 => 'ipRouteMask',
    12 => 'ipRouteMetric5',
    13 => 'ipRouteInfo',
};

my $_ipRouteType =
{
    1 => 'other',
    2 => 'invalid',
    3 => 'direct',
    4 => 'indirect',
};

my $_ipRouteProto =
{
    1 => 'other',
    2 => 'local',
    3 => 'netmgmt',
    4 => 'icmp',
    5 => 'egp',
    6 => 'ggp',
    7 => 'hello',
    8 => 'rip',
    9 => 'is-is',
    10 => 'es-is',
    11 => 'ciscoIgrp',
    12 => 'bbnSpfIgp',
    13 => 'ospf',
    14 => 'bgp',
};

sub get
{
    $TAB = {};
    my $url_params = shift;
    my $result = route_table_get($url_params);
    return $result
        if $result;

    return route_table_render();
}

sub route_table_render
{
    my $table = table_begin("route table", 8);

    $table->addRow( "destination", "gateway", "interface", "protocol", "type", "age", "metric", "info");

    $table->setCellAttr(2, 1, 'class="g4"');
    $table->setCellAttr(2, 2, 'class="g4"');
    $table->setCellAttr(2, 3, 'class="g4"');
    $table->setCellAttr(2, 4, 'class="g4"');
    $table->setCellAttr(2, 5, 'class="g4"');
    $table->setCellAttr(2, 6, 'class="g4"');
    $table->setCellAttr(2, 7, 'class="g4"');
    $table->setCellAttr(2, 8, 'class="g4"');

    my @row;
    for my $route (sort keys %$TAB)
    {
         @row = ();
         $route = $TAB->{$route};
         push @row, fix_ip_net($route->{ipRouteDest}, $route->{ipRouteMask});
         push @row, $route->{ipRouteNextHop};
         push @row, $route->{ipRouteIfIndex};
         push @row, $route->{ipRouteProto};
         push @row, $route->{ipRouteType};
         push @row, $route->{ipRouteAge};
         push @row, fix_metric($route);
         push @row, $route->{ipRouteInfo};
         $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
    } 

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {   
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return scalar $table;
}

sub fix_metric
{
    my $r = shift;

    my @m;
    for ( qw( ipRouteMetric1 ipRouteMetric2 ipRouteMetric3 ipRouteMetric4 ipRouteMetric5 ) )
    {
         push @m, $r->{$_}
             if $r->{$_} > -1 && $r->{$_} ne '';
    }

    return join(", ", @m);
};

sub fix_ip_net
{
    my ($ip, $mask) = @_;
    return "default"
        if $ip eq '0.0.0.0';

    my @m = split /\./, $mask;
    $mask = '';
    for(@m)
    {
       $mask = $mask . unpack("B32", pack("N", $_));
    }
    $mask =~ s/0//g;

    return sprintf(qq|%s/%s|, $ip, length($mask));
}

sub route_table_get
{
    my $url_params = shift;
    my $entity = Entity->new(DB->new(), $url_params->{id_entity});

    return "unknown entity"
        unless $entity;

    log_audit($entity, sprintf(qq|plugin %s executed|, (split /::/, __PACKAGE__,2)[1]));

    my $ip = $entity->params('ip');
    return sprintf( qq|missing ip address in entity %s|, $entity->id_entity)
        unless $ip;

    my ($session, $error) = snmp_session($ip, $entity, 1);
    if (! $session || $error)
    {
        return "snmp error: $error";
    }


    my $result = $session->get_bulk_request(
        -callback       => [\&if_cb, {}],
        -maxrepetitions => 10,
        -varbindlist    => [$IF_OID]
        );
    if (!defined($result)) 
    {
       return sprintf("ERROR 1: %s.\n", $session->error);
    }
    $session->snmp_dispatcher();

    my $result = $session->get_bulk_request(
        -callback       => [\&route_cb, {}],
        -maxrepetitions => 10,
        -varbindlist    => [$ROUTE_OID]
        );
    if (!defined($result)) 
    {
       return sprintf("ERROR 1: %s.\n", $session->error);
    }
    $session->snmp_dispatcher();

    $session->close;

    return 0;
}

sub route_cb
{
    my ($session, $table) = @_;

    if (!defined($session->var_bind_list)) 
    {
        return sprintf("ERROR 2: %s\n", $session->error);
    }
    else 
    {
        my $next;

        for my $oid (oid_lex_sort(keys(%{$session->var_bind_list}))) 
        {
            if (! oid_base_match($ROUTE_OID, $oid)) 
            {
                $next = undef;
                last;
            }
            $next = $oid;
            $table->{$oid} = $session->var_bind_list->{$oid};
        }

        if (defined($next)) 
        {
            my $result = $session->get_bulk_request(
                -callback       => [\&route_cb, $table],
                -maxrepetitions => 10,
                -varbindlist    => [$next]
                );

            if (!defined($result)) 
            {
                return sprintf("ERROR3: %s\n", $session->error);
            }
        }
        else 
        {
            my $s;
            foreach my $oid (oid_lex_sort(keys(%{$table}))) 
            {
                $s = $oid;
                $s =~ s/^$ROUTE_OID\.1\.//;
                $s = [ split /\./, $s, 2 ];
                if ($_ipRoute->{ $s->[0] } eq 'ipRouteType')
                {
                    $table->{$oid} = $_ipRouteType->{ $table->{$oid} };
                }
                elsif ($_ipRoute->{ $s->[0] } eq 'ipRouteProto')
                {
                    $table->{$oid} = $_ipRouteProto->{ $table->{$oid} };
                }
                elsif ($_ipRoute->{ $s->[0] } eq 'ipRouteIfIndex')
                {
                    $table->{$oid} = $IF->{ $table->{$oid} };
                }
                $TAB->{$s->[1]}->{ $_ipRoute->{ $s->[0] } } = $table->{$oid};
            }
        }
    }
}

sub if_cb
{
    my ($session, $table) = @_;
    
    if (!defined($session->var_bind_list))
    {
        return sprintf("ERROR 2: %s\n", $session->error);
    }   
    else
    {
        my $next;
        
        for my $oid (oid_lex_sort(keys(%{$session->var_bind_list})))
        {
            if (! oid_base_match($IF_OID, $oid))
            {
                $next = undef;
                last;
            }
            $next = $oid;
            $table->{$oid} = $session->var_bind_list->{$oid};
        }

        if (defined($next))
        {
            my $result = $session->get_bulk_request(
                -callback       => [\&if_cb, $table],
                -maxrepetitions => 10,
                -varbindlist    => [$next]
                );

            if (!defined($result))
            {
                return sprintf("ERROR3: %s\n", $session->error);
            }
        }
        else
        {
            my $s;
            foreach my $oid (oid_lex_sort(keys(%{$table})))
            {
                $s = $oid;
                $s =~ s/^$IF_OID\.//;
                $IF->{$s} = $table->{$oid};
            }
        }
    }
}

1;
