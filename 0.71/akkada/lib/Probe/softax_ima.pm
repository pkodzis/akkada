package Probe::softax_ima;

use vars qw($VERSION);

$VERSION = 0.4;

use base qw(Probe);
use strict;

use Time::HiRes qw(gettimeofday tv_interval);

use Net::SNMP;

use MyException qw(:try);
use Constants;
use Configuration;
use Log;
use Entity;
use URLRewriter;
use Common;

use RRDGraph;

our $IgnoreSource = CFG->{Probes}->{softax_ima}->{IgnoreSource};
our $IgnoreText = CFG->{Probes}->{softax_ima}->{IgnoreText};
our $DataDir = CFG->{Probe}->{DataDir};
our $LogEnabled = CFG->{LogEnabled};

$|=1;

my $OID = '1.3.6.1.4.1.11036.3.1.1.1.1';

my $_imaEntry = 
{
    1 => 'imaIp',
    2 => 'imaName',
    3 => 'imaActive',
    4 => 'imaRestart',

    5 => 'imaErrorCount',
    6 => 'imaLastErrorText',
    7 => 'imaLastErrorSubsystem',
    8 => 'imaLastErrorTime',
    10 => 'imaLastErrorSource',

    11 => 'imaWarnCount',
    12 => 'imaLastWarnText',
    13 => 'imaLastWarnSubsystem',
    14 => 'imaLastWarnTime',
    16 => 'imaLastWarnSource',

};

use constant
{
    IMAENTRY => 10,
    ENTITY => 12,
};

sub name
{
    return 'Softax IMA service';
}

sub id_probe_type
{
    return 16;
}

sub imaEntry
{
    return $_[0]->[IMAENTRY];
}

sub entity
{
    my $self = shift;
    $self->[ENTITY] = shift
        if @_;
    return $self->[ENTITY];
}

sub clear_data
{
    my $self = shift;
    $self->[IMAENTRY] = {};
    $self->[ENTITY] = undef;
};

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);

    $self->clear_data;

    my $entity = shift;

    $self->entity($entity);
    my $id_entity = $entity->id_entity;

    my ($t0, $t1);

    $t0 = [gettimeofday];

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter(sprintf( qq|ip in entity %s|, $id_entity))
        unless $ip;

    my $softax_ima_port = $entity->params('softax_ima_port');
    throw EEntityMissingParameter('softax_ima_port')
        unless $softax_ima_port;

    my $softax_ima_community = $entity->params('softax_ima_community');
    throw EEntityMissingParameter('softax_ima_community')
        unless $softax_ima_community;

    my $index = $entity->params('index');
    throw EEntityMissingParameter(sprintf( qq|index in entity %s|, $id_entity))
        unless $index;

    my ($name, $ima_ip) = split /:/, $entity->name, 2;
    $name = join '.', unpack( 'c*', $name );

    my $version = 'snmpv2c';

    my $timeout = $entity->params('timeout');
    $timeout = 3
        unless defined $timeout;

    my $softax_ima_min_active = $entity->params('softax_ima_min_active');
    $softax_ima_min_active = 1
        unless defined $softax_ima_min_active;
    my $softax_ima_max_active = $entity->params('softax_ima_max_active');
    $softax_ima_max_active = 0
        unless defined $softax_ima_max_active;

    my ($session, $error, $result, $oids, $tmp);

    ($session, $error) = Net::SNMP->session(
        -hostname => $ip,
        -community => $softax_ima_community,
        -port => $softax_ima_port,
        -version => $version,
        -translate => ['-all'],
        -timeout => 3,
        -retries => 3);

    if (! $error)
    {
        $session->max_msg_size(8096);

        $oids = $self->oids_build($name, $ima_ip, $index);

        for (@$oids)
        {
            $tmp = $session->get_request( -varbindlist => [ $_ ] );
            $result->{$_} = $tmp->{$_};
            $error = $session->error;
            last
                if $error;
        };

        $session->close
            if $session;

    }

    if (! $error )
    {  
        $self->result_dispatch($result, $name, $ima_ip, $index);

        my $imaEntry = $self->imaEntry;
        $self->cache_update($id_entity, $imaEntry);
        my $ignore = 0;
        if (keys %$imaEntry)
        {
            my $ch = $self->cache;
            $ch = defined $ch->{$id_entity}
                ? $ch->{$id_entity}
                : undef;
            if ( defined $ch && $ch->{imaRestart}->[1] ne 'U' && $ch->{imaRestart}->[1] > 0)
            {
                $self->errmsg('component restarts detected!');
                $self->status(_ST_MAJOR);
            }
            if ( $imaEntry->{imaActive} < $softax_ima_min_active )
            {
                $self->errmsg('too less components');
                $self->status(_ST_DOWN);
            }
            elsif (  $softax_ima_max_active && $imaEntry->{imaActive} > $softax_ima_max_active )
            {
                $self->errmsg('too many components');
                $self->status(_ST_MINOR);
            }

            if (defined $ch && $ch->{imaErrorCount}->[1] ne 'U' && $ch->{imaErrorCount}->[1] > 0)
            {
                my $softax_ima_stop_alarm_errors = $entity->params('softax_ima_stop_alarm_errors');

                for (@$IgnoreSource)
                {
                    if ($imaEntry->{imaLastErrorSource} =~ /$_/i)
                    {
                        $ignore++;
                        last;
                    }
                }

                if (! $ignore )
                {
                    for (@$IgnoreText)
                    {
                        if ($imaEntry->{imaLastErrorText} =~ /$_/i)
                        {
                            $ignore++;
                            last;
                        }
                    }
                }

                if (! $ignore && ! $softax_ima_stop_alarm_errors)
                {
                    $error = sprintf(qq|subsystem %s source: %s|,
                        $imaEntry->{imaLastErrorSubsystem},
                        $imaEntry->{imaLastErrorSource},
                    );
                    $self->errmsg($error);
                    $self->status(_ST_MAJOR);
                }
            } 

            if (defined $ch && $ch->{imaWarnCount}->[1] ne 'U' && $ch->{imaWarnCount}->[1] > 0)
            {
                my $softax_ima_start_alarm_warnings = $entity->params('softax_ima_start_alarm_warnings');
                if ($softax_ima_start_alarm_warnings)
                {

                    for (@$IgnoreSource)
                    {
                        if ($imaEntry->{imaLastWarnSource} =~ /$_/i)
                        {
                            $ignore++;
                            last;
                        }
                    }

                    if (! $ignore )
                    {
                        for (@$IgnoreText)
                        {
                            if ($imaEntry->{imaLastWarnText} =~ /$_/i)
                            {
                                $ignore++;
                                last;
                            }
                        } 
                    }   

                    if (! $ignore)
                    {
                        $error = sprintf(qq|subsystem: %s source: %s|,
                            $imaEntry->{imaLastWarnSubsystem},
                            $imaEntry->{imaLastWarnSource},
                        );
                        $self->errmsg($error);
                        $self->status(_ST_MINOR);
                    }
                }
            }
        }
        else
        {
            $self->errmsg('component information not available');
            $self->status(_ST_DOWN);
        }
    }
    else
    {   
        $self->errmsg('snmp error: ' . $error);
        $self->status(_ST_MAJOR);
    }

    $self->rrd_save($id_entity, $self->status);
    $self->save_data($id_entity);
}

sub cache_keys
{  
    return
    [
        'imaRestart',
        'imaWarnCount',
        'imaErrorCount',
    ];
}

sub oids_build
{
    my $self = shift;

    my $name = shift;
    my $ima_ip = shift;
    my $index = shift;

    my (@oids, $s);

    for (keys %$_imaEntry)
    {   
        next
            if $_ < 3;
        push @oids, sprintf(qq|%s.%s.%s.%s.%s|, $OID, $_, $ima_ip, $index, $name);
    }

    return \@oids;
}

sub result_dispatch
{
    my $self = shift;

    my $result = shift;
    my $name = shift;
    my $ima_ip = shift;
    my $index = shift;

    return 
        unless defined $result;

    my $key;

    for (keys %$result)
    {   
        $key = $_;
        if (/^$OID\./)
        {   
            s/^$OID\.//g;
            s/\.$ima_ip.$index.$name$//g;
            $self->[IMAENTRY]->{ $_imaEntry->{$_} } = $result->{$key}
                if defined $_imaEntry->{$_};
        }
    }
}

sub rrd_result
{
    my $self = shift;
    my $imaEntry = $self->imaEntry;
    return
    {   
        'imaActive' => defined $imaEntry->{imaActive} ? $imaEntry->{imaActive} : 'U',
        'imaRestart' => defined $imaEntry->{imaRestart} ? $imaEntry->{imaRestart} : 'U',
        'imaErrorCount' => defined $imaEntry->{imaErrorCount} ? $imaEntry->{imaErrorCount} : 'U',
        'imaWarnCount' => defined $imaEntry->{imaWarnCount} ? $imaEntry->{imaWarnCount} : 'U',
    };
}

sub rrd_config
{   
    return
    {   
        'imaActive' => 'GAUGE',
        'imaRestart' => 'COUNTER',
        'imaErrorCount' => 'COUNTER',
        'imaWarnCount' => 'COUNTER',
    };
}

sub discover_mode
{
    return _DM_MIXED;
}

sub discover_mandatory_parameters
{       
    my $self = shift;
    my $mp = $self->SUPER::discover_mandatory_parameters();
    
    push @$mp, 'softax_ima_port';
    push @$mp, 'softax_ima_community';
    
    return $mp;
}   

sub discover 
{
    my $self = shift;
    $self->SUPER::discover(@_);
    my $entity = shift;

    my $softax_ima_port = $entity->params('softax_ima_port');
    throw EEntityMissingParameter('softax_ima_port')
        unless $softax_ima_port;

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter('ip')
        unless $ip;

    my $softax_ima_community = $entity->params('softax_ima_community');
    throw EEntityMissingParameter('softax_ima_community')
        unless $softax_ima_community;
    
    my $version = 'snmpv1';
    my ($session, $error);

    my @ima_ports = split /::/, $softax_ima_port;

    my $result;
    my $new;
    my $st; #tmp string
    my $oid;
    my $old;

    for my $ima_port (@ima_ports)
    {
        $old = {};
        $new = {};
        ($session, $error) = Net::SNMP->session(
            -hostname => $ip,
            -community => $softax_ima_community,
            -version => $version,
            -port => $ima_port,
            -translate => ['-all'],
            -timeout => 3,
            -retries => 3);
    

        if (! $error)
        {
            $session->max_msg_size(8096);


            $oid = $OID . ".2";
            $result = $session->get_table(-baseoid => $oid);

            $error = $session->error();

            if ($error)
            {
                log_debug($error, _LOG_WARNING)
                    if $LogEnabled;
                return;
            }

            for (keys %$result)
            {
                $st = $result->{$_};

                next
                    unless $st;

                s/^$oid.//g;
                $new->{ $_ }->{name} = $st;
                $new->{ $_ }->{index} = (split /\./, $_)[4];
            }

            $oid = $OID . ".1";
            $result = $session->get_table(-baseoid => $oid);

            $error = $session->error();

            if ($error)
            {
                log_debug($error, _LOG_WARNING)
                    if $LogEnabled;
                return;
            }

            for (keys %$result)
            {
                $st = $result->{$_};

                next
                    unless $st;

                s/^$oid.//g;
                $new->{ $_ }->{oid} = "$oid.$_";
                $new->{ $_ }->{softax_ima_index_ip} = $st;
            }

            return
                unless $new;

            for (keys %$new)
            {
                $st = sprintf(qq|%s:%s:%s|, $new->{$_}->{name}, $new->{$_}->{softax_ima_index_ip}, $ima_port);
                $new->{ $st }  = $new->{ $_ };
                delete $new->{ $_ };
            }

            $old = $self->_discover_get_existing_entities($entity);

            for my $name (keys %$old)
            {
                next
                    unless defined $new->{$name};

                $old->{$name}->{entity}->params('index', $new->{$name}->{index})
                    if $new->{$name}->{index} ne $old->{$name}->{index};

                if ($old->{$name}->{entity}->status eq _ST_BAD_CONF)
                {
                    $old->{$name}->{entity}->errmsg('');
                    $old->{$name}->{entity}->status(_ST_UNKNOWN);
                }

                delete $new->{$name};
                delete $old->{$name};
            }

            for (keys %$new)
            {
                $self->_discover_add_new_entity($entity, $_, $new->{$_});
                delete $new->{$_};
            }

            for (keys %$old)
            {
            #    $old->{$_}->{entity}->status(_ST_BAD_CONF);
            #    $old->{$_}->{entity}->db_update_entity;
            # albo serwis jest gaszony albo go nie ma. jak to wykryc?
            }

        }
        else
        {
            log_debug($error, _LOG_WARNING)
                if $LogEnabled;
        }
    }

}

sub _discover_add_new_entity
{
    my ($self, $parent, $name, $new) = @_;

    $name =~ /(.*:.*:)(.*)/;
    $name = $1;
    my $softax_ima_port = $2;
    $name =~ s/:$//;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s index %s ima_port %s|, $parent->id_entity, $name, $new->{index}, $softax_ima_port), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = $self->_entity_add({
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {
           index => $new->{index},
           softax_ima_port => $softax_ima_port,
       },
       }, $self->dbh);

    if (ref($entity) eq 'Entity')
    {
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s index %s ima_port %s|, 
            $parent->id_entity, $entity->id_entity, $name, $new->{index}, $softax_ima_port), _LOG_INFO)
            if $LogEnabled;
    }
}

sub _discover_get_existing_entities
{

    my $self = shift;

    my @list = $self->SUPER::_discover_get_existing_entities(@_);

    my $parent = shift;

    my $result;
    my $name;

    for (@list)
    {   
        my $entity = Entity->new($self->dbh, $_);                                   
        if (defined $entity)
        {
            $name = $entity->name;
            $name = sprintf("%s:%s", $name, $entity->params('softax_ima_port'));
            $result->{$name}->{entity} = $entity;
            $result->{$name}->{index} = $entity->params('index');
        };
    };
    return $result;
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;
    my $data = $self->imaEntry;
    my $ch = $self->cache->{$id_entity};

    my $data_dir = $DataDir;

    open F, ">$data_dir/$id_entity";

    for ( map { "$_\|$data->{$_}\n" } keys %$data )
    {
        print F $_;
    }

    #print F sprintf(qq|imaActive\|%s\n|, $data->{imaActive})
    #    if defined $data->{imaActive};
    #print F sprintf(qq|imaRestart\|%s\n|, $data->{imaRestart})
    #    if defined $data->{imaRestart};

    if (defined $ch->{imaRestart})
    {
        print F sprintf(qq|imaRestartDelta\|%s\n|, $ch->{imaRestart}->[1]);
        print F sprintf(qq|imaRestartDeltaTime\|%s\n|, $ch->{delta});
    }
    if (defined $ch->{imaErrorCount})
    {
        print F sprintf(qq|imaErrorCountDelta\|%s\n|, $ch->{imaErrorCount}->[1]);
        print F sprintf(qq|imaErrorCountDeltaTime\|%s\n|, $ch->{delta});
    }
    if (defined $ch->{imaWarnCount})
    {
        print F sprintf(qq|imaWarnCountDelta\|%s\n|, $ch->{imaWarnCount}->[1]);
        print F sprintf(qq|imaWarnCountDeltaTime\|%s\n|, $ch->{delta});
    }

    close F;

    open F, ">$data_dir/$id_entity.chat";
    print F "=======LAST ERROR: ====================================================\n";
    print F sprintf(qq|subsystem: %s\n|, $data->{imaLastErrorSubsystem});
    print F sprintf(qq|source: %s\n|, $data->{imaLastErrorSource});
    print F sprintf(qq|time: %s\n|, snmp_DateAndTime_2_str($data->{imaLastErrorTime}));
    print F sprintf(qq|text: %s\n|, $data->{imaLastErrorText});
    print F "=======LAST WARNING: ====================================================\n";
    print F sprintf(qq|subsystem: %s\n|, $data->{imaLastWarnSubsystem});
    print F sprintf(qq|source: %s\n|, $data->{imaLastWarnSource});
    print F sprintf(qq|time: %s\n|, snmp_DateAndTime_2_str($data->{imaLastWarnTime}));
    print F sprintf(qq|text: %s\n|, $data->{imaLastWarnText});
    close F;

}

sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    if (defined $data->{imaActive})
    {   
        push @$result, sprintf(qq|active: %s|, $data->{imaActive});
    }
    else
    {   
        push @$result, qq|active: n/a|;
    }

    if (defined $data->{imaRestart})
    {    
        push @$result, sprintf(qq|total restarts: %s|, $data->{imaRestart});
    }  
    else
    {    
        push @$result, qq|total restarts: n/a|;
    }    

    if (defined $data->{imaRestartDelta} && $data->{imaRestartDelta} > 0)
    {   
        push @$result, sprintf(qq|restarts: %s in %.f last sec|, $data->{imaRestartDelta}, $data->{imaRestartDeltaTime});
    }

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity, $url_params) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    $table->addRow('active components', $data->{imaActive})
        if defined $data->{imaActive};
    $table->addRow('total restarts count', $data->{imaRestart})
        if defined $data->{imaRestart};
    if (defined $data->{imaRestartDelta})
    {
        $table->addRow('restarts progress', sprintf(qq|%s in %.f last sec|, $data->{imaRestartDelta}, $data->{imaRestartDeltaTime}));
    }

    if (defined $data->{imaErrorCountDelta})
    {
        $table->addRow('errors progress', sprintf(qq|%s in %.f last sec|, $data->{imaErrorCountDelta}, $data->{imaErrorCountDeltaTime}));
    }
    if (defined $data->{imaWarnCountDelta})
    {
        $table->addRow('warnings progress', sprintf(qq|%s in %.f last sec|, $data->{imaWarnCountDelta}, $data->{imaWarnCountDeltaTime}));
    }
    
    my $data_dir = $DataDir;
    if (open F, sprintf(qq|%s/%s.chat|, $data_dir, $entity->id_entity))
    {
        my $flag = 0;
        $data = "";
        while (<F>)
        {
            if ($_ =~/=======LAST /)
            {
                s/=//g;
                $flag = 1;
                if ($data)
                {
                    $data .= "</pre>";
                    $table->addRow($data);
                    $table->setCellColSpan($table->getTableRows, 1, 2);
                    $data = "";
                }
            }
            if ($flag)
            {
                $flag = 0;
                $table->addRow("");
                $table->setCellColSpan($table->getTableRows, 1, 2);
                $data = "<pre>";
            }
            $data .= $_;
        }

        $data .= "</pre>";
        close F;
        $table->addRow($data);
        $table->setCellColSpan($table->getTableRows, 1, 2);
    }
}

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;

    my $result = sprintf(qq|%s:%s%s|,
        $entity->name,
        $entity->params('softax_ima_port'),
        $entity->status_weight == 0
            ? '*'
            : '');

    return $result;
}  

sub menu_stat
{ 
    return 1;
}

sub alarm_utils_button_get
{
    my ($self, $id_entity, $id_probe_type, $url_params) = @_;
    use Window::Buttons;
    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $buttons->add({ caption => '-= show last IMA messages =-', target => $id_entity,
        url => url_get({ id_entity => $id_entity, section => 'utils', 
        id_probe_type => $id_probe_type, form_id => 1 }, $url_params)});
    return $buttons->get();
}

sub alarm_utils_button
{
    return 1;
}

sub stat
{
    my $self = shift;
    my $table = shift;
    my $entity = shift;
    my $url_params = shift;
    my $default_only = defined @_ ? shift : 0;

    my $cgi = CGI->new();

    my $url;
    $url_params->{probe} = 'softax_ima';
    
    $url_params->{probe_prepare_ds} = 'prepare_ds';
                 
    $url_params->{probe_specific} = 'imaActive';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    return
        if $default_only;

    $url_params->{probe_specific} = 'imaRestart';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'imaErrorCount';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'imaWarnCount';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $url_params = $rrd_graph->url_params;

    if ($url_params->{probe_specific} eq 'imaRestart')
    {
        $rrd_graph->title('component restarts');
    }
    elsif ($url_params->{probe_specific} eq 'imaRestart')
    {
        $rrd_graph->title('active components');
    }
    elsif ($url_params->{probe_specific} eq 'imaErrorCount')
    {
        $rrd_graph->title('errors count');
    }
    elsif ($url_params->{probe_specific} eq 'imaWarnCount')
    {
        $rrd_graph->title('warnings count');
    }

    $rrd_graph->unit('no');
}

sub snmp
{
    return 1;
}

1;
