package Discover;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;          
use MyException qw(:try);
use Entity;
use Configuration;
use Log;
use Constants;
use Common;
use DB;

our $FlagsControlDir = CFG->{FlagsControlDir};
our $Period = CFG->{Discover}->{Period};
our $LastDiscoverDir = CFG->{Discover}->{LastDiscoverDir};
our $LogEnabled = CFG->{LogEnabled};
our $ProbesMapRev = CFG->{ProbesMapRev};
our $ProbesMap = CFG->{ProbesMap};
our $System = CFG->{System};

use constant
{
    PROBES => 0,
    DBH => 1,
    ENTITIES => 2,
    PROBE_DBH => 1,  #musi byc takie samo jak w Probe.pm DBH
};


sub new
{
    my $this = shift;
    my $class = ref($this) || $this;

    my $self = [];

    $self->[DBH] = DB->new();
    $self->[PROBES] = {};
    $self->[ENTITIES] = {};

    bless $self, $class;

    $self->load_probes();
    $self->entities_init();

    return $self;
}

sub load_probes
{
    my $self = shift;
    for my $probe ( keys %$ProbesMap )
    {
        eval "require Probe::$probe; \$self->[PROBES]->{\$probe} = Probe::${probe}->new();";
    }

    for (keys %{ $self->[PROBES] })
    {
        $self->[PROBES]->{$_}->[1] = $self->[DBH];
    }
}

sub probes
{
    return $_[0]->[PROBES];
}

sub dbh
{
    return $_[0]->[DBH];
}

sub entities
{
    return $_[0]->[ENTITIES];
}

sub entities_init
{
    my $self = shift;

    my $file;
    my $last_discover_dir = $LastDiscoverDir;

    my $s = sprintf("entities table reinitialization: before: %s; ", scalar( keys %{ $self->entities } ) );

    $self->[ENTITIES] = {};

    my @entities = map [$_->[0], $_->[1]],
        @{ $self->dbh->exec( qq|SELECT id_entity,discover_period FROM entities 
            WHERE id_probe_type=1
            AND id_entity NOT IN 
                (SELECT id_entity FROM entities_2_parameters,parameters 
                 WHERE name='dont_discover' 
                 AND value<>0 
                 AND entities_2_parameters.id_parameter=parameters.id_parameter)| )->fetchall_arrayref};

    keys ( %{ $self->[ENTITIES] } ) = $#entities;

    my $stop_discover = $self->dbh->exec( qq|SELECT id_entity,value FROM entities_2_parameters, parameters
        WHERE name='stop_discover' 
        AND entities_2_parameters.id_parameter=parameters.id_parameter| )->fetchall_hashref("id_entity");

    my @t;
    for my $id_entity (keys %$stop_discover)
    {
        @t = split /::/, $stop_discover->{$id_entity}->{value};
        $stop_discover->{$id_entity} = {};
        $stop_discover->{$id_entity}->{$_} = 1
            for @t;
    }

    for my $entity (@entities)
    {
        for my $probe ( keys %$ProbesMap )
        {
            $self->entities->{ $entity->[0] }->{$probe}->{discover_period} = $entity->[1]; 
            $self->entities->{ $entity->[0] }->{$probe}->{stop_discover} = 
                defined $stop_discover->{ $entity->[0] } && $stop_discover->{ $entity->[0] }->{$probe}
                    ? 1
                    : 0;
            #tutaj dlatego zeby w przyszlosci mozna bylo rozne periody dla roznych sond

            $file = sprintf("%s/%s.%s", $last_discover_dir, $entity->[0], $probe);
            if (! -e $file ) 
            {
                $self->entities->{ $entity->[0] }->{$probe}->{last_discover} = time  - 100000;
                try
                {
                    open F, ">$file";
                    print F sprintf("%s:%s", $self->entities->{ $entity->[0] }->{$probe}->{last_discover}, 0);
                    close F;
                }
                except
                {
                    log_exception( EFileSystem->new($!), _LOG_ERROR);
                };
            }
            else
            {
                try
                {
                    open F, $file;
                    ($self->entities->{ $entity->[0] }->{$probe}->{last_discover}, 
                        $self->entities->{ $entity->[0] }->{$probe}->{last_delta}) 
                        = split /:/, <F>;
                    close F;
                }
                except
                {
                    log_exception( EFileSystem->new($!), _LOG_ERROR);
                }
            };
        }
    }
    $s .= sprintf("post: %s; ", scalar( keys %{ $self->entities } ) );
    log_debug($s, _LOG_INFO)
        if $LogEnabled;
}

sub force_discover
{
    my $self = shift;
    my $dbh = $self->dbh;
    my @fd = map [$_->[0], $_->[1], $_->[2], $_->[3], $_->[4]],
        @{ $dbh->exec( qq|SELECT id_probe_type, id_entity, id_user, ip, timestamp FROM discover| )->fetchall_arrayref};

    return
        unless scalar @fd;

    my $entities = $self->entities;

    for (@fd)
    {
        if (defined $entities->{ $_->[1] } && defined $entities->{ $_->[1] }->{ $ProbesMapRev->{$_->[0]} })
        {
            $entities->{ $_->[1] }->{ $ProbesMapRev->{$_->[0]} }->{last_discover} = 1;
            $entities->{ $_->[1] }->{ $ProbesMapRev->{$_->[0]} }->{force} = 1;
            log_debug(sprintf(qq|discover forced by user id %s (%s) at %s for entity %s probe %s|, 
                $_->[2], $_->[3], $_->[4], $_->[1], $ProbesMapRev->{$_->[0]}), _LOG_INFO);
        }
        $dbh->exec( sprintf(qq|DELETE FROM discover WHERE id_probe_type=%s AND id_entity=%s|, $_->[0], $_->[1]) );
    }
}

sub are_there_entities_of_that_kind
{
    my $self = shift;
    my $id_parent = shift;
    my $id_probe_type = shift;

    my @entities = map $_->[0],
        @{ $self->dbh->exec( 
            sprintf(qq|SELECT id_entity FROM entities,links where id_probe_type=%s and id_parent=%s and id_child=id_entity|,
            $id_probe_type, $id_parent))->fetchall_arrayref};

    return scalar @entities;
}

sub run
{
    my $self = shift;
    my $ppid = shift;

    my $entity;
    my $job;
    my $delta;


    while (1) 
    { 
        exit
            if ! kill(0, $ppid);

        $self->entities_init()
            if flag_file_check($FlagsControlDir, 'entities_init.Discover', 1);

        $self->force_discover();

        $job = {};

        for my $id_entity ( keys %{ $self->entities } )
        {
            for my $probe ( keys %{ $self->entities->{$id_entity} } )
            {
                $delta = time - $self->entities->{$id_entity}->{$probe}->{last_discover};
                if ($delta > $self->entities->{$id_entity}->{$probe}->{discover_period}
                        || $self->entities->{$id_entity}->{$probe}->{force})
                {
                    $job->{$id_entity}->{$probe} = $delta
                        if $System->{Probes}->{$probe};
                }
            }
        }

        my $force;
        for my $id_entity ( sort { $job->{$b} > $job->{$a} } keys %$job )
        {
            try
            {
                for my $probe (keys %{ $job->{$id_entity} })
                {
                    next
                        if $self->entities->{$id_entity}->{$probe}->{stop_discover};
                    $force = $self->entities->{$id_entity}->{$probe}->{force};
                    $self->entities->{$id_entity}->{$probe}->{force} = 0;
                    log_debug(sprintf(qq|begin discover for entity %s probe %s|, $id_entity, $probe), _LOG_INFO) 
                         if $LogEnabled;
                    if ($self->probes->{$probe}->discover_mode eq _DM_AUTO)
                    {
                        $self->discover($probe, $id_entity);
                    }
                    elsif ($self->probes->{$probe}->discover_mode eq _DM_MIXED)
                    {
                        $self->discover($probe, $id_entity)
                            if $self->are_there_entities_of_that_kind($id_entity, $ProbesMap->{$probe})
                            || (defined $force && $force);
                    }
                    elsif ($self->probes->{$probe}->discover_mode eq _DM_MANUAL)
                    {
                        if (defined $force && $force)
                        {
                            $self->discover($probe, $id_entity);
                        }
                    }
                    $self->entities->{$id_entity}->{$probe}->{last_discover} = time;
                    $self->update_last_discover( $id_entity, $probe,
                        sprintf("%s:%s", 
                        $self->entities->{$id_entity}->{$probe}->{last_discover}, 
                        $job->{$id_entity}->{$probe} ) );
                    log_debug(sprintf(qq|finish discover for entity %s probe %s|, $id_entity, $probe), _LOG_INFO) 
                         if $LogEnabled;
                }
            }
            catch EEntityMissingParameter with
            {
                log_exception(shift, _LOG_WARNING);
            }
            except
            {
            };
        }

        sleep ($Period ? $Period : 15);
    }
}

sub discover
{
    my $self = shift;
    my $probe = shift;
    my $id_entity = shift;

    log_debug(sprintf(qq|discover %s: id_entity: %s|, $probe, $id_entity), _LOG_INFO)
        if $LogEnabled;
    
    my $entity = $self->probes->{$probe}->entity_get($id_entity, 1);
    
    throw EEntityDoesNotExists($id_entity)
        unless ref($entity) eq 'Entity';
        
    throw ECommon(sprintf(qq|entity %s id_probe_type %s; for discovery it must be id_probe_type 1|,
        $id_entity,
        $entity->id_probe_type))
        unless $entity->id_probe_type eq '1';

    my $instances_count = get_param_instances_count($entity->params('snmp_version'));

    $instances_count = 0
        if $probe eq 'softax_ima';

    log_debug(sprintf(qq|discover %s: id_entity: %s configured snmp instances: %s|, $probe, $id_entity, $instances_count+1), 
        _LOG_DEBUG)
        if $LogEnabled;

    for my $i (0..$instances_count)
    {
        log_debug(sprintf(qq|discover %s: id_entity: %s discover for snmp instance: %s|, $probe, $id_entity, $i), 
            _LOG_DEBUG)
            if $LogEnabled;
        $entity->param_set_temp('snmp_instance', $i);
        $self->probes->{$probe}->discover($entity);
        return
            unless $self->probes->{$probe}->snmp;
    }
}

sub update_last_discover
{
    my $self = shift;
    my $id_entity = shift;
    my $probe = shift;
    open F, sprintf("+<%s/%s.%s", $LastDiscoverDir, $id_entity, $probe);
    seek(F, 0, 0);
    print F shift;
    truncate(F, tell(F));
    close F;
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;
