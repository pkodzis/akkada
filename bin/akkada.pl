#!/akkada/bin/perl -w

$0 = 'akkada.pl';

use lib "$ENV{AKKADA}/lib";
use Entity;
use MyException qw(:try);
use Common;
use Log;
use Configuration;
use Constants;
use strict;
use Proc::ProcessTable;

our $FlagsControlDir = CFG->{FlagsControlDir};
our $MySQLAdminFile = CFG->{MySQLAdminFile};
our $MySQLStatusFile = CFG->{MySQLStatusFile};
our $LogEnabled = CFG->{LogEnabled};
our $System = CFG->{System};
our $SystemLimits = CFG->{SystemLimits};
our $AkkadaMgmtPeriod = CFG->{AkkadaMgmtPeriod};
our $DBUsername = CFG->{Database}->{Username};
our $DBPassword = CFG->{Database}->{Password};


my $STOPED  = {};
my $PROC = {};

if ( (getpwuid($<))[0] ne CFG->{OSLogin})
{
    print sprintf(qq|switch to user %s before starting the system\n|, CFG->{OSLogin});
    exit;
}

sub got_sig_quit
{

    get_process_table();
    action_global_stop();

    try
    {  
        unlink $MySQLStatusFile
            if -e $MySQLStatusFile
    }       
    except
    {   
        throw EFileSystem($@ . ';' . $!);
    };

    log_debug("akk\@da stoped", _LOG_WARNING)
        if $LogEnabled;
    exit;
}

runtime(1);

$SIG{QUIT} = \&got_sig_quit;
$SIG{INT} = \&got_sig_quit;
$SIG{TERM} = \&got_sig_quit;
$SIG{STOP} = \&got_sig_quit;

try
{
    while(1)
    {
        get_process_table();

        for my $action (qw| start stop restart |)
        {   
            if (flag_file_check( $FlagsControlDir, 'manager.' . $action))
            {   
                log_debug("global action: $action", _LOG_WARNING);

                if ($action eq 'stop')
                {
                    action_global_stop();
                }
                elsif ($action eq 'start')
                {
                    action_global_start();
                }
                elsif ($action eq 'restart')
                {
                    action_global_stop();
                    action_global_start();
                }

                flag_file_check( $FlagsControlDir, 'manager.' . $action, 1);
             
                last;
            }
        }

        auto_start_modules();

        check_modules();

eval {
        if (-e $MySQLStatusFile)
        {   
            open F, "+<$MySQLStatusFile";
        }
        else
        {   
            open F, ">$MySQLStatusFile";
        }
        seek(F, 0, 0);
        open G, "$MySQLAdminFile status --user=$DBUsername --password=$DBPassword|";
        print F <G>;
        close G;
        truncate(F, tell(F));
        close F;
};

        mem_check();

        sleep $AkkadaMgmtPeriod;
    }
}
catch Error with
{
    log_exception(shift, _LOG_ERROR);
};

sub action_global_stop
{
    if (defined $PROC->{Modules} && ref($PROC->{Modules}))
    {
        for (keys %{$PROC->{Modules}})
        {
            action_stop('nm', $_);
        }
    }
    if (defined $PROC->{Probes} && ref($PROC->{Probes}))
    {
        for (keys %{$PROC->{Probes}})
        {
            action_stop('np', $_);
        }
    }

    ++$STOPED->{stop};
}

sub action_global_start
{
    $STOPED = {};
}

sub kill_process
{
    my $pid = shift;
    my $name = shift;

    log_debug(sprintf(qq|stopping %s pid %s ...|, $name, $pid), _LOG_WARNING);

    while ( kill(0, $pid) )
    { 
        kill(9, $pid);
        select(undef, undef, undef, 0.25);
    }

    log_debug(sprintf(qq|stoped %s pid %s|, $name, $pid), _LOG_WARNING);
}

sub dispatch_module_name
{
    my $name = shift;
    my @t = split /manager\.process\./, $name;
    my ($module, $action);
    ($module, $name, $action) = split /\./, $t[1], 3;
    return ($module, $name, $action);
}

sub action_stop
{
    my $pref = shift;
    my $name = shift;

    ++$STOPED->{$name};

    my $pids = [];
    if ($pref eq 'nm')
    {   
        $pids = [map { $_->[0] } @{$PROC->{Modules}->{$name}->[2]}]
            if defined $PROC->{Modules}->{$name}->[2];
    }  
    else
    {  
        $pids = [map { $_->[0] } @{$PROC->{Probes}->{$name}->[2]}]
            if defined $PROC->{Probes}->{$name}->[2];
    }

    for (@$pids)
    {
        kill_process($_, $name);
    }
}

sub mem_check
{
    my $self = shift;

    my $i;
    my $name;
    my $pr = { 'Modules' => 'nm', 'Probes' => 'np' };

    for my $pref ( qw( Modules Probes ) )
    {
        for my $name (keys %{$PROC->{$pref}})
        {
            next
                unless defined $PROC->{$pref}->{$name}->[2];
            next
                unless defined $SystemLimits->{$pref}->{$name} && $SystemLimits->{$pref}->{$name};
            $i = 0;
            $i += $_
                for map {$_->[1]} @{$PROC->{$pref}->{$name}->[2]};

            if ($i > $SystemLimits->{$pref}->{$name})
            {
                log_debug("$pr->{$pref}-" . lc($name) . ".pl RAM size $i limit $SystemLimits->{$pref}->{$name} exceeded;", _LOG_ERROR)
                    if $LogEnabled;
                action_restart($pr->{$pref}, $name);
            }
            else
            {
                log_debug("$pr->{$pref}-" . lc($name) . ".pl RAM size $i is OK; limit $SystemLimits->{$pref}->{$name} not exceeded;",_LOG_INTERNAL)
                    if $LogEnabled;
            }
        }
    }
}

sub check_modules
{
    my $modules = check_modules_flags();

    my $action;
    my $module;

    my $pref;

    for my $name (@$modules)
    {
        unlink $FlagsControlDir . "/" . $name
            if -e $FlagsControlDir . "/" . $name;

        ($module, $name, $action) = dispatch_module_name( $name );

        $pref = $module eq 'Modules'
            ? 'nm'
            : 'np';

        if ($action eq 'stop')
        {
            action_stop($pref, $name);
        }
        elsif ($action eq 'start')
        {
            delete $STOPED->{$name}
                if defined $STOPED->{$name};
            if ($pref eq 'nm')
            {
                system "$ENV{AKKADA}/bin/$pref-$name.pl $$"
                    for (1 .. $System->{$module}->{$name});
            }
            else
            {
                system "$ENV{AKKADA}/bin/$pref-run.pl $name $$"
                    for (1 .. $System->{$module}->{$name});
            }
        }
        elsif ($action eq 'restart')
        {
            action_restart($pref, $name);
        }
        log_debug("module $name action: $action", _LOG_WARNING);
    }
}

sub action_restart
{
    my $pref = shift;
    my $name = shift;
    action_stop($pref, $name);
    delete $STOPED->{$name}
        if defined $STOPED->{$name};
}

sub check_modules_flags
{
    my $file;
    my @result = ();

eval {
    opendir(DIR, $FlagsControlDir);
    while ( defined($file = readdir(DIR)) )
    {   
        next
            if $file !~ /manager\.process\./;
        push @result, $file;
    }
    closedir(DIR);
};

    return \@result;
}

sub get_process_table
{
    my $pt = {};
    $PROC = {};
    my @t;
    my $name;
    my $count;

    my $t = new Proc::ProcessTable;
    for ( @{$t->table} )
    {   
        next
            unless defined $_;
        next
            unless defined $_->cmndline;

        ++$pt->{ $_->cmndline }->{count};
        push @{$pt->{ $_->cmndline }->{processes}}, [$_->pid, $_->size];
    }

    for (keys %{ $System->{Modules} })
    {   
        $name = sprintf(qq|nm-%s.pl|, $_);
        $count = $System->{Modules}->{$_};

        @t = grep { /$name/ } keys %$pt;

        if (@t)
        {   
            $PROC->{Modules}->{$_} = [$pt->{ $t[0] }->{count}, $count, $pt->{ $t[0] }->{processes}];
        }
        else
        {   
            $PROC->{Modules}->{$_} = [0, $count];
        }
    };

    for (keys %{ $System->{Probes} })
    {
        $name = sprintf(qq|np-%s.pl|, $_);
        $count = $System->{Probes}->{$_};

        @t = grep { /$name/ } keys %$pt;

        if (@t)
        {
            $PROC->{Probes}->{$_} = [$pt->{ $t[0] }->{count}, $count, $pt->{ $t[0] }->{processes}];
        }
        else
        {
            $PROC->{Probes}->{$_} = [0, $count];
        }
    };
}

sub auto_start_modules
{
    for my $pr (sort keys %{ $System->{Probes} })
    {
        next
            if defined $STOPED->{ $pr };
        if ($PROC->{ Probes }->{ $pr }->[0] < $System->{Probes}->{ $pr })
        {
            for (1 .. $System->{Probes}->{ $pr } - $PROC->{ Probes }->{ $pr }->[0])
            {
                system "$ENV{AKKADA}/bin/np-run.pl $pr $$";
            }
            log_debug("auto module started: $pr", _LOG_WARNING);
        }
    }

    for my $md (keys %{ $System->{Modules} })
    {
        next
            if defined $STOPED->{ $md };
        if ($PROC->{ Modules }->{ $md }->[0] < $System->{Modules}->{ $md })
        {
            system "$ENV{AKKADA}/bin/nm-$md.pl $$"
                for (1 .. $System->{Modules}->{ $md } - $PROC->{ Modules }->{ $md }->[0]);
            log_debug("auto module started: $md", _LOG_WARNING);
        }
    }
}
