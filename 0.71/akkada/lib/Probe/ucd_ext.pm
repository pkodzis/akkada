package Probe::ucd_ext;

use vars qw($VERSION);

$VERSION = 1.1;

use base qw(Probe);
use strict;

use Net::SNMP qw(snmp_dispatcher oid_lex_sort ticks_to_time);
use Number::Format qw(:subs);

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use URLRewriter;
use FormatDispatcher;

our $DataDir = CFG->{Probe}->{DataDir};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};
our $MaxSNMPSplitRequest = CFG->{MaxSNMPSplitRequest};

$Number::Format::DECIMAL_FILL = 1;

sub id_probe_type
{
    return 9;
}

sub name
{
    return 'UCD MIB extension';
}

use constant
{
    DATA => 11,
    SESSION => 13,
    ENTITY => 14,
    RRD_DATA => 15,
    DATA_TYPE => 16,
    RRD_CONFIG_STAT => 17,
    CACHE_KEYS => 18,
    NUM_RESULT => 19,
};

our $OID = '1.3.6.1.4.1.2021.8.1';

my $_entry =
{
    2 => 'extNames',
    3 => 'extCommand',
    100 => 'extResult', #exit script code
    101 => 'extOutput', #first line of the output script
};

sub oids_build
{   
    my $self = shift;
    my $index = shift;

    my @oids = ();

    for (keys %$_entry)
    {   
        push @oids, "$OID.$_.$index";
    }

    return \@oids;
}

sub clear_data
{
    my $self = shift;
    $self->[DATA] = {};
    $self->[DATA_TYPE] = _DT_RAW;
    $self->[RRD_DATA] = {};
    $self->[ENTITY] = undef;
    $self->[RRD_CONFIG_STAT] = {};
};

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->[SESSION] = undef;
    $self->[RRD_DATA] = {};
    $self->[RRD_CONFIG_STAT] = {};
    $self->[CACHE_KEYS] = [];

    return $self;
}

sub cache_keys
{
    return $_[0]->[CACHE_KEYS];
}

sub data
{
    return $_[0]->[DATA];
}

sub rrd_data
{
    return $_[0]->[RRD_DATA];
}

sub num_result
{
    return $_[0]->[NUM_RESULT];
}

sub session
{
    my $self = shift;
    $self->[SESSION] = shift
        if @_;
    return $self->[SESSION];
}

sub data_type
{
    my $self = shift;
    $self->[DATA_TYPE] = shift
        if @_;
    return $self->[DATA_TYPE];
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

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error)
    {
        $session->max_msg_size(2944);
        $self->session( $session );

        my $index = undef;
        my $result = $self->discover_data;

        $index = $result->{ $entity->name }
            if defined $result;

        if (! defined $index)
        {
            $self->errmsg('not found');
            $self->status(_ST_MAJOR);
            return;
        }

        $result = $session->get_request( -varbindlist => $self->oids_build( $index ) );

        my $error = $session->error();
        if (! $error )
        {
            $self->result_dispatch($result);
            $self->cache_update($id_entity, $self->num_result)
                if $self->data_type eq _DT_STAT;
            $self->utilization_status;
            $self->rrd_save($id_entity, $self->status);
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

    $self->save_data($id_entity);

    $session->close
        if $session;
}

sub result_dispatch
{
    my $self = shift;
    my $result = shift;

    if (scalar keys %$result == 0)
    {
        $self->errmsg('data information not found');
        $self->status(_ST_MAJOR);
        return;
    }

    my $data = $self->data;

    my $key;
    my $index;

    for (keys %$result)
    {
        $key = $_;

        if (/^$OID\./)
        {
            s/^$OID\.//g;
            $index = (split /\./, $_)[0];
            $data->{ $_entry->{$index} } = $result->{$key};
        }
    }

    if ( defined $data->{extOutput} && $data->{extOutput} ne '')
    {
        my @tmp = split /\|\|/, $data->{extOutput};
        if (@tmp && $tmp[0] eq 'AKKADA')
        {
            if (defined $tmp[1] && $tmp[1] eq 'TEXT')
            {
                $self->data_type( _DT_TEXT );
            }
            elsif (defined $tmp[1] && $tmp[1] eq 'STAT')
            {
                $self->data_type( _DT_STAT );
            }
            else
            {
                $self->data_type( _DT_BAD );
            }
        }
    }

    my $data_type = $self->data_type;
    $self->entity->params('ucd_ext_data_type', $data_type);

    if ($data_type eq _DT_TEXT)
    {
        $self->result_dispatch_text();
    }
    elsif ($data_type eq _DT_STAT)
    {
        $self->result_dispatch_stat();
    }
    elsif ($data_type eq _DT_RAW)
    {
        my $rrd_data = $self->rrd_data;
        $rrd_data->{extOutput} = $data->{extOutput} ne '' && $data->{extOutput} =~ /^-{0,1}\d*\.{0,1}\d+$/
            ? $data->{extOutput}
            : 'U';
        my %h = %$rrd_data;
        $self->[NUM_RESULT] = \%h;
    }
}

sub result_dispatch_text
{  
    my $self = shift;
    my $data = $self->data;
    my $error = '';

    ($data->{text}, $error) = format_dispatch($data->{extOutput});

#use Data::Dumper; log_debug("Y: " . Dumper($self->data),_LOG_ERROR);

    if ($error)
    {
        log_debug( $error, _LOG_WARNING);
        $self->data_type( _DT_BAD );
    }
}

sub result_dispatch_stat
{  
    my $self = shift;
    my $data = $self->data;
    my $error = '';

    ($data->{stati}, $error) = format_dispatch($data->{extOutput});

    if ($error)
    {
        log_debug( $error, _LOG_WARNING);
        $self->data_type( _DT_BAD );
    }

    my $rrd_config_stat = $self->rrd_config_stat;
    my $rrd_data = $self->rrd_data;
    $self->cache_keys_init;
    my $cache_keys = $self->cache_keys;

    for (sort { $a <=> $b } keys %{$data->{stati}})
    {
        $rrd_config_stat->{ $data->{stati}->{$_}->{title} } = $data->{stati}->{$_}->{cfs};
        $rrd_data->{ $data->{stati}->{$_}->{title} } = $data->{stati}->{$_}->{output};
        push @$cache_keys, $data->{stati}->{$_}->{title}
            if $data->{stati}->{$_}->{cfs} eq 'COUNTER';
    }
#use Data::Dumper; log_debug(Dumper($rrd_config_stat) . ":x:" . Dumper($rrd_data), _LOG_DEBUG);

    my %h = %$rrd_data;
    $self->[NUM_RESULT] = \%h;
}

sub cache_keys_init
{
    $_[0]->[CACHE_KEYS] = [];
}

sub utilization_status
{  
    my $self = shift;
    my $data = $self->data;
#use Data::Dumper; log_debug("X:" . Dumper($data),_LOG_ERROR);

    my $data_type = $self->data_type;
    my $entity = $self->entity;

    if ($data->{extResult} != 0)
    {
        $self->errmsg(qq|script error|);
        $self->status(_ST_MAJOR);
        return;
    }

    if ($data_type eq _DT_BAD)
    {
        $self->errmsg(qq|script output format problem|);
        $self->status(_ST_DOWN);
    }
    elsif ($data_type eq _DT_RAW)
    {
        my $ucd_ext_min = $entity->params('ucd_ext_min') || 0;
        my $ucd_ext_max = $entity->params('ucd_ext_max') || 0;
        my $ucd_ext_expect = $entity->params('ucd_ext_expect') || '';
        my $ucd_ext_bad = $entity->params('ucd_ext_bad') || '';

        if ($ucd_ext_expect ne '' && $data->{extOutput} !~ /$ucd_ext_expect/)
        {
            $self->errmsg(sprintf(qq|expected string "%s" not found|,$ucd_ext_expect));
            $self->status(_ST_DOWN);
        }
        if ($ucd_ext_bad ne '' && $data->{extOutput} =~ /$ucd_ext_bad/)
        {
            $self->errmsg(sprintf(qq|bad string "%s" found|,$ucd_ext_bad));
            $self->status(_ST_DOWN);
        }
        if ($ucd_ext_min && $data->{extOutput} < $ucd_ext_min)
        {
            $self->errmsg(qq|script output too less|);
            $self->status(_ST_MINOR);
        }
        elsif ($ucd_ext_max && $data->{extOutput} > $ucd_ext_max)
        {
            $self->errmsg(qq|script output too high|);
            $self->status(_ST_MINOR);
        }
    }
    elsif ($data_type eq _DT_TEXT)
    {
        my $output = $data->{text}->{output};
        my $expected = $data->{text}->{expected};
        my $bad = $data->{text}->{bad};
#use Data::Dumper; log_debug(Dumper($data),_LOG_ERROR);

        if (defined $expected && ref($expected) eq 'ARRAY')
        {
            for (@$expected)
            {
                if ($output !~ /$_/)
                {
                    $self->errmsg(sprintf(qq|expected string "%s" not found|,$_));
                    $self->status(_ST_DOWN);
                }
            }
        }
        if (defined $bad && ref($bad) eq 'ARRAY')
        {
            for (@$bad)
            {   
                if ($output =~ /$_/)
                {
                    $self->errmsg(sprintf(qq|bad string "%s" found|,$_));
                    $self->status(_ST_DOWN);
                }
            }   
        }
    }
    elsif ($data_type eq _DT_STAT)
    {   
        for (keys %{$data->{stati}})
        {
            if ($data->{stati}->{$_}->{cfs} eq 'COUNTER')
            {
                my $ch = $self->cache->{$entity->id_entity};
                if (defined $data->{stati}->{$_}->{min} && $ch->{$_}->[1] < $data->{stati}->{$_}->{min})
                {
                    $self->errmsg(sprintf(qq|%s minimum threshold exceeded|, $data->{stati}->{$_}->{title}));
                    $self->status(_ST_MINOR);
                }
                elsif (defined $data->{stati}->{$_}->{max} && $ch->{$_}->[1] > $data->{stati}->{$_}->{max})
                {
                    $self->errmsg(sprintf(qq|%s maximum threshold exceeded|, $data->{stati}->{$_}->{title}));
                    $self->status(_ST_MINOR);
                }
            }
            else
            {
                if (defined $data->{stati}->{$_}->{min} && $data->{stati}->{$_}->{output} < $data->{stati}->{$_}->{min})
                {
                    $self->errmsg(sprintf(qq|%s minimum threshold exceeded|, $data->{stati}->{$_}->{title}));
                    $self->status(_ST_MINOR);
                }
                elsif (defined $data->{stati}->{$_}->{max} && $data->{stati}->{$_}->{output} > $data->{stati}->{$_}->{max})
                {
                    $self->errmsg(sprintf(qq|%s maximum threshold exceeded|, $data->{stati}->{$_}->{title}));
                    $self->status(_ST_MINOR);
                }
            }
        }
    }
}

sub rrd_config_stat
{   
    return $_[0]->[RRD_CONFIG_STAT];
}

sub rrd_config_raw
{   
    return
    {
        'extOutput' => 'GAUGE',
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

sub discover_data
{
    my $self = shift;
    my $session = $self->session;

    my $data = $session->get_table(-baseoid => "$OID.2" );

    return undef
        if $self->log_snmp_error( $session->error() );

    return undef
        unless keys %$data;

    my $result = {};

    my $blade_fake = blade_fake();
    for (keys %$data)
    {
        next
            unless $data->{$_};
        next
            if $data->{$_} =~ /^$blade_fake/;
        $result->{ $data->{$_} } = $_;
    }
    for (keys %$result)
    {
        $result->{$_} =~ s/^$OID\.2\.//g;
    }

    return scalar keys %$result
        ? $result
        : undef;
}

sub _discover_get_existing_entities
{
    my $self = shift;
    my @list = $self->SUPER::_discover_get_existing_entities(@_);

    my $result;

    for (@list)
    {   

        my $entity = Entity->new($self->dbh, $_);
        if (defined $entity)
        {   

            my $name = $entity->name;

            $result->{ $name }->{entity} = $entity;
        };
    };

    return $result;

}

sub discover_mandatory_parameters
{       
    my $self = shift;
    my $mp = $self->SUPER::discover_mandatory_parameters();
    
    push @$mp, ['snmp_community_ro', 'snmp_user'];
    
    return $mp;
}   

sub discover
{
    my $self = shift;
    $self->SUPER::discover(@_);
    my $entity = shift;    

    my $ip = $entity->params('ip');
    if (! defined $ip)
    {   
        log_debug('ignored; ip address not configured', _LOG_WARNING)
            if $LogEnabled;
        return;
    }

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error)
    {
        $session->max_msg_size(2944);
        $self->session( $session );

        my $new = undef;

        $new = $self->discover_data();

        $session->close
            if $session;

        if (defined $new)
        {
            my $old = $self->_discover_get_existing_entities($entity);
            
            for my $name (keys %$old)
            {
                if (defined $new->{$name})
                {
                    delete $new->{$name};
                }
                else
                {
                    $old->{$name}->{entity}->status(_ST_BAD_CONF);
                    $old->{$name}->{entity}->db_update_entity;
                }
            }
            for my $name (keys %$new)
            {
                $self->_discover_add_new_entity($entity, $name);
            }
        }
    }
    else
    {
        log_debug($error, _LOG_WARNING)
            if $LogEnabled;
    }

}

sub _discover_add_new_entity
{
    my ($self, $parent, $name) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s|, $parent->id_entity, $name), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       };

    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);


    if (ref($entity) eq 'Entity')
    {       
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s|,
            $parent->id_entity, $entity->id_entity, $name), _LOG_INFO)
            if $LogEnabled;
    }                   
}

sub save_data
{       
    my $self = shift;

    my $id_entity = shift;
    
    my $data_dir = $DataDir;

    my $h; 

    open F, ">$data_dir/$id_entity";

    $h = $self->data;

#use Data::Dumper; log_debug(Dumper($h), _LOG_ERROR);

    if ($self->data_type eq _DT_STAT)
    {
        my $ch = $self->cache->{$id_entity};

        for (keys %{ $h->{stati} })
        {
            print F sprintf("%s\|%s\n", 
                $h->{stati}->{$_}->{title}, 
                $h->{stati}->{$_}->{cfs} eq 'COUNTER' 
                    ? $ch->{ $h->{stati}->{$_}->{title} }->[1] 
                    : $h->{stati}->{$_}->{output});
        }

        print F sprintf("title\|%s\n", join("::", map { $h->{stati}->{$_}->{title} } keys %{$h->{stati}}));
    }
    elsif ($self->data_type eq _DT_TEXT)
    {
        print F sprintf(qq|expected\|%s\n|, join(',', @{$h->{text}->{expected}}))
            if defined $h->{text}->{expected} && ref($h->{text}->{expected});
        print F sprintf(qq|bad\|%s\n|, join(',', @{$h->{text}->{bad}}))
            if defined $h->{text}->{bad} && ref($h->{text}->{bad});
        print F sprintf(qq|brief\|%s\n|, $h->{text}->{brief})
            if defined $h->{text}->{brief};
        print F sprintf(qq|output\|%s\n|, $h->{text}->{output})
            if defined $h->{text}->{output};
    }

    for ( map { "$_\|$h->{$_}\n" } keys %$h )
    {       
        print F $_;
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

    my $data_type = $entity->params('ucd_ext_data_type');

    if ($data_type eq _DT_STAT)
    {    
        for ( (split /\:\:/, $data->{title}) )
        {   
            push @$result, sprintf("%s: %s", $_, $data->{$_});
        }
    }
    else
    {
        if (defined $data->{brief})
        {
            push @$result, $data->{brief};
        }  
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

    my $data_type = $entity->params('ucd_ext_data_type');

    if ($data_type eq _DT_TEXT)
    {
        $table->addRow('output:', $data->{output})
            if defined $data->{output};
        $table->addRow('expected:', $data->{expected})
            if defined $data->{expected};
        $table->addRow('bad:', $data->{bad})
            if defined $data->{bad};
    }
    elsif ($data_type eq _DT_STAT)
    {
        my ($r, $e) = format_dispatch( $data->{extOutput} );
        for (sort {$a <=> $b} keys %$r)
        {
            $table->addRow(sprintf("%s:", $r->{$_}->{title}), $data->{ $r->{$_}->{title} } );
        }
    }

    $table->addRow('command:', $data->{extCommand});
    $table->addRow('result code:', $data->{extResult});

    $table->addRow('output:', $data->{extOutput})
        unless $data_type eq _DT_STAT;
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
    my $self = shift;
    return ( $self->data_type eq _DT_RAW ? $self->rrd_config_raw : $self->rrd_config_stat, $self->rrd_data);
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
    my $data_type = $entity->params('ucd_ext_data_type');

    my $cgi = CGI->new();
        
    my $url;
    $url_params->{probe} = 'ucd_ext';
   
    if ($data_type eq _DT_RAW)
    { 
        $url_params->{probe_prepare_ds} = 'prepare_ds';
        $url_params->{probe_specific} = 'extOutput';
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    }
    elsif ($data_type eq _DT_STAT)
    { 
        $url_params->{probe_prepare_ds} = 'prepare_ds_stat';
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    } 
    
}           

sub prepare_ds_stat
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;
    my $title = load_data_file($entity->id_entity);
    $title = [ split(/\:\:/, $title->{title}) ];

    my $rrd_file = sprintf(qq|%s/%s.%s|, CFG->{Probe}->{RRDDir}, $entity->id_entity, $url_params->{probe});

    my $up = 1;
    my $down = 0;

    my $colors = CFG->{Web}->{RRDGraph}->{Colors};

    my $i = 0;
    for (@$title)
    {
        ++$i;
        push @$args, "DEF:ds$i=$rrd_file:$_:$cf";
        push @$args, "LINE1:ds$i#$colors->[$i]:$_";
    }

    return ($up, $down, "ds1");
}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    $rrd_graph->unit('');
    $rrd_graph->title('');
}

sub prepare_ds_stat_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    $rrd_graph->unit('');
    $rrd_graph->title('');
}

sub snmp
{
    return 1;
}

1;
