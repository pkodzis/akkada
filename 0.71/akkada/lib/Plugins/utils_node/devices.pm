package Plugins::utils_node::devices;

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
use Number::Format qw(:subs);

$Number::Format::DECIMAL_FILL = 1;

sub available
{
    return 'hardware';
}

my $TAB = {};
my $URL_PARAMS;

our $OID = '1.3.6.1.2.1.25.3.2.1'; 

my $_hrDeviceEntry =
{
     1 => 'hrDeviceIndex',
     2 => 'hrDeviceType',
     3 => 'hrDeviceDescr',
     4 => 'hrDeviceID',
     5 => 'hrDeviceStatus',
     6 => 'hrDeviceErrors',
};

my $_hrDeviceType =
{
    1 => 'other',
    2 => 'unknown',
    3 => 'processor',
    4 => 'network',
    5 => 'printer',
    6 => 'disk drive',
    10 => 'video',
    11 => 'audio',
    12 => 'coprocessor',
    13 => 'keyboard',
    14 => 'modem',
    15 => 'parallel port',
    16 => 'pointing',
    17 => 'serial port',
    18 => 'type',
    19 => 'clock',
    20 => 'volatile memory',
    21 => 'non-volatile memory',
};

my $_hrDeviceStatus =
{
    1 => 'unknown',
    2 => 'running',
    3 => 'warning',
    4 => 'testing',
    5 => 'down',
};

sub get
{
    $TAB = {};
    $URL_PARAMS = shift;
    my $result = table_get();
    return $result
        if $result;

    return table_render();
}

sub make_col_title
{
    my ($name, $order) = @_;
    return sprintf(qq|<a class="g4" href="%s">%s</a>|,
        url_get({ utilities_options => $order }, $URL_PARAMS),
        $name);

}

sub table_render
{
    my $sort_order = $URL_PARAMS->{utilities_options} || 'hrDeviceType';

    return "not supported"
        unless keys %$TAB;

    my $table = table_begin("devices", 5);

    $table->addRow
    ( 
         make_col_title("type", 'hrDeviceType'),
         make_col_title("description", 'hrDeviceDescr'), 
         make_col_title("status", 'hrDeviceStatus'),
         make_col_title("errors", 'hrDeviceErrors'),
         make_col_title("id", 'hrDeviceID'),
    );

    my @row;
    for my $h ( sort 
        { 
            uc $TAB->{$a}->{$sort_order} cmp uc $TAB->{$b}->{$sort_order}
        } keys %$TAB)
    {
         @row = ();
         $h = $TAB->{$h};
         push @row, $h->{hrDeviceType} || '';
         push @row, $h->{hrDeviceDescr} || '';
         push @row, defined $h->{hrDeviceStatus} ? $h->{hrDeviceStatus} : 'n/a';
         push @row, defined $h->{hrDeviceErrors} ? $h->{hrDeviceErrors} : 'n/a';
         push @row, $h->{hrDeviceID} || '';
         $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
         $table->setCellAttr($table->getTableRows, 1, 'class="f"');
         $table->setCellAttr($table->getTableRows, 2, 'class="f"');
         $table->setCellAttr($table->getTableRows, 3, 'class="f"');
         $table->setCellAttr($table->getTableRows, 4, 'class="f"');
         $table->setCellAttr($table->getTableRows, 5, 'class="f"');
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
    my $entity = Entity->new(DB->new(), $URL_PARAMS->{id_entity});

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
                $s =~ s/^$OID\.//;
                $s = [ split /\./, $s, 2 ];
                if ( $_hrDeviceEntry->{ $s->[0] } eq 'hrDeviceType')
                {
                    $table->{$oid} =~ s/^1\.3\.6\.1\.2\.1\.25\.3\.1\.//g;
                    $table->{$oid} = $_hrDeviceType->{ $table->{$oid} };
                }
                elsif ( $_hrDeviceEntry->{ $s->[0] } eq 'hrDeviceStatus')
                {
		    $table->{$oid} = $_hrDeviceStatus->{ $table->{$oid} };
                }
                $TAB->{ $s->[1] }->{ $_hrDeviceEntry->{ $s->[0] } } = $table->{$oid};
            }
        }
    }
}

1;
