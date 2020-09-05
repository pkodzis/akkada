package Probe;

use vars qw($AUTOLOAD);

our $VERSION = 0.41;

use strict;          
use MyException qw(:try);
use Entity;
use Configuration;
use Log;
use Constants;
use Common;
use RRDs;
use Time::HiRes qw( gettimeofday tv_interval );
use URLRewriter;
use HTML::Table;

use constant ID_PROBE_TYPE_VALUE => 0;

use constant
{
    ID_PROBE_TYPE => 0,
    DBH => 1,
    ENTITIES => 2,
    ENTITY_CACHE => 3,
    ERRMSG => 4,
    STATUS => 5,
    THRESHOLD_MEDIUM => 6,
    THRESHOLD_HIGH => 7,
    CACHE => 8,
    RRD_CACHE => 9,
    _Q_FAST => 'fast',
    _Q_NORMAL => 'normal',
    _Q_SLOW => 'slow',
};

our $FlagsControlDir;
our $FlagsUnreachableDir;
our $LastCheckDir;
our $FlagsCheckTimeSlots;
our $ForceCheckTimeSlots;
our $RRDDir;
our $LogEnabled;
our $ThresholdMediumDefault;
our $ThresholdHighDefault;
our $StatusDir;
our $ProbesMaxCountPerCycle;
our $EntityTestDeltaRandomFactor;
our $RRDCacheMaxEntries;
our $RRDCacheMaxEntriesNotOK;
our $RRDCacheMaxEntriesRandomFactor;
our $QueuePolicy;
our $BadConfReload;
our $TreeCacheDir;
our $FlagsMaxAge;


our $SEEN_UNREACHABLE = {};

sub init_globals
{
    $FlagsMaxAge = CFG->{FlagsMaxAge};
    $FlagsControlDir = CFG->{FlagsControlDir};
    $FlagsUnreachableDir = CFG->{FlagsUnreachableDir};
    $LastCheckDir = CFG->{Probe}->{LastCheckDir};
    $FlagsCheckTimeSlots = CFG->{Probe}->{FlagsCheckTimeSlots};
    $ForceCheckTimeSlots = CFG->{Probe}->{ForceCheckTimeSlots};
    $RRDDir = CFG->{Probe}->{RRDDir};
    $LogEnabled = CFG->{LogEnabled};
    $ThresholdMediumDefault = CFG->{Probe}->{ThresholdMediumDefault};
    $ThresholdHighDefault = CFG->{Probe}->{ThresholdHighDefault};
    $StatusDir = CFG->{Probe}->{StatusDir};
    $ProbesMaxCountPerCycle = CFG->{ProbesMaxCountPerCycle};
    $EntityTestDeltaRandomFactor = CFG->{EntityTestDeltaRandomFactor};
    $RRDCacheMaxEntries = CFG->{RRDCacheMaxEntries};
    $RRDCacheMaxEntriesNotOK = CFG->{RRDCacheMaxEntriesNotOK};
    $RRDCacheMaxEntriesRandomFactor = CFG->{RRDCacheMaxEntriesRandomFactor};
    $QueuePolicy = CFG->{Probe}->{QueuePolicy};
    $BadConfReload = CFG->{Probe}->{BadConfReload};
    $TreeCacheDir = CFG->{Web}->{TreeCacheDir};
}

sub version
{
    return eval('$' .  ref($_[0]) . '::VERSION');
}

sub name
{
    return 'unknown probe name';
}

sub new
{
    my $this = shift;
    my $class = ref($this) || $this;

    init_globals();

    my $self = [];

    $self->[DBH] = undef;
    $self->[ID_PROBE_TYPE] = ID_PROBE_TYPE_VALUE;
    $self->[ERRMSG] = [];
    $self->[STATUS] = 0;
    $self->[ENTITIES] = {};
    $self->[CACHE] = { counters => {}, strings => {} };
    $self->[RRD_CACHE] = {};
    $self->[ENTITY_CACHE] = {};

    bless $self, $class;

    $self->[THRESHOLD_HIGH] = $ThresholdHighDefault;
    $self->[THRESHOLD_MEDIUM] = $ThresholdMediumDefault;

    return $self;
}

sub rrd_cache
{
    return $_[0]->[RRD_CACHE];
}

sub entity_cache
{
    return $_[0]->[ENTITY_CACHE];
}

sub cache
{
    my $self = shift;
    my $what = @_ ? shift : 'counters';
    return $self->[CACHE]->{$what};
}

sub cache_keys
{
    return [];
}

sub alarm_utils_button
{
    return 0;
}

sub _entity_add
{
    my ($self, $entity, $dbh) = @_;
    $entity = entity_add($entity, $self->dbh);
    flag_files_create($TreeCacheDir, sprintf(qq|add.%s|, $entity->id_entity) );
    return $entity;
}

sub cache_string
{   
    my $self = shift;
    my $id_entity = shift;
    my $key  = shift;
    
    if (! @_)
    {
        return $self->cache('strings')->{$id_entity}->{$key};
    }   
    
    my $value  = shift;
    
    my $old = $self->cache('strings')->{$id_entity};
    
    if (! defined $old)
    {
        $old->{$key} = [0, $value];
    }   
    elsif (! defined $old->{$key})
    {   
        $old->{$key} = [0, $value];
    }   
    else     
    {   
        if ( $old->{$key}->[1] eq $value)
        {
             $old->{$key} = [0, $value];
        }
        else
        {
             $old->{$key} = [1, $value];
        }
    }
    
    $self->cache('strings')->{$id_entity} = $old;
}   

sub cache_update
{
    my $self = shift;
#use Data::Dumper; log_debug('xxx: ' . Dumper(\@_) . "::$_[0]", _LOG_INFO); 
    return 
        unless @_ && defined $_[0];
    my $id_entity = shift;
    my $values = @_ && defined $_[0] ? shift : undef;
#use Data::Dumper; log_debug('yyy: ' . "$id_entity", _LOG_INFO); 

    if (! defined $values || ref($values) eq '')
    {
#use Data::Dumper; log_debug(Dumper($id_entity, $values), _LOG_INFO); 
        return;
    }

    my $ks = $self->cache_keys;
    my $timestamp = [gettimeofday];
    my $old = $self->cache->{$id_entity};
    my $new = {};
#use Data::Dumper; log_debug(Dumper($id_entity, $values, $ks, $old), _LOG_INFO);
    if (! defined $old)
    {   
        for (@$ks)
        {   
            $new->{$_} = [$values->{$_}, 'U'];
        }
    }  
    else
    {   
        my $old_v;   
        for my $key (@$ks)
        {   
            $old_v = $old->{$key};

            if (! defined $old_v)
            {   
                $new->{$key} = [$values->{$key}, 'U'];
            }
            elsif (defined $old_v && defined $old_v->[0] && $old_v->[0] eq 'U')
            {   
                $new->{$key} = [$values->{$key}, 'U'];
            }
            elsif (! defined $old_v->[0])
            {
                $new->{$key} = [$values->{$key}, 0];
            }
            elsif (! $old_v->[0])
            {
                $new->{$key} = [$values->{$key}, 0];
            }
            elsif ($values->{$key} eq '')
            {
                $new->{$key} = [ $values->{$key} , 'U'];
            }
            else
            {
                $new->{$key} = [$values->{$key}, $values->{$key} - $old_v->[0] ];
                $new->{$key} = [$new->{$key}->[0], 'U']
                    if $new->{$key}->[1] < 0;
            }

        }
    }

    $new->{delta} = $old && $old->{timestamp} ? tv_interval($old->{timestamp}, $timestamp) : 0;
    $new->{timestamp} = $timestamp;

    if ($new->{delta})
    {
        for ( grep { $_ ne 'delta' && $_ ne 'timestamp' } @$ks)
        {
            if ($new->{$_}->[1] eq 'U')
            {
                $new->{$_}->[1] = 0;
#                $values->{$_} = 'U';
            }
            else
            {
                $new->{$_}->[1] = $new->{$_}->[1]/$new->{delta};
#                $values->{$_} = $new->{$_}->[1];
            }
        }
    }
    else
    {
        for ( grep { $_ ne 'delta' && $_ ne 'timestamp' } keys %$new)
        {
            $new->{$_}->[1] = 'U';
#            $values->{$_} = 'U';
        }
    }

    $self->cache->{$id_entity} = $new;

}

sub desc_brief
{
    my ($self, $entity) = @_;
    
    my $result = [];

    return $result;
}

sub desc_brief_get
{
    my ($self, $entity) = @_;

    my $result = $self->desc_brief($entity);

    my $s = $entity->description;
    push @$result, "<b>$s</b>"
        if defined $s && $s;

    $s = $entity->params_own;
    if (defined $s->{ip} && $s->{ip})
    {
        push @$result, sprintf(qq|<b>%s</b>|, $s->{ip});
    }
    else
    {
        $s = $entity->params('nic_ip');
        push @$result, sprintf(qq|<b>%s</b>|, $s)
            if $s;
    }

    return $result;
}

sub dbh
{
    my $self = shift;
    if (! defined $self->[DBH])
    {
        $self->[DBH] = DB->new();
    }
    return $self->[DBH];
}

sub entities
{
    return $_[0]->[ENTITIES];
}

sub menu_stat_no_default
{
    return 0;
}

sub menu_stat
{
    return 0;
}

sub id_probe_type
{
    my $self = shift;
    throw EReadOnlyMethod
        if @_;
    return $self->[ID_PROBE_TYPE];
}

sub flags_check_entities_init
{
    my $self = shift;

    my $file = sprintf (qq|%s/entities_init.%s|, $FlagsControlDir, $$);

    $self->entities_init()
        if flag_file_check( $FlagsControlDir, sprintf(qq|entities_init.%s|, $$), 1);
    $self->add_entities();
}

sub add_entities
{
    my $self = shift;
    my $id_probe_type = $self->id_probe_type;

    opendir(DIR, $FlagsControlDir)
        or log_debug("directory probems: $!", _LOG_ERROR);
    my @job = grep { /^add\.$id_probe_type\./ } readdir(DIR);
    closedir DIR;

    for (@job)
    {
        $self->add_entity($_);
    }
}

sub add_entity
{
    my $self = shift;
    my $file = shift;

    return
        unless flag_file_check($FlagsControlDir, $file, 1);

    my $s = sprintf("entities table add new entity: %s before: %s; ", $file, scalar( keys %{ $self->entities } ) );

    my $id_entity = (split /\./, $file)[2];

    my $entity = $self->dbh->exec( sprintf(qq|SELECT check_period FROM entities WHERE id_entity=%s|, 
        $id_entity) )->fetchrow_hashref;

    if (! $entity)
    {
        log_debug("failed to add entity $file", _LOG_ERROR);
        return;
    }

    $self->entities->{ $id_entity }->{check_period} = $entity->{check_period};

    $file = sprintf("%s/%s", $LastCheckDir, $id_entity);
    if (! -e $file )
    {
        $self->entities->{ $id_entity }->{last_check} = time  - 10000;
        $self->entities->{ $id_entity }->{queue} = _Q_NORMAL;
        $self->entities->{ $id_entity }->{queue_clsf} = 0;
        try
        {
            open F, ">$file";
            print F sprintf("%s:%s", $self->entities->{ $id_entity }->{last_check}, 0);
            close F;
        }
        except
        {
            throw EFileSystem($@ . ';' . $!);
        };
    }
    else
    {
        try
        {
            $self->entities->{ $id_entity }->{last_check} = (stat($file))[9];
            $self->entities->{ $id_entity }->{queue} = _Q_NORMAL;
            $self->entities->{ $id_entity }->{queue_clsf} = 0;
        }
        except
        {
            throw EFileSystem($@ . ';' . $!);
        };
    }

    $self->entity_load_to_cache($id_entity);

    $self->write_status_file();

    $self->dbh->exec( sprintf( qq|UPDATE entities SET probe_pid=%s WHERE id_entity = %s and monitor <> 0|, $$, $id_entity) );

    $s .= sprintf("post: %s; ", scalar( keys %{ $self->entities } ) );
    log_debug($s, _LOG_WARNING)
        if $LogEnabled;
}

sub entity_load_to_cache
{
    my $self = shift;
    my $id_entity = shift;
    my $data = @_ ? shift : 0;
    try
    {
        log_debug("getting entity $id_entity from database", _LOG_INTERNAL)
            if $LogEnabled;

        $self->entity_cache->{$id_entity}->{entity} = $data 
            ? Entity->new($self->dbh, $id_entity, 0, $data)
            : Entity->new($self->dbh, $id_entity, 0);
    }
    catch  EEntityDoesNotExists with
    {
    }
    except
    {
    };
}


sub entities_init
{
    my $self = shift;

    my $file;

    my $s = sprintf("entities table reinitialization: before: %s; ", scalar( keys %{ $self->entities } ) );

    $self->[ENTITIES] = {};

    my @entities = map [$_->[0], $_->[1]],
        @{ $self->dbh->exec( sprintf(qq|SELECT entities.id_entity,check_period FROM entities, links, statuses 
            WHERE id_child=entities.id_entity AND statuses.id_entity=id_parent AND statuses.status<>%d
            AND id_probe_type=%s AND probe_pid=%s|, 
            _ST_UNREACHABLE, $self->id_probe_type, $$) )->fetchall_arrayref};

    keys ( %{ $self->[ENTITIES] } ) = $#entities;
    for my $entity (@entities)
    {
        $self->entities->{ $entity->[0] }->{check_period} = $entity->[1];
        $self->entities->{ $entity->[0] }->{queue} = _Q_NORMAL;
        $self->entities->{ $entity->[0] }->{queue_clsf} = 0;

        $file = sprintf("%s/%s", $LastCheckDir, $entity->[0]);
        if (! -e $file ) 
        {
            $self->entities->{ $entity->[0] }->{last_check} = time  - 10000;
            try
            {
                open F, ">$file";
                print F sprintf("%s:%s", $self->entities->{ $entity->[0] }->{last_check}, 0);
                close F;
            }
            except
            {
                throw EFileSystem($@ . ';' . $!);
            };
        }
        else
        {
            try
            {
                $self->entities->{ $entity->[0] }->{last_check} = (stat($file))[9];
                #open F, $file;
                #($self->entities->{ $entity->[0] }->{last_check}, $self->entities->{ $entity->[0] }->{last_delta}) = split /:/, <F>;
                #close F;
            }
            except
            {
                throw EFileSystem($@ . ';' . $!);
            };
        }
    }
    $self->write_status_file();
    $s .= sprintf("post: %s; ", scalar( keys %{ $self->entities } ) );
    log_debug($s, _LOG_INFO)
        if $LogEnabled;
}

sub check_reload_needed
{
    my $self = shift;
    my $entities = $self->entities;
    my $entity_cache = $self->entity_cache;
    my $result = {};

    my $file;
    my $id_entity;
    opendir(DIR, $FlagsControlDir);
    while (defined($file = readdir(DIR)))
    {
        unlink "$FlagsControlDir/$file"
            if time - (stat("$FlagsControlDir/$file"))[9] > $FlagsMaxAge;
        next
            unless $file =~ /^entity\./;
        $id_entity = (split /\./, $file, 2)[1];
        if (defined $entities->{$id_entity})
        {
            ++$result->{$id_entity};
            unlink "$FlagsControlDir/$file";
        }
    }
    closedir(DIR);

    for (keys %$entities)
    {
        ++$result->{$_}
            unless defined $entity_cache->{$_};
    }

    return $result;
}

sub entity_get
{
    my $self = shift;
    my $id_entity = shift;
    my $force_db = @_ ? shift : 0;

    my $reload_needed = $self->check_reload_needed;
    ++$reload_needed->{$id_entity}
        if $force_db;

    my $entity_cache = $self->entity_cache;

    my $lst = 0;
    my $mlst = 0;
    my $flag = 0;

    $lst = flag_file_check($FlagsUnreachableDir, sprintf(qq|%s.last|, $entity_cache->{$id_entity}->{entity}->id_parent), 0)
        if defined $entity_cache->{$id_entity}
        && defined $entity_cache->{$id_entity}->{entity};
    log_debug(sprintf(qq|parent last unreachable file %s.last: file timestamp: %s; cache timestamp: %s|, 
        $entity_cache->{$id_entity}->{entity}->id_parent, $lst, defined $entity_cache->{$id_entity}->{lst} ? $entity_cache->{$id_entity}->{lst} : 'unknown'), _LOG_INTERNAL)
        if defined $entity_cache->{$id_entity} 
        && defined $entity_cache->{$id_entity}->{entity}
        && $LogEnabled;

    if ( $lst )
    {
        if (defined $entity_cache->{$id_entity}->{lst} 
            && $entity_cache->{$id_entity}->{lst} != $lst
            && defined $entity_cache->{$id_entity}->{entity})
        {
            $entity_cache->{$id_entity}->{entity}->my_parent_has_parent_unreachable_status;
            ++$flag;
        }
    }

    $mlst = flag_file_check($FlagsUnreachableDir, sprintf(qq|%s.last|, $id_entity), 0);
    log_debug(sprintf(qq|my last unreachable file %s.last: file timestamp: %s; cache timestamp: %s|, 
        $id_entity, $mlst, defined $entity_cache->{$id_entity}->{mlst} ? $entity_cache->{$id_entity}->{mlst} : 'unknown'), _LOG_INTERNAL)
        if $LogEnabled;

    if ( $mlst && ! $flag )
    {
        if (defined $entity_cache->{$id_entity}->{mlst} 
            && $entity_cache->{$id_entity}->{mlst} != $mlst
            && defined $entity_cache->{$id_entity}->{entity})
        {
            $entity_cache->{$id_entity}->{entity}->my_parent_has_parent_unreachable_status;
            ++$flag;
        }
    }

    $entity_cache->{$id_entity}->{lst} = $lst;
    $entity_cache->{$id_entity}->{mlst} = $mlst;

#log_debug($id_entity . ": BEGIN", _LOG_ERROR);
#log_debug($id_entity . ": CACHE", _LOG_ERROR)
#if defined $entity_cache->{$id_entity}->{entity} && ! keys %$reload_needed;
#use Data::Dumper; log_debug($id_entity . ":A1 " . Dumper($entity_cache->{$id_entity}->{entity}), _LOG_ERROR)
#if defined $entity_cache->{$id_entity}->{entity} && ! keys %$reload_needed;
#log_debug($id_entity . ": END", _LOG_ERROR)
#if defined $entity_cache->{$id_entity}->{entity} && ! keys %$reload_needed;

    return $entity_cache->{$id_entity}->{entity}
        if defined $entity_cache->{$id_entity}->{entity} && ! keys %$reload_needed;

    ++$reload_needed->{$id_entity};

#5usi Data::Dumper; log_debug($id_entity . ":A2 " . Dumper($entity_cache->{$id_entity}->{entity}), _LOG_ERROR)
#if defined $entity_cache->{$id_entity}->{entity};
    for (keys %$reload_needed)
    {
        $self->entity_load_to_cache($_);
    }
#use Data::Dumper; log_debug($id_entity . ":A3 " . Dumper($entity_cache->{$id_entity}->{entity}), _LOG_ERROR);
#log_debug($id_entity . ": END", _LOG_ERROR);
    return $entity_cache->{$id_entity}->{entity};
}

sub cache_parent_unreachable_check
{
    my $self = shift;
    my $id_parent = shift;
    my $entity_cache = $self->entity_cache;

    for (keys %$entity_cache)
    {
        $entity_cache->{ $_ }->{entity}->my_parent_has_parent_unreachable_status
           if defined $entity_cache->{ $_ }->{entity}
           && $entity_cache->{ $_ }->{entity}->id_parent == $id_parent;
    }
}

sub entity_pre_test
{
    my ($self, $entity) = @_;
    $entity->pre_test;
}

sub entity_test
{
    my $self = shift;

    throw EMissingArgument("entity object")
        unless defined $_[0] && ref($_[0]) eq 'Entity';
    my $entity = shift; 
    $self->[ERRMSG] = [];
    $self->[STATUS] = 0;
    #select undef, undef, undef, 0.008 + (int( rand(8)) * 0.001);
}

sub status
{
    my $self = shift;
    if (@_)
    {
        $self->[STATUS] = $_[0]
            if $self->[STATUS] < $_[0];
    }
    return $self->[STATUS];
}

sub errmsg
{
    my $self = shift;
    if (@_)
    {
        push @{ $self->[ERRMSG] }, shift;
    }
    return $self->[ERRMSG];
}

sub entity_post_test
{
    my ($self, $entity, $hdl) = @_;

    my $tm = $entity->has_parent_unreachable_status;
    if ($tm)
    {
        log_debug(sprintf(qq|entity %s test result ignored; parent %s unreachable flag exists|,
            $entity->id_entity, $entity->id_parent), _LOG_INFO);
        $self->cache_parent_unreachable_check($entity->id_parent)
            unless defined $SEEN_UNREACHABLE->{$tm};
        ++$SEEN_UNREACHABLE->{$tm}
            unless defined $SEEN_UNREACHABLE->{$tm};
        return;
    }
    elsif ($entity->have_i_unreachable_status || $entity->status == _ST_UNREACHABLE)
    {
        log_debug(sprintf(qq|entity %s test result ignored; unreachable flag exists or status unreachable|, 
            $entity->id_entity), _LOG_INFO);
        return;
    }
    elsif ($self->snmp && $entity->has_parent_nosnmp_status)
    {
        log_debug(sprintf(qq|entity %s test result ignored; parent %s nosnmp flag exists|,
            $entity->id_entity, $entity->id_parent), _LOG_INFO);
        $self->status(_ST_UNKNOWN);
        $self->[ERRMSG] = [];
    }

    $$hdl->{check_period} = $entity->set_status($self->status, join('|', @{$self->errmsg}));

    $entity->post_test( $hdl );
}

sub force_test
{
    my $self = shift;

    opendir(DIR, $FlagsControlDir)
        or log_debug("directory probems: $!", _LOG_ERROR);
    my @job = grep { /^force_test\./ } readdir(DIR);
    closedir DIR;

    return
        unless @job;

    my $entities = $self->entities;
    for my $id_entity (@job)
    {
        $id_entity = (split /\./, $id_entity)[1];

        if (defined $entities->{ $id_entity })
        {   
            flag_file_check($FlagsControlDir, 'force_test.' . $id_entity, 1);
            my $dbh = $self->dbh;
            my $req = $dbh->exec( qq|SELECT * FROM force_test| )->fetchrow_hashref;

            return
                unless defined $req;

            $entities->{ $req->{id_entity} }->{last_check} = 1;
            log_debug(sprintf(qq|test forced by user id %s (%s) at %s for entity %s|,
                $req->{id_user}, $req->{ip}, $req->{timestamp}, $req->{id_entity}), _LOG_INFO);
            $dbh->exec( sprintf(qq|DELETE FROM force_test WHERE id_entity=%s|, $req->{id_entity} ) );
        }
    }
}

sub got_sig_quit 
{
    my $status_file = sprintf(qq|%s/%s|, $StatusDir, $$);

    try
    {   
        unlink $status_file
            if -e $status_file;
    }
    except
    {   
        throw EFileSystem($@ . ';' . $!);
    };
    log_debug("got sig quit", _LOG_WARNING)
        if $LogEnabled;
    exit;
}

=pod
sub got_sig_usr1
{
    ++CFG->{TraceLevel};
    Log::init_globals();
    log_debug(sprintf(qq|trace level increased. current trace level %d|, CFG->{TraceLevel}), _LOG_ERROR)
        if $LogEnabled;
}

sub got_sig_usr2
{
    ++CFG->{TraceLevel}
        if CFG->{TraceLevel};
    Log::init_globals();
    log_debug(sprintf(qq|trace level decreased. current trace level %d|, CFG->{TraceLevel}), _LOG_ERROR)
        if $LogEnabled;
}
=cut

sub write_status_file
{
    my $self = shift;
    my $status_file = sprintf(qq|%s/%s|, $StatusDir, $$);

    try
    {   
        if (-e $status_file)
        {
            open F, "+<$status_file" or die $@;
        }
        else
        {
            open F, ">$status_file" or die $@;
        }
        seek(F, 0, 0);
        print F sprintf(qq|%s:%s|, time, scalar( keys %{ $self->entities } ) );
        truncate(F, tell(F));
        close F;
    }
    except
    {   
        throw EFileSystem($@ . ';' . $!);
    };
}

sub run
{
    my $self = shift;
    my $ppid = shift;
    my $entity;
    my $counter;

    my $job;
    my $delta;

    my $flags_check_entities_init_counter = 0;

    my $tm;
    my $cycle_tm;
    my $bench;
    my $total_count = 0;
    my $total_tm = 0;
    my $cycle_count;
    my $removed;

    $SIG{QUIT} = \&got_sig_quit;
    $SIG{INT} = \&got_sig_quit;
    $SIG{TERM} = \&got_sig_quit;
    $SIG{USR1} = \&got_sig_usr1;
    $SIG{USR2} = \&got_sig_usr2;
    $SIG{TRAP} = \&trace_stack;

    log_debug("probe started", _LOG_WARNING);

    my $queue = _Q_NORMAL;
    my $entities = $self->entities;
    my $force_count;
    my $queue_change;

    while (1) 
    { 
#$entities = $self->entities;
        if (! kill(0, $ppid))
        {
            log_debug("akkada stoped", _LOG_WARNING);
            exit;
        }

        if (flag_file_check($FlagsControlDir, sprintf(qq|probe.dump.entities.table.%s|, $$), 1))
        {
            use Data::Dumper;
            log_debug(Dumper($entities), _LOG_ERROR);
        }
   
        ++$flags_check_entities_init_counter;
        ++$force_count;

        $cycle_tm = [gettimeofday]; 
        $counter = 0;
        $job = {};
        $cycle_count = 0;
        $removed = 0;

#use Data::Dumper; log_debug("YYY: " . Dumper($entities), _LOG_ERROR);
        for my $id_entity ( grep { $entities->{$_}->{queue} eq $queue  } keys %$entities )
        {
            if (flag_file_check($FlagsControlDir, sprintf(qq|%s.remove|, $id_entity), 1))
            {
                delete $entities->{$id_entity};
                log_debug(sprintf("entity %d was removed", $id_entity), _LOG_WARNING);
                ++$removed;
                next;
            }
            elsif (flag_file_check($FlagsControlDir, sprintf(qq|%s.check_period|, $id_entity), 1))
            {
                $self->entity_load_to_cache($id_entity);
                $entities->{$id_entity}->{check_period} = $self->entity_cache->{$id_entity}->{entity}->check_period;
                log_debug(sprintf("entity %d check period changed to %d", 
                    $id_entity, $self->entity_cache->{$id_entity}->{entity}->check_period), _LOG_WARNING);
            }
            elsif (defined $self->entity_cache->{$id_entity}->{entity}
                && $self->entity_cache->{$id_entity}->{entity}->status == _ST_BAD_CONF)
            {
                if ($BadConfReload)
                {
                    $self->entity_load_to_cache($id_entity);
                    $entities->{$id_entity}->{check_period} = $self->entity_cache->{$id_entity}->{entity}->check_period;
                    log_debug(sprintf("entity %d reloaded from database due to bad entity configuration", $id_entity), _LOG_WARNING);
                }
            }

            if (flag_file_check($FlagsControlDir, sprintf(qq|%s.load_actions|, $id_entity), 1))
            {
                $entity = $self->entity_get($id_entity, 0);
                $entity->load_actions;
                log_debug(sprintf("entity %d actions reloaded", $id_entity), _LOG_INFO)
                    if $LogEnabled;
            }

            $delta = time - $entities->{$id_entity}->{last_check};
            next
                unless $delta - int( rand( $entities->{$id_entity}->{check_period} * $EntityTestDeltaRandomFactor ) )
                > $entities->{$id_entity}->{check_period};
            $job->{$id_entity} = $entities->{$id_entity}->{last_check};
            #$job->{$id_entity} = $delta;
            ++$cycle_count;
            last
                if $cycle_count == $QueuePolicy->{$queue}->[1];
                #if $cycle_count == $ProbesMaxCountPerCycle;
        }

        if ($removed)
        {
            $self->write_status_file;
        }

#use Data::Dumper; log_debug(Dumper($job), _LOG_ERROR);
        for my $id_entity ( sort { $job->{$b} <=> $job->{$a} } keys %$job )
        {
            $entity = $self->entity_get($id_entity, 0);
#use Data::Dumper; log_debug(Dumper($entity), _LOG_ERROR);
            if ( ref($entity) eq 'Entity')
            {
                $tm = $entity->has_parent_unreachable_status;
                if ($tm)
                {
                    $self->update_time_info(\$entities->{$id_entity});
                    $entity->update_last_check(\$entities->{$id_entity});
                    log_debug(sprintf(qq|entity %s ignored; parent %s unreachable flag exists|,
                        $entity->id_entity, $entity->id_parent), _LOG_INFO);
                    $self->cache_parent_unreachable_check($entity->id_parent)
                        unless defined $SEEN_UNREACHABLE->{$tm};
                    ++$SEEN_UNREACHABLE->{$tm}
                        unless defined $SEEN_UNREACHABLE->{$tm};
                    next;
                }
                elsif ($entity->have_i_unreachable_status || $entity->status == _ST_UNREACHABLE)
                {
                    $self->update_time_info(\$entities->{$id_entity});
                    $entity->update_last_check(\$entities->{$id_entity});
                    $entity->update_data_file_timestamp;
                    log_debug(sprintf(qq|entity %s ignored; s unreachable flag exists or status unreachable|,
                        $entity->id_entity), _LOG_INFO);
                    next;
                }

                log_debug(sprintf("entity %s starting test; status: %s", $id_entity, $entity->status), _LOG_INTERNAL)
                    if $LogEnabled;

                $tm = [gettimeofday];

                $self->entity_pre_test($entity);

                try
                {
                    $self->entity_test($entity);
                }
                catch EEntityMissingParameter with
                {
                    $self->status(_ST_BAD_CONF);
                    $self->errmsg('');
                }
                except
                { 
                };

                $self->update_time_info(\$entities->{$id_entity});
                $self->entity_post_test($entity, \$entities->{$id_entity});

                $tm = tv_interval( $tm, [gettimeofday] );

                ($entities->{$id_entity}->{queue}, $entities->{$id_entity}->{queue_clsf}, $queue_change) = 
                    $self->classify_to_queue($queue, $tm, \$entities->{$id_entity}->{queue_clsf});

                $total_count++;
                $total_tm = $total_tm + $tm;

                if ($queue_change == 2 && $LogEnabled)
                {
                    log_debug(sprintf("entity %s test finished; queue change %s => %s; status: %s; dur: %.4f; avg dur: %.4f,  %.0f spm",
                        $id_entity, $queue, $entities->{$id_entity}->{queue}, $entity->status, $tm,
                        $total_tm/$total_count, 60/($total_tm/$total_count)), _LOG_INFO);
                }
                elsif ($queue_change == 1 && $LogEnabled)
                {
                    log_debug(sprintf("entity %s test finished; queue %s; queue cassifier incresed; status: %s; dur: %.4f; avg dur: %.4f,  %.0f spm",
                        $id_entity, $queue, $entity->status, $tm, $total_tm/$total_count, 60/($total_tm/$total_count)), _LOG_INFO);
                }
                elsif (! $queue_change && $LogEnabled)
                {
                    log_debug(sprintf("entity %s test finished; queue %s; status: %s; dur: %.4f; avg dur: %.4f,  %.0f spm",
                        $id_entity, $queue, $entity->status, $tm, $total_tm/$total_count, 60/($total_tm/$total_count)), _LOG_INFO);
                }

            }
            else
            {
                delete $entities->{$id_entity};
                log_debug(sprintf("Probe type %s: id_entity: %s unknown", $self->id_probe_type, $id_entity), _LOG_WARNING)
                    if $LogEnabled;
            }
            $counter++;
        }

        $cycle_tm = tv_interval( $cycle_tm, [gettimeofday] );
        if ($QueuePolicy->{$queue}->[2] && $counter)
        {
            my @q = grep { $entities->{$_}->{queue} eq $queue } keys %$entities;
            log_debug(sprintf("queue %s %s ents processed in : %.4f; total ents in queue %s",
                $queue, $counter, $cycle_tm, scalar @q), _LOG_WARNING);
        }

        if ($total_count && $counter && $LogEnabled)
        {
            if (scalar keys %$entities > 60/($total_tm/$total_count))
            {
                #log_debug(sprintf("PROBE OVERLOADED!!! statistics: %d entities in probe; currently processed: %d; avg: %.4f;  %.0f spm",
                log_debug(sprintf("statistics: %d entities in probe; currently processed: %d; avg: %.4f;  %.0f spm",
                    scalar keys %$entities , $counter, $total_tm/$total_count, 60/($total_tm/$total_count)),
                    _LOG_INFO);
                    #_LOG_ERROR);
            }
            else
            {
                log_debug(sprintf("statistics: %d entities in probe; currently processed: %d; avg: %.4f;  %.0f spm",
                    scalar keys %$entities , $counter, $total_tm/$total_count, 60/($total_tm/$total_count)),
                    _LOG_INFO);
	    }
        }

        if ($flags_check_entities_init_counter > $FlagsCheckTimeSlots)
        {
            $self->flags_check_entities_init();
            $entities = $self->entities;
            $flags_check_entities_init_counter = 0;
        }
#log_debug("XXX: " . Dumper($entities), _LOG_ERROR);

        if ($force_count > $ForceCheckTimeSlots)
        {
            $self->force_test();
            $force_count = 0;
        }

        $queue = $self->next_queue($queue);

        if ($LogEnabled)
        {
            my @qf = grep { $entities->{$_}->{queue} eq _Q_FAST  } keys %$entities;
            my @qn = grep { $entities->{$_}->{queue} eq _Q_NORMAL } keys %$entities;
            my @qs = grep { $entities->{$_}->{queue} eq _Q_SLOW } keys %$entities;
            log_debug(sprintf(qq|entities in queues: %s fast, %s normal, %s slow|, scalar @qf, scalar @qn, scalar @qs), _LOG_INTERNAL);
        }


        sleep 1; 
    }
}

sub classify_to_queue
{
    my $self = shift;
    my $queue = shift;
    my $tm = shift;
    my $queue_clsf = shift;

    my $new_queue = $tm < $QueuePolicy->{fast}->[0]
        ? _Q_FAST
            : $tm < $QueuePolicy->{normal}->[0]
                ? _Q_NORMAL
                : _Q_SLOW;

    return ($queue, 0, 0)
        if $queue eq $new_queue;

    ++$$queue_clsf;

    return ($queue, $$queue_clsf, 1)
        if $$queue_clsf < 3;

    return ($new_queue, 0, 2);
}

sub next_queue
{
    my $self = shift;
    my $queue = shift;
    return "fast"
        if $queue eq "slow";
    return "normal"
        if $queue eq "fast";
    return "slow"
        if $queue eq "normal";
}

sub update_time_info
{
    my $self = shift;
    my $entities_stats = shift;
    my $old_last_check = $$entities_stats->{last_check};
                
    $$entities_stats->{last_check} = time;
    $$entities_stats->{last_delta} = $$entities_stats->{last_check} - $old_last_check;
}

sub rrd_load_data
{
    my $self = shift;
    return ($self->rrd_config, $self->rrd_result);
}

sub rrd_save
{
    my $self = shift;
    my $id_entity = shift;
    my $status = @_ ? shift : _ST_OK;

    my $rrd_file = sprintf(qq|%s/%s.%s|, $RRDDir, $id_entity, $self->probe_name);

    my ($rrd_cfg, $rrd_res) = $self->rrd_load_data();

#    return
#        unless keys %$rrd_cfg;

#use Data::Dumper;
#log_debug("XXX: " . Dumper($rrd_cfg), _LOG_ERROR);
#log_debug("YYY: " . Dumper($rrd_res), _LOG_ERROR);

    if (! -e $rrd_file)
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
        push @data, qq|DS:delta:GAUGE:300:U:U|;
        for (sort keys %$rrd_cfg)
        {
            push @data, sprintf(qq|DS:%s:%s:300:U:U|, $_, $rrd_cfg->{$_});
        }
#use Data::Dumper; log_debug(Dumper(\@data),_LOG_ERROR);
        RRDs::create ( @data );
        my $error = RRDs::error();
        log_exception( ERRDs->new( sprintf(qq|entity %s file %s: %s|, $id_entity, $rrd_file, $error)) , _LOG_WARNING )
            if $error;
    }

    my $tm = time;
    my $delta = $self->entities->{$id_entity}->{last_check} == 1
        ? 'U'
        : ($tm - $self->entities->{$id_entity}->{last_check});
            
    my @data = ($tm, $delta);

    push @data, map { defined $rrd_res->{$_} ? $rrd_res->{$_} : 'U' } sort keys %$rrd_cfg;

    my $rrd_cache = $self->rrd_cache;
    $rrd_cache->{$id_entity} = []
        unless defined $rrd_cache->{$id_entity};

    push @{$rrd_cache->{$id_entity}}, \@data;

    log_debug($id_entity . ": items in cache: " . @{$rrd_cache->{$id_entity}} . "; status: $status; RRDCacheMaxEntriesNotOK: $RRDCacheMaxEntriesNotOK; RRDCacheMaxEntries: $RRDCacheMaxEntries", _LOG_INTERNAL)
        if $LogEnabled;

    my $rrd_sync = 0;

    if ($status > _ST_OK && $status < _ST_UNKNOWN && @{$rrd_cache->{$id_entity}} >= $RRDCacheMaxEntriesNotOK)
    {
        ++$rrd_sync;
    }
    elsif (@{$rrd_cache->{$id_entity}} - int(rand( $RRDCacheMaxEntriesRandomFactor )) >= $RRDCacheMaxEntries)
    {
        ++$rrd_sync;
    }
    
    if ($rrd_sync)
    {
        log_debug($id_entity . ": status $status: " . join(" # ", map { join(":", @$_) } @{$rrd_cache->{$id_entity}}), _LOG_INTERNAL)
            if $LogEnabled;
        RRDs::update ($rrd_file, map { join(":", @$_) } @{$rrd_cache->{$id_entity}});
        $rrd_cache->{$id_entity} = [];
    }

    my $error = RRDs::error();
    log_debug( sprintf(qq|entity %s file %s: %s|, $id_entity, $rrd_file, $error) , _LOG_WARNING )
        if $error;
}

sub rrd_get_data
{
    my $self = shift;
    my $entity = shift;

    my $rrd_file = sprintf(qq|%s/%s.%s|, $RRDDir, $entity->id_entity, CFG->{ProbesMapRev}->{$self->id_probe_type});

    my $lastupdate = RRDs::last ($rrd_file) - 65;

    return undef
        unless (time - $lastupdate) < 120;

    my ($start,$step,$names,$data) = RRDs::fetch ($rrd_file, 'LAST', '-s', $lastupdate, '-e', $lastupdate);

    #print "\#", $RRDs::error, "#$rrd_file#\n";
    #use Data::Dumper; print Data::Dumper::Dumper($data);
    if ($RRDs::error)
    {
        log_debug( ERRDs->new($RRDs::error), _LOG_WARNING );
        return undef;
    }

    #use Data::Dumper; print Data::Dumper::Dumper($data);
    $data = shift @$data;
    shift @$data;

    my $rrd = $self->rrd_config;
    for (sort keys %$rrd)
    {
        $rrd->{$_} = shift @$data;
    }
    return $rrd;
}

sub threshold_high
{
    my $self = shift;
    if (@_)
    {
        $self->[THRESHOLD_HIGH] = defined $_[0]
            ? shift
            : $ThresholdHighDefault;
    }
    return $self->[THRESHOLD_HIGH];
}

sub threshold_medium
{
    my $self = shift;
    if (@_)
    {
        $self->[THRESHOLD_MEDIUM] = defined $_[0]
            ? shift
            : $ThresholdMediumDefault;
    }
    return $self->[THRESHOLD_MEDIUM];
}

sub timeout
{ 
    return sub { die 'GOT TIMEOUT'; } 
}

sub discover_mode
{
    return _DM_AUTO;
}

sub discover_mandatory_parameters
{
    return
    [
        'ip',
    ]
}

sub discover 
{
    my ($self, $entity) = @_;

=pod
    log_debug(sprintf(qq|discover %s: id_entity: %s|, ref($self), $id_entity), _LOG_INFO)
        if $LogEnabled;

    my $entity = $self->entity_get($id_entity, 1);

    throw EEntityDoesNotExists($id_entity)
        unless ref($entity) eq 'Entity';

    throw ECommon(sprintf(qq|entity %s id_probe_type %s; for discovery it must be id_probe_type 1|,
        $id_entity,
        $entity->id_probe_type))
        unless $entity->id_probe_type eq '1';

    return $entity;
=cut
}

sub _discover_get_existing_entities
{               
    my ($self, $entity) = @_;

    if (! $entity->params('snmp_instance'))
    {

        return map $_->[0], @{ $self->dbh->exec(
            sprintf(qq| SELECT entities.id_entity FROM entities,links 
                WHERE id_probe_type=%s
                AND id_parent=%s 
                AND id_child=id_entity 
                AND (id_entity 
                    NOT IN ( SELECT entities.id_entity FROM entities,links,entities_2_parameters,parameters 
                        WHERE id_probe_type=%s 
                        AND id_parent=%s
                        AND entities.id_entity=entities_2_parameters.id_entity 
                        AND entities_2_parameters.id_parameter=parameters.id_parameter 
                        AND parameters.name='snmp_instance' 
                        AND id_child=entities.id_entity)
                    OR id_entity 
                    IN (SELECT entities.id_entity FROM entities,links,entities_2_parameters,parameters 
                        WHERE id_probe_type=%s 
                        AND id_parent=%s
                        AND entities.id_entity=entities_2_parameters.id_entity 
                        AND entities_2_parameters.id_parameter=parameters.id_parameter 
                        AND parameters.name='snmp_instance' 
                        AND id_child=entities.id_entity
                        AND entities_2_parameters.value='0'))|,
                $self->id_probe_type,
                $entity->id_entity,
                $self->id_probe_type,
                $entity->id_entity,
                $self->id_probe_type,
                $entity->id_entity)
                )->fetchall_arrayref 
            }; 

    }
    else
    {
        return map $_->[0], @{ $self->dbh->exec(
            sprintf(qq|SELECT entities.id_entity FROM entities,links,parameters,entities_2_parameters 
                WHERE id_probe_type=%s AND id_parent=%s AND entities.id_entity=id_child
                AND parameters.id_parameter=entities_2_parameters.id_parameter 
                AND parameters.name='snmp_instance'
                AND entities_2_parameters.id_entity=entities.id_entity
                AND entities_2_parameters.value='%s'|,
                $self->id_probe_type,
                $entity->id_entity,
                $entity->params('snmp_instance'))
                )->fetchall_arrayref 
            }; 
    }
}

sub probe_name
{
    my $result = ref(shift);
    $result =~ s/Probe\:\://g;
    return $result;
}

sub popup_item_url_app
{
    my $self = shift;
    my $view_mode = shift;

    my $result = '';

    if (! defined $VIEWS_TREE_PURE{$view_mode})
    {
        $result = sprintf(qq|?form_name=form_view_mode_change&nvm=%s&id_entity=|, 
            (defined $VIEWS_HARD{$view_mode} ? _VM_TREE : _VM_TREE_LIGHT));
    }

    return $result;
}

sub popup_items
{ 
    my $self = shift;
    my $buttons = $_[0]->{buttons};
    my $class = $_[0]->{class};
    my $section = $_[0]->{section};
    my $view_mode = $_[0]->{view_mode};
    my $top_level = $_[0]->{top_level};
    $buttons->add({ caption => "general", url => "javascript:open_location('0','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class');",});
    $buttons->add({ caption => "<hr>", url => "",});

    if (CFG->{Web}->{Sections}->{$section} eq 'alarms' && ! $top_level)
    {
        $buttons->add({ caption => "approve alarm", 
            url => "javascript:open_location($section,'?form_name=form_alarm_approval&id_entity=','current','$class');", 
            img => 'checkmark'});
        $buttons->add({ caption => "approve host alarms", 
            url => "javascript:open_location($section,'?form_name=form_alarm_approval&atype=1&id_entity=','current','$class');", 
            img => 'aah'});
        $buttons->add({ caption => "approve selected type alarms on all hosts", 
            url => "javascript:open_location($section,'?form_name=form_alarm_approval&atype=2&id_entity=','current','$class');", 
            img => 'aat'});
        $buttons->add({ caption => "<hr>", url => "",});
    }

    $buttons->add({ caption => "alarms", url => "javascript:open_location('3','"
        .$self->popup_item_url_app($view_mode)
        . "','','$class');",});
    $buttons->add({ caption => "stat", url => "javascript:open_location('5','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class');",})
        if $self->menu_stat && ! $top_level;
    $buttons->add({ caption => "log", url => "javascript:open_location('4','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class');",});

    if (! $top_level)
    {

    $buttons->add({ caption => "options", url => "javascript:open_location('1','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class');",});
    $buttons->add({ caption => "service options", url => "javascript:open_location('2','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class');",})
        if $class eq 'node';
    $buttons->add({ caption => "contacts", url => "javascript:open_location('8','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class');",});
    $buttons->add({ caption => "rights", url => "javascript:open_location('6','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class');",});
    $buttons->add({ caption => "<hr>", url => "",});
    #$buttons->add({ caption => "set status weight = 0", 
    #    url => "javascript:open_location($section,'?form_name=form_options_mandatory&status_weight=0&id_entity=','current','$class');",});
    $buttons->add({ caption => "stop monitor", 
        url => "javascript:open_location($section,'?form_name=form_options_mandatory&monitor=0&monitor_children=on&id_entity=','current','$class');",});
    $buttons->add({ caption => "add to view", url => "javascript:open_location('0','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class','6');",});
    $buttons->add({ caption => "reload entity in cache",
        url => "javascript:open_location($section,'?form_name=form_entity_cache_reload&id_entity=','current','$class');",});
    }

}


sub popup_menu
{ 
    my $self = shift;
    my $section = $_[0]->{section} || 0;
    my $view_mode = $_[0]->{view_mode} || _VM_TREE;
    my $top_level = $_[0]->{top_level} || 0;
    my $class = (split /::/, ref($self))[1];

    my $buttons = Window::Buttons->new();
    $buttons->vertical(1);
    $buttons->button_refresh(0);
    $buttons->button_back(0);

    $self->popup_items({buttons => $buttons, class => $class, 
        section => $section, view_mode => $view_mode, top_level => $top_level});

    $class .= "_top_level"
        if $top_level;

    my $result = qq|
        <style type="text/css">#flyout_${class}{position:absolute;top:100px;left:353px;display:none;z-index:100}</style>
        <div id="flyout_$class"><table class="y" cellpadding=0 cellspacing=0><tr><td>|;
    $result .= qq|<table cellspacing="0" class="u"><tr><td>|;
    $result .= $buttons;
    $result .= qq|</td></tr></table>|;
    $result .= qq|</td></tr></table></div>|;

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity, $url_params) = @_;

    my $flap = $entity->flap;

    my $s = $flap 
        ? sprintf(qq|%d flaps since %s; <font color="#606060">last error: "%s"</font>|,
              $entity->flap_count, duration($flap), $entity->flap_errmsg) 
        : $entity->errmsg;

    if ($s && $entity->status > _ST_OK && $entity->status < _ST_UNKNOWN)
    {
        $table->addRow(sprintf(qq|<b>ERROR:&nbsp;</b>%s|, join(qq|<b>ERROR:&nbsp;</b>|, map { "$_<br>"} split(/\|/,$s)) ));
    }
    elsif ($s)
    {
        $table->addRow(sprintf(qq|<b>INFO:&nbsp;</b>%s|, join(qq|<b>INFO:&nbsp;</b>|, map { "$_<br>"} split(/\|/,$s)) ));
    }

    $s = $entity->params_own->{ip};
    if ($s)
    {
        $table->addRow('ip address:', sprintf(qq|<b>%s</b>|, $s));
    }
    else
    {
        $s = $entity->params('nic_ip');
        $table->addRow('ip address:', sprintf(qq|<b>%s</b>|, $s))
            if $s;
    }

    $s = $entity->description;
    $table->addRow('description:', $s)
        if $s;
}

sub desc_full
{
    my $self = shift;
    my $entity = shift;
    my $url_params = shift;


    my $monitor = $entity->monitor;

    my $result;

    my $table = table_begin('collected information');

    if ($monitor)
    {
        $self->desc_full_rows($table, $entity, $url_params);
    }
    else
    {
        $table->addRow('not monitored');
    }

    my $start = 2;
    my $color = 0;

    if (($entity->flap || $entity->errmsg) && $monitor)
    {
        ++$start;
        $color = ! $color;
        $table->setCellColSpan(2, 1, $table->getTableCols);
        $table->setCellClass(2, 1, $entity->status > _ST_OK && $entity->status < _ST_UNKNOWN ? 'c3' : 'c4');
    }

    for my $i ( $start .. $table->getTableRows)
    {

        if ($table->getCell($i,1) eq '')
        {
            # to sa pogrubione biale linie
            $color = 0;
        }

        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $table->setCellClass($i, 1, 'f');
        $color = ! $color;
    }

    $table->setCellColSpan(1, 1, $table->getTableCols);
    $result = scalar $table if $table->getTableRows > 1;

    return $result;
}

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;
    return $entity->name;
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

sub stat
{
    my $self = shift;
    my $table = shift;
    $table->addRow('statistics must be implemented in probe');
}

sub color_get
{
    my $self = shift;
    return '333399'
        if $_[0] eq 'AVERAGE';
    return '66FF33'
        if $_[0] eq 'MIN';
    return 'FF3333'
        if $_[0] eq 'MAX';
    return '000000';
}

sub prepare_ds
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;

    my $rrd_file = sprintf(qq|%s/%s.%s|, CFG->{Probe}->{RRDDir}, $entity->id_entity, $url_params->{probe});

    my ($track_mode, $track_form, $track_ext, $track_name) = $rrd_graph->get_track_mode_and_form( $cf );
    my $track_color = $self->color_get( $cf );

    my $up = 0;
    my $down = 0;
    ++$up
        if $track_mode > 0;
    ++$down
        if $track_mode < 0;

    push @$args, "DEF:ds0$track_ext=$rrd_file:$url_params->{probe_specific}:$cf";
    push @$args, "CDEF:ds0$track_ext$track_ext=ds0$track_ext," . ( $track_mode < 0 ? '-1' : '1' ) . ",*";
    push @$args, $track_form. ":ds0$track_ext$track_ext#$track_color:$track_name";

    return ($up, $down, "ds0$track_ext");
}

sub stat_delta
{
    my $self = shift;
    my $table = shift;
    my $entity = shift;
    my $url_params = shift;

    my $cgi = CGI->new();

    $url_params->{probe} = CFG->{ProbesMapRev}->{ $self->id_probe_type };

    return 
        if $url_params->{probe} eq 'icmp_monitor';

    $url_params->{probe_prepare_ds} = 'prepare_ds_delta';
    $url_params->{probe_specific} = 'delta';

    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}

sub prepare_ds_delta
{
    my $self = shift;
    $self->prepare_ds(@_);
}

sub prepare_ds_delta_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    $rrd_graph->title('test delta');
    $rrd_graph->unit('sec');
}

sub manual
{
    return 0; # jesli jest 1 to serwisy mozna dodawac recznie z weba, ale wtedy musi byc zdefiniowana metoda mandatory_fields
}

sub stat_cell_content
{
    my $self = shift;
    my $cgi = shift;
    my $url_params = shift;

    my $pr_ds = $url_params->{probe_prepare_ds};
    my $pr_sp = defined $url_params->{probe_specific}
        ? $url_params->{probe_specific}
        : '';

    my $id = "$pr_ds:$pr_sp:$url_params->{id_entity}";
    my $url = url_get($url_params, {}, '/graph');

    my $table = HTML::Table->new();
    $table->setAlign("LEFT");
    $table->setAttr('class="w"');

    $table->addRow(
        $cgi->img({name=> "_$id", onClick =>qq|formShowHide('AG', '$id', 0)|, src => "/img/o.gif", }),
        $cgi->img
        ({ 
            onMouseOver => qq|set_OBJ('$id:$url', 'graphtime')|,
            onMouseOut =>qq|clear_OBJ()|,
            onClick =>qq|graph_reload('$id:$url')|,
            onLoad =>qq|formShowHide('AG', '$id', 1)|,
            name => $id,
            id => $id,
            src => $url,
        })
    );
    $table->setCellAttr(1, 1, 'class="g3"');

    return scalar $table;
}

sub popup_items_graphtime
{          
    my $self = shift;
    my $buttons = $_[0]->{buttons};

    my $def = CFG->{Web}->{RRDGraph}->{Defaults};
    my $url_params = $_[0]->{url_params};

    $url_params->{width} = $def->{Width}
        unless defined $url_params->{width} && $url_params->{width};
    $url_params->{height} = $def->{Height}
        unless defined $url_params->{height} && $url_params->{height};

    $buttons->add({ caption => "1 hour", url => "javascript:open_graphtime('-1h');"});
    $buttons->add({ caption => "3 hours", url => "javascript:open_graphtime('-3h');"});
    $buttons->add({ caption => "6 hours", url => "javascript:open_graphtime('-6h');"});
    $buttons->add({ caption => "12 hours", url => "javascript:open_graphtime('-12h');"});
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "1 day", url => "javascript:open_graphtime('-1d');"});
    $buttons->add({ caption => "3 days", url => "javascript:open_graphtime('-3d');"});
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "1 week", url => "javascript:open_graphtime('-1w');"});
    $buttons->add({ caption => "2 weeks", url => "javascript:open_graphtime('-2w');"});
    $buttons->add({ caption => "1 month", url => "javascript:open_graphtime('-1m');"});
    $buttons->add({ caption => "3 months", url => "javascript:open_graphtime('-3m');"});
    $buttons->add({ caption => "year", url => "javascript:open_graphtime('-1y');"});
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "zoom in", url => "javascript:zoom("  . $_[0]->{url_params}->{width} . "," .  $_[0]->{url_params}->{height} . ", true);"});
    $buttons->add({ caption => "zoom out", url => "javascript:zoom("  . $_[0]->{url_params}->{width} . "," .  $_[0]->{url_params}->{height} . ", false);"});
    #$buttons->add({ caption => "<hr>", url => "",});
    #$buttons->add({ caption => "copy", url => "javascript:cpi();"});
}           
            
sub popup_menu_graphtime
{
    my $self = shift;
    my $url_params = shift;
    my $buttons = Window::Buttons->new();
    $buttons->vertical(1);
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $self->popup_items_graphtime({buttons => $buttons, url_params => $url_params });
    return qq|<SCRIPT type="text/javascript" src="/graphtime.js"></script>
        <style type="text/css">#flyout_graphtime{position:absolute;top:100px;left:353px;display:none;z-index:100}</style>
        <div id="flyout_graphtime"><table class="y" cellpadding=0 cellspacing=0><tr><td><table cellspacing="0" class="u"><tr><td>|
        . $buttons . qq|</td></tr></table></td></tr></table></div>|;
}

sub popup_menu_bqv
{
    my $self = shift;
    my $id_parent = shift;
    my $id_probe_type = shift;
    my $probe_name = shift;
    my $buttons = Window::Buttons->new();
    $buttons->vertical(1);
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $self->popup_items_bqv({buttons => $buttons, id_parent => $id_parent, 
        id_probe_type => $id_probe_type, probe_name => $probe_name });
    return qq|<style type="text/css">#flyout_| . $probe_name 
        . qq|{position:absolute;top:100px;left:353px;display:none;z-index:100}</style><div id="flyout_| . $probe_name 
        . qq|"><table class="y" cellpadding=0 cellspacing=0><tr><td><table cellspacing="0" class="u"><tr><td>| . $buttons
        . qq|</td></tr></table></td></tr></table></div>|;
}

sub popup_items_bqv_app
{
    my $self = shift;
    my $id_parent = $_[0]->{id_parent};
    my $id_probe_type = $_[0]->{id_probe_type};
    return sprintf(qq|?form_name=form_entity_find&treefind=1&id_parent=%s&id_probe_type=%s&id_entity=|, $id_parent, $id_probe_type);
}

sub popup_items_bqv
{ 
    my $self = shift;
    my $buttons = $_[0]->{buttons};
    my $probe_name = $_[0]->{probe_name};
    $buttons->add({ caption => "general", 
        url => "javascript:open_location('0','" . $self->popup_items_bqv_app($_[0]) . "','','$probe_name');",});
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "alarms", 
        url => "javascript:open_location('3','" . $self->popup_items_bqv_app($_[0]) . "','','$probe_name');",});
    $buttons->add({ caption => "stat", 
        url => "javascript:open_location('5','" . $self->popup_items_bqv_app($_[0]) . "','','$probe_name');",});
    $buttons->add({ caption => "log", 
        url => "javascript:open_location('4','" . $self->popup_items_bqv_app($_[0]) . "','','$probe_name');",});
}

sub popup_menu_view
{           
    my $self = shift;
    my $view_mode = $_[0]->{view_mode};
    my $buttons = Window::Buttons->new();
    $buttons->vertical(1); 
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $self->popup_items_view({buttons => $buttons, view_mode => $view_mode});
    return qq|<style type="text/css">#flyout_view{position:absolute;top:100px;left:353px;display:none;z-index:100}</style><div id="flyout_view"><table class="y" cellpadding=0 cellspacing=0><tr><td><table cellspacing="0" class="u"><tr><td>| . $buttons
        . qq|</td></tr></table></td></tr></table></div>|;
}   
    
sub popup_items_view_app
{   
    my $self = shift;
    my $view_mode = $_[0]->{view_mode}; 

    if (defined $VIEWS_ALLVIEWS{$view_mode})
    {
        return qq|?form_name=form_view_select&id_view=|;
    }
    else
    {
        return sprintf(qq|?form_name=form_view_mode_change&nvm=%s&id_view=|, 
            (defined $VIEWS_HARD{$view_mode} ? _VM_TREEVIEWS : _VM_TREEVIEWS),);
    }
}   
    
sub popup_items_view
{   
    my $self = shift;
    my $buttons = $_[0]->{buttons};
    $buttons->add({ caption => "general",
        url => "javascript:open_location('0','" . $self->popup_items_view_app($_[0]) . "','','view');",});
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "alarms",
        url => "javascript:open_location('3','" . $self->popup_items_view_app($_[0]) . "','','view');",});
    $buttons->add({ caption => "stat", 
        url => "javascript:open_location('5','" . $self->popup_items_view_app($_[0]) . "','','view');",});
    $buttons->add({ caption => "log",
        url => "javascript:open_location('4','" . $self->popup_items_view_app($_[0]) . "','','view');",});
}   

sub popup_menu_find
{
    my $self = shift;
    my $view_mode = $_[0]->{view_mode};
    my $buttons = Window::Buttons->new();
    $buttons->vertical(1);
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $self->popup_items_find({buttons => $buttons, view_mode => $view_mode});
    return qq|<style type="text/css">#flyout_find{position:absolute;top:100px;left:353px;display:none;z-index:100}</style><div id="flyout_find"><table class="y" cellpadding=0 cellspacing=0><tr><td><table cellspacing="0" class="u"><tr><td>| . $buttons
        . qq|</td></tr></table></td></tr></table></div>|;
}


sub popup_menu_teeny
{
    my $self = shift;
    my $view_mode = $_[0]->{view_mode};
    my $buttons = Window::Buttons->new();
    $buttons->vertical(1);
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $self->popup_items_teeny({buttons => $buttons, view_mode => $view_mode});
    return qq|<style type="text/css">#flyout_teeny_top_level{position:absolute;top:100px;left:353px;display:none;z-index:100}</style><div id="flyout_teeny_top_level"><table class="y" cellpadding=0 cellspacing=0><tr><td><table cellspacing="0" class="u"><tr><td>| . $buttons
        . qq|</td></tr></table></td></tr></table></div>|;
}

sub popup_menu_permissions
{
    my $self = shift;
    my $view_mode = $_[0]->{view_mode};
    my $buttons = Window::Buttons->new();
    $buttons->vertical(1);
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $self->popup_items_permissions({buttons => $buttons, view_mode => $view_mode});
    $self->popup_items_teeny({buttons => $buttons, view_mode => $view_mode});
    return qq|<style type="text/css">#flyout_permissions_top_level{position:absolute;top:100px;left:353px;display:none;z-index:100}</style><div id="flyout_permissions_top_level"><table class="y" cellpadding=0 cellspacing=0><tr><td><table cellspacing="0" class="u"><tr><td>| . $buttons
        . qq|</td></tr></table></td></tr></table></div>|;
}

sub popup_menu_dashboard
{
    my $self = shift;
    my $view_mode = $_[0]->{view_mode};
    my $buttons = Window::Buttons->new();
    $buttons->vertical(1);
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $self->popup_items_dashboard({buttons => $buttons, view_mode => $view_mode});
    $self->popup_items_teeny({buttons => $buttons, view_mode => $view_mode});
    return qq|<style type="text/css">#flyout_dashboard_top_level{position:absolute;top:100px;left:353px;display:none;z-index:100}</style><div id="flyout_dashboard_top_level"><table class="y" cellpadding=0 cellspacing=0><tr><td><table cellspacing="0" class="u"><tr><td>| . $buttons
        . qq|</td></tr></table></td></tr></table></div>|;
}

sub popup_menu_actions
{
    my $self = shift;
    my $view_mode = $_[0]->{view_mode};
    my $buttons = Window::Buttons->new();
    $buttons->vertical(1);
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $self->popup_items_actions({buttons => $buttons, view_mode => $view_mode});
    $self->popup_items_teeny({buttons => $buttons, view_mode => $view_mode});
    return qq|<style type="text/css">#flyout_actions_top_level{position:absolute;top:100px;left:353px;display:none;z-index:100}</style><div id="flyout_actions_top_level"><table class="y" cellpadding=0 cellspacing=0><tr><td><table cellspacing="0" class="u"><tr><td>| . $buttons
        . qq|</td></tr></table></td></tr></table></div>|;
}

sub popup_items_find_app
{
    my $self = shift;
    my $view_mode = $_[0]->{view_mode};

    if (defined $VIEWS_FIND{$view_mode})
    {
        return qq|?|; #form_name=form_view_select&id_view=|;
    }
    else
    {
        return sprintf(qq|?form_name=form_view_mode_change&nvm=%s&id_view=|,
            (defined $VIEWS_HARD{$view_mode} ? _VM_FIND_LIGHT: _VM_FIND),);
    }
}

sub popup_items_find
{
    my $self = shift;
    my $buttons = $_[0]->{buttons};
    $buttons->add({ caption => "general",
        url => "javascript:open_location('0','" . $self->popup_items_find_app($_[0]) . "','','find');",});
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "alarms",
        url => "javascript:open_location('3','" . $self->popup_items_find_app($_[0]) . "','','find');",});
    $buttons->add({ caption => "stat",
        url => "javascript:open_location('5','" . $self->popup_items_find_app($_[0]) . "','','find');",});
    $buttons->add({ caption => "log",
        url => "javascript:open_location('4','" . $self->popup_items_find_app($_[0]) . "','','find');",});
}

sub popup_items_teeny
{
    my $self = shift;
    my $buttons = $_[0]->{buttons};
    $buttons->add({ caption => "network", 
        url => "javascript:open_location('0','?form_name=form_view_mode_change&nvm=10&id_entity=','','teeny_top_level');",});
    $buttons->add({ caption => "views", 
        url => "javascript:open_location('0','?form_name=form_view_mode_change&nvm=11&id_entity=','','teeny_top_level');",});
    $buttons->add({ caption => "find", 
        url => "javascript:open_location('0','?form_name=form_view_mode_change&nvm=13&id_entity=','','teeny_top_level');",});
    $buttons->add({ caption => "dashboard", 
        url => "javascript:open_location('10','?form_name=form_view_mode_change&nvm=15&id_entity=','','teeny_top_level');",});
    $buttons->add({ caption => "contacts", 
        url => "javascript:open_location('105','?form_name=form_view_mode_change&nvm=10&id_entity=','','teeny_top_level');",});
    $buttons->add({ caption => "actions", 
        url => "javascript:open_location('106','?form_name=form_view_mode_change&nvm=10&id_entity=','','teeny_top_level');",});
    $buttons->add({ caption => "permissions", 
        url => "javascript:open_location('101','?form_name=form_view_mode_change&nvm=10&id_entity=','','teeny_top_level');",});
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "logout", 
        url => "javascript:open_location('100','','','teeny_top_level');",});
    $buttons->add({ caption => "about", 
        url => "javascript:open_location('107','','','teeny_top_level');",});
}

sub popup_items_permissions
{
    my $self = shift;
    my $buttons = $_[0]->{buttons};
    $buttons->add({ caption => "users & groups",
        url => "javascript:open_location('101','?form_name=form_view_mode_change&nvm=10&id_entity=','','teeny_top_level', '1');",});
    $buttons->add({ caption => "rights",
        url => "javascript:open_location('101','?form_name=form_view_mode_change&nvm=10&id_entity=','','teeny_top_level', '2');",});
    $buttons->add({ caption => "<hr>", url => "",});
}

sub popup_items_dashboard
{
    my $self = shift;
    my $buttons = $_[0]->{buttons};
    $buttons->add({ caption => "general",
        url => "javascript:open_location('10','?form_name=form_view_mode_change&nvm=15&id_entity=','','teeny_top_level');",});
    $buttons->add({ caption => "histograms",
        url => "javascript:open_location('10','?form_name=form_view_mode_change&nvm=15&id_entity=','','teeny_top_level', '2');",});
    $buttons->add({ caption => "top 10",
        url => "javascript:open_location('10','?form_name=form_view_mode_change&nvm=15&id_entity=','','teeny_top_level', '5');",});
    $buttons->add({ caption => "system status",
        url => "javascript:open_location('10','?form_name=form_view_mode_change&nvm=15&id_entity=','','teeny_top_level', '3');",});
    $buttons->add({ caption => "manage system",
        url => "javascript:open_location('10','?form_name=form_view_mode_change&nvm=15&id_entity=','','teeny_top_level', '4');",});
    $buttons->add({ caption => "settings",
        url => "javascript:open_location('10','?form_name=form_view_mode_change&nvm=15&id_entity=','','teeny_top_level', '1');",});
    $buttons->add({ caption => "<hr>", url => "",});
}

sub popup_items_actions
{
    my $self = shift;
    my $buttons = $_[0]->{buttons};
    $buttons->add({ caption => "bindings",
        url => "javascript:open_location('106','?form_name=form_view_mode_change&nvm=10&id_entity=','','teeny_top_level', '1');",});
    $buttons->add({ caption => "actions",
        url => "javascript:open_location('106','?form_name=form_view_mode_change&nvm=10&id_entity=','','teeny_top_level', '2');",});
    $buttons->add({ caption => "commands",
        url => "javascript:open_location('106','?form_name=form_view_mode_change&nvm=10&id_entity=','','teeny_top_level', '3');",});
    $buttons->add({ caption => "time periods",
        url => "javascript:open_location('106','?form_name=form_view_mode_change&nvm=10&id_entity=','','teeny_top_level', '4');",});
    $buttons->add({ caption => "<hr>", url => "",});
}


sub DESTROY
{
    my $self = shift;
    my $rrd_cache = $self->rrd_cache;

    my $probe = CFG->{ProbesMapRev}->{$self->id_probe_type};
    my $rrd_file;

    for my $id_entity (keys %$rrd_cache)
    {
        if (@{$rrd_cache->{$id_entity}})
        {
            $rrd_file = sprintf(qq|%s/%s.%s|, $RRDDir, $id_entity, $probe);
            RRDs::update ($rrd_file, map { join(":", @$_) } @{$rrd_cache->{$id_entity}})
        }
    }

}

sub snmp
{
    return 0;
}

1;

