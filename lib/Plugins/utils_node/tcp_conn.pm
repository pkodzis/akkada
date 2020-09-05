package Plugins::utils_node::tcp_conn;

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
    return "TCP connections";
}

our $OID = '.1.3.6.1.2.1.6.13';
my $TAB = {};

my $_tcpConnEntry =
{
    1 => 'tcpConnState',
    2 => 'tcpConnLocalAddress',
    3 => 'tcpConnLocalPort',
    4 => 'tcpConnRemAddress',
    5 => 'tcpConnRemPort',
};

my $_tcpConnState =
{
    1 => 'closed',
    2 => 'listen',
    3 => 'synSent',
    4 => 'synReceived',
    5 => 'established',
    6 => 'finWait1',
    7 => 'finWait2',
    8 => 'closeWait',
    9 => 'lastAck',
    10 => 'closing',
    11 => 'timeWait',
    12 => 'deleteTCB',
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
    return "not supported"
        unless keys %$TAB;

    my $table = table_begin("TCP connections", 5);

    $table->addRow( "local<br>address", "local<br>port", "remote<br>address", "remote<br>port", "state");

    $table->setCellAttr(2, 1, 'class="g4"');
    $table->setCellAttr(2, 2, 'class="g4"');
    $table->setCellAttr(2, 3, 'class="g4"');
    $table->setCellAttr(2, 4, 'class="g4"');
    $table->setCellAttr(2, 5, 'class="g4"');

    my @row;
    for my $h ( keys %$TAB)
    {
         @row = ();
         $h = $TAB->{$h};
         push @row, $h->{tcpConnLocalAddress};
         push @row, $h->{tcpConnLocalPort};
         push @row, $h->{tcpConnRemAddress};
         push @row, $h->{tcpConnRemPort};
         push @row, $h->{tcpConnState};
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

                if ( $_tcpConnEntry->{ $s->[0] } =~  /Address/ )
                {
                    $table->{$oid} = '*'
                        if $table->{$oid} eq '0.0.0.0';
                }
                elsif ( $_tcpConnEntry->{ $s->[0] } =~  /Port/ )
                {
                    $table->{$oid} = $table->{$oid} eq '0'
                        ? '*'
                        : getservbyport($table->{$oid}, 'tcp') || $table->{$oid};
                }
                elsif ( $_tcpConnEntry->{ $s->[0] } eq 'tcpConnState')
                {
                    $table->{$oid} = $_tcpConnState->{ $table->{$oid} };
                }
                $TAB->{ $s->[1] }->{ $_tcpConnEntry->{ $s->[0] } } = $table->{$oid};
            }
        }
    }
}

1;
