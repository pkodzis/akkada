package Plugins::utils_node::cisco_processes;

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
    return $_[0] =~ /^1\.3\.6\.1\.4\.1\.9/ ? 'cisco processes' : 0;
}

my $TAB = {};
my $URL_PARAMS;

our $OID = '1.3.6.1.4.1.9.9.109.1.2.1.1';

my $_cpmProcessEntry =
{
    1 => 'cpmProcessPID',
    2 => 'cpmProcessName',
    4 => 'cpmProcessuSecs',
    5 => 'cpmProcessTimeCreated',
    6 => 'cpmProcessAverageUSecs ',
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
#use Data::Dumper; return Dumper $TAB;
    my $sort_order = $URL_PARAMS->{utilities_options} || 'cpmProcessPID';

    return "not supported"
        unless keys %$TAB;

    my $table = table_begin("running processes", 5);

    $table->addRow
    ( 
         make_col_title("pid", 'cpmProcessPID'), 
         make_col_title("name", 'cpmProcessName'), 
         make_col_title("CPU<br>time", 'cpmProcessuSecs'),
         make_col_title("avg<br>CPU<br>time", 'cpmProcessAverageUSecs'),
         make_col_title("start<br>time", 'cpmProcessTimeCreated'),
    );

    my @row;
    for my $h ( sort 
        { 
            ($sort_order eq 'cpmProcessPID' || ! defined $TAB->{$b}->{$sort_order})
                ? $a <=> $b 
            : $sort_order eq 'cpmProcessuSecs'
                ? $TAB->{$b}->{$sort_order} <=> $TAB->{$a}->{$sort_order}
            : $sort_order eq 'cpmProcessAverageUSecs'
                ? $TAB->{$b}->{$sort_order} <=> $TAB->{$a}->{$sort_order}
                : uc $TAB->{$a}->{$sort_order} cmp uc $TAB->{$b}->{$sort_order}
    
        } keys %$TAB)
    {
         @row = ();
         $h = $TAB->{$h};
         push @row, $h->{cpmProcessPID} || '';
         push @row, $h->{cpmProcessName};
         push @row, $h->{cpmProcessuSecs};
         push @row, $h->{cpmProcessAverageUSecs};
         push @row, (split / /, timeticks_2_duration($h->{cpmProcessTimeCreated}))[2];
         $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
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
                $s =~ s/^$OID\.//;
                $s = [ split /\./, $s, 3 ];
#$TAB->{$oid} = $table->{$oid};
                $TAB->{ $s->[2] }->{ $_cpmProcessEntry->{ $s->[0] } } = $table->{$oid};
            }
        }
    }
}

1;
