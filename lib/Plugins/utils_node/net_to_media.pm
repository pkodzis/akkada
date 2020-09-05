package Plugins::utils_node::net_to_media;

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
    return "ARP table";
}

our $OID = '.1.3.6.1.2.1.4.22';
our $IF_OID = '1.3.6.1.2.1.2.2.1.2';
my $TAB = {};
my $IF = {};

my $_ipNetToMediaEntry =
{
    1 => 'ipNetToMediaIfIndex',
    2 => 'ipNetToMediaPhysAddress',
    3 => 'ipNetToMediaNetAddress',
    4 => 'ipNetToMediaType',
};

my $_ipNetToMediaType =
{
    1 => 'other',
    2 => 'invalid',
    3 => 'dynamic',
    4 => 'static',
};

sub get
{
    $TAB = {};
    my $url_params = shift;
    my $result = table_get($url_params);
    return $result
        if $result;

    return table_render();
}

sub table_render
{
    my $table = table_begin("ARP table", 4);

    $table->addRow( "IP address", "MAC address", "interface", "type");

    $table->setCellAttr(2, 1, 'class="g4"');
    $table->setCellAttr(2, 2, 'class="g4"');
    $table->setCellAttr(2, 3, 'class="g4"');
    $table->setCellAttr(2, 4, 'class="g4"');

    my @row;
    for my $h (sort keys %$TAB)
    {
         @row = ();
         $h = $TAB->{$h};
         push @row, $h->{ipNetToMediaNetAddress};
         push @row, $h->{ipNetToMediaPhysAddress};
         push @row, $h->{ipNetToMediaIfIndex};
         push @row, $h->{ipNetToMediaType};
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

sub table_get
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
        -callback       => [\&main_cb, {}],
        -maxrepetitions => 10,
        -varbindlist    => [$OID]
        );
    if (!defined($result)) 
    {
       return sprintf("ERROR 1: %s.\n", $session->error);
    }
    $session->snmp_dispatcher();

    $session->close;

    return 0;
}

sub main_cb
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
            if (! oid_base_match($OID, $oid)) 
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
                -callback       => [\&main_cb, $table],
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
                $s =~ s/^$OID\.1\.//;
                $s = [ split /\./, $s, 2 ];

                if ($_ipNetToMediaEntry->{ $s->[0] } eq 'ipNetToMediaType')
                {
                    $table->{$oid} = $_ipNetToMediaType->{ $table->{$oid} };
                }
                elsif ($_ipNetToMediaEntry->{ $s->[0] } eq 'ipNetToMediaPhysAddress')
                {
                    $table->{$oid} = decode_mac( $table->{$oid} );
                }
                elsif ($_ipNetToMediaEntry->{ $s->[0] } eq 'ipNetToMediaIfIndex')
                {
                    $table->{$oid} = $IF->{ $table->{$oid} };
                }
                $TAB->{$s->[1]}->{ $_ipNetToMediaEntry->{ $s->[0] } } = $table->{$oid};
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
