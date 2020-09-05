#!/akkada/bin/perl -w
use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use IPC::Open3;
use File::Spec;
use Symbol qw(gensym);
use Time::HiRes qw( gettimeofday tv_interval );
use threads;
use threads::shared;
use Data::Dumper;

use lib "$ENV{AKKADA}/lib";
use MyException qw(:try);
use Configuration;
use Log;
use Constants;
use Common;
use RRDs;
use DB;
use Entity;

our $PPID = $ARGV[0] || die;
$0 = 'nm-icmp_monitor.pl';

runtime(1);

our $LogEnabled = CFG->{LogEnabled};
our $Period = CFG->{ICMPMonitor}->{Period};
our $FPing = CFG->{ICMPMonitor}->{fping};
our $ThreadsCount = CFG->{ICMPMonitor}->{ThreadsCount};
our $FlagsControlDir = CFG->{FlagsControlDir};
our $StatusDir = CFG->{ICMPMonitor}->{StatusDir};
our $DefaultLostThreshold = CFG->{ICMPMonitor}->{DefaultLostThreshold};
our $DefaultDelayThreshold = CFG->{ICMPMonitor}->{DefaultDelayThreshold};
our $DisableUnreachableIPAtFirstTimeCheck = CFG->{ICMPMonitor}->{DisableUnreachableIPAtFirstTimeCheck};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $RRDCacheMaxEntries = CFG->{RRDCacheMaxEntries};
our $RRDCacheMaxEntriesNotOK = CFG->{RRDCacheMaxEntriesNotOK};
our $RRDCacheMaxEntriesRandomFactor = CFG->{RRDCacheMaxEntriesRandomFactor};

our $PingCount = 20; # musi byc parzysty!

our $DBH = DB->new();

our %IDS : shared = ();
our %IPS : shared = ();
our %IPM : shared = (); #lista median
our %MAX_DELAY_THRESHOLD : shared = ();
our %CHECK_LOST_THRESHOLD : shared = ();
our %RRD_CACHE : shared = ();
our $WAIT : shared = 0;
our $STOP : shared = 0;

our @THREADS = ();

$SIG{QUIT} = \&got_sig_quit;
$SIG{INT} = \&got_sig_quit;
$SIG{TERM} = \&got_sig_quit;
$SIG{USR1} = \&got_sig_usr1;
$SIG{USR2} = \&got_sig_usr2;

$SIG{CHLD} = sub 
{
    my $pid = waitpid(-1, 0);
    log_debug(">> eof PID $pid -> $?\n", _LOG_INTERNAL)
        if $LogEnabled;;
};

#main procedure
run();

sub lockdata 
{ 
    log_debug("thread " . threads->self->tid . " tring to set data lock by " . (caller(1))[3], _LOG_INTERNAL)
        if $LogEnabled;
    while ($WAIT)
    { 
        log_debug("thread " . threads->self->tid . " waiting for data lock by " . (caller(1))[3], _LOG_INTERNAL)
            if $LogEnabled;
        sleep 1; 
    }; 
    { 
        lock $WAIT; 
        $WAIT = 1;
    };
    log_debug("thread " . threads->self->tid . " data lock done by " . (caller(1))[3], _LOG_INTERNAL)
        if $LogEnabled;
}

sub unlockdata 
{ 
    { 
        lock $WAIT; 
        $WAIT = 0;
    }
    log_debug("thread " . threads->self->tid . " data unlock done by " . (caller(1))[3], _LOG_INTERNAL)
        if $LogEnabled;
}

sub _init
{
    lockdata();

    for (keys %IDS) { delete $IDS{$_}; };
    for (keys %IPS) { delete $IPS{$_}; };
    for (keys %MAX_DELAY_THRESHOLD) { delete $MAX_DELAY_THRESHOLD{$_}; };
    for (keys %CHECK_LOST_THRESHOLD) { delete $CHECK_LOST_THRESHOLD{$_}; };

    my $req = $DBH->exec(qq|SELECT id_entity,value FROM entities_2_parameters,parameters
        WHERE parameters.id_parameter=entities_2_parameters.id_parameter
        AND (parameters.name='ip' OR parameters.name='nic_ip')
        AND id_entity NOT IN (SELECT id_entity FROM entities_2_parameters,parameters
        WHERE parameters.id_parameter=entities_2_parameters.id_parameter
        AND parameters.name='nic_ip_icmp_check_disable')|
        )->fetchall_arrayref();
    for (@$req)
    {
        $IDS{$_->[0]} = $_->[1]; # id => ip
        $IPS{$_->[1]} = $_->[0]; # ip => id
    }

    $req = $DBH->exec(qq|SELECT id_entity, value FROM entities_2_parameters,parameters
        WHERE parameters.id_parameter=entities_2_parameters.id_parameter
        AND parameters.name='nic_ip_icmp_check_max_delay_threshold'|
        )->fetchall_arrayref();
    for (@$req)
    {
        next
            unless  defined $IDS{$_->[0]};
        $MAX_DELAY_THRESHOLD{$_->[0]} = $_->[1]; # id => nic_ip_icmp_check_max_delay_threshold
    }
    $req = $DBH->exec(qq|SELECT id_entity, value FROM entities_2_parameters,parameters
        WHERE parameters.id_parameter=entities_2_parameters.id_parameter
        AND parameters.name='nic_ip_icmp_check_lost_threshold'|
        )->fetchall_arrayref();
    for (@$req)
    {
        next
            unless defined $IDS{$_->[0]};
        $CHECK_LOST_THRESHOLD{$_->[0]} = $_->[1]; # id => nic_ip_icmp_check_lost_threshold
    }

    for (keys %IPM)
    {
        delete $IPM{$_}
            unless defined $IPS{$_};
    }

    unlockdata();

    if ($LogEnabled)
    {
        log_debug("main thread: init process finished", _LOG_INTERNAL);
        log_debug("main thread: IP addresses on the process list: " . join(", ", keys %IPS), _LOG_INTERNAL);
        log_debug("main thread: max delay thresholds table: " . Dumper(\%MAX_DELAY_THRESHOLD), _LOG_INTERNAL);
        log_debug("main thread: check lost thresholds table: " . Dumper(\%CHECK_LOST_THRESHOLD), _LOG_INTERNAL);
    }

}

sub run
{
    _init();

    for (1..$ThreadsCount)
    {
        push @THREADS, threads->new(\&icmp_check);
        log_debug("thread $_ created", _LOG_INTERNAL)
            if $LogEnabled;
    }

    while (1) 
    { 
        got_sig_quit()
            if ! kill(0, $PPID);
        log_debug("main loop", _LOG_INTERNAL)
            if $LogEnabled;

        _init()
            if flag_file_check($FlagsControlDir, 'entities_init.ICMPMonitor', 1);

        sleep ($Period ? $Period : 30);
    }
}

sub icmp_check
{
    my ($ip, @times, $pid, $inh, $outh, $errh, $result, $nic_ip_icmp_check_disable, $st);

    my $tid = threads->self->tid();

    log_debug("thread $tid is starting to work", _LOG_INTERNAL)
        if $LogEnabled;

    $DBH = DB->new();

    my $iteration;
    my %ids;
    my %ips;
    my %ipm;
    my @ipsk;
    my %mdt;
    my %clt;
    my %tmp;
    my $tm;
    my $avg;

    while(!$STOP)
    {
        $tm = [gettimeofday];

        ++$iteration;
        log_debug("thread $tid iteration $iteration", _LOG_INTERNAL)
            if $LogEnabled;

        @ipsk = ();

        while (! @ipsk) 
        {
            @ipsk = ();
            %tmp = ();
#use Data::Dumper; log_debug("thread $tid 1: " . Dumper(\%IPS), _LOG_ERROR);
            lockdata();
            %ids = %IDS;
            %ips = %IPS;
            %ipm = %IPM;
            %mdt = %MAX_DELAY_THRESHOLD;
            %clt = %CHECK_LOST_THRESHOLD;
            unlockdata();

            for (keys %ips)
            {
                $tmp{$_} = defined $ipm{$_} ? $ipm{$_} : 0;
            }

#use Data::Dumper; log_debug("thread $tid 2: " . Dumper(\%tmp), _LOG_ERROR);
            @ipsk = sort { $tmp{$a} <=> $tmp{$b} } keys %tmp;

#use Data::Dumper; log_debug("thread $tid 3: " . Dumper(\@ipsk), _LOG_ERROR);
            @ipsk = get_part_of_array(\@ipsk, $ThreadsCount, $tid);
#use Data::Dumper; log_debug("thread $tid 4: " . Dumper(\@ipsk), _LOG_ERROR);

            if (! @ipsk)
            {
                log_debug("thread $tid: nothing to do. sleepeing 5 seconds", _LOG_INFO)
                    if $LogEnabled;
                sleep(5);
            }
        }

        log_debug("thread $tid current job: " . join(", ", @ipsk), _LOG_INTERNAL)
            if $LogEnabled;

        $pid = open3($inh,$outh,$errh, @$FPing, $PingCount, @ipsk);

        for (<$outh>)
        {

            if (/^open3:/)
            {
                log_debug("thread $tid: $_", _LOG_ERROR)
                    if $LogEnabled;
                next;
            }

            next
                if /duplicate/;

            chomp;
            @times = split /\s+/;

            $ip = shift @times;

            next
                unless defined $ips{$ip}; # czasami fping zwraca ICMP redirect itp.

            shift @times;
            @times = sort {$a <=> $b} grep { ! /^-$/ } @times;

            for my $i (0..$#times)
            {
                $times[$i] = $times[$i] / 1000; 
            }

            $result = {};

            $avg = 0;
            if (@times)
            {
                $avg += $_ for @times;
                $avg *= 1000;
                $avg /= @times;
                $avg = sprintf("%.2f", $avg);
            }
            else
            {
                $avg = '-';
            }

            $result->{response} = [sort @times];
            $result->{median} = $result->{response}->[ $PingCount/2 ];
            $result->{min} = @times ? ($times[0] * 1000) : '-';
            $result->{avg} = $avg;
            $result->{max} = @times ? ($times[$#times] * 1000) : '-';
            $result->{loss} = $PingCount - $#times - 1;
            $result->{lossperc} = sprintf("%.2f", ($result->{loss} * 100 / $PingCount) );


            ($nic_ip_icmp_check_disable, $st) = update_status($ip, $result, \%ids, \%ips, \%mdt, \%clt); #lokuje dane - upd median
            rrd_save($ip, $result, $nic_ip_icmp_check_disable, $st); #rrd_save lokuje dane
        }

        waitpid($pid, 0);
        close $inh
            if defined $inh;
        close $outh
            if defined $outh;
        close $errh
            if defined $errh;

        $tm = tv_interval( $tm, [gettimeofday] );

        log_debug(sprintf("thread $tid: iteration completed in %.4f sec", $tm), _LOG_INFO)
            if $LogEnabled;

        sleep ($Period ? $Period : 30);
    }
    $DBH->dbh->disconnect();
    exit_cleaning(\%ips);
}

sub disable_ip_check
{
    lockdata();

    my $ip = shift;

    my $id_entity = $IPS{$ip};

    log_debug(sprintf(qq|thread %s disabling icmp check for entity %s ip %s|, threads->self->tid, $id_entity, $ip), _LOG_WARNING)
        if $LogEnabled;

    delete $IPS{$ip};
    delete $IDS{ $id_entity };

    my $entity;

    my $res = $DBH->exec(sprintf(qq| SELECT id_entity FROM entities WHERE id_entity=%s|, $id_entity))->fetchrow_arrayref;
    if ( defined $res && @$res == 1 )
    {
        $entity = Entity->new($DBH, $id_entity);
    }
    else
    {
        unlockdata();
        log_debug(sprintf(qq|thread %s disabling icmp check for entity %s ip %s failed - entity does not exists|, 
            threads->self->tid, $id_entity, $ip), _LOG_WARNING)
            if $LogEnabled;
        return;
    }

    $entity->params('nic_ip_icmp_check_disable', 1);

    flag_file_check($StatusDir, sprintf(qq|%s.lost|,$ip),1);
    flag_file_check($StatusDir, sprintf(qq|%s.delay|,$ip),1);
    flag_file_check($FlagsControlDir, 'entities_init.ICMPMonitor', 1);

    unlockdata();
}

sub rrd_save    
{               
    my $ip = shift;
    my $result  = shift;
    my $nic_ip_icmp_check_disable = shift;
    my $status = shift;
                        
    my $rrd_file = sprintf(qq|%s/%s.icmp_monitor|, $RRDDir, $ip);
                
    if (! -e $rrd_file && $nic_ip_icmp_check_disable && $DisableUnreachableIPAtFirstTimeCheck)
    {
        disable_ip_check($ip);
        return;
    }
    elsif (! -e $rrd_file && ! $nic_ip_icmp_check_disable)
    {
        my @data = (
        $rrd_file, "--step",300,
        "RRA:AVERAGE:0.5:1:600",
        "RRA:AVERAGE:0.5:6:700",
        "RRA:AVERAGE:0.5:24:775",
        "RRA:AVERAGE:0.5:288:797",
        "RRA:MIN:0.5:1:600",
        "RRA:MIN:0.5:6:700",
        "RRA:MIN:0.5:24:775",
        "RRA:MIN:0.5:288:797",
        "RRA:MAX:0.5:1:600",
        "RRA:MAX:0.5:6:700",
        "RRA:MAX:0.5:24:775",
        "RRA:MAX:0.5:288:797",
        "RRA:LAST:0.5:1:600",
        "RRA:LAST:0.5:6:700",
        "RRA:LAST:0.5:24:775",
        "RRA:LAST:0.5:288:797",
  "RRA:HWPREDICT:1440:0.1:0.0035:288:3",  ### ???????????
  "RRA:SEASONAL:288:0.1:2",
  "RRA:DEVPREDICT:1440:5",
  "RRA:DEVSEASONAL:288:0.1:2",
  "RRA:FAILURES:288:7:9:5",

        );
        push @data, qq|DS:loss:GAUGE:300:0:$PingCount|;
        push @data, qq|DS:median:GAUGE:300:0:$PingCount|;
        push @data, map { "DS:ping${_}:GAUGE:300:0:10" } 1..$PingCount;

        RRDs::create ( @data );
        my $error = RRDs::error();
        log_exception( ERRDs->new( sprintf(qq|ip %s file %s: %s|, $ip, $rrd_file, $error)) , _LOG_WARNING )
            if $error;
    }

    my @data = (time);

    push @data, map { defined $result->{$_} ? $result->{$_} : 'U' } qw/loss median/;

    if ($result->{loss})
    {
        for (1..$result->{loss})
        {
            push @{$result->{response}}, 'U';
        }
    }

    push @data, map { $_ ne '' ? $_ : 'U' } @{$result->{response}};

    my $data_row = join(":", $ip, @data);

    lockdata();

    $RRD_CACHE{$data_row} = 1;

    log_debug("thread " . threads->self->tid . ": " . $ip . ": status $status : items in cache:\n" 
        . join("\n", grep { /^$ip:/ } keys %RRD_CACHE), _LOG_INTERNAL)
        if $LogEnabled;

    if ((grep { /^$ip:/ } keys %RRD_CACHE) - int(rand( $RRDCacheMaxEntriesRandomFactor ))
        >= ($status ? $RRDCacheMaxEntriesNotOK : $RRDCacheMaxEntries))
    {
        RRDs::update ($rrd_file, 
            sort { (split ':', $a, 2)[0] <=> (split ':', $b, 2)[0] } 
            map { my $tmp = $_; $tmp =~ s/^$ip://; $tmp; } 
            grep { /^$ip:/ } 
            keys %RRD_CACHE);

        delete @RRD_CACHE{grep { /^$ip:/ } keys %RRD_CACHE};


        my $error = RRDs::error();
        if ($error)
        {
            log_exception( ERRDs->new( sprintf(qq|ip %s file %s: %s|, $ip, $rrd_file, $error)) , _LOG_WARNING );
        }
        elsif ($LogEnabled)
        {
            log_debug("thread " . threads->self->tid . ": " . $ip . ": rrd data saved", _LOG_DEBUG);
        }
    }
    unlockdata();
}

sub update_status
{
    my $ip = shift;
    my $result = shift;

    my $ids = shift;
    my $ips = shift;
    my $mdt = shift;
    my $clt = shift;

    my $status = 0;
    my $nic_ip_icmp_check_disable = 0;

    my $id = $ips->{$ip};

    log_debug("thread " . threads->self->tid . " unknown ip address $ip!", _LOG_ERROR)
        unless defined $id;
    log_debug("thread " . threads->self->tid . " bad data in module for ip addres $ip!", _LOG_ERROR)
        unless defined $ids->{$id};

    if (defined $id && defined $ids->{$id})
    {
        lockdata();
        $IPM{$ip} = defined $result->{median} ? $result->{median} : 5;
        unlockdata();
    }

    if ((defined $clt->{ $id } && $result->{lossperc} > $clt->{ $id })
        || (! defined $clt->{ $id } && $result->{lossperc} > $DefaultLostThreshold))
    {
        flag_file_check($StatusDir, sprintf(qq|%s.delay|,$ip),1);
        flag_files_create($StatusDir, sprintf(qq|%s.lost|,$ip));
        $status = 1;
        $nic_ip_icmp_check_disable = 1
            if $result->{loss} == $PingCount;
    } elsif (
        (defined $mdt->{ $id } && $result->{median} > $mdt->{ $id })
        || (! defined $mdt->{ $id } && $result->{median} > $DefaultDelayThreshold))
    {
        $status = 1;
        flag_file_check($StatusDir, sprintf(qq|%s.lost|,$ip),1);
        flag_files_create($StatusDir, sprintf(qq|%s.delay|,$ip));
    }
    else
    {
        flag_file_check($StatusDir, sprintf(qq|%s.lost|,$ip),1);
        flag_file_check($StatusDir, sprintf(qq|%s.delay|,$ip),1);
    }
    
    log_debug("thread " . threads->self->tid . " address $ip: id $id, status $status, max_delay " 
        . (defined $mdt->{ $id } ? $mdt->{ $id } : $DefaultDelayThreshold) 
        . " delay " . (defined $result->{median} ? $result->{median} : "?")
        . " check_lost " . (defined $clt->{ $id } ? $clt->{ $id } : $DefaultLostThreshold)
        . " lost " . (defined $result->{loss} ? $result->{loss} : "?")
        , _LOG_DEBUG)
        if $LogEnabled;
    open F, ">$StatusDir/$ip";

    print F sprintf(qq|loss\|%s\n|, defined $result->{loss} ? $result->{loss} : 0);
    print F sprintf(qq|lossperc\|%s\n|, defined $result->{lossperc} ? $result->{lossperc} : 0);
    print F sprintf(qq|median\|%s\n|, defined $result->{median} ? $result->{median} : 0);
    print F sprintf(qq|avg\|%s\n|, defined $result->{avg} ? $result->{avg} : 0);
    print F sprintf(qq|min\|%s\n|, defined $result->{min} ? $result->{min} : 0);
    print F sprintf(qq|max\|%s\n|, defined $result->{max} ? $result->{max} : 0);
    print F sprintf("response\|%s\n", join(":", map { defined $_ ? $_ : '' } @{ $result->{response} }));

    close F;

    return ($nic_ip_icmp_check_disable, $status);
}

sub exit_cleaning
{
    my $ips = shift;
    my $rrd_file;

    for my $ip (keys %$ips)
    {
        if (grep { /^$ip:/ } keys %RRD_CACHE)
        {
            $rrd_file = sprintf(qq|%s/%s.icmp_monitor|, $RRDDir, $ip);
            RRDs::update ($rrd_file,
                sort { (split ':', $a, 2)[0] <=> (split ':', $b, 2)[0] }
                map { my $tmp = $_; $tmp =~ s/^$ip://; $tmp; }
                grep { /^$ip:/ }
                keys %RRD_CACHE);
        }
    }
    log_debug(sprintf(qq|thread %s is exiting|, threads->self->tid), _LOG_WARNING)
        if $LogEnabled;
}

sub got_sig_quit 
{
    log_debug("got sig quit. starting end procedure...", _LOG_WARNING)
        if $LogEnabled;
    {
        lock $STOP;
        $STOP = 1;
    }

    for my $thr (threads->list) 
    { 
        if ($thr->tid && !threads::equal($thr, threads->self)) 
        { 
            $thr->join; 
        } 
    }

    log_debug("end procedure completed. exiting.", _LOG_WARNING)
        if $LogEnabled;
    exit;
}

sub get_part_of_array
{
    my ($ar, $parts_count, $offset) = @_;

    return ()
        unless @$ar;

    my $ar_size = scalar @$ar;
    my $length = int($ar_size/$parts_count);    
    $length = 1
        if $length < 1;

    if ($offset > $parts_count-1)
    {
        $offset--;
        $offset = $offset*$length;
        $length = $ar_size - $offset;
    }
    else
    {
        $offset--;
        $offset = $offset*$length;
    }

    return ()
        unless $length > 0;

    return splice(@$ar, $offset, $length);
}

