package Tools::time_synchronization_report;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use Common;
use Window::Buttons;
use Desktop::GUI;
use DB;
use Entity;
use Time::Local;
use HTML::Table;
use Configuration;

use Data::Dumper;
use Log;

our $Config = do "$ENV{AKKADA}/etc/Tools/time_synchronization_report.conf";
our $ProbesMapRev = CFG->{ProbesMapRev};
our $ImagesDir = CFG->{ImagesDir};

sub image_function
{
    my $function = shift;
    $function = 'host'
        unless $function;
    my $alt = shift || '';

    my $img = -e "$ImagesDir/$function.gif"
        ? "/img/$function.gif"
        : "/img/unknown.gif";
    return CGI::img({ src=>$img, class => 'o', alt => $alt ? $alt : "function: $function"});
}

sub image_vendor
{
    my $vendor = shift || '';

    return ''
        unless $vendor;

    my $img = -e "$ImagesDir/$vendor.gif"
        ? "/img/$vendor.gif"
        : "/img/unknown.gif";
    return CGI::img({ src=>$img, class => 'o', alt => "vendor: $vendor"})
}

sub desc
{
    return <<EOF;
generate time synchronization report for all hosts configured in <b>akk\@da</b>.<p>
it uses SNMP to collect current host time. If host supports NTP and has configured NTP,<br>
also NTP synchronization status is checked.<p>
report's generation can take a few minutes, if your network is large.<p>
EOF
}

sub button_start
{
    my $url_params = shift;
    $url_params = url_dispatch( $url_params );

    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $buttons->add({ caption => 'start' , url => url_get({section => 'tool', start => 1}, $url_params), });
    $buttons->add({ caption => 'start in separate window' , target => $url_params->{tool_name},
        url => url_get({section => 'tool', start => 1}, $url_params), });
    return $buttons->get;
}

sub run
{
    my $url_params = shift;
    $url_params = url_dispatch( $url_params );

    my $db = DB->new();
    my $dbh = $db->dbh;

    $url_params->{options} = 2
        unless defined $url_params->{options} && $url_params->{options};

    my $items = $dbh->selectall_hashref("select entities.id_entity,entities.name,value as ip, status as entity_status,id_probe_type from entities,parameters,entities_2_parameters where parameters.name='ip' and entities_2_parameters.id_parameter = parameters.id_parameter and entities.id_entity=entities_2_parameters.id_entity and entities.id_probe_type=1", "id_entity");

    my $items_ntp = $dbh->selectall_hashref("select status,entities.id_entity,entities.name,id_probe_type,id_parent from entities,links where id_probe_type=25 and id_entity in (select id_child from links) and entities.id_entity=links.id_child", "id_entity");

    my $items_functions = $dbh->selectall_hashref("select entities.id_entity,value from entities,entities_2_parameters where id_parameter=16 and entities.id_entity = entities_2_parameters.id_entity", "id_entity");
    my $items_vendors = $dbh->selectall_hashref("select entities.id_entity,value from entities,entities_2_parameters where id_parameter=15 and entities.id_entity = entities_2_parameters.id_entity", "id_entity");

    my $entity;
    my $s;
    my $item;
    my $id_entity;
    my @d;
    my $auth;


    for $id_entity (keys %$items_ntp)
    {
        $entity = Entity->new( $db, $id_entity, 1);
        $s = $entity->data;

        $auth = undef;

        if ( ! defined $s->{raw} || ! $s->{raw})
        {
            $s = 'information not collected';
        }
        else
        {
            $s = $s->{raw};
            $auth = auth_time_sources($s, $entity->params('ip'));
            $s =~ s/::/<br>/g;
            $s = sprintf(qq|<pre>%s|, $s);
            #$s = sprintf(qq|<div class="x9">%s</div>|, $s);
        }

        $items->{ $items_ntp->{$id_entity}->{id_parent} }->{ntp} = $s;
        $items->{ $items_ntp->{$id_entity}->{id_parent} }->{ntp_status} = $entity->status;
        $items->{ $items_ntp->{$id_entity}->{id_parent} }->{ntp_auth} = $auth;
    }

    my $session;
    my $error;
    my $result;

    my $oid = '1.3.6.1.2.1.25.1.2.0';

    for $id_entity (keys %$items)
    {
        next
            unless defined $items->{$id_entity}->{ip} 
                && $items->{$id_entity}->{ip} 
                && $items->{$id_entity}->{entity_status} != _ST_NOSNMP 
                && $items->{$id_entity}->{entity_status} != _ST_UNREACHABLE;

        $entity = Entity->new( $db, $id_entity);
        ($session, $error) = snmp_session($items->{$id_entity}->{ip}, $entity);

        next
            if $error;

        $session->max_msg_size(2944);
        $items->{$id_entity}->{tstart} = time;
        $result = $session->get_request( -varbindlist => [$oid] );
        $items->{$id_entity}->{tstop} = time;
        $error = $session->error();

        if ($error)
        {
            $items->{$id_entity}->{snmp} = $error
                if $session->error_status != 2;
            next;
        }

        if (defined $result->{$oid} && $result->{$oid})
        {        
            $result = unpack( "H*", $result->{$oid});
            $result =  pack( "H*", scalar $result);
            @d = unpack "H4C*", $result;

            $items->{$id_entity}->{TDF} = $d[8] ? sprintf(qq| %s%s:%s|, $d[7] == 43 ? '+' : '-', $d[8], $d[9]) : ' n/a';
            $items->{$id_entity}->{snmp} = timelocal($d[5],$d[4],$d[3],$d[2],$d[1]-1,hex($d[0]));

            $items->{$id_entity}->{status} = $items->{$id_entity}->{snmp} >= $items->{$id_entity}->{tstart}-$url_params->{options}
                && $items->{$id_entity}->{snmp} <= $items->{$id_entity}->{tstop}+$url_params->{options}
                ? 1
                : 0;
        } 
        else
        { 
            $items->{$id_entity}->{snmp} = 'n/a';
        } 
    }

    my $table = table_begin("time synchronization report (precision: $url_params->{options} sec)", 5);

    $table->addRow
    (
         '',
         make_col_title("name"),
         '',
         make_col_title("ip"),
         make_col_title("system time"),
         make_col_title("NTP status"),
         make_col_title("NTP details"),
    );

    my @row;
    my $tab;
    my $function;
    my $vendor;

    for $id_entity (sort { uc $items->{$a}->{name} cmp uc $items->{$b}->{name} }  keys %$items)
    {
        @row = ();
        $item = $items->{$id_entity};

        $function = $items_functions->{$id_entity}->{value};
        $function = $ProbesMapRev->{ $items->{id_probe_type} }
            unless $function;
        $vendor = $items_vendors->{$id_entity}->{value};

        push @row, image_vendor($vendor);
        push @row, $item->{name};
        push @row, image_function($function);
        push @row, $item->{ip};
        if (defined $item->{status})
        {
            $tab = HTML::Table->new( -align=>'left', -border=>0, -width=>'100%', -spacing=>0, -padding=>0,);
            $tab->addRow("test start time:", scalar localtime($item->{tstart}));
            $tab->addRow("<b>system time:</b>", 
                sprintf(qq|<font class="%s">%s %s</font>|, $item->{status} ? "j_10" : "j_100", scalar localtime($item->{snmp}), $item->{TDF}));

            $tab->addRow("test stop time:", scalar localtime($item->{tstop}));

            for (1..3)
            {
                $tab->setCellAttr($_, 1, 'class="n"');
                $tab->setCellAttr($_, 2, 'class="n"');
            }
            
            push @row, $tab;
        }
        else
        {
            push @row, $item->{snmp} ? $item->{snmp} : 'n/a';
        }
        push @row, defined $item->{ntp} ? status_name($item->{ntp_status}) : 'n/a';
        push @row, defined $item->{ntp} ? $item->{ntp} : 'n/a';

        for (0..$#row)
        {
            $row[$_] = "<nobr>&nbsp;$row[$_]&nbsp;</nobr>"
                unless $_ == 4 || $_ == 6;
        }

        $table->addRow(@row);

        if (defined $item->{ntp})
        {
            $table->setCellClass($table->getTableRows, 6, sprintf(qq|ts%s|, $item->{ntp_status}));
            $table->setCellClass($table->getTableRows, 7, ! defined $item->{ntp_auth} || $item->{ntp_auth} ? "e1" : "j_100")
        }
        else
        {
            $table->setCellClass($table->getTableRows, 6, "e1");
            $table->setCellClass($table->getTableRows, 7, "e1");
        }
    }

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
        for my $j (1..$table->getTableCols)
        {
            next
                if $j == 6 || $j == 7 || $j == 1 || $j == 3;
            $table->setCellClass($i, $j, "e1");
        }
        $table->setCellClass($i, 1, "n");
        $table->setCellClass($i, 3, "n");
    }


    return [0, $table];
}

sub make_col_title
{
    my ($name ) = @_;
    return sprintf(qq|<font class="g4">%s</font>|, $name);
}

sub auth_time_sources
{
    my @r = split /::/, shift;
    my $ip = shift;

    my (@k, $f, $g, $d);

    for (@r)
    {
        next
            unless $_;
        next
            if /====/;

        ($f,$g) = split //, $_, 2;
        @k = split /\s+/, $g;

        $d->{$k[0]} =
        {
            sync => $f,
            refid =>$k[1],
            stratum => $k[2],
            t => $k[3],
            when => $k[4],
            poll => $k[5],
            reach => $k[6],
            delay => $k[7],
            offset => $k[8],
            jitter => $k[9],
        }
    }

    $g = defined $Config->{$ip} ? $Config->{$ip} : $Config->{'*'};

    for (keys %$d)
    {
        next
            if $_ eq '';
        return 0
            unless defined $g->{$_};
    }    
    return 1;
}

1;
