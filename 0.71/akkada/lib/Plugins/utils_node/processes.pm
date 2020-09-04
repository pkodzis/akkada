package Plugins::utils_node::processes;

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
    return "processes";
}

my $TAB = {};
my $URL_PARAMS;

our $OID = '1.3.6.1.2.1.25.4.2.1';  # process table
our $OID2 = '1.3.6.1.2.1.25.5.1.1'; # proces perf table

my $_hrSWRun =
{
    1 => 'hrSWRunIndex',
    2 => 'hrSWRunName',
    3 => 'hrSWRunID',
    4 => 'hrSWRunPath',
    5 => 'hrSWRunParameters',
    6 => 'hrSWRunType',
    7 => 'hrSWRunStatus',
};

my $_hrSWRunPerf =
{
    1 => 'hrSWRunPerfCPU',
    2 => 'hrSWRunPerfMem',
};

my $_hrSWRunStatus =
{
    1 => 'running',
    2 => 'runnable',    #-- waiting for resource -- (i.e., CPU, memory, IO)
    3 => 'notRunnable', #-- loaded but waiting for event
    4 => 'invalid',     #-- not loaded
};

my $_hrSWRunType =
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
    my $sort_order = $URL_PARAMS->{utilities_options} || 'hrSWRunIndex';

    return "not supported"
        unless keys %$TAB;

    my $table = table_begin("running processes", 9);

    $table->addRow
    ( 
         make_col_title("pid", 'hrSWRunIndex'), 
         make_col_title("name", 'hrSWRunName'), 
         make_col_title("status", 'hrSWRunStatus'),
         make_col_title("memory<br>size", 'hrSWRunPerfMem'),
         make_col_title("CPU<br>usage", 'hrSWRunPerfCPU'),
         make_col_title("type", 'hrSWRunType'),
         make_col_title("path", 'hrSWRunPath'),
         make_col_title("parameters", 'hrSWRunParameters'),
         make_col_title("product ID", 'hrSWRunID'),
    );

    my @row;
    #for my $h ( sort { uc $TAB->{$a}->{hrSWRunName} cmp uc $TAB->{$b}->{hrSWRunName} } keys %$TAB)
    for my $h ( sort 
        { 
            ($sort_order eq 'hrSWRunIndex' || ! defined $TAB->{$b}->{$sort_order})
                ? $a <=> $b 
            : $sort_order eq 'hrSWRunPerfMem'
                ? $TAB->{$b}->{hrSWRunPerfMem} <=> $TAB->{$a}->{hrSWRunPerfMem}
            : $sort_order eq 'hrSWRunPerfCPU'
                ? $TAB->{$b}->{hrSWRunPerfCPU} <=> $TAB->{$a}->{hrSWRunPerfCPU}
                : uc $TAB->{$a}->{$sort_order} cmp uc $TAB->{$b}->{$sort_order}
    
        } keys %$TAB)
    {
         @row = ();
         $h = $TAB->{$h};
         push @row, $h->{hrSWRunIndex} || '';
         push @row, $h->{hrSWRunName} || '';
         push @row, $h->{hrSWRunStatus} || '';
         push @row, format_bytes($h->{hrSWRunPerfMem}*1024) || '';
         push @row, (split / /, timeticks_2_duration($h->{hrSWRunPerfCPU}))[2] || '';
         push @row, $h->{hrSWRunType} || '';
         push @row, $h->{hrSWRunPath} || '';
         push @row, $h->{hrSWRunParameters} || '';
         push @row, $h->{hrSWRunID} || '';
         $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
         $table->setCellAttr($table->getTableRows, 2, 'class="f"');
         $table->setCellAttr($table->getTableRows, 7, 'class="f"');
         $table->setCellAttr($table->getTableRows, 8, 'class="f"');
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

    if (! keys %$TAB)
    {
        $session->close;
        return 0;
    }

    $result = $session->get_bulk_request(
        -callback       => [\&perf_cb, {}],
        -maxrepetitions => 10,
        -varbindlist    => [$OID2]
        );
    if (!defined($result))
    {
       return sprintf("ERROR 2: %s.\n", $session->error);
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
                $s = [ split /\./, $s, 2 ];

                if ( $_hrSWRun->{ $s->[0] } eq 'hrSWRunStatus')
                {
                    $table->{$oid} = $_hrSWRunStatus->{ $table->{$oid} };
                }
                elsif ( $_hrSWRun->{ $s->[0] } eq 'hrSWRunType')
                {
                    $table->{$oid} = $_hrSWRunType->{ $table->{$oid} };
                }
                $TAB->{ $s->[1] }->{ $_hrSWRun->{ $s->[0] } } = $table->{$oid};
            }
        }
    }
}

sub perf_cb
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
            if (! oid_base_match($OID2, $oid))
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
                -callback       => [\&perf_cb, $table],
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
                $s =~ s/^$OID2\.//;
                $s = [ split /\./, $s, 2 ];
                $TAB->{ $s->[1] }->{ $_hrSWRunPerf->{ $s->[0] } } = $table->{$oid};
            }
        }
    }
}

1;
