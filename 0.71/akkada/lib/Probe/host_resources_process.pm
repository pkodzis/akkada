package Probe::host_resources_process;

use vars qw($VERSION);

$VERSION = 0.2;

use base qw(Probe);
use strict;

use Net::SNMP;
use Number::Format qw(:subs);

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use URLRewriter;


our $DataDir = CFG->{Probe}->{DataDir};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};
our $MaxSNMPSplitRequest = CFG->{MaxSNMPSplitRequest};


$Number::Format::DECIMAL_FILL = 1;

sub id_probe_type
{
    return 17;
}

sub name
{
    return 'process';
}

use constant
{
    PROCESS => 11,
    SESSION => 13,
    ENTITY => 14,
    HOST_RESOURCES_PROCESS_PATH_MODE => 15,
};

our $OID = '1.3.6.1.2.1.25.4.2.1';  # process table
our $OID2 = '1.3.6.1.2.1.25.5.1.1'; # proces perf table
our $OID3 = '1.3.6.1.2.1.25.1.1.0'; #system uptime for CPU usage calculation ????

my $_hrSWRun =
{
    #1 => 'hrSWRunIndex',
    2 => 'hrSWRunName',
    #3 => 'hrSWRunID',
    4 => 'hrSWRunPath',
    5 => 'hrSWRunParameters',
    6 => 'hrSWRunType',
    7 => 'hrSWRunStatus',
};

my $_hrSWRunPerf =
{
    1 => 'hrSWRunPerfCPU',
    2 => 'hrSWRunPerfMem',
};

my $_hrSWRunStatus =
{
    1 => 'running',
    2 => 'runnable',    #-- waiting for resource -- (i.e., CPU, memory, IO)
    3 => 'notRunnable', #-- loaded but waiting for event
    4 => 'invalid',     #-- not loaded
};

my $_hrSWRunType =
{
    1 => 'unknown',
    2 => 'operatingSystem',
    3 => 'deviceDriver',
    4 => 'application',
};

sub oids_build
{
    my $self = shift;
    my $h = shift;
    my $snmp_split_request = shift;

    my @oids = ();
    my $index;

    for $index (keys %$h)
    {
        for (keys %$_hrSWRun)
        {   
            next
                if $_ < 3;
            push @oids, "$OID.$_.$index";
        }   
        for (keys %$_hrSWRunPerf)
        {   
            push @oids, "$OID2.$_.$index";
        }   
    }

    return [\@oids]
        if $snmp_split_request == 1;

    my $split = 0;
    my $result;

    for (@oids)
    {
        push @{$result->[$split]}, $_;
        ++$split;
        $split = 0
            if $split == $snmp_split_request;
    }
    return $result;
}


sub clear_data
{
    my $self = shift;
    $self->[PROCESS] = {};
    $self->[ENTITY] = undef;
};

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->[SESSION] = undef;
    $self->[HOST_RESOURCES_PROCESS_PATH_MODE] = 0;

    return $self;
}

sub process
{
    return $_[0]->[PROCESS];
}

sub host_resources_process_path_mode
{
    my $self = shift;
    $self->[HOST_RESOURCES_PROCESS_PATH_MODE] = shift
        if @_;
    return $self->[HOST_RESOURCES_PROCESS_PATH_MODE];
}

sub session
{
    my $self = shift;
    $self->[SESSION] = shift
        if @_;
    return $self->[SESSION];
}

sub mandatory_fields
{
    return
    [
        'host_resources_process_min',
        'host_resources_process_max',
    ]
}

sub manual
{
    return 1;
}

sub entity
{
    my $self = shift;
    $self->[ENTITY] = shift
        if @_;
    return $self->[ENTITY];
}

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);
    
    my $entity = shift;
    
    $self->clear_data;
    $self->entity($entity);

    if ($entity->has_parent_nosnmp_status)
    {
        $self->clear_data;
        $self->errmsg('');
        $self->status(_ST_UNKNOWN);
        return;
    }   
    
    my $id_entity = $entity->id_entity;

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter(sprintf( qq|ip in entity %s|, $id_entity))
        unless $ip;

    my $snmp_split_request = $entity->params_own->{'snmp_split_request'};
    log_debug(sprintf(qq|entity %s snmp_split_request: %s|, $id_entity, $snmp_split_request), _LOG_DEBUG)
        if $LogEnabled && $snmp_split_request;
    $snmp_split_request = 1
        unless $snmp_split_request;

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error)
    {
        $session->max_msg_size(2966);

        $self->session( $session );

        $self->host_resources_process_path_mode( $entity->params('host_resources_process_path_mode') );

        my $prList = undef;
        my $result = $self->discover_process;

        $prList = $result->{ $entity->name }
            if defined $result;


        if (! defined $prList )
        {
            my $host_resources_process_min = $entity->params('host_resources_process_min');
            if ($host_resources_process_min  != 0)
            {
                $self->errmsg('not found');
                $self->status(_ST_DOWN);
            }
            $self->save_data($id_entity);
#use Data::Dumper; print Dumper $self->process, $self->errmsg, $self->status; exit;
            $session->close
                if $session;

            return;
        }

        my $oids = $self->oids_build($prList, $snmp_split_request);

#use Data::Dumper; log_debug(Dumper $oids, _LOG_ERROR); 

        $result = {};

        if ($snmp_split_request == 1)
        {
            $result = $session->get_request( -varbindlist => $oids->[0] );
        }
        else
        {
            my $res;
            for (@$oids)
            {
                $res = $session->get_request( -varbindlist => $_ );

                if ($session->error)
                {
                    $oids->[0] = $_;
                    last;
                }

                for (keys %$res)
                {
                    $result->{$_} = $res->{$_};
                }
            }
        }

        $error = $session->error;
        if (! $error )
        {
            $self->result_dispatch($result);
            $self->utilization_status;
        }
        elsif ($error eq 'Message size exceeded maxMsgSize')
        {
#print $ip, ": ", $session->error, ": request too big - need to split\n";
            if ($snmp_split_request <= $MaxSNMPSplitRequest)
            {
                #my $parent = Entity->new($self->dbh, $entity->id_parent);
                ++$snmp_split_request;
                $entity->params('snmp_split_request', $snmp_split_request);
                #$parent->params('snmp_split_request', $snmp_split_request);
            }
            else
            {
                log_debug(sprintf(qq|maximum snmp_split_request value %s already set. cannot fix that!!! check configuration|,
                    $MaxSNMPSplitRequest), _LOG_ERROR);
            }
#print "new snmp_split_request: ", $snmp_split_request, "\n\n";
        }
        else
        {
            $self->errmsg('snmp error: ' . $error);
            $self->status(_ST_MAJOR);
        }
    }
    else
    {
        $self->errmsg($error);
        $self->status(_ST_MAJOR);
    }

#use Data::Dumper; print Dumper $self->process, $self->errmsg, $self->status; exit;

    $self->rrd_save($id_entity, $self->status);
    $self->save_data($id_entity);

    $session->close
        if $session;
}

sub result_dispatch
{
    my $self = shift;
    my $result = shift;

    if (! defined $result ||scalar keys %$result == 0)
    {
        $self->errmsg('process information not found');
        $self->status(_ST_MAJOR);
        return;
    }

    my $key;
    my $index;
    my $pr_index;
    my $process = $self->process;
    my $tmp = {};

    for (keys %$result)
    {
        $key = $_;

        if (/^$OID\./)
        {
            s/^$OID\.//g;
            ($index, $pr_index) = split /\./, $_, 2;
   
            if ($_hrSWRun->{$index} eq 'hrSWRunType')
            {
                $tmp->{$pr_index}->{ $_hrSWRun->{$index} } = defined $_hrSWRunType->{ $result->{$key} }
                     ? $_hrSWRunType->{ $result->{$key} }
                     : $result->{$key};
            } 
            elsif ($_hrSWRun->{$index} eq 'hrSWRunStatus')
            {
                $tmp->{$pr_index}->{ $_hrSWRun->{$index} } = defined $_hrSWRunStatus->{ $result->{$key} }
                     ? $_hrSWRunStatus->{ $result->{$key} }
                     : $result->{$key};
            }
            elsif ($_hrSWRun->{$index} eq 'hrSWRunPath' || $_hrSWRun->{$index} eq 'hrSWRunParameters')
            {
                $tmp->{$pr_index}->{ $_hrSWRun->{$index} } = $result->{$key}
                     ? $result->{$key}
                     : 'n/a';
            }
            else
            {
                $tmp->{$pr_index}->{ $_hrSWRun->{$index} } = $result->{$key};
            }
        } 
        elsif (/^$OID2\./)
        {
            s/^$OID2\.//g;
            ($index, $pr_index) = split /\./, $_, 2;
            $tmp->{$pr_index}->{ $_hrSWRunPerf->{$index} } = $result->{$key};
        }
    }

    if (scalar keys %$tmp == 0)
    {
        $process->{count} = 'U';
    }
    else
    {
        $process->{count} = scalar keys %$tmp;
        $process->{memory} = 0;
        $process->{cpu} = 0;
        $process->{pids} = [ sort { $a <=> $b } keys %$tmp];
        $process->{memorys} = [];
        $process->{cpus} = [];
        $process->{paths} = [];
        $process->{parameters} = [];
        $process->{types} = [];
        $process->{statuses} = [];
        $process->{invalid} = 0;
      
        for (sort { $a <=> $b } keys %$tmp)
        {
            $process->{memory} += ($tmp->{$_}->{hrSWRunPerfMem}*1024)
                if $tmp->{$_}->{hrSWRunPerfMem};
            $process->{cpu} += int($tmp->{$_}->{hrSWRunPerfCPU}/100)
                if $tmp->{$_}->{hrSWRunPerfCPU};

            push @{ $process->{memorys} }, $tmp->{$_}->{hrSWRunPerfMem}
                ? ($tmp->{$_}->{hrSWRunPerfMem}*1024)
                : 'n/a';
            push @{ $process->{cpus} }, $tmp->{$_}->{hrSWRunPerfCPU}
                ? int($tmp->{$_}->{hrSWRunPerfCPU}/100)
                : 'n/a';
            push @{ $process->{paths} }, $tmp->{$_}->{hrSWRunPath};
            push @{ $process->{parameters} }, $tmp->{$_}->{hrSWRunParameters};
            push @{ $process->{types} }, $tmp->{$_}->{hrSWRunType};
            push @{ $process->{statuses} }, $tmp->{$_}->{hrSWRunStatus};
            ++$process->{invalid}
                if $tmp->{$_}->{hrSWRunStatus} eq 'invalid';
        }
    }
#use Data::Dumper; print Dumper $result, $tmp, $process; exit if $self->entity->id_entity == 11883;
}

sub utilization_status
{  
    my $self = shift;
    my $process = $self->process;
    my $entity = $self->entity;

    my $host_resources_process_min = $entity->params('host_resources_process_min') || 0;
    my $host_resources_process_max = $entity->params('host_resources_process_max') || 0;
    my $host_resources_process_memory_max = $entity->params('host_resources_process_memory_max') || 0;
    my $host_resources_process_cpu_time_max = $entity->params('host_resources_process_cpu_time_max') || 0;
    my $host_resources_process_ignore_invalid_state = $entity->params('host_resources_process_ignore_invalid_state') || 0;

    if ($process->{invalid} && ! $host_resources_process_ignore_invalid_state)
    {
        $self->errmsg(qq|one or more processes in "invalid" status; zombie possible|);
        $self->status(_ST_DOWN);
    }

    if ($process->{count} !~ /\D/)
    {
        if ($host_resources_process_min && ! $process->{count})
        {
            $self->errmsg(qq|no process|);
            $self->status(_ST_DOWN);
        }
        elsif ($host_resources_process_min && $process->{count} < $host_resources_process_min)
        {
            $self->errmsg(qq|too less processes|);
            $self->status(_ST_MINOR);
        }
        elsif ($host_resources_process_max && $process->{count} > $host_resources_process_max)
        {
            $self->errmsg(qq|too few processes|);
            $self->status(_ST_MINOR);
        }
    }
    if ($process->{cpu} !~ /\D/)
    {
        if ($host_resources_process_cpu_time_max && $process->{cpu} > $host_resources_process_cpu_time_max)
        {
            $self->errmsg(qq|processes consumed too much CPU time|);
            $self->status(_ST_MINOR);
        }
    }
    if ($process->{memory} !~ /\D/)
    {
        if ($host_resources_process_memory_max && $process->{memory} > $host_resources_process_memory_max)
        {
            $self->errmsg(qq|processes consumed too much system memory|);
            $self->status(_ST_MINOR);
        }
    }
}

sub rrd_config
{   
    return
    {
        'count' => 'GAUGE',
        'memory' => 'GAUGE',
        'cpu' => 'COUNTER',
        'invalid' => 'GAUGE',
    };
}

sub log_snmp_error
{
    my $self = shift;
    if ($_[0])
    {
        log_debug($_[0], _LOG_WARNING)
            if $LogEnabled;
        return 1;
    }
    return 0;
}

sub discover_mode
{
    return _DM_NODISCOVER;
}

sub discover
{
    log_debug('configuration error! this probe does not support discover', _LOG_WARNING)
        if $LogEnabled;
    return;
}

sub discover_process
{
    my $self = shift;
    my $session = $self->session;

    my $host_resources_process_path_mode = $self->host_resources_process_path_mode;
    my $process = $session->get_table(-baseoid => sprintf(qq|%s.%s|, $OID, ($host_resources_process_path_mode ? 4 : 2)) );

    return undef
        if $self->log_snmp_error( $session->error() );

    return undef
        unless keys %$process;

    my $result = {};
    my $key;

    for (keys %$process)
    { 
        next
            unless $process->{$_};
        $key = $_;
        $host_resources_process_path_mode
            ? $result->{ $process->{$key} }->{ (split /$OID\.4\./, $_)[1] }++
            : $result->{ $process->{$key} }->{ (split /$OID\.2\./, $_)[1] }++;
    }

    return scalar keys %$result
        ? $result
        : undef;
}

sub save_data
{       
    my $self = shift;

    my $id_entity = shift;
    
    my $data_dir = $DataDir;

    my $h; 

    open F, ">$data_dir/$id_entity";

    $h = $self->process;

    my $tracks = ['count','memory','cpu'];
    for ( @$tracks )
    {       
        print F "$_\|$h->{$_}\n"
            if defined $h->{$_};
    }   

    $tracks = [ 'pids', 'memorys', 'cpus', 'paths', 'parameters', 'types', 'statuses' ];
    for ( @$tracks )
    {       
        print F sprintf(qq|$_\|%s\n|, join('|', @{ $h->{$_} }))
            if defined $h->{$_} && @{ $h->{$_} };
    }   

    close F;
}  

sub desc_brief
{   
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    if (defined $data->{count})
    {   
        push @$result, sprintf(qq|processes count: %s|, $data->{count});
    }  
    else
    {   
        push @$result, qq|processes count: n/a|;
    }

    if (defined $data->{cpu})
    {   
        my $d = duration_row($data->{cpu});
        push @$result, sprintf(qq|cpu time: %s|, $d ? $d : '00s');
    }  
    else
    {   
        push @$result, qq|cpu: n/a|;
    }


    if (defined $data->{memory})
    {   
        push @$result, sprintf(qq|memory: %s|, format_bytes($data->{memory}));
    }  
    else
    {  
        push @$result, qq|memory: n/a|;
    }

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    $table->addRow("processes count:",
        $data->{'count'} eq 'U'
            ? 'unknown'
            : $data->{'count'});

    if (defined $data->{pids})
    {
        my $t = HTML::Table->new();
        $t->setAttr('class="w"');

        $t->addRow('pid','cpu time','memory','status','type','path','parameters');

        $t->setCellAttr(1, $_, 'class="g4"')
            for (1 .. 7);
 
        my $i;
        my $j;
        my $d;
        my @s;
        my $tracks = ['pids','cpus','memorys','statuses','types','paths','parameters'];

        my $sume = {};

        for my $tr (@$tracks)
        { 
            next
                unless defined $data->{$tr};
            ++$i;
            @s = split /\|/, $data->{$tr};
            $j = 1;
            for (@s) 
            {
                ++$j;
                if ($tr eq 'cpus')
                {
                    $d = duration_row($_);
                    $t->setCell($j, $i, $d ? $d : '00s');
                    $sume->{$tr} += $_;
                }
                elsif ($tr eq 'memorys')
                {
                    $t->setCell($j, $i, format_bytes($_) );
                    $sume->{$tr} += $_;
                }
                else
                {
                    $t->setCell($j, $i, $_ );
                }
            }
        }
        $sume->{'cpus'} = duration_row( $sume->{cpus} );
        $t->addRow('<b>total:</b>', "<b>$sume->{cpus}</b>", "<b>" . format_bytes($sume->{memorys}) . "</b>");

        $t->setRowAttr(1, qq|class="t1"|);
        my $color = 0;
        for (2 .. $t->getTableRows)
        {   
            $t->setRowAttr($_, sprintf(qq|class="tr_%d"|, $color));
            $color = ! $color;
        }

        $table->addRow( 'processes table:', $t->getTable );
        $table->setCellAttr($table->getTableRows, 2, 'class="t1"');
    }
}   

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;

    my $result = sprintf(qq|%s%s|,
        $entity->name,
        $entity->status_weight == 0
            ? '*'
            : '');

    return $result;
}

sub rrd_load_data
{
    return ($_[0]->rrd_config, $_[0]->process);
}

sub menu_stat
{ 
    return 1;
}   

sub stat
{       
    my $self = shift;
    my $table = shift;
    my $entity = shift;
    my $url_params = shift;

    my $cgi = CGI->new();
        
    my $url;
    $url_params->{probe} = 'host_resources_process';
    
    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'count';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    
    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'cpu';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    
    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'memory';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    
    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'invalid';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    
}           
    
sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $url_params = $rrd_graph->url_params;

    if ($url_params->{probe_specific} eq 'count')
    {
        $rrd_graph->unit('no.');
        $rrd_graph->title('processes count');
    }
    elsif ($url_params->{probe_specific} eq 'cpu')
    {
        $rrd_graph->unit('sec');
        $rrd_graph->title('CPU time consumed by processes');
    }
    elsif ($url_params->{probe_specific} eq 'memory')
    {
        $rrd_graph->unit('Bytes');
        $rrd_graph->title('real system memory allocated to processes');
    }
    elsif ($url_params->{probe_specific} eq 'invalid')
    {
        $rrd_graph->unit('no');
        $rrd_graph->title('number of processes in invalid state');
    }
}

sub snmp
{
    return 1;
}

1;
