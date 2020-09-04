package System;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;         
use Configuration;
use Constants;
use Common;
use URLRewriter;
use Forms;
use Proc::ProcessTable;

use constant 
{
    DB => 0,
    SESSION => 1,
    CGI => 5,
    URL_PARAMS => 6,
    PROC => 7,
    PMGMT => 8,
    PROBES => 9,
};

our $System = CFG->{System};
our $StatusDir = CFG->{Probe}->{StatusDir};
our $ProbesMap = CFG->{ProbesMap};
our $ImagesDir = CFG->{ImagesDir};
our $FlagsControlDir = CFG->{FlagsControlDir};
our $MySQLStatusFile = CFG->{MySQLStatusFile};
our $ICMPMonitorThreadsCount = CFG->{ICMPMonitor}->{ThreadsCount};

sub new
{       
    my $class = shift;

    my $self;

    $self->[DB] = shift;
    $self->[SESSION] = shift;
    $self->[CGI] = shift;
    $self->[URL_PARAMS] = shift;
    $self->[PROC] = {};
    $self->[PMGMT] = 0;

    bless $self, $class;

    $self->get_process_table;
    $self->load_probes;

    return $self;
}

sub load_probes
{
    my $self = shift;

    my $libdir = CFG->{LibDir} . "/Probe";
    my ($file, $probe);

    opendir(DIR, $libdir);
    while ( defined($file = readdir(DIR)) )
    {   
        next
            if $file !~ /\.pm$/;
        $file = (split /\.pm$/, $file)[0];
        eval "require Probe::$file; \$probe = Probe::${file}->new;" or die $@;
        $self->[PROBES]->{$file} = $probe;
    }
    closedir(DIR);
#use Data::Dumper; warn Dumper $self->[PROBES];
}

sub probes
{
    return $_[0]->[PROBES];
}

sub get_process_table
{
    my $self = shift;
    my $proc = $self->proc;

    my $pt = {};
    my @t;
    my $name;
    my $count;

    my $t = new Proc::ProcessTable;
    for ( @{$t->table} )
    {   
        ++$pt->{ $_->cmndline }->{count};
        $pt->{ $_->cmndline }->{processes}->{$_->pid} = {};
    }

    $self->[PMGMT] = 1
        if defined $pt->{'akkada.pl'};

    for (keys %{ $System->{Modules} })
    {
        $name = sprintf(qq|nm-%s.pl|, $_);
        $count = /^icmp_monitor$/
            ? ($ICMPMonitorThreadsCount+2)
            : $System->{Modules}->{$_};

        @t = grep { /$name/ } keys %$pt;

        if (@t)
        {
            $proc->{modules}->{$_} = [$pt->{ $t[0] }->{count}, $count, $pt->{ $t[0] }->{processes}];
        }
        else
        {
            $proc->{modules}->{$_} = [0, $count];
        }
    };

    for (keys %{ $System->{Probes} })
    {   
        $name = sprintf(qq|np-%s.pl|, $_);
        $count = $System->{Probes}->{$_};

        @t = grep { /$name/ } keys %$pt;

        if (@t)
        {   
            $proc->{probes}->{$_} = [$pt->{ $t[0] }->{count}, $count, $pt->{ $t[0] }->{processes}];
        }
        else
        {   
            $proc->{probes}->{$_} = [0, $count];
        }
    };

    my $file;
    for my $p (keys %{$proc->{probes}})
    {   
        for (keys %{ $proc->{probes}->{$p}->[2] } )
        {
            $proc->{probes}->{$p}->[2]->{$_}->{entc} = 'n/a';
            $proc->{probes}->{$p}->[2]->{$_}->{entt} = 'n/a';

            $file = sprintf(qq|%s/%s|, $StatusDir, $_);
            if (-e $file)
            {
                open F, $file or die $@;
                $file = <F>;
                close F;
                $file = [ split /:/, $file, 2 ];    
                $proc->{probes}->{$p}->[2]->{$_}->{entt} = $file->[0];
                $proc->{probes}->{$p}->[2]->{$_}->{entc} = $file->[1];
            }
        }
    }
#use Data::Dumper; warn Dumper $proc;
}


sub proc
{
    return $_[0]->[PROC];
}

sub session
{
    return $_[0]->[SESSION];
}

sub url_params
{
    return $_[0]->[URL_PARAMS];
}

sub pmgmt
{
    return $_[0]->[PMGMT];
}

sub db
{
    return $_[0]->[DB];
}

sub cgi
{
    return $_[0]->[CGI];
}

sub status
{
    my $self = shift;

    my $table= HTML::Table->new();
    $table->setAlign("LEFT");
    $table->setAttr('class="w"');

    $table->addRow( $self->form_status_modules(), $self->form_status_probes());
    $table->addRow( $self->form_status_mysql() );
    $table->setCellRowSpan(1, $table->getTableCols, $table->getTableRows);

    return $table;
}

sub load_mysql_status
{
    my $self = shift;

    return 
    {   
        Uptime => 'n/a',
        Threads => 'n/a',
        Questions => 'n/a',
        'Slow queries' => 'n/a',
        Opens => 'n/a',
        'Flush tables' => 'n/a',
        'Open tables' => 'n/a',
        'Queries per second avg' => 'n/a',
    }
        unless -e $MySQLStatusFile;

    my $s;
    my $result = {};

    open F, $MySQLStatusFile;
    $s = <F>; 
    $s =~ s/\n//g;
    close F;

    my @t = split /  /, $s;
    $s = [];
    for (@t)
    {
        @$s = split /: /, $_;
        $result->{ $s->[0] } = $s->[1];
    }

    return $result;
}

sub form_status_mysql
{
    my $self = shift;
    my $mode = shift || 0;
    my $cgi = $self->cgi;
                 
    my $cont;
                    
    my $mysql = $self->load_mysql_status; 
    my $pmgmt = $self->pmgmt;

    $mysql->{Uptime} = duration_row($mysql->{Uptime})
        unless $mysql->{Uptime} eq 'n/a';
         
    $cont = {};
    $cont->{form_name} = 'form_status_mysql';
    $cont->{form_title} = 'mysql status';
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} },
        { caption => "OK", url => qq|javascript:document.forms['form_status_mysql'].submit()| }
        if $mode == 1 && $pmgmt;

    for ( sort keys %$mysql)
    {
         push @{ $cont->{rows} },
         [
             $_,
             $mysql->{$_},
         ];
         push @{ $cont->{class} }, [ $#{ $cont->{rows} } + 3, 2, 'f' ];
    }

    return form_create($cont);
}


sub form_status_modules
{
    my $self = shift;
    my $mode = shift || 0;
    my $cgi = $self->cgi;

    my ($proc, $cont, @prc, $i);

    my $pmgmt = $self->pmgmt;

    $cont = {};
    $cont->{form_name} = 'form_status_modules';
    $cont->{form_title} = 'modules status';
    $cont->{title_row} = $mode && $pmgmt
        ? [ '', 'name', 'process count', 'expected process count', '', 'action']
        : [ '', 'name', 'process count', 'expected process count', ''];
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} },
        { caption => "OK", url => qq|javascript:document.forms['form_status_modules'].submit()| }
        if $mode == 1 && $pmgmt;

    $proc = $self->proc->{modules};
    for my $pr ( sort {uc($a) cmp uc($b)} keys %$proc)
    {
         $mode && $pmgmt
?
         push @{ $cont->{rows} },
         [   
             $cgi->img({ src=>"/img/windows_service1.gif", class => 'o', alt  => ''}),
             "<b>$pr</b>",
             $proc->{$pr}->[0],
             $proc->{$pr}->[1],
             $proc->{$pr}->[0] == $proc->{$pr}->[1]
                 ? 'OK'
                 : $proc->{$pr}->[0] eq '0'
                     ? ($proc->{$pr}->[1] ne '0'
                         ? '<span class="d">DOWN</span>'
                         : 'DISABLED')
                     : '<span class="d">PROBLEM</span>',
             $self->popup_action($pr, $proc->{$pr}->[0], 'Modules'),
         ]  
:
         push @{ $cont->{rows} },
         [
             $cgi->img({ src=>"/img/windows_service1.gif", class => 'o', alt  => ''}),
             "<b>$pr</b>",
             $proc->{$pr}->[0],
             $proc->{$pr}->[1],
             $proc->{$pr}->[0] == $proc->{$pr}->[1]
                 ? 'OK'
                 : $proc->{$pr}->[0] eq '0'
                     ? ($proc->{$pr}->[1] ne '0'
                         ? '<span class="d">DOWN</span>'
                         : 'DISABLED')
                     : '<span class="d">PROBLEM</span>',
         ]; 

         push @{ $cont->{class} }, [ $#{ $cont->{rows} } + 4, 1, 't2' ];
         push @{ $cont->{class} }, [ $#{ $cont->{rows} } + 4, 6, 'f' ]
             if $mode && $pmgmt;
    }

    return form_create($cont);
}

sub popup_action
{
    my $self = shift;
    my $pr = shift;
    my $run = shift;
    my $module = shift;

    for (qw| start stop restart |)
    {
        return "$_ in progress"
            if flag_file_check( $FlagsControlDir, sprintf(qq|manager.%s|, $_));
    }

    for (qw| start stop restart |)
    {
        return "$_ in progress"
            if flag_file_check( $FlagsControlDir, sprintf(qq|manager.process.%s.%s.%s|, $module, $pr, $_));
    }

    my $actions =
    {
        '' => '--- select ---',
    };

    $actions->{start} = 'start'
        if $run == 0;
    $actions->{stop} = 'stop'
        if $run > 0;
    $actions->{restart} = 'restart'
        if $run > 0;

    return $self->cgi->popup_menu
    (
        -name=> 'action_' . $pr,
        -values => [ sort { uc $actions->{$a} cmp uc $actions->{$b} } keys %$actions],
        -labels => $actions,
        -class => 'textfield',
    );
}

sub form_status_probes
{       
    my $self = shift;    
    my $mode = shift || 0;
    my $cgi = $self->cgi;

    my $entc = $self->db->dbh->selectall_hashref("SELECT id_probe_type,count(*) AS count FROM entities WHERE monitor<> 0 GROUP BY id_probe_type",
        "id_probe_type");
    @$entc{ keys %$entc } = map { $entc->{$_}->{count} } keys %$entc;
    
    my ($proc, $cont, @prc, $i, $span_count, $img, $count);
    
    my $pmgmt = $self->pmgmt;
        
    $cont = {};
    $cont->{form_name} = 'form_status_probes';
    $cont->{form_title} = 'probes status';
    $cont->{title_row} = $mode && $pmgmt
        ? [ '', 'name', 'ver', 'process count', 'expected process count', '', 'total entities count in db', 'pid', 'entities count in probe', 'last entities init time', 'action' ]
        : [ '', 'name', 'ver', 'process count', 'expected process count', '', 'total entities count in db', 'pid', 'entities count in probe', 'last entities init time' ];
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, 
        { caption => "OK", url => qq|javascript:document.forms['form_status_probes'].submit()| }
        if $mode == 1 && $pmgmt;

    $proc = $self->proc->{probes};
    $span_count = 0;

    my $total = {};
    my $probes = $self->probes;

    for my $pr ( sort {uc($a) cmp uc($b)} keys %$proc)
    {
        $img = -e "$ImagesDir/$pr.gif"
            ? "/img/$pr.gif"
            : "/img/unknown.gif";

        @prc = keys %{ $proc->{$pr}->[2] };
        $count = 0;
        $total->{entc} += $proc->{$pr}->[0];
        $total->{entec} += $proc->{$pr}->[1];
        $total->{enttc} += $entc->{ $ProbesMap->{$pr} };
        if (@prc)
        {
            for (@prc)
            {
                $total->{entpc} += $proc->{$pr}->[2]->{$_}->{entc};

$mode && $pmgmt
?
                push @{ $cont->{rows} },
                [   
                    $cgi->img({ src=>$img, class => 'o', alt  => ''}),
                    "<b>$pr</b>",
                    $probes->{$pr}->version,
                    $proc->{$pr}->[0],
                    $proc->{$pr}->[1],
                    $proc->{$pr}->[0] == $proc->{$pr}->[1]
                        ? 'OK'
                        : '<span class="d">PROBLEM</span>',
                    $entc->{ $ProbesMap->{$pr} } || 0,
                    $_,
                    $proc->{$pr}->[2]->{$_}->{entc},
                    $proc->{$pr}->[2]->{$_}->{entt} eq ''
                    || $proc->{$pr}->[2]->{$_}->{entt} =~ /\D/
                        ? 'n/a'
                        : scalar localtime($proc->{$pr}->[2]->{$_}->{entt}),
                    $self->popup_action($pr, $proc->{$pr}->[0], 'Probes'),
                ]
:
                push @{ $cont->{rows} },
                [
                    $cgi->img({ src=>$img, class => 'o', alt  => ''}),
                    "<b>$pr</b>",
                    $probes->{$pr}->version,
                    $proc->{$pr}->[0],
                    $proc->{$pr}->[1],
                    $proc->{$pr}->[0] == $proc->{$pr}->[1]
                        ? 'OK'
                        : '<span class="d">PROBLEM</span>',
                    $entc->{ $ProbesMap->{$pr} } || 0,
                    $_,
                    $proc->{$pr}->[2]->{$_}->{entc},
                    $proc->{$pr}->[2]->{$_}->{entt} eq ''
                    || $proc->{$pr}->[2]->{$_}->{entt} =~ /\D/
                        ? 'n/a'
                        : scalar localtime($proc->{$pr}->[2]->{$_}->{entt}),
                ];
                $count += $proc->{$pr}->[2]->{$_}->{entc};
            }
            push @{ $cont->{class} }, [ $#{ $cont->{rows} } + 4, 10, 'f' ];
            push @{ $cont->{class} }, [ $#{ $cont->{rows} } + 4, 11, 'f' ]
                if $mode && $pmgmt;

            $i = @prc;
            if ($i > 1)
            {
                $span_count = $#{ $cont->{rows} } + 4 - $i + 1;
                push @{ $cont->{cellRowSpans} }, [ $span_count, $_, $i ]
                    for (1..7);
                push @{ $cont->{class} }, [ $span_count, $_, 'c' ]
                    for (1..10);
                push @{ $cont->{class} }, [ $span_count, 7, 'd' ]
                    if $count < ($entc->{ $ProbesMap->{$pr} } || 0);
if ($mode && $pmgmt)
{
                push @{ $cont->{cellRowSpans} }, [ $span_count, 11, $i ];
                push @{ $cont->{class} }, [ $span_count, 11, 'c' ];
}
            }
            else
            {
                push @{ $cont->{class} }, [ $#{ $cont->{rows} } + 4, 7, 'd' ]
                    if $count < ($entc->{ $ProbesMap->{$pr} } || 0);
            }
        }
        else
        {
$mode && $pmgmt
?
            push @{ $cont->{rows} },
            [   
                $cgi->img({ src=>$img, class => 'o', alt  => ''}),
                "<b>$pr</b>",
                $probes->{$pr}->version,
                $proc->{$pr}->[0],
                $proc->{$pr}->[1],
                     ($proc->{$pr}->[1] ne '0'
                         ? '<span class="d">DOWN</span>'
                         : 'DISABLED'),
                $entc->{ $ProbesMap->{$pr} } || 0,
                'n/a',
                'n/a',
                'n/a',
                $self->popup_action($pr, $proc->{$pr}->[0], 'Probes'),
            ]
:
            push @{ $cont->{rows} },
            [  
                $cgi->img({ src=>$img, class => 'o', alt  => ''}),
                "<b>$pr</b>",
                $probes->{$pr}->version,
                $proc->{$pr}->[0],
                $proc->{$pr}->[1],
                     ($proc->{$pr}->[1] ne '0'
                         ? '<span class="d">DOWN</span>'
                         : 'DISABLED'),
                $entc->{ $ProbesMap->{$pr} } || 0,
                'n/a',
                'n/a',
                'n/a',
            ];
        }
    }

    push @{ $cont->{rows} },
    [  
        '',
        '<b>total</b>',
        '',
        $total->{entc},
        $total->{entec},
        '',
        $total->{enttc},
        '',
        $total->{entpc},
        '',
    ];

    return form_create($cont);
}

sub action_permited
{
    my $ok = '';
    for (qw| start stop restart |)
    {
        if (flag_file_check( $FlagsControlDir, 'manager.' . $_))
        {
            $ok = $_;
            last;
        }
    }
}


sub form_system_global
{
    my $self = shift;
    my $cgi = $self->cgi;


    my $actions =
    {   
        '' => '--- select ---',
    };

    my $ok;
    my $proc = $self->proc->{probes};
    for (keys %$proc)
    {
        ++$ok
            if $proc->{$_}->[0];
    }
    $proc = $self->proc->{modules};
    for (keys %$proc)
    {
        ++$ok
            if $proc->{$_}->[0];
    }
   
    $actions->{start} = 'start' 
        if $ok == 0;
    $actions->{stop} = 'stop' 
        if $ok > 0;
    $actions->{restart} = 'restart' 
        if $ok > 0;

    $ok = '';
    for (qw| start stop restart |)
    {   
        if (flag_file_check( $FlagsControlDir, 'manager.' . $_))
        {
            $ok = $_;
            last;
        }
    }

    my $cont = {};
    $cont->{form_name} = 'form_system_global';
    $cont->{form_title} = 'global action';
    $cont->{no_border} = 1;

    if (! $self->pmgmt)
    {
        push @{ $cont->{rows} }, [ "akkada.pl is not runing." ];
        push @{ $cont->{rows} }, [ "start akkada.pl from command line." ];
        push @{ $cont->{rows} }, [ "after this web process management will be possible." ];
    }
    elsif ($ok)
    {
        push @{ $cont->{rows} }, [ "action '$ok' waits for proccessing." ];
        push @{ $cont->{rows} }, [ "global actions are not permited in this situation." ];
        push @{ $cont->{rows} }, [ "try again later." ];
    }
    else
    {
        push @{ $cont->{buttons} }, { caption => "process", url => qq|javascript:document.forms['form_system_global'].submit()| };

        push @{ $cont->{rows} },
        [   
            "action",
            $cgi->popup_menu(
                -name=>'action',
                -values=>[ sort { uc $actions->{$a} cmp uc $actions->{$b} } keys %$actions],
                -labels=> $actions,
                -class => 'textfield', ),
        ];
    }

    return form_create($cont);
}

sub manage
{
    my $self = shift;

    my $table= HTML::Table->new();
    $table->setAlign("LEFT");
    $table->setAttr('class="w"');

    $table->addRow( $self->form_status_modules(1), $self->form_status_probes(1));

    $table->addRow( $self->form_status_mysql );

    $table->addRow( $self->form_system_global );

    $table->setCellRowSpan(1, $table->getTableCols, $table->getTableRows);

    return $table;
}

sub form_configuration_gui
{   
    my $self = shift;
    my $cgi = $self->cgi;
    my $web = CFG->{Web};

    my $cont = {};
    $cont->{form_name} = 'form_configuration_gui';
    $cont->{form_title} = 'GUI';
    $cont->{no_border} = 1;

    push @{ $cont->{buttons} }, { caption => "save", url => qq|javascript:document.forms['form_configuration_gui'].submit()| };

    push @{ $cont->{rows} },
    [
        "<nobr>show delta test graphs</nobr>",
        $cgi->checkbox({name => "show_delta_test", label => "", checked => $web->{Stat}->{ShowDeltaTest} ? 'checked' : ''}),
    ];
    push @{ $cont->{rows} },
    [
        "<nobr>list view: show vendors images</nobr>",
        $cgi->checkbox({name => "list_view_show_vendors_images", label => "", checked => $web->{ListViewShowVendorsImages} ? 'checked' : ''}),
    ];
    push @{ $cont->{rows} },
    [
        "<nobr>list view: show functions images</nobr>",
        $cgi->checkbox({name => "list_view_show_functions_images", label => "", checked => $web->{ListViewShowFunctionsImages} ? 'checked' : ''}),
    ];
    push @{ $cont->{rows} },
    [
        "<nobr>tree: show active node services (!)</nobr>",
        $cgi->checkbox({name => "show_active_node_service", label => "", checked => $web->{Tree}->{ShowActiveNodeService} ? 'checked' : ''}),
    ];
    push @{ $cont->{rows} },
    [
        "<nobr>tree: show services alarms</nobr>",
        $cgi->textfield({ name => 'show_services_alarms', value => $web->{Tree}->{ShowServicesAlarms}, class => "textfield", size => 1}),
        "<nobr>0 - not visible; 1 - visible only if alarms tab selected; 2 - always visible</nobr>",
    ];
    push @{ $cont->{rows} },
    [
        "<nobr>history: records per page</nobr>",
        $cgi->textfield({ name => 'history_default_limit', value => $web->{History}->{DefaultLimit}, class => "textfield", size => 1}),
    ];
    push @{ $cont->{rows} },
    [
        "<nobr>history: graph time slot</nobr>",
        $cgi->textfield({ name => 'history_stat_resolution', value => $web->{History}->{StatResolution}, class => "textfield", size => 1}),
    ];

    return form_create($cont);
}

sub configuration
{
    my $self = shift;

    my $table= HTML::Table->new();
    $table->setAlign("LEFT");
    $table->setAttr('class="w"');

    $table->addRow( $self->form_configuration_gui );

    return $table;
}

1;
