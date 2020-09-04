package Plugins::utils_node::software;

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
    return "software";
}

my $TAB = {};
my $URL_PARAMS;

our $OID = '1.3.6.1.2.1.25.6.3.1';  # process table

my $_hrSWInstalled =
{
    1 => 'hrSWInstalledIndex',
    2 => 'hrSWInstalledName',
    3 => 'hrSWInstalledID',
    4 => 'hrSWInstalledType',
    5 => 'hrSWInstalledDate',
};

my $_hrSWInstalledType =
{
    1 => 'unknown',
    2 => 'operatingSystem',
    3 => 'deviceDriver',
    4 => 'application',
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
    my $sort_order = $URL_PARAMS->{utilities_options} || 'hrSWInstalledName';

    return "not supported"
        unless keys %$TAB;

    my $table = table_begin("installed software", 4);

    $table->addRow
    ( 
         make_col_title("name", 'hrSWInstalledName'), 
         make_col_title("date", 'hrSWInstalledDate'),
         make_col_title("type", 'hrSWInstalledType'),
         make_col_title("id", 'hrSWInstalledID'),
    );

    my @row;
    for my $h ( sort 
        { 
            uc $TAB->{$a}->{$sort_order} cmp uc $TAB->{$b}->{$sort_order}
        } keys %$TAB)
    {
         @row = ();
         $h = $TAB->{$h};
         push @row, $h->{hrSWInstalledName} || '';
         push @row, $h->{hrSWInstalledDate} || '';
         push @row, $h->{hrSWInstalledType} || '';
         push @row, $h->{hrSWInstalledID} || '';
         $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
         $table->setCellAttr($table->getTableRows, 1, 'class="f"');
         $table->setCellAttr($table->getTableRows, 2, 'class="f"');
         $table->setCellAttr($table->getTableRows, 3, 'class="f"');
         $table->setCellAttr($table->getTableRows, 4, 'class="f"');
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

                if ( $_hrSWInstalled->{ $s->[0] } eq 'hrSWInstalledType')
                {
                    $table->{$oid} = $_hrSWInstalledType->{ $table->{$oid} };
                }
                elsif ( $_hrSWInstalled->{ $s->[0] } eq 'hrSWInstalledDate')
                {
                    $table->{$oid} = snmp_DateAndTime_2_str($table->{$oid});
                }
                $TAB->{ $s->[1] }->{ $_hrSWInstalled->{ $s->[0] } } = $table->{$oid};
            }
        }
    }
}

1;
