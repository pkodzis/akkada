package Entity;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION $AUTOLOAD);

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( entity_add );
%EXPORT_TAGS = ( default => [qw(entity_add)] );

use strict;          
use DB;
use MyException qw(:try);
use Configuration;
use Constants;
use Log;
use Common;
use Data::Dumper;

our $DataDir = CFG->{Probe}->{DataDir};
our $LogEnabled = CFG->{LogEnabled};
our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};
our $StatusCalcDir = CFG->{StatusCalc}->{StatusCalcDir};
our $FlagsControlDir = CFG->{FlagsControlDir};
our $LastCheckDir = CFG->{Probe}->{LastCheckDir};
our $FlagsNoSNMPDir = CFG->{FlagsNoSNMPDir};
our $FlagsUnreachableDir = CFG->{FlagsUnreachableDir};
our $FlapsAlarmCount = CFG->{FlapsAlarmCount};
our $FlapsTimeSlot = CFG->{FlapsTimeSlot};
our $FlapsDeltaMultiplier = CFG->{FlapsDeltaMultiplier};
our $DisableErrorMessageLog = CFG->{DisableErrorMessageLog};

use constant
{
    DBH => 0,
    ID_ENTITY => 1,
    ID_PARENT => 2,
    ID_PROBE_TYPE => 3,
    PARAMS => 4,

    STATUS => 5,
    STATUS_OLD => 6,
    STATUS_LAST_CHANGE => 7,
    STATUS_WEIGHT => 8,

    NAME => 9,
    CHECK_PERIOD => 10,
    ERRMSG => 11,
    ERRMSG_OLD => 12,

    DATA => 13,
    DESCRIPTION_STATIC => 14,
    DESCRIPTION_DYNAMIC => 15,

    PARAMS_OWN => 16,

    DELETED => 17,
    MONITOR => 18,
    DB_SAVE => 19,

    ERR_APPROVED_BY => 20,
    ERR_APPROVED_AT => 21,
    ERR_APPROVED_IP => 22,

    FLAP => 23,
    FLAP_MONITOR => 24,
    FLAP_ERRMSG => 25,
    FLAP_ERRMSG_OLD => 26,
    FLAP_STATUS => 27,
    FLAP_STATUS_OLD => 28,
    FLAP_COUNT => 29,
 
    ACTIONS => 30,
    PARENT_NAME => 31,
    STATUS_LAST_CHANGE_PREV => 32,
};

our $NO_PARAMS_CHANGE = 0;

our $PARAMS_CHANGE_IGNORE =
{
    'attempts_current_count' => 1,
    'flap_monitor' => 1,
};

our $PARAMS_TREE_IMPORTANT =
{
    'ip' => 1,
    'vendor' => 1,
    'function' => 1,
};

our $FIELDS_TREE_IMPORTANT =
{
    'name' => 1,
    'status' => 1,
    'status_weight' => 1,
    'errmsg' => 1,
    'err_approved_by' => 1,
    'monitor' => 1,
};

sub new
{
    my $class = shift;
    my $self = [];

    $self->[DBH] = shift;
    throw EMissingArgument("database handle")
        unless $self->[DBH] && ref($self->[DBH]) eq 'DB';

    my $id_entity = shift;
    throw EMissingArgument("id_entity")
        unless $id_entity;
    $self->[ID_ENTITY] = $id_entity;

    bless $self, $class;

    my $load_data = @_ ? shift : undef;

    my $data = @_ ? shift : undef;

    $self->[DB_SAVE] = {};
    $self->[ERRMSG_OLD] = '';

    if (! defined $data)
    {
        $data = get_entities_mass_data($self->[DBH], [ $id_entity ]);
#use Data::Dumper; log_debug(Dumper($data),_LOG_ERROR); 
        $data = $data->{$id_entity};
        throw EEntityDoesNotExists(sprintf(qq|unknown entity id %s; first add to database, table entities|, $id_entity))
            unless defined $data;
    }

#use Data::Dumper; log_debug(Dumper($data),_LOG_ERROR);

    $self->[ID_PROBE_TYPE] = $data->{id_probe_type};
    $self->[STATUS] = $data->{status};
    $self->[STATUS_OLD] = $self->[STATUS];
    $self->[STATUS_WEIGHT] = $data->{status_weight};
    $self->[NAME] = $data->{name};
    $self->[CHECK_PERIOD] = $data->{check_period} || 60;
    $self->[ERRMSG] = $data->{errmsg} || '';
    $self->[STATUS_LAST_CHANGE] = $data->{status_last_change};
    $self->[STATUS_LAST_CHANGE_PREV] = $data->{status_last_change_prev};
    $self->[ID_PARENT] = defined $data->{id_parent} ? $data->{id_parent} : 0;
    $self->[PARENT_NAME] = defined $data->{parent_name} ? $data->{parent_name} : 0;
    $self->[PARAMS] = $data->{params} ? $data->{params} : {};
    $self->[PARAMS_OWN] = $data->{params_own} ? $data->{params_own} : {};

    $self->[DESCRIPTION_STATIC] = $data->{description_static};
    $self->[DESCRIPTION_DYNAMIC] = $data->{description_dynamic} || '';

    $self->[DELETED] = $data->{deleted};
    $self->[MONITOR] = $data->{monitor};

    $self->[ERR_APPROVED_BY] = $data->{err_approved_by} || 0;
    $self->[ERR_APPROVED_AT] = $data->{err_approved_at} || 0;
    $self->[ERR_APPROVED_IP] = $data->{err_approved_ip} || '';

    $self->[FLAP_MONITOR] = $data->{flap_monitor} || '0000000000000000';
    $self->[FLAP] = $data->{flap} || 0;
    $self->[FLAP_ERRMSG] = $data->{flap_errmsg} || '';
    $self->[FLAP_STATUS] = $data->{flap_status} || $self->[STATUS];
    $self->[FLAP_ERRMSG_OLD] = $self->[FLAP_ERRMSG];
    $self->[FLAP_STATUS_OLD] = $self->[FLAP_STATUS];
    $self->[FLAP_COUNT] = $data->{flap_count} || 0;

    $self->[ACTIONS] = $data->{actions} || {};

    $self->[DATA] = $load_data
        ? load_data_file($id_entity)
        : undef;

    return $self;
}

sub load_actions
{
    my $self = shift;

    my $id_entity = $self->id_entity;

    log_debug("entity $id_entity: reloading actions", _LOG_INFO)
        if $LogEnabled;

    log_debug("entity $id_entity: actions before reload: " . Dumper($self->actions), _LOG_DEBUG)
        if $LogEnabled;

    $self->[ACTIONS] = {};

    my $req = $self->dbh->exec( sprintf(qq| SELECT id_e2a, id_entity, inherit FROM entities_2_actions,actions
        WHERE entities_2_actions.id_action=actions.id_action AND id_entity in (%s, %s)|, $id_entity, $self->id_parent))->fetchall_arrayref;
    for my $ac (@$req)
    {
        next
            if ! $ac->[2] && $ac->[1] != $id_entity;
        $self->[ACTIONS]->{ $ac->[0] } = $ac->[2] && $ac->[1] != $id_entity ? 0 : 1;
    }

    log_debug("entity $id_entity: actions after reload: " . Dumper($self->actions), _LOG_DEBUG)
        if $LogEnabled;
}

sub has_parent_nosnmp_status
{
    my $self = shift;
    return flag_file_check($FlagsNoSNMPDir, $self->id_parent, 0);
}

sub has_parent_unreachable_status
{
    my $self = shift;
    if (flag_file_check($FlagsUnreachableDir, $self->id_parent, 0))
    {
        $self->my_parent_has_parent_unreachable_status;
        return 1;
    }
    return 0;
}

sub my_parent_has_parent_unreachable_status
{
    my $self = shift;
    my $status = $self->status;

    log_debug("my_parent_has_parent_unreachable_status: status $status: phase 1", _LOG_INTERNAL)
        if $LogEnabled;

    return
        if $status == _ST_UNKNOWN;

    $self->dbh->disable_updates(1);
    $self->set_status(_ST_UNKNOWN, '', 1);
    $self->dbh->disable_updates(0);

    log_debug("my_parent_has_parent_unreachable_status: status $status: phase 2", _LOG_INTERNAL)
        if $LogEnabled;
}

sub have_i_unreachable_status
{
    my $self = shift;
    return flag_file_check($FlagsUnreachableDir, $self->id_entity, 0);
}

sub flaps_clear
{
    my $self = shift;
    my $dbh = $self->dbh;
    my $id_entity = $self->id_entity;

    $dbh->exec( sprintf(qq|UPDATE entities SET flap=0,flap_status=0,flap_errmsg='',flap_count=0,flap_monitor=''
        WHERE id_entity=%s|, $id_entity) );
    $self->history_record( $self->errmsg . "(manual flap clear)");

    actions_do($self);
    flag_files_create($StatusCalcDir, $self->id_parent);
    flag_files_create($FlagsControlDir, sprintf(qq|entity.%s|, $id_entity) );
    flag_files_create($TreeCacheDir, sprintf(qq|reload.%s|, $id_entity) );
}

sub flaps_reset
{
    my $self = shift;
    my $dbh = $self->dbh;
    my $id_entity = $self->id_entity;

    $dbh->exec( sprintf(qq|UPDATE entities SET flap_monitor='' WHERE id_entity=%s|, $id_entity) );
    flag_files_create($FlagsControlDir, sprintf(qq|entity.%s|, $id_entity) );
    flag_files_create($TreeCacheDir, sprintf(qq|reload.%s|, $id_entity) );

}


sub get_parameters
{
    my $self = shift;

    throw EMissingArgument("id_entity")
        unless defined $_[0] && $_[0];
    my $id_entity = shift;

    my $q = sprintf(qq| SELECT name, value FROM parameters,entities_2_parameters
            WHERE entities_2_parameters.id_entity=%s 
            AND entities_2_parameters.id_parameter=parameters.id_parameter|, $id_entity);
    #$q .= qq| AND parameters.inherit=1|
    #    if @_ && $_[0];

    my $req = $self->dbh->exec($q)->fetchall_hashref('name');
    @{$self->[PARAMS]}{keys %$req} = values %$req;

    $self->[PARAMS_OWN] = {};
    @{$self->[PARAMS_OWN]}{keys %$req} = values %$req;
}

sub db_save
{
    my $self = shift;
    $self->[DB_SAVE]->{$_[0]} = 1
        if @_;
    return $self->[DB_SAVE];
}

sub deleted
{
    my $self = shift;
    if (@_ && $_[0] != $self->[DELETED])
    {
        $self->[DELETED] = shift;
        $self->db_save('deleted');
    }
    return $self->[DELETED];
}   

sub err_approved_by
{
    my $self = shift;
    if (@_)
    {
        $self->[ERR_APPROVED_BY] = shift;
        $self->[ERR_APPROVED_IP] = shift || '';

        my $dbh = $self->dbh;
        my $id_entity = $self->id_entity;

        $dbh->exec(sprintf(qq|
            UPDATE entities SET err_approved_by=%s,
            err_approved_at=UNIX_TIMESTAMP(NOW())-UNIX_TIMESTAMP(status_last_change),
            err_approved_ip='%s'
            WHERE id_entity=%s|,
            $self->err_approved_by,
            $self->err_approved_ip,
            $id_entity ));

        $self->[ERR_APPROVED_AT] = 
            $dbh->exec(qq| select err_approved_at from entities where id_entity=$id_entity|)->fetchrow_arrayref->[0];

        if ($self->flap)
        {
            $self->history_record($self->flap_errmsg);
        }
        else
        {
            $self->history_record($self->errmsg);
        }
    }
    return $self->[ERR_APPROVED_BY];
}

sub parent_name
{
    return $_[0]->[PARENT_NAME];
}

sub actions
{
    return $_[0]->[ACTIONS];
}

sub flap_monitor
{
    return $_[0]->[FLAP_MONITOR];
}

sub flap_count
{
    return $_[0]->[FLAP_COUNT];
}

sub flap_errmsg
{
    my $self = shift;

    if (@_)
    {   
        if ($self->[FLAP_ERRMSG] ne $_[0])
        {   
            log_debug(sprintf(qq|entity %s flap_errmsg changed: %s -> %s|, $self->id_entity, $self->[FLAP_ERRMSG], $_[0]), _LOG_DEBUG)
                if $LogEnabled;
            $self->[FLAP_ERRMSG_OLD] = $self->[FLAP_ERRMSG];
            $self->[FLAP_ERRMSG] = $_[0];
            $self->db_save('flap_errmsg');
        }
    };
    return $self->[FLAP_ERRMSG];
}

sub flap_status
{
    my $self = shift;
    if (@_)
    {
        if ($self->[FLAP_STATUS] ne $_[0])
        {
            my $status = shift;
            
            log_debug(sprintf(qq|entity %s flap_status changed: %s -> %s|, $self->id_entity, $self->[FLAP_STATUS], $status), _LOG_DEBUG)
                if $LogEnabled;
                
            $self->[FLAP_STATUS_OLD] = $self->[FLAP_STATUS];
            $self->[FLAP_STATUS] = $status;
        }
    }
    return $self->[FLAP_STATUS];
}

sub flap
{
    return $_[0]->[FLAP];
}

sub flap_status_old
{
    my $self = shift;
    $self->[FLAP_STATUS_OLD] = shift
        if @_;
    return $self->[FLAP_STATUS_OLD];
}

sub flap_errmsg_old
{
    my $self = shift;
    $self->[FLAP_ERRMSG_OLD] = shift
        if @_;
    return $self->[FLAP_ERRMSG_OLD];
}

sub err_approved_ip
{
    return $_[0]->[ERR_APPROVED_IP];
}

sub err_approved_at
{
    return $_[0]->[ERR_APPROVED_AT];
}

sub data
{
    return $_[0]->[DATA];
}

sub load_data
{
    my $self = shift;
    $self->[DATA] = load_data_file($self->id_entity);
    return $_[0]->[DATA];
}

sub dbh
{
    return $_[0]->[DBH];
}

sub id_entity
{
    return $_[0]->[ID_ENTITY];
}

sub flap_stop
{
    my $self = shift;
    $self->[FLAP_MONITOR] = '1000000000000000';
    $self->[FLAP] = 0;
    $self->[FLAP_COUNT] = 0;
    $self->flap_errmsg('');
    $self->flap_status(_ST_NOSTATUS);
}

sub monitor
{
    my $self = shift;

    if (@_ && $_[0] != $self->[MONITOR])
    {
        $self->[MONITOR] = shift;
        $self->db_save('monitor');
        if ($self->id_probe_type)
        {
            $self->errmsg_clear;
            $self->flap_stop;
            $self->status($self->[MONITOR] ? _ST_UNKNOWN : _ST_NOSTATUS);

            $self->history_record( $self->[MONITOR] ? "monitoring enabled by user" : "monitoring disabled by user" );
            $self->status_calc_flag_create( $self->id_entity )
                if $self->id_probe_type < 2;
            $self->status_calc_flag_create( $self->id_parent );
        }
    }
    return $self->[MONITOR];
}

sub id_parent
{
    my $self = shift;
    if (@_ && $_[0] != $self->[ID_PARENT])
    {
        my $dbh = $self->dbh;
        my $id_parent_new = Entity->new($dbh, $_[0]);

        return
            unless $id_parent_new;

        $id_parent_new = $_[0];

        if ($self->[ID_PARENT] && $id_parent_new)
        {
            $dbh->exec(sprintf(qq|UPDATE links SET id_parent=%d WHERE id_child=%d|, $id_parent_new, $self->id_entity));
        }
        elsif ($self->[ID_PARENT])
        {
            $dbh->exec(sprintf(qq|DELETE FROM links WHERE id_child=%d|, $self->id_entity));
        }
        else
        {
            $dbh->exec(sprintf(qq|INSERT INTO links VALUES(%d,%d)|, $id_parent_new, $self->id_entity));
        }
        $self->status_calc_flag_create( $id_parent_new )
            if $id_parent_new;
        $self->status_calc_flag_create( $self->[ID_PARENT] )
            if $self->[ID_PARENT];

        flag_files_create(CFG->{FlagsControlDir}, 'entities_init.Available');
        flag_files_create(CFG->{FlagsControlDir}, 'available2.init_graph');

        #flag_files_create($TreeCacheDir, sprintf(qq|move.%s.%s.%s|, $self->id_entity, $self->id_parent, $id_parent_new) );

        $self->[ID_PARENT] = $id_parent_new;
    }
    return $self->[ID_PARENT];
}

sub description_static
{
    my $self = shift;
    if (@_)
    {
        $_[0] = sql_fix_string($_[0]);
        if ( $_[0] ne $self->[DESCRIPTION_STATIC])
        {
            $self->[DESCRIPTION_STATIC] = shift;
            $self->db_save('description_static');
        }
    }
    return $self->[DESCRIPTION_STATIC];
}

sub description_dynamic
{
    my $self = shift;
    if (@_ && defined $_[0]) 
    { 
        $_[0] = sql_fix_string($_[0]);
        if ( $_[0] ne $self->[DESCRIPTION_DYNAMIC])
        {
            $self->[DESCRIPTION_DYNAMIC] = shift;
            $self->db_save('description_dynamic');
        }
    }
    return $self->[DESCRIPTION_DYNAMIC];
}

sub description
{
    my $self = shift;

    my $result .= $self->[DESCRIPTION_STATIC];

    if ($self->[DESCRIPTION_DYNAMIC])
    {
        $result .= "; "
            if $result;
        $result .= $self->[DESCRIPTION_DYNAMIC]
    }
    return $result;
}

sub params_own
{
    return $_[0]->[PARAMS_OWN];
}

sub params_change
{
    my $self = shift;
    my $param = shift;
    my $tree = @_ ? shift : 1;

    if ($param =~ /^nic_ip/)
    {   
        flag_files_create($FlagsControlDir, 'entities_init.ICMPMonitor',);
        flag_files_create($FlagsControlDir, "actionsbroker_ips_load");
    }
    elsif ($param eq 'ip')
    {
        flag_files_create($FlagsControlDir, 'entities_init.Available');
        flag_files_create($FlagsControlDir, 'available2.init_graph');
        flag_files_create($FlagsControlDir, "actionsbroker_ips_load");
    }
    elsif ($param eq 'ip_forwarding' || $param eq 'ip_addresses' || $param eq 'availability_check_disable')
    {
        flag_files_create($FlagsControlDir, 'available2.init_graph');
    }
    elsif ($param eq 'dont_discover' || $param eq 'stop_discover')
    {
        flag_files_create($FlagsControlDir, 'entities_init.Discover');
    }

    if ($self->id_probe_type == 1)
    {
        my $children = child_get_ids($self->dbh, $self->id_entity);

        if ($children && ref($children))
        {
            flag_files_create($FlagsControlDir, sprintf(qq|entity.%s|, $_) )
                for @$children;
            flag_files_create($TreeCacheDir, sprintf(qq|reload.%s|, $_) )
                for @$children;
        }
    }

=pod
    elsif ($param eq 'attempts_max_count' || $param eq 'attempts_retry_interval')
    {
        my $children = child_get_ids($self->dbh, $self->id_entity);

        if ($children && ref($children))
        {
            flag_files_create($FlagsControlDir, sprintf(qq|entity.%s|, $_) )
                for @$children;
        }
    }
=cut

    if (! defined $PARAMS_CHANGE_IGNORE->{$param})
    {
        flag_files_create($FlagsControlDir, sprintf(qq|entity.%s|, $self->id_entity) );
    }

    if ($tree && defined $PARAMS_TREE_IMPORTANT->{$param})
    {
        flag_files_create($TreeCacheDir, sprintf(qq|reload.%s|, $self->id_entity) );
    }
}

sub param_set_temp
{
    my $self = shift;
    my $param = shift;
    my $value = shift;
    $self->[PARAMS]->{$param} = $value;
}

sub params
{
    my $self = shift;
    my $param = shift || throw EMissingArgument('param');

    if (@_)
    {
        my $value = shift;

        my $tree = @_ ? shift : 1;

        if (! defined $value || $value eq '')
        {
            $self->params_delete($param)
                if defined $self->[PARAMS_OWN]->{$param};
            return undef;
        }

        $value = sql_fix_string($value);

        if (defined $value && (! defined $self->[PARAMS_OWN]->{$param} || $self->[PARAMS_OWN]->{$param} ne $value))
        {
            $self->db_update_params($param, $value);
            $self->params_change($param, $tree)
                unless $NO_PARAMS_CHANGE;
        }
        $self->[PARAMS]->{$param} = $value;
        $self->[PARAMS_OWN]->{$param} = $value;
    }

    return defined $self->[PARAMS]->{$param}
        ? $self->[PARAMS]->{$param}
        : undef;
}


sub params_delete
{
    my $self = shift;
    my $param = shift;
    my $tree = @_ ? shift : 1;

    my $id_parameter = parameter_get_id($self->dbh, $param);

    if (! $id_parameter )
    {
        log_debug(sprintf(qq|unknown parameter %s; check parameters table|, $param), _LOG_WARNING)
            if $LogEnabled;
        return;
    }

    $self->dbh->exec( sprintf(qq| DELETE FROM entities_2_parameters WHERE id_entity=%s AND id_parameter=%s |
        ,$self->id_entity, $id_parameter) );
    delete $self->[PARAMS]->{$param};
    $self->params_change($param, $tree);
}

sub db_update_params
{
    my ($self, $name, $value) = @_;

    my $id_parameter = parameter_get_id($self->dbh, $name);

    if (! $id_parameter )
    {
        log_debug(sprintf(qq|unknown parameter %s; check parameters table|, $name), _LOG_WARNING)
            if $LogEnabled;
        return;
    }

    my $req = $self->dbh->exec(
        sprintf(qq| SELECT id_entity,id_parameter,value FROM entities_2_parameters
            WHERE id_entity=%s 
            AND id_parameter=%s | , $self->id_entity, $id_parameter)
        )->fetchrow_hashref;


    if (defined $req)
    {
        log_debug(sprintf("entity %s param update %s: %s => %s", $self->id_entity, $name, $req->{value}, $value), _LOG_DEBUG)
            if $LogEnabled;

        $self->dbh->exec(
            sprintf(qq|UPDATE entities_2_parameters SET value='%s' 
                WHERE id_entity=%s
                AND id_parameter=%s|, $value, $self->id_entity, $id_parameter)
            );
    }
    else
    {
        log_debug(sprintf("entity %s parameter insert %s: %s", $self->id_entity, $name, $value), _LOG_DEBUG)
            if $LogEnabled;
        $self->dbh->exec(
            sprintf(qq|INSERT INTO entities_2_parameters VALUES(%s, %s, '%s')|,
                $self->id_entity, $id_parameter, $value)
            );
    }

}

sub status
{
    my $self = shift;
    if (@_)
    {
        if ($self->[STATUS] eq $_[0])
        {
            if ($self->flap)
            {
                my $delta = time - $self->status_last_change;
                if ($delta > 0)
                {
                    if ($delta > $FlapsDeltaMultiplier*$FlapsTimeSlot)
                    {
                        $self->flap_stop;
                        $self->dbh->exec(sprintf(qq|UPDATE entities SET err_approved_by=0,err_approved_at=0,
                            err_approved_ip='',flap_monitor='%s',flap=%d,flap_status=%d,flap_errmsg='%s',
                            flap_count=%d WHERE id_entity=%s|,
                            $self->flap_monitor,
                            $self->flap,
                            $self->flap_status,
                            $self->flap_errmsg,
                            $self->flap_count,
                            $self->id_entity
                        ));

                        $self->history_record($self->errmsg);
                        actions_do($self);

                        flag_files_create($TreeCacheDir, sprintf(qq|reload.%s|, $self->id_entity) );

                        $self->status_calc_flag_create($self->id_parent)
                            if $self->id_parent;

                    }
                }
            }
        }
        else
        {
            throw EBadArgumentType(sprintf(qq|status: '%s'|, $_[0]))
                unless $_[0] =~ /^[0-9].*$/;

            my $status = shift;

            my $flaps_disable_monitor = @_ ? shift : 0;
            $flaps_disable_monitor = $self->params('flaps_disable_monitor')
                unless $flaps_disable_monitor;

            log_debug(sprintf(qq|entity %s status changed: %s -> %s|, 
                $self->id_entity, $self->status, $status), _LOG_DEBUG)
                if $LogEnabled;
            
	    $self->[STATUS_OLD] = $self->[STATUS];
            $self->[STATUS] = $status;

            my $delta = time - $self->status_last_change;

            $flaps_disable_monitor = 1
                if ! $flaps_disable_monitor && ($status == _ST_UNREACHABLE || $self->[STATUS_OLD] == _ST_UNREACHABLE);

            if ($delta > 0 && ! $flaps_disable_monitor)
            {
               $delta = int( $delta/$FlapsTimeSlot );

               my $flaps_alarm_count = 0;
               $flaps_alarm_count = $self->params('flaps_alarm_count') || CFG->{FlapsAlarmCount}
                   if $delta < $FlapsDeltaMultiplier;


               $delta = '1' . (0 x $delta) . $self->[FLAP_MONITOR];
               $self->[FLAP_MONITOR] = unpack("A16", $delta);

               if ($flaps_alarm_count)
               {
                   if ( $flaps_alarm_count <= scalar @{[ $self->[FLAP_MONITOR] =~ /1/g]} )
                   {
                       if ($status && ! $self->[FLAP])
                       { 
                           $self->[FLAP] = time;
                       } 
                       if ($self->[FLAP] && $status)
                       {
                           $self->flap_errmsg( $self->errmsg );
                           $self->flap_status($status);
                           $self->[FLAP_COUNT]++;
                       }
                   }
               }
            }

            $self->db_update_entity_status;

            $self->status_calc_flag_create($self->id_entity);
            flag_files_create($TreeCacheDir, sprintf(qq|reload.%s|, $self->id_entity) );

            my $id_parent = $self->id_parent;
            $self->status_calc_flag_create($id_parent)
                if $id_parent;
        }
    };
    return $self->[STATUS];
}

sub history_record
{
    my $self = shift;
    my $msg = shift;

    $self->dbh->exec(sprintf(qq|INSERT INTO history24 values(DEFAULT, %d, %d, %d, '%s', NOW(), %s, %s, '%s', 0)|,
       $self->id_entity,
       $self->status_old,
       $self->status,
       $msg,
       $self->err_approved_at,
       $self->err_approved_by,
       $self->err_approved_ip));
}

sub status_weight
{
    my $self = shift;
    if (@_ && $_[0] != $self->[STATUS_WEIGHT])
    {
        my $old = $self->[STATUS_WEIGHT];
        $self->[STATUS_WEIGHT] = shift;
        $self->db_save('status_weight');
        $self->history_record(sprintf(qq|status weight changed from %s to %s by user|, $old, $self->[STATUS_WEIGHT]));
    }
    return $self->[STATUS_WEIGHT];
}

sub status_last_change
{
    return $_[0]->[STATUS_LAST_CHANGE];
}

sub status_last_change_prev
{
    return $_[0]->[STATUS_LAST_CHANGE_PREV];
}

sub set_status
{
    my $self = shift;
    my $status = shift;
    my $errmsg = @_ ? shift : '';
    my $flaps_disable_monitor = @_ ? shift : 0;

    my $attempts_max_count = $self->params('attempts_max_count');
    if (defined $attempts_max_count && $attempts_max_count)
    {
        if ($status eq _ST_UNKNOWN || $status eq _ST_UNREACHABLE)
        {
            $self->params('attempts_current_count', 0);

            log_debug(sprintf("%s attempts_current_count => 0", $self->id_entity), _LOG_INTERNAL)
                if $LogEnabled;
        }
        elsif ($status eq _ST_OK && $self->params('attempts_current_count'))
        {
            $self->params('attempts_current_count', 0);

            log_debug(sprintf("%s attempts_current_count => 0", $self->id_entity), _LOG_INTERNAL)
                if $LogEnabled;
        }
        elsif ($status ne _ST_OK && $status ne $self->status)
        {
            my $attempts_current_count = $self->params('attempts_current_count') || 0;
            my $attempts_retry_interval = $self->params('attempts_retry_interval') || 30;

            ++$attempts_current_count;

            if ($attempts_current_count < $attempts_max_count)
            {
                $self->params('attempts_current_count', $attempts_current_count);
                #$self->params('attempts_retry_interval', $attempts_retry_interval);
                log_debug(sprintf("%s attempts_current_count => %s, attempts_retry_interval => %s",
                    $self->id_entity, $attempts_current_count, $attempts_retry_interval), _LOG_INTERNAL)
                    if $LogEnabled;

                return $attempts_retry_interval;
            }
            else
            {
                $self->params('attempts_current_count', 0);
                log_debug(sprintf("%s attempts_current_count => 0", $self->id_entity), _LOG_INTERNAL)
                    if $LogEnabled;
            }
        }
    }

    $self->errmsg($errmsg);
    $self->status($status, $flaps_disable_monitor);
    return $self->check_period;
}

sub errmsg_clear
{
    my $self = shift;
    if ($self->[ERRMSG] ne '')
    {
        log_debug(sprintf(qq|entity %s errmsg changed: %s -> %s|, $self->id_entity, $self->errmsg, ''), _LOG_DEBUG)
            if $LogEnabled;
        $self->db_save('errmsg');
        $self->[ERRMSG_OLD] = $self->[ERRMSG];
        $self->[ERRMSG] = '';
    }
}

sub errmsg
{
    my $self = shift;

    if (@_)
    {
        my $e = sql_fix_string($_[0]);
        if ($self->[ERRMSG] ne $e)
        {
            log_debug(sprintf(qq|entity %s errmsg changed: %s -> %s|, $self->id_entity, $self->errmsg, $e), _LOG_DEBUG)
                if $LogEnabled;
            $self->db_save('errmsg');
            $self->[ERRMSG_OLD] = $self->[ERRMSG];
            $self->[ERRMSG] = shift;
        }
    };
    return $self->[ERRMSG];
}


sub errmsg_old
{
    return $_[0]->[ERRMSG_OLD];
}

sub name
{
    my $self = shift;
    if (@_)
    {
        if (defined $_[0] && $self->[NAME] ne $_[0])
        {
            log_debug(sprintf(qq|entity %s name changed: %s -> %s|, $self->id_entity, $self->name, $_[0]), _LOG_DEBUG)
                if $LogEnabled;
            $self->db_save('name');
            $self->[NAME] = shift;
        }
    };
    return $self->[NAME];
}

sub pre_test
{
    my $self = shift;
}

sub post_test
{
    my $self = shift;

    my $entities_stats = shift;

    $self->update_last_check($entities_stats);

    $self->db_update_entity;
}

sub status_old
{
    return $_[0]->[STATUS_OLD];
}

sub db_update_entity_status
{
    my $self = shift;

    my $err_approved_by = 0;
    my $err_approved_at = 0;
    my $err_approved_ip ='';

    my $flap = $self->flap;

    if ($flap)
    {
        $err_approved_by = $self->err_approved_by;
        $err_approved_at = $self->err_approved_at;
        $err_approved_ip = $self->err_approved_ip;
    }
    $self->[STATUS_LAST_CHANGE_PREV] = $self->[STATUS_LAST_CHANGE];
    $self->[STATUS_LAST_CHANGE] = time();
    $self->dbh->exec(sprintf(qq|UPDATE entities 

        SET

        status=%d,
        errmsg='%s',
        status_last_change=NOW(),
        err_approved_by=%d,
        err_approved_at=%d,
        err_approved_ip='%s',
        flap_monitor='%s',
        flap=%d,
        flap_status=%d,
        flap_errmsg='%s',
        flap_count=%d,
        status_last_change_prev=%d

        WHERE
        id_entity=%s|,

        $self->status,
        $self->errmsg,
        $err_approved_by,
        $err_approved_at,
        $err_approved_ip,
        $self->flap_monitor,
        $self->flap,
        $self->flap_status,
        $self->flap_errmsg,
        $self->flap_count,
        $self->status_last_change_prev,
        $self->id_entity

        ));

    if ($flap)
    {
#print "FL_ER:",$self->flap_errmsg, ";FL_OER:", $self->flap_errmsg_old, ";FL_ST:", $self->flap_status, ";FL_OST:", $self->flap_status_old, "\n";
        if ($self->flap_errmsg ne $self->flap_errmsg_old || $self->flap_status ne $self->flap_status_old)
        {
            $self->dbh->exec(sprintf(qq|INSERT INTO history24 values(DEFAULT, %d, %d, %d, '%s', NOW(), 0, 0, '', 1)|,
                $self->id_entity, $self->flap_status_old == _ST_NOSTATUS ? $self->status : $self->flap_status_old, $self->flap_status, $self->flap_errmsg));
            $self->flap_errmsg_old( $self->flap_errmsg );
            $self->flap_status_old( $self->flap_status );
            actions_do($self);
        }
    }
    else
    {
        if ($self->status ne $self->status_old)
        {
            $self->dbh->exec(sprintf(qq|INSERT INTO history24 values(DEFAULT, %d, %d, %d, '%s', NOW(), 0, 0, '', 0)|,
                $self->id_entity, $self->status_old, $self->status, $self->errmsg));
            actions_do($self);
        }
        elsif ($self->errmsg ne $self->errmsg_old 
            && ! $DisableErrorMessageLog 
            && ! $self->params('disable_error_message_change_log'))
        {
            $self->dbh->exec(sprintf(qq|INSERT INTO history24 values(DEFAULT, %d, %d, %d, '%s', NOW(), 0, 0, '', 0)|,
                $self->id_entity, $self->status, $self->status, $self->errmsg));
                #$self->id_entity, $self->status_old, $self->status, $self->errmsg));
            actions_do($self);
        }
    }

    delete $self->db_save->{errmsg};
    delete $self->db_save->{flap_errmsg}
        if defined $self->db_save->{flap_errmsg};
}


sub db_update_entity
{
    my $self = shift;

    my $db_save = $self->db_save;
#use Data::Dumper; print Dumper($db_save);
    return
        unless %$db_save;

    my $do_not_tree_cache_sync = @_ ? shift : 0;
   
    my $statement = join(",", map { "$_='" . $self->$_ . "'" } keys %$db_save);

    $statement = sprintf(qq|UPDATE entities SET %s WHERE id_entity=%s|, $statement, $self->id_entity);
#print $statement, "\n";

    if ($db_save->{errmsg} || $db_save->{flap_errmsg})
    {
        my $flap = $self->flap;

        if (! $flap && $db_save->{errmsg} && $self->errmsg ne $self->errmsg_old)
        {   
            $self->dbh->exec(sprintf(qq|INSERT INTO history24 values(DEFAULT, %d, %d, %d, '%s', NOW(), 0, 0, '', 0)|,
                $self->id_entity, $self->status, $self->status, $self->errmsg))
                #$self->id_entity, $self->status_old, $self->status, $self->errmsg))
                if ! $DisableErrorMessageLog && ! $self->params('disable_error_message_change_log');
            actions_do($self);
        }   
        elsif ($flap && $db_save->{flap_errmsg} && $self->flap_errmsg ne $self->flap_errmsg_old)
        {   
            $self->dbh->exec(sprintf(qq|INSERT INTO history24 values(DEFAULT, %d, %d, %d, '%s', NOW(), 0, 0, '', 1)|,
                $self->id_entity, $self->flap_status_old, $self->flap_status, $self->flap_errmsg));
            $self->flap_errmsg_old( $self->flap_errmsg );
            actions_do($self);
        }   
    }


    $self->[DB_SAVE] = {};

    $self->dbh->exec($statement);

    if (! $do_not_tree_cache_sync )
    {
        for (keys %$db_save)
        {
            if (defined $FIELDS_TREE_IMPORTANT->{$_})
            {
                flag_files_create($TreeCacheDir, sprintf(qq|reload.%s|, $self->id_entity) );
                last;
            }
        }
    }

    flag_files_create($StatusCalcDir, $self->id_parent)
        if defined $db_save->{status_weight};
    #flag_files_create($FlagsControlDir, 'replan.JobPlanner')

    flag_files_create($FlagsControlDir, $self->monitor
        ? sprintf(qq|add.%s.%s|, $self->id_probe_type, $self->id_entity)
        : sprintf(qq|%s.remove|, $self->id_entity))
        if defined $db_save->{monitor};
    flag_files_create($FlagsControlDir, sprintf(qq|%s.check_period|, $self->id_entity))
        if defined $db_save->{check_period};
}


sub status_calc_flag_create
{
    my $self = shift;
    my $id = shift;

    if (flag_files_create($StatusCalcDir, $id))
    {
        log_debug(sprintf(qq|entity %s created flag for status recalculation for parent %s|,
            $self->id_entity,
            $id), _LOG_DEBUG)
            if $LogEnabled;
    }
}

sub update_last_check
{
    my $self = shift;
    my $entities_stats = shift;
    open F, sprintf("+<%s/%s", $LastCheckDir, $self->id_entity);
    seek(F, 0, 0);
    print F sprintf("%s:%s", $$entities_stats->{last_check}, $$entities_stats->{last_delta});
    truncate(F, tell(F));
    close F;
}

sub entity_add
{
   #function to create new entity - do not use in OO model!

   my $h = shift;

   my $dbh = @_ ? shift : DB->new();

   throw EBadArgumentType('probe_name must be defined in akkada.conf file ProbesMap')
       unless defined CFG->{ProbesMap}->{$h->{probe_name}};

   my $entity;

   try
   {
       $entity = $h->{id_parent} ? Entity->new($dbh, $h->{id_parent}) : undef;
   }
   catch  EEntityDoesNotExists with
   {
       throw EBadArgumentType('parent not found!');
       return undef;
   }
   except
   {
   };

   if ($h->{probe_name} eq 'node' && (! $h->{id_parent} || $entity->id_probe_type))
   {
       throw EBadArgumentType('node parent must be group!');
   }
   elsif ($h->{probe_name} eq 'group' && $entity && $entity->id_probe_type)
   { 
       throw EBadArgumentType('group parent must be root or group!');
   }
   elsif ($h->{probe_name} ne 'group' && $h->{probe_name} ne 'node' && (! $entity || $entity->id_probe_type ne '1'))
   {
       throw EBadArgumentType('service parent must be node!');
   }

   my $parameters = $dbh->exec(qq| select * from parameters |)->fetchall_hashref('name');

   $dbh->exec(
       sprintf(qq|insert into entities(name,id_probe_type,probe_pid,status) values('%s', %d, %d, %d)|, $h->{name}, CFG->{ProbesMap}->{$h->{probe_name}}, $$, $h->{probe_name} eq 'group' ? _ST_OK : _ST_INIT)
       );

   $entity = $dbh->exec(sprintf(qq| select * from entities where probe_pid=%d order by id_entity desc limit 1|, $$))->fetchrow_hashref;

   $dbh->exec( sprintf(qq|insert into links values(%d, %d)|, $h->{id_parent}, $entity->{id_entity}))
       if $h->{id_parent};

   if ($h->{probe_name} eq 'node' || $h->{probe_name} eq 'group')
   {
       $dbh->exec( sprintf(qq|insert into statuses(id_entity,status) values(%d, %d)|, $entity->{id_entity}, _ST_INIT));
   }

   #flag_files_create($TreeCacheDir, sprintf(qq|add.%s|, $entity->{id_entity}) );
   # to jest zalatwiane przez formyularze dodawania -> wymuszaja load_node w drzewku init_from_cache

   $entity = Entity->new($dbh, $entity->{id_entity});

   flag_files_create($FlagsControlDir, sprintf(qq|add.%s.%s|, $entity->id_probe_type, $entity->id_entity));

   return $entity
       unless defined $h->{params};

   $h = $h->{params};

   $NO_PARAMS_CHANGE = 1;

   for (keys %$h)
   {
       $entity->params($_, $h->{$_});
   }

   $NO_PARAMS_CHANGE = 0;

   flag_files_create($FlagsControlDir, "actionsbroker_ips_load");

   return $entity;
}

sub id_probe_type
{
    return $_[0]->[ID_PROBE_TYPE];
}

sub check_period
{
    my $self = shift;
    if (@_ && $_[0] != $self->[CHECK_PERIOD])
    {
        my $old = $self->[CHECK_PERIOD];
        $self->[CHECK_PERIOD] = shift;
        $self->db_save('check_period');
        $self->history_record(sprintf(qq|check period changed from %s to %s by user|, $old, $self->[CHECK_PERIOD]));
    }
    return $self->[CHECK_PERIOD];
}

sub entity_2_string
{
    my $self = shift;
    my $s = "Entity id: " . $self->id_entity;
    $s .= "\n\n	name: " . $self->name;
    $s .= "\n	probe_name: " . CFG->{ProbesMapRev}->{$self->id_probe_type};
    $s .= "\n	status: " . $self->status;
    $s .= "\n	check_period: " . $self->check_period;
    $s .= "\n\n	parameters:\n\n";
    $s .= join("\n", map { "		$_ => $self->[PARAMS]->{$_}" } keys %{ $self->[PARAMS] } );
    $s .= "\n\n";
    return $s;
}

sub update_data_file_timestamp
{
    utime(time, time, sprintf("%s/%s", $DataDir, $_[0]->id_entity));
}


sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;
