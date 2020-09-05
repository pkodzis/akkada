package Dashboard;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;         
use Configuration;
use Constants;
use Common;
use Forms;
use System;
use Common;
use URLRewriter;

our $ProbesMapRev = CFG->{ProbesMapRev};
our $ProbesMap = CFG->{ProbesMap};
our $LastCheckHistogramFilePrefix = CFG->{SysStat}->{LastCheckHistogramFilePrefix};
our $LastCheckHistogramDir = CFG->{SysStat}->{LastCheckHistogramDir};
our $Period = CFG->{SysStat}->{Period};


use constant COLUMNS_COUNT => 4;

use constant 
{
    DESKTOP => 0,
    SYSTEM => 1,
    ALARMS_STAT => 2,
    ALARMS_TOTAL => 3,
    ALARMS_APPR => 4,
    #ALARMS_NODES => 5,
    CONFIG => 6,
    GRAPHS_PERIOD => 7,
};

our %FRM_IDS = 
(
    0 => 'get_table_entities_types',
    1 => 'get_table_alarms',
    #2 => 'get_table_nodes',
    3 => 'form_status_mysql',
    4 => 'get_table_entities_count',
    5 => 'get_table_logs',
    6 => 'get_table_akkada_modules',
    7 => 'get_table_last_check_histogram',
);

our %FRM_TITLES =
(
    0 => 'entities status by type',
    1 => 'status totals',
    #2 => 'calculated status totals',
    3 => 'mysql status',
    4 => 'entities count',
    5 => 'log totals',
    6 => 'system',
    7 => 'checking frequency',
);

sub new
{       
    my $class = shift;

    my $self;

    $self->[DESKTOP] = shift;

    bless $self, $class;

    $self->[SYSTEM] = System->new(
        $self->[DESKTOP]->dbh, 
        $self->[DESKTOP]->session, 
        $self->[DESKTOP]->cgi,
        $self->[DESKTOP]->url_params);

    $self->config_init;
    $self->graphs_period_init;
    $self->analyze_data_alarms;

    return $self;
}

sub graphs_period
{
    return $_[0]->[GRAPHS_PERIOD];
}


sub graphs_period_init
{
    my $self = shift;
    my $dbh = @_ ? shift : $self->desktop->dbh;

    $self->[GRAPHS_PERIOD] = '-3h';

    my $session = session_get;

    my $id_user = $session->param('_LOGGED');

    my $cfg = $dbh->exec(sprintf(qq|SELECT dashboard FROM users WHERE id_user=%s|, $id_user))->fetchrow_arrayref()->[0];

    return $self->[GRAPHS_PERIOD]
        unless $cfg;

    my @cols = split /\|\|/, $cfg;

    $self->[GRAPHS_PERIOD] = shift @cols;

    return $self->[GRAPHS_PERIOD];
}


sub config_init
{
    my $self = shift;
    my $dbh = @_ ? shift : $self->desktop->dbh;
    $self->[CONFIG] = 
    [
       [1], 
       [0,3],
       [7,5,6,4],
       [],
    ];

    my $session = session_get;

    my $id_user = $session->param('_LOGGED');

    my $cfg = $dbh->exec(sprintf(qq|SELECT dashboard FROM users WHERE id_user=%s|, $id_user))->fetchrow_arrayref()->[0];

    return $self->[CONFIG]
        unless $cfg;

    my @cols = split /\|\|/, $cfg;

    shift @cols;

    return $self->[CONFIG]
        unless @cols;

    $cfg = [];
    push @$cfg, [ split(/::/, $_) ]
        for @cols;

    $self->[CONFIG] = $cfg
        if defined $self;

    return $cfg;
}


sub config_save
{
    my $self = shift;
    my $dbh = @_ ? shift : $self->desktop->dbh;
    my $cfg = @_ ? shift : $self->config;
    my $gp = @_ ? shift : $self->graphs_period;

    my $cfgtxt = [];
    push @$cfgtxt, $gp
        if defined $gp;

    for (@$cfg)
    {
        push @$cfgtxt, join('::', ref($_) ? @$_ : '');
    }

    my $session = session_get;

    my $id_user = $session->param('_LOGGED');

    $dbh->exec(sprintf(qq|UPDATE users SET dashboard='%s' WHERE id_user=%s|, join('||', @$cfgtxt), $id_user));
}

sub config
{
    return $_[0]->[CONFIG];
}

sub alarms_stat
{
    return $_[0]->[ALARMS_STAT];
}

sub alarms_total
{
    return $_[0]->[ALARMS_TOTAL];
}

sub alarms_appr
{
    return $_[0]->[ALARMS_APPR];
}

sub desktop
{
    return $_[0]->[DESKTOP];
}

sub system
{
    return $_[0]->[SYSTEM];
}

sub get
{
    my $self = shift;

    my $table= HTML::Table->new();
    $table->setAlign("LEFT");
    $table->setAttr('class="w"');

    my $tc = HTML::Table->new();
    $tc->setAlign("LEFT");
    $tc->setAttr('class="w"');

    my ($row, $row_c) = $self->arrange();

    $table->addRow(@$row); 
    $table->setRowVAlign(1, 'top');

    $tc->addRow(@$row_c);

    $table->addRow(scalar $tc);

    $table->setCellColSpan(2, 1, 4);


    $table->addRow( make_popup_form($self->form_graphs_period, 'section_form_graphs_period', 'graphs period'));
    $table->setCellColSpan(3, 1, 4);

    return "<br>" . scalar $table . "<br>";
}

sub histograms_get
{
    my $self = shift;

    my $file;

    my @keys = ();

    my $table = HTML::Table->new();
    $table->setAlign("LEFT");
    $table->setAttr('class="w"');

    my @row = ();

    opendir(DIR, $LastCheckHistogramDir);
    while (defined($file = readdir(DIR)))
    {
        next
            unless $file =~ /^$LastCheckHistogramFilePrefix\./;
        push @keys, (split /\./, $file)[1];
    }
    closedir(DIR);

    for (@keys)
    {
        push @row, $self->form_get($FRM_IDS{7}, $_ eq 'global' ? 'global' : $ProbesMapRev->{$_}) 
            . $self->form_closed($FRM_IDS{7}, $FRM_TITLES{7}, $_ eq 'global' ? 'global' : $ProbesMapRev->{$_});
        if (@row == 4)
        {
            $table->addRow(@row);
            $table->setCellAttr($table->getTableRows, $_, qq|class="f"|)
                for (1..@row);
            @row = ();
        }
    }
    if (@row)
    {
        $table->addRow(@row);
        $table->setCellAttr($table->getTableRows, $_, qq|class="f"|)
            for (1..@row);
    }

    return @keys ? scalar $table : 'no data. check nm-sysstat.pl process<p>';
}

sub settings_get
{
    my $self = shift;

    my $cfg = $self->config;

    my $cgi = $self->desktop->cgi;
    my $url_params = $self->desktop->url_params;

    my $i;
    my $result = {};
    my $cont;
    my $col = 0;

    my %FRM_MISS = %FRM_TITLES;

    for my $j (@$cfg)
    {
        $i = 0;
        $cont = {};
        ++$col;

        $cont->{form_name} = "form_dashboard_manage_$col";
        $cont->{no_border} = 1;

        for (@$j)
        {
            ++$i;
            delete $FRM_MISS{$_};
            push @{ $cont->{rows} },
            [
                sprintf("%s.", $i),
                $FRM_TITLES{$_},
                $i == 1 ? '' : $cgi->a({ -href => url_get($url_params) 
                    . '?form_name=form_dashboard_manage&action=up&id_form=' . $_ . '&col=' . $col},
                    $cgi->img({ src=>'/img/r_up.gif', class => 'o', alt => "move up"})),
                $i == @$j ? '' : $cgi->a({ -href => url_get($url_params) 
                    . '?form_name=form_dashboard_manage&action=down&id_form=' . $_ . '&col=' . $col},
                    $cgi->img({ src=>'/img/r_down.gif', class => 'o', alt => "move down"})),
                $cgi->a({ -href => url_get($url_params) 
                    . '?form_name=form_dashboard_manage&action=del&id_form=' . $_ . '&col=' . $col},
                    $cgi->img({ src=>'/img/r_del.gif', class => 'o', alt => "remove"})),
            ];

            push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, 2, 'f'];
            push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, 3, 'm'];
            push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, 4, 'm'];
            push @{ $cont->{class} }, [ scalar @{ $cont->{rows} } + 1, 5, 'm'];
        }

        if (! @$j)
        {
            push @{ $cont->{rows} }, ['empty' ];
        }

        $result->{$col} = defined $cont->{rows}
            ? form_create($cont)
            : '';
    }


    my $table= HTML::Table->new();
    $table->setAlign("LEFT");
    $table->setAttr('class="w"');

    for (1..COLUMNS_COUNT)
    {
        $table->setCell(1, $_, "column $_:&nbsp;&nbsp;&nbsp;");
        $table->setCell(2, $_, defined $result->{$_} ? $result->{$_} : 'empty');
        $table->setCellAttr($table->getTableRows, $_, qq|class="o9"|);
    }

    $table->setRowVAlign(2, 'top');

    if (keys %FRM_MISS)
    {
        $cont = {};
        $cont->{form_name} = 'form_dashboard_manage';
        $cont->{no_border} = 1;

        push @{ $cont->{rows} },
        [
            "form name",
            $cgi->popup_menu(
                -name=>"id_form",
                -values=>[ sort { uc $FRM_MISS{$a} cmp uc $FRM_MISS{$b} } keys %FRM_MISS],
                -labels=> \%FRM_MISS,
                -class => 'textfield'),
        ];
        push @{ $cont->{rows} },
        [
            "column",
            $cgi->popup_menu(
                -name=>"col",
                -values=>[1,2,3,4],
                -class => 'textfield') . qq|<input type=hidden name="action" value="add">|,
        ];

        push @{ $cont->{buttons} }, 
            { caption => "add", url => "javascript:document.forms['form_dashboard_manage'].submit()" };

        $table->addRow("");
        $table->addRow(form_create($cont));
        $table->setCellColSpan($table->getTableRows, 1, COLUMNS_COUNT);
        $table->setCellAttr($table->getTableRows, 1, qq|class="o8"|);
    }

    return "<br>" . scalar $table . "<br>"

}

sub form_graphs_period
{
    my $self = shift;

    my $cont = {};

    $cont->{form_name} = 'form_dashboard_manage';
    $cont->{no_border} = 1;

    push @{ $cont->{rows} }, [ qq|<input type="hidden" name="col" value="0"  /><input type="hidden" name="id_form" value="0"  /><input type="hidden" name="action" value="gp"  />| 
        . sprintf(qq|<input type="text" name="period" value="%s"  />|, $self->graphs_period) ]; # bez CGI!
    push @{ $cont->{buttons} }, { caption => "update", url => "javascript:document.forms['form_dashboard_manage'].submit()" };

    return form_create($cont);
}

sub arrange
{
    my $self = shift;
    my $cfg = $self->config;

    my $result = [];
    my $result_c = [];
    my $form_name;

    for my $i (0..COLUMNS_COUNT)
    {
        $result->[$i] = '';
        for (@{$cfg->[$i]})
        {
            next
                unless defined $FRM_IDS{$_};
            $result->[$i] .= $self->form_get($FRM_IDS{$_}, $_ == 7 ? 'global' : undef);
            push @$result_c, $self->form_closed($FRM_IDS{$_}, $FRM_TITLES{$_}, $_ == 7 ? 'global' : undef);
        }
    }

    return ($result, $result_c);
};

sub form_get
{
    my $self = shift;
    my $name = shift;
    my $subname = @_ ? shift : undef;

    return $self->system->form_status_mysql(0, 1)
        if $name eq 'form_status_mysql';

    return $self->$name($subname);
}

sub get_table_akkada_modules
{
    my $self = shift;

    my $tree = $self->desktop->tree();

    my $cont = {};

    $cont->{form_name} = 'get_table_akkada_modules';
    $cont->{form_title} = $FRM_TITLES{6};
    $cont->{title_row} = [ '', 'enabled', 'disabled', 'up', 'down', 'problems'];
    $cont->{no_border} = 1;
    $cont->{close} = 1;
    

    my $h = {enabled => 0, disabled => 0, up => 0, down => 0, problems => 0};

    my $proc;

    my $err = 0;

    for my $mod ('modules', 'probes')
    {
        $proc = $self->system->proc->{$mod};
        for my $pr ( sort {uc($a) cmp uc($b)} keys %$proc)
        {
            $proc->{$pr}->[1] eq '0'
                ? ++$h->{disabled}
                : ++$h->{enabled};

            $h->{up} += $proc->{$pr}->[0];
            $h->{down} += ($proc->{$pr}->[1] - $proc->{$pr}->[0]);
            ++$h->{problems}
                if $proc->{$pr}->[1] ne $proc->{$pr}->[0];
        }

        ++$err
            if $h->{problems};

        push @{ $cont->{rows} },
        [
            $mod,
            $h->{enabled},
            $h->{disabled},
            $h->{up},
            format_string_state($h->{down}, $h->{down}),
            format_string_state($h->{problems}, $h->{problems}),
        ];
    }

    if ($err)
    {
        push @{ $cont->{rows} }, [ format_string_state("ERROR: some of the AKK\@DA components do not work properly. for more details see <a href=\"/gui/0,10,4\"><span class=g88>here</span></a>", 1, 1) ];
        push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3, 1, ''];
        push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} } + 2, 1, 6];
    }

    return form_create($cont);
}

sub get_table_alarms
{
    my $self = shift;

    my $cont = {};

    my $total = $self->alarms_total;
    my $appr = $self->alarms_appr;

    $cont->{form_name} = 'get_table_alarms';
    $cont->{form_title} = $FRM_TITLES{1};
    $cont->{title_row} = [ 'status', 'total %', 'total count', 'flaps', 'approved %', 'approved count'];
    $cont->{no_border} = 1;
    $cont->{close} = 1;

    for (sort { $a <=> $b } sort keys %_ST_LIST)
    {
         next
             if $_ == _ST_RECOVERED;
         if ($_ == _ST_NOSTATUS)
         {
             push @{ $cont->{rows} }, [];
             push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} } + 2, 1, 6];
             push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3,  1, 'g5'];

             push @{ $cont->{rows} },
             [
                 status_name($_),
                 $total->{statuses}->{ $_ }
                     ? sprintf(qq|<span class="ts$_"><a href="/gui/,0,?form_name=form_entity_find&status=$_">%.2f%%</a></span>|,
                         $total->{statuses}->{ $_ }*100/$total->{count})
                     : 'n/a',
                 $total->{statuses}->{ $_ }
                     ? sprintf(qq|<span class="ts$_"><a href="/gui/,0,?form_name=form_entity_find&status=$_">%s</a></span>|,
                         $total->{statuses}->{ $_ })
                     : 'n/a',
                 '','',''
             ];
             push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3,  4, 'g5'];
             push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3,  5, 'g5'];
             push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3,  6, 'g5'];

             next;
         }

         push @{ $cont->{rows} },
         [
             status_name($_),
	     $total->{statuses}->{ $_ }
                 ? sprintf(qq|<span class="ts$_"><a href="/gui/,0,?form_name=form_entity_find&status=$_">%.2f%%</a></span>|,
                    $total->{statuses}->{ $_ }*100/$total->{count})
                 : 'n/a',
             $total->{statuses}->{ $_ }
                 ? sprintf(qq|<span class="ts$_"><a href="/gui/,0,?form_name=form_entity_find&status=$_">%s</a></span>|,
                    $total->{statuses}->{ $_ })
                 : 'n/a',
             $total->{flaps}->{ $_ }
                 ? sprintf(qq|<span class="ts$_"><a href="/gui/,0,?form_name=form_entity_find&status=$_">%s</a></span>|,
                    $total->{flaps}->{ $_ })
                 : 'n/a',
             $_ > 0 && $_ < 63 && $total->{statuses}->{$_}
                 ? sprintf(qq|<font class="%s">%.2f%%</font>|, 
                     percent_bar_style_select($appr->{$_}*100/$total->{statuses}->{$_},2),
                     $appr->{$_}*100/$total->{statuses}->{$_})
                 : 'n/a',
             $_ > 0 && $_ < 63 && $total->{statuses}->{$_}
                 ? $appr->{$_}
                     ? $appr->{$_} 
                     : 0
                 : 'n/a',
         ];
    }


#    return sprintf(qq|<a href="javascript:nw('/actions/%s',600,800);"><img src="/img/action.gif"></a>|,
#        $no_inherited ? join(',', @myown) : join(',', keys %$actions) );


    push @{ $cont->{rows} }, [ '<a href="javascript:nw(\'/graphsysstat/status/' 
        . $self->graphs_period 
        . '/840/640\',800,1000);"><img src="/graphsysstat/status/' 
        . $self->graphs_period .  '"></a>'];
    push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} } + 2, 1, 6];
    push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3,  1, 'g5'];
    push @{ $cont->{rows} }, [ '<a href="javascript:nw(\'/graphsysstat/status_unr/'
        . $self->graphs_period 
        . '/840/640\',800,1000);"><img src="/graphsysstat/status_unr/'
        . $self->graphs_period . '"></a>'];
    push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} } + 2, 1, 6];
    push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3,  1, 'g5'];

    return form_create($cont);
}

sub analyze_data_alarms
{
    my $self = shift;

    my $desktop = $self->desktop;
    my $tree = $desktop->tree;

    my @st = grep { $_ != _ST_RECOVERED } sort { $a <=> $b } keys %_ST_LIST;

    my $items = $tree->items;

    my $stat = {};
    my $id_probe_type;
    my $total = {};
    my $appr = {};
    my $nodes = {};

    my $status;

    for (keys %$items)
    {
        next
            unless $desktop->matrix('general', $items->{$_});
        next
            unless $items->{$_}->id;
        next
            unless $items->{$_}->status_weight;

        $id_probe_type = $items->{$_}->id_probe_type;
        $status = $items->{$_}->status;
        $status = $items->{$_}->state
            if $id_probe_type < 2 && $status != _ST_UNREACHABLE && $status != _ST_NOSNMP;
        $stat->{ $id_probe_type }->{statuses}->{ $status }++;
        $stat->{ $id_probe_type }->{count}++
            if $status != _ST_NOSTATUS;
        $stat->{ $id_probe_type }->{count_ok}++
            unless $status > _ST_OK && $status < _ST_RECOVERED;
        $total->{statuses}->{$status }++;
        $total->{flaps}->{$status }++
            if $items->{$_}->flap;
        ++$total->{count}
            if $status != _ST_NOSTATUS;
        ++$total->{count_ok}
            unless $status > _ST_OK && $status < _ST_RECOVERED;
        $appr->{$status }++
            if $items->{$_}->err_approved_by || ($id_probe_type < 2 && $status != _ST_UNREACHABLE && $status != _ST_NOSNMP);
    }
#use Data::Dumper; warn Dumper $total;
    $self->[ALARMS_STAT] = $stat;
    $self->[ALARMS_TOTAL] = $total;
    $self->[ALARMS_APPR] = $appr;
}

sub form_closed
{
    my $self = shift;
    my $name = shift;
    my $title = shift;
    my $subname = @_ && defined $_[0] ? shift : '';

    my $cont = {};

    $cont->{form_name} = $name . $subname;
    $cont->{form_title} = $subname . " " . $title;
    $cont->{no_border} = 1;
    $cont->{close} = 2;

    return form_create($cont);
}

sub get_table_logs
{
    my $self = shift;


    my $tree = $self->desktop->tree();
    my $total = $tree->total;


    my $cont = {};

    $cont->{form_name} = 'get_table_logs';
    $cont->{form_title} = $FRM_TITLES{5};
    $cont->{no_border} = 1;
    $cont->{close} = 1;

    push @{ $cont->{rows} }, [ '<a href="javascript:nw(\'/graphsysstat/logs/'
        . $self->graphs_period
        . '/840/640\',800,1000);"><img src="/graphsysstat/logs/' . $self->graphs_period .  '"></a>'];
    

    return form_create($cont);
}

sub get_table_entities_types
{
    my $self = shift;

    my $cont = {};
    my @st = grep { $_ != _ST_RECOVERED } sort { $a <=> $b } keys %_ST_LIST;

    $cont->{form_name} = 'get_table_entities_types';
    $cont->{form_title} = $FRM_TITLES{0};
    $cont->{title_row} = ['probe type', 'total', map { $_ != _ST_NOSTATUS ? status_name($_) : ('',  status_name($_)) } @st];
    $cont->{no_border} = 1;
    $cont->{close} = 1;

    my $stat = $self->alarms_stat;

    for my $p (sort { $ProbesMapRev->{$a} cmp $ProbesMapRev->{$b} } keys %$stat)
    {
         push @{ $cont->{rows} },
         [
              sprintf(qq|<a href="/gui/,0,?form_name=form_entity_find&id_probe_type=%s">%s</a>|,$p, $ProbesMapRev->{$p}),
              $stat->{ $p }->{count},
              (map 
              {  
                  $_ != _ST_NOSTATUS
                  ? ($stat->{ $p }->{statuses}->{ $_ }
                      ? sprintf(qq|<span class="ts$_"><a href="/gui/,0,?form_name=form_entity_find&status=$_&id_probe_type=%s">%.2f%% (| . $stat->{ $p }->{statuses}->{ $_ } . qq|)</a></span>|,
                          $p, ($stat->{ $p }->{count} ? $stat->{ $p }->{statuses}->{ $_ }*100/$stat->{ $p }->{count} : 100)) 
                      : qq|<small>n/a</small>|
                    )
                  : ($stat->{ $p }->{statuses}->{ $_ }
                      ? ('', sprintf(qq|<span class="ts$_"><a href="/gui/,0,?form_name=form_entity_find&status=$_&id_probe_type=%s">%.2f%% (| . $stat->{ $p }->{statuses}->{ $_ } . qq|)</a></span>|,
                          $p, ($stat->{ $p }->{count} ? $stat->{ $p }->{statuses}->{ $_ }*100/$stat->{ $p }->{count} : 100)) )
                      : ('', qq|<small>n/a</small>|)
                    )
                  
              } grep { $_ != _ST_RECOVERED } sort { $a <=> $b } keys %_ST_LIST),
         ];
         push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3,  14, 'g5'];
         #push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3,  2 + scalar keys %_ST_LIST, 'g5'];
    }

    return form_create($cont);
}

sub get_table_entities_count
{
    my $self = shift;

    my $tree = $self->desktop->tree();


    my $total = $tree->total;
    my $total_m = $tree->total_m;
    my $total_nm = $total - $total_m;
    my $cached = (scalar keys %{ $tree->items }) - 1;

    my $total_m_p = $total ? sprintf(qq|%.2f%%|, $total_m*100/$total) : 'n/a';
    my $total_nm_p = $total ? sprintf(qq|%.2f%%|, $total_nm*100/$total) : 'n/a';

    my $err = $total == $cached ? 0 : 1;


    my $cont = {};

    $cont->{form_name} = 'get_table_entities_count';
    $cont->{form_title} = $FRM_TITLES{4};
    $cont->{no_border} = 1;
    $cont->{close} = 1;

    push @{ $cont->{rows} }, [ "total",  format_string_state($total, $err) ];
    push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 2, 3, 'g5'];

    push @{ $cont->{rows} }, [ "cached", format_string_state($cached, $err) ];
    push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 2, 3, 'g5'];

    push @{ $cont->{rows} }, [ "monitored", $total_m, $total_m_p ];
    push @{ $cont->{rows} }, [ "not monitored", $total_nm, $total_nm_p ];


    if ($err)
    {
        my $TreeCacheDir = CFG->{Web}->{TreeCacheDir};

        push @{ $cont->{rows} }, [ format_string_state("ERROR: total db entities count does not equal cached entities count. possible cache process error. all cache files and directories at $TreeCacheDir should be removed and tree_cache process should be restarted.", 1, 1), "" ];
        push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 2, 1, ''];
        push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} } + 1, 1, 3];
    }

    return form_create($cont);
}

sub get_table_last_check_histogram
{
    my $self = shift;
    my $prefix = shift;

    my $cont = {};

    my $name;
    if ($prefix eq 'global')
    {
        $name = $prefix;
    }
    else
    {
        $name = $ProbesMap->{$prefix};
    }

    $cont->{form_name} = 'get_table_last_check_histogram' . $prefix;
    $cont->{form_title} = $prefix . " " . $FRM_TITLES{7};
    $cont->{no_border} = 1;
    $cont->{close} = 1;

    my $file = "$LastCheckHistogramDir/$LastCheckHistogramFilePrefix.$name";

    if (! -e $file)
    {
        push @{ $cont->{rows} }, [ "no data. check nm-sysstat.pl process" ];
        return form_create($cont);
    }

    my $h = {};
    my $total;
    my @tmp;

    open F, $file;
    %$h= map { s/\n// && split /\|\|/, $_ && $_ } <F>;
    close F;

    $total = $h->{total};
    delete $h->{total};
    delete $h->{''};

    for (keys %$h)
    {
        $h->{$_} = int($h->{$_}*100/$total);
    }

    $cont->{title_row} = [ '', map { $_ == 9999 ? 'longer': "<${_}s" } sort { $a <=> $b } keys %$h ];

    my $cols = [keys %$h];
    $cols = $#$cols+1;

    push @{ $cont->{rows} }, [ "<img src=/img/bgd.gif width=1 height=100 >",
        map
        {
            "<img src=/img/bgd.gif width=32 height=$h->{$_}>"
        } sort { $a <=> $b } keys %$h ];
    push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3, $_, 'g55']
        for (1..$cols+1);
    push @{ $cont->{rows} }, [ '', map { "$h->{$_}%" } sort { $a <=> $b } keys %$h ];
    push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3, $_, 'g55']
        for (1..$cols+1);

    my $statement = 'SELECT check_period,count(check_period) AS cpc
        FROM entities
        WHERE monitor=1 AND id_probe_type>0 AND status<>126';
    $statement .= " AND id_probe_type=$name"
        if $name ne 'global';
    $statement .= ' GROUP BY check_period';
    my $req = $self->desktop->dbh->exec($statement)->fetchall_hashref("check_period");
    my $time_delta = time - (stat($file))[9];
    my $bad = $time_delta > 10*$Period ? 1 : 0;
    push @{ $cont->{rows} }, [ "<pre>your checking frequency settings:\n" 
        . join("\n", map {sprintf(qq|$_ sec: $req->{$_}->{cpc} (%d%%)|, int($req->{$_}->{cpc}*100/$total) )} sort { $a <=> $b } keys %$req) 
        . ($name ne 'global' ? "" : "\nreport date: <font color=" . ($bad ? "red>" : "\"\">") . scalar localtime((stat($file))[9]) . "</font>\nmore details <a href=\"" . url_get({settings => 2}, $self->desktop->url_params) . "\">here.</a>")
        . "</pre>" ];
    push @{$cont->{cellColSpans}}, [scalar @{ $cont->{rows} } + 2, 1, $cols+1];
    push @{ $cont->{class} }, [scalar @{ $cont->{rows} } + 3, 1, 'g555'];

    return form_create($cont);
}

1;
