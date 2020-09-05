package SysStat;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;          
use MyException qw(:try);
use Configuration;
use Log;
use Constants;
use Common;
use DB;
use Data::Dumper;
use RRDs;
use Time::HiRes qw( gettimeofday );


our $FlagsControlDir;
our $FlagsUnreachableDir;
our $FlagsNoSNMPDir;
our $LogEnabled;
our $Period;
our $RRDDir;
our $ProbesMapRev;
our $ProbesMap;
our $LastCheckDir;
our $LastCheckHistogramFilePrefix;
our $LastCheckHistogramDir;
our $GrepBin;

our $FreshnessGuardEnabled;
our $FreshnessThreshold;
our $FreshnessStartCalcAfter;
our $FreshnessStaleAlarmLevel;
our $FreshnessStarted;



sub cfg_init
{
    Configuration->reload_cfg;

    $FlagsControlDir = CFG->{FlagsControlDir};
    $FlagsUnreachableDir = CFG->{FlagsUnreachableDir};
    $FlagsNoSNMPDir = CFG->{FlagsNoSNMPDir};
    $LogEnabled = CFG->{LogEnabled};
    $Period = CFG->{SysStat}->{Period};
    $RRDDir = CFG->{Probe}->{RRDDir};
    $ProbesMapRev = CFG->{ProbesMapRev};
    $ProbesMap = CFG->{ProbesMap};
    $LastCheckDir = CFG->{Probe}->{LastCheckDir};
    $LastCheckHistogramFilePrefix = CFG->{SysStat}->{LastCheckHistogramFilePrefix};
    $LastCheckHistogramDir = CFG->{SysStat}->{LastCheckHistogramDir};
    $GrepBin = CFG->{GrepBin};

    $FreshnessGuardEnabled = CFG->{SysStat}->{FreshnessGuardEnabled};
    $FreshnessThreshold = CFG->{SysStat}->{FreshnessThreshold};
    $FreshnessStartCalcAfter = CFG->{SysStat}->{FreshnessStartCalcAfter};
    $FreshnessStaleAlarmLevel = CFG->{SysStat}->{FreshnessStaleAlarmLevel};
    $FreshnessStarted = 0;

    log_debug("configuration initialized", _LOG_WARNING)
        if $LogEnabled;
}

use constant
{
    DBH => 1,
    PROBES => 2,
    STALE => 3,
};


sub new
{
    cfg_init();

    my $this = shift;
    my $class = ref($this) || $this;

    my $self = [];

    $self->[DBH] = DB->new();
    $self->[STALE] = {};

    bless $self, $class;

    $self->[PROBES] = $FreshnessGuardEnabled ? load_probes($self->dbh) : undef;

    $SIG{USR1} = \&got_sig_usr1;
    $SIG{USR2} = \&got_sig_usr2;
    $SIG{HUP} = \&cfg_init;
    $SIG{TRAP} = \&trace_stack;
    $SIG{QUIT} = \&got_sig_quit;
    $SIG{INT} = \&got_sig_quit;
    $SIG{TERM} = \&got_sig_quit;

    return $self;
}

sub got_sig_quit
{
    log_debug("stopped", _LOG_WARNING);
    exit;
}


sub dbh
{
    return $_[0]->[DBH];
}

sub stale
{
    return $_[0]->[STALE];
}

sub probes
{
    return $_[0]->[PROBES];
}

sub run
{
    my $self = shift;
    my $ppid = shift;
    my $file;
    my $last_check = 0;

    while (1) 
    { 
        exit
            if ! kill(0, $ppid);

        if (! $FreshnessStarted && $FreshnessGuardEnabled && time - $^T > $FreshnessStartCalcAfter)
        {
            ++$FreshnessStarted;
            log_debug("freshness guard started", _LOG_WARNING)
                if $LogEnabled;
        }

        $self->stat_logs;
        $self->stat_status;

        $last_check += $Period;

        if ($last_check > 1) #5*$Period)
        {
            $last_check = 0;
            $self->stat_last_check;
        }

        sleep ($Period ? $Period : 15);
    }
}

sub stat_last_check
{
    my $self = shift;

    my $probes = $self->probes;
    my $stale = $self->stale;

    my $result = {};
    my $tm = time;
    my $file;

    my $h = {};

    my $req = $self->dbh->exec(qq|SELECT id_entity,monitor,status,id_probe_type,check_period,id_parent 
        FROM entities,links 
        WHERE entities.id_entity=links.id_child|)->fetchall_hashref("id_entity");

    open(F, sprintf(qq"cd %s; %s : * 2>/dev/null|", $LastCheckDir, $GrepBin));
    while (<F>)
    {
        s/\n//g;
        #s/$LastCheckDir\///g;
        /(\d*):(\d*):(\d*)/;

        next
            unless $req->{$1}->{monitor} && $req->{$1}->{status} != _ST_BAD_CONF; 

        $tm - $2 > $3
            ? $result->{global}->{$tm - $2}++
            : $result->{global}->{$3}++;
        $tm - $2 > $3
            ? $result->{$req->{$1}->{id_probe_type}}->{$tm - $2}++
            : $result->{$req->{$1}->{id_probe_type}}->{$3}++;

#freshness monitor
        if (
            $FreshnessGuardEnabled   #guard enabled
            && $FreshnessStarted      # freshness started
            && ! flag_file_check($FlagsUnreachableDir, $1)  #entity reachable
            && ! flag_file_check($FlagsUnreachableDir, $req->{$1}->{id_parent}) #parent reachable
            && ! 
            (
                $probes->{ $ProbesMapRev->{ $req->{$1}->{id_probe_type} } }->snmp 
                && flag_file_check($FlagsNoSNMPDir, $req->{$1}->{id_parent})

            ) #entity snmp parent snmp agent ok;
            && time - $2 > $FreshnessThreshold * $req->{$1}->{check_period} # last check outdated
           )
        {
            if (! defined $stale->{$1})
            {
                $self->raise_freshness_alarm($1, $req->{$1}->{check_period});
                ++$stale->{$1};
                log_debug("entity $1 is stale", _LOG_DEBUG)
                    if $LogEnabled;
            }
        }
        else
        {
            if (defined $stale->{$1})
            {
                delete $stale->{$1};
                log_debug("entity $1 is fresh", _LOG_DEBUG)
                    if $LogEnabled;
            }
        }
=pod
my $probe = $ProbesMapRev->{ $entity->id_probe_type };
    if (flag_file_check($FlagsUnreachableDir, $self->id_parent, 0))
    {
   elsif ($self->snmp && $entity->has_parent_nosnmp_status)

lsif ($entity->have_i_unreachable_status || $entity->status == _ST_UNREACHABLE)

sub has_parent_nosnmp_status
{
    my $self = shift;
    return flag_file_check($FlagsNoSNMPDir, $self->id_parent, 0);
}
=cut

    }
    closedir(F);

    my %template = (
        65 => 0,
        75 => 0,
        85 => 0,
        95 => 0,
        125 => 0,
        185 => 0,
        245 => 0,
        325 => 0,
        605 => 0,
        9999 => 0,
        'total' => 0,
    );

    my %h = ();

    for my $k (keys %$result)
    {
        $h{$k} = 
        {
            65 => 0,
            75 => 0,
            85 => 0,
            95 => 0,
            125 => 0,
            185 => 0,
            245 => 0,
            325 => 0,
            605 => 0,
            9999 => 0,
            'total' => 0,
        }
            unless defined $h{$k};

        for (keys %{$result->{$k}})
        {
            $h{$k}{total} += $result->{$k}->{$_};
            if ($_ < 65) { $h{$k}{65} += $result->{$k}->{$_} }
            elsif ($_ < 75) { $h{$k}{75} += $result->{$k}->{$_} }
            elsif ($_ < 85) { $h{$k}{85} += $result->{$k}->{$_} }
            elsif ($_ < 95) { $h{$k}{95} += $result->{$k}->{$_} }
            elsif ($_ < 125) { $h{$k}{125} += $result->{$k}->{$_} }
            elsif ($_ < 185) { $h{$k}{185} += $result->{$k}->{$_} }
            elsif ($_ < 245) { $h{$k}{245} += $result->{$k}->{$_} }
            elsif ($_ < 325) { $h{$k}{325} += $result->{$k}->{$_} }
            elsif ($_ < 605) { $h{$k}{605} += $result->{$k}->{$_} }
            else { $h{$k}{9999} += $result->{$k}->{$_} }
        }
    }

#use Data::Dumper; log_debug(Dumper(\%h), _LOG_ERROR);

    for my $k (keys %h)
    {
        $file = "$LastCheckHistogramDir/$LastCheckHistogramFilePrefix.$k";
        if (-e $file)
        {
            open F, "+<$file";
        }
        else
        {
            open F, ">$file";
        }
        seek(F, 0, 0);
        print F join("\n", map {"$_||$h{$k}{$_}"} keys %{$h{$k}});
        truncate(F, tell(F));
        close F;
    }
}

sub raise_freshness_alarm
{
    my $self = shift;
    my $id_entity = shift;
    my $check_period = shift;

    my $errmsg = sprintf(qq|last check older that %s|, duration_row($FreshnessThreshold * $check_period));
    my $entity;

    try
    {
        log_debug("getting entity $id_entity from database", _LOG_INTERNAL)
            if $LogEnabled;

        $entity = Entity->new($self->dbh, $id_entity, 0);
    }
    catch  EEntityDoesNotExists with
    {
        log_debug("entity $id_entity does not exists", _LOG_WARNING)
            if $LogEnabled;
    }
    except
    {
    };

    $entity->set_status($FreshnessStaleAlarmLevel, $errmsg);
}

sub stat_logs
{
    my $self = shift;

    my $req = $self->dbh->exec(qq|SELECT COUNT(id) FROM history24|)->fetchrow_arrayref()->[0];

    $self->rrd_save('logs', {logs => 'COUNTER'}, { logs => $req });
}

sub stat_status
{
    my $self = shift;

    my $req = $self->dbh->exec(qq|SELECT status,count(status) as number FROM entities WHERE status_weight<>0 GROUP BY status|)->fetchall_hashref("status");

    my $data = {};
    my $cfg = {};
    my $name;

    for (0,1,2,3,4,5,6,64,124,125,126,127)
    {
        $name = status_name($_);
        $name =~ s/ //g;
        $data->{$name} = defined $req->{$_} ? $req->{$_}->{number} : 0;
        $cfg->{$name} = 'GAUGE';
    }

    $self->rrd_save('status', $cfg, $data);
}

sub rrd_save
{
    my $self = shift;
    my $name = shift;
    my $ds = shift;
    my $data = shift;

    my $rrd_file = sprintf(qq|%s/sysstat.%s|, $RRDDir, $name);

    if (! -e $rrd_file)
    {
        my @data = (
        $rrd_file, "--step",60,
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
            "RRA:HWPREDICT:1440:0.1:0.0035:288:3",
            "RRA:SEASONAL:288:0.1:2",
            "RRA:DEVPREDICT:1440:5",
            "RRA:DEVSEASONAL:288:0.1:2",
            "RRA:FAILURES:288:7:9:5",
        );

        for (sort keys %$ds)
        {
            push @data, sprintf(qq|DS:%s:%s:300:U:U|, $_, $ds->{$_});
        }
        RRDs::create ( @data );
        my $error = RRDs::error();
        log_exception( ERRDs->new( sprintf(qq|file %s: %s|, $rrd_file, $error)) , _LOG_WARNING )
            if $error;
    }

#use Data::Dumper; log_debug(Dumper([$rrd_file, join(":", time, map { defined $data->{$_} ? $data->{$_} : 'U' } sort keys %$ds)]), _LOG_ERROR);
    RRDs::update ($rrd_file, join(":", time, map { defined $data->{$_} ? $data->{$_} : 'U' } sort keys %$ds));

    my $error = RRDs::error();
    log_debug( sprintf(qq|file %s: %s|, $rrd_file, $error) , _LOG_WARNING )
        if $error;
}

1;
