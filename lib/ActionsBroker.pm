package ActionsBroker;

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
use Data::Dumper;
use Time::Period;
use IP;

our $FlagsControlDir = CFG->{FlagsControlDir};
our $Period = CFG->{ActionsBroker}->{Period};
our $LogEnabled = CFG->{LogEnabled};
our $ActionsDir = CFG->{ActionsBroker}->{ActionsDir};

use constant
{
    DBH => 1,
    ACTIONS => 2,
    ATABLE => 3,
    IPS => 4,
};


sub new
{
    my $this = shift;
    my $class = ref($this) || $this;

    my $self = [];

    $self->[DBH] = DB->new();
    $self->[ACTIONS] = {};
    $self->[ATABLE] = {};
    $self->[IPS] = {};

    bless $self, $class;

    $self->actions_load();
    $self->ips_load();

    $SIG{USR1} = \&got_sig_usr1;
    $SIG{USR2} = \&got_sig_usr2;
    $SIG{TRAP} = \&trace_stack;

    return $self;
}

sub dbh
{
    return $_[0]->[DBH];
}

sub actions
{
    return $_[0]->[ACTIONS];
}

sub atable
{
    return $_[0]->[ATABLE];
}

sub ips
{
    return $_[0]->[IPS];
}

sub ips_load
{
    $_[0]->[IPS] = get_entities_ips($_[0]->dbh);
}

sub actions_load
{   
    my $self = shift;
    
    my $s = sprintf("actions table reinitialization: before: %s; ", scalar( keys %{ $self->actions} ) );

    $self->[ACTIONS] = $self->dbh->exec(qq|
            SELECT id_e2a,actions.id_action,id_entity,actions.name,commands.name,commands.command,commands.module,
                active,notification_interval,notification_start,notification_stop,service_type,calc,inherit,id_cgroup,
                error_messages_like,statuses,notify_recovery,monday as "1",tuesday as "2",wednesday as "3",thursday as "4",friday as "5",
                saturday as "6",sunday as "0"
            FROM actions,entities_2_actions,commands,time_periods 
            WHERE actions.id_action=entities_2_actions.id_action 
                AND entities_2_actions.id_time_period=time_periods.id_time_period 
                AND actions.id_command=commands.id_command| )->fetchall_hashref('id_e2a');

    $s .= sprintf("post: %s; ", scalar( keys %{ $self->actions } ) );
    log_debug($s, _LOG_INFO)
        if $LogEnabled;

    $self->actions_convert();
}

sub actions_convert
{
    my $self = shift;
    my $act = $self->actions;

    my @tmp;

    for my $id_e2a (keys %$act)
    {

#konwersja time periodow
        for my $day (0..6)
        {
            $act->{$id_e2a}->{time_period}->{$day} = join (" ", map {"hr {$_}"} split(/\,/, $act->{$id_e2a}->{$day}));
            delete $act->{$id_e2a}->{$day};
        }

#konwersja statusow do status_arraya
        %{$act->{$id_e2a}->{statuses_array}} = %_ST_LIST;
        @tmp = split /\,/, $act->{$id_e2a}->{statuses};

        for my $t (@tmp)
        {
            if ($t =~ /^\d+$/)
            {
                $act->{$id_e2a}->{statuses_array}->{$t}++
                    if defined $act->{$id_e2a}->{statuses_array}->{$t};
            }
            elsif ($t =~ /^(\d+)\-(\d+)$/)
            {
                for ($1..$2)
                {
                    $act->{$id_e2a}->{statuses_array}->{$_}++
                        if defined $act->{$id_e2a}->{statuses_array}->{$_};
                }
            }
        }
    }
}

#tylko do testu - skasowac TMPF i wszystko co jest z tym zwiazane;

#my %TMPF;

sub run
{
    my $self = shift;
    my $ppid = shift;
    my $file;

    while (1) 
    { 
        exit
            if ! kill(0, $ppid);

        opendir(DIR, $ActionsDir);
        while (defined($file = readdir(DIR)))
        {
            next
                unless $file =~ /^action\./;

#SKASOWAC
#next
#    if defined $TMPF{$file};
#$TMPF{$file}++;
#KONIEC KASOWANIA

            $self->process_action_file($file);
        }
        closedir(DIR);

        $self->process_atable;

        if (flag_file_check($FlagsControlDir, 'actions_load', 1))
        {
            $self->actions_load;
        }
        if (flag_file_check($FlagsControlDir, 'atable_clear', 1))
        {
            $self->[ATABLE] = {};
        }
        if (flag_file_check($FlagsControlDir, 'actionsbroker_ips_load', 1))
        {
            $self->ips_load;
        }
        if (flag_file_check($FlagsControlDir, 'actions_dump', 1))
        {
            log_debug(Dumper($self->actions),_LOG_ERROR);
        }
        if (flag_file_check($FlagsControlDir, 'atable_dump', 1))
        {
            log_debug(Dumper($self->atable),_LOG_ERROR);
        }
        if (flag_file_check($FlagsControlDir, 'actionsbroker_ips_dump', 1))
        {
            log_debug(Dumper($self->ips),_LOG_ERROR);
        }

        sleep ($Period ? $Period : 15);
    }
}

sub process_action_file
{
    my $self = shift;
    my $file = shift;
    my $fullfile = sprintf(qq|%s/%s|, $ActionsDir, $file);

    log_debug(sprintf(qq|start processing action %s|,$file),_LOG_DEBUG)
        if $LogEnabled;

    my $data = {};

    open F, $fullfile
        or log_exception( EFileSystem->new($!), _LOG_ERROR);
    %$data = map { s/\n// && split /\|\|/, $_ && $_ } <F>;
    close F;

# DUPA - odkomentowac to
    unlink $fullfile
        or log_exception( EFileSystem->new($!), _LOG_ERROR);

    my ($tmp, $timestamp, $id_e2a, $id_entity) = split /\./, $file;
    $self->atable->{$id_entity}->{$id_e2a}->{queue}->{$timestamp} = $data;
}

sub process_atable
{
    my $self = shift;
    my $actions = $self->actions;
    my $atable = $self->atable;

    my ($act, $act_delete, $data, $id_e2a, $id_entity, $action, $tmp_ntf, $tmp_st, $tmp_st_old, $tmp_st_c, $tmp_st_c_old);

    for $id_entity (keys %$atable)
    {
        for $id_e2a (keys %{ $atable->{$id_entity} })
        {
            $act = $atable->{$id_entity}->{$id_e2a};

            if (! defined $actions->{$id_e2a})
            {
                delete $atable->{$id_entity}->{$id_e2a};
                delete $atable->{$id_entity}
                    unless keys %{$atable->{$id_entity}};
                next;
            }

            $action = $actions->{$id_e2a};
            $act_delete = 0;

            if (keys %{$act->{queue}})
            {
                $act->{notification_current} = 0
                    unless defined $act->{notification_current};
                for my $q_item (sort {$a <=> $b} keys %{$act->{queue}})
                {
                    $data = $act->{queue}->{$q_item};
#procesowanie kazdej nowej akcji z kolejki
#jesli status == OK -> docelowo usuniecie tej akcji z atable
                    if ((defined $data->{status} && $data->{status} eq _ST_OK)
                        || (defined $data->{status_calculated} && $data->{status_calculated} eq _ST_OK))
                    {
                        if ($action->{notify_recovery} && defined $act->{notification_sent} && $act->{notification_sent})
                        {
#potwierdzenie, ze juz jest OK;
                            $data->{recovered} = 1;
                            $data->{change} = defined $data->{status} ? 'own' : 'calc';
                            $self->job_create($id_entity, $data, $action, 1, $id_e2a, $act);
                        }
                        $act_delete = 1;
                    }
                    else
                    {
                        $act_delete = 0;
                        $act->{timestamp} = $q_item;
                    }
                    delete $act->{queue}->{$q_item};
                }
                $tmp_st = defined $act->{data}->{status} ? $act->{data}->{status}  : undef;
                $tmp_st_old = defined $act->{data}->{status_old} ? $act->{data}->{status_old}  : undef;
                $tmp_st_c = defined $act->{data}->{status_calculated} ? $act->{data}->{status_calculated}  : undef;
                $tmp_st_c_old = defined $act->{data}->{status_calculated_old} ? $act->{data}->{status_calculated_old}  : undef;
                $act->{data} = $data;

                if (defined $data->{status})
                {
                    $act->{data}->{status_calculated} = $tmp_st_c;
                    $act->{data}->{status_calculated_old} = $tmp_st_c_old;
                    $act->{data}->{change} = 'own';
                }
                else
                {
                    $act->{data}->{status} = $tmp_st;
                    $act->{data}->{status_old} = $tmp_st_old;
                    $act->{data}->{change} = 'calc';
                }
            }
            else
            {
#procesowanie starej akcji - czyli moze kolejna notyfikacja or cos
                $act->{notification_time} =  time - $act->{timestamp} - $action->{notification_start}
                    + $action->{notification_interval};

                $tmp_ntf = $action->{notification_interval}
                    ? int($act->{notification_time}/$action->{notification_interval})
                    : 0;

                $act->{notification_factor} = $tmp_ntf;
                if ($act->{notification_factor} > $act->{notification_current} 
                    && (! $action->{notification_stop} || $act->{notification_factor} <= $action->{notification_stop}))
                {
                    ++$act->{notification_current};
                    $self->job_create($id_entity, $act->{data}, $action, $act->{notification_current}, $id_e2a, $act );
#wykonaj kolejna notyfikacje
                }
#log_debug(sprintf(qq|time: %s factor: %s, current: %s, start: %s, stop: %s|,$act->{notification_time},$act->{notification_factor},$act->{notification_current},$action->{notification_start},$action->{notification_stop}),_LOG_ERROR);
            }

            $self->atable_entry_delete($id_entity, $id_e2a)
                if $act_delete;
        }
    }

}

sub atable_entry_delete
{
    my $self = shift;
    my $id_entity = shift;
    my $id_e2a = shift;

    my $atable = $self->atable;

    delete $atable->{$id_entity}->{$id_e2a};
    if (! keys %{$atable->{$id_entity}})
    {
        delete $atable->{$id_entity};
    }
}

sub job_create
{
    my $self = shift;
    my $id_entity = shift;
    my $data = shift;
    my $action = shift;
    my $notification_factor = shift;
    my $id_e2a = shift;
    my $act = shift;

    if (! keys %$action)
    {
        $self->atable_entry_delete($id_entity, $id_e2a);
        log_debug(sprintf(qq|action for entity %s ignored because action was deleted|, $id_entity), _LOG_INFO)
            if $LogEnabled;
        return;
    }
    elsif (! defined $action->{active} || $action->{active} ne '1')
    {
        $self->atable_entry_delete($id_entity, $id_e2a);
        log_debug(sprintf(qq|action for entity %s ignored because action is not active|, $id_entity), _LOG_INFO)
            if $LogEnabled;
        return;
    }
    elsif (! $action->{inherit} && $action->{id_entity} ne $id_entity)
    {
        $self->atable_entry_delete($id_entity, $id_e2a);
        log_debug(sprintf(qq|action for entity %s ignored because action is not inherited to children|, $id_entity), _LOG_INFO)
            if $LogEnabled;
        return;
    }
    elsif (defined $data->{status_calculated} && $data->{status_calculated} ne ' ' && $action->{calc})
    {
        delete $data->{status_calculated};
        delete $data->{status_calculated_old};
        log_debug(sprintf(qq|action for entity %s ignored because ignore calculated status change option enabled|,
            $id_entity), _LOG_DEBUG)
            if $LogEnabled;
        return;
    }


    if ( inPeriod(time(), $action->{time_period}->{ (localtime)[6] }) != 1)
    {
        log_debug(sprintf(qq|entity id %s, action id %s ignored because time didn\'t match configured time period.|, $id_entity, $action->{id_action}), _LOG_DEBUG)
            if $LogEnabled;;
        return;
    }

#test typu serwisu
    if ($action->{service_type})
    {
        log_debug('you configured action based on service type - this optioin is not yet supported and is ignored',_LOG_ERROR);
    }

#test err msg
    if ($action->{error_messages_like} && ! defined $data->{recovered})
    {
        if ($data->{errmsg} !~ /$action->{error_messages_like}/)
        {
            log_debug(sprintf(qq|entity id %s, action id %s ignored because error message "%s" didn\'t match action configured error message "%s".|, 
                $id_entity, $action->{id_action}, $data->{errmsg}, $action->{error_messages_like}), _LOG_DEBUG)
                if $LogEnabled;;
            return;
        }
    }

    if ($data->{change} eq 'own')
    {
        if ((! defined $data->{recovered} && $action->{statuses_array}->{$data->{status} } == 0)
            || (defined $data->{recovered} && $data->{recovered} && $data->{status} ne '0'))
            #|| (defined $data->{recovered} && $data->{recovered} && $data->{status_old} ne ' '
            #    && $action->{statuses_array}->{$data->{status_old} } == 0))
        {
            log_debug(sprintf(qq|entity id %s, action id %s ignored because current or previous status "%s" didn\'t match action configured statuses "%s".|, 
                $id_entity, $action->{id_action}, $data->{status}, $action->{statuses}), _LOG_DEBUG)
                if $LogEnabled;;
            return;
        }
    }
    else
    {
        if ((! defined $data->{recovered} 
            && defined  $action->{statuses_array} 
            && $data->{status_calculated}
            && defined $action->{statuses_array}->{$data->{status_calculated} }
            && $action->{statuses_array}->{$data->{status_calculated} } == 0)
            || (defined $data->{recovered} && $data->{recovered} && $data->{status_calculated} ne '0'))
            #|| (defined $data->{recovered} && $data->{recovered} && $data->{status_calculated_old} ne ' '
            #    && $action->{statuses_array}->{$data->{status_calculated_old} } == 0))
        {
            log_debug(sprintf(qq|entity id %s, action id %s ignored because current or previous status "%s" didn\'t match action configured statuses "%s".|, 
	        $id_entity, $action->{id_action}, $data->{status_calculated}, $action->{statuses}), _LOG_DEBUG)
	        if $LogEnabled;;
            return;
        }
    }

    ++$act->{notification_sent};
    $data->{command} = $action->{command};
    $data->{id_entity} = $id_entity;
    $data->{id_e2a} = $action->{id_e2a};
    $data->{id_e2a} = $action->{id_e2a};
    $data->{id_cgroup} = $action->{id_cgroup};
    $data->{cmd_name} = $action->{module};
    $data->{notification_factor} = $notification_factor; # - $action->{notification_start} + 1;
    $data->{notification_factor} .= " (last)"
        if $notification_factor == $action->{notification_stop};

    my $ips = $self->ips;
    $data->{entity_ip} = $ips->{$id_entity}
        if defined $ips->{$id_entity};
    $data->{parent_ip} = $ips->{$data->{id_parent}}
        if defined $ips->{$data->{id_parent}};

    for (keys %$data)
    {
        $data->{$_} = ' '
            if ! defined $data->{$_} || $data->{$_} eq '';
    }

    open F, sprintf(">%s/job.%s.%s.%s", $ActionsDir,$action->{module},$data->{id_entity},time()) || die $!;
    print F join("\n", map { "$_\|\|$data->{$_}" } keys %$data) . "\n";
    close F;

    log_debug(sprintf(qq|job %s for entity %s created|, $action->{module}, $data->{id_entity}), _LOG_DEBUG)
        if $LogEnabled;

#use Data::Dumper; log_debug($id_entity . Dumper($data) . Dumper($action) . " NTF_F: " . $notification_factor, _LOG_ERROR);
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;
