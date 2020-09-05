package Probe::cisco_css_owner;

use vars qw($VERSION);

$VERSION = 0.13;

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
our $LogEnabled = CFG->{LogEnabled};
our $MaxSNMPSplitRequest = CFG->{MaxSNMPSplitRequest};

sub id_probe_type
{
    return 20;
}

sub name
{
    return 'Cisco CSS owner';
}

use constant
{
    APOWNENTRY => 10,
    RRD_RESULT => 11,
};

my $OID = '1.3.6.1.4.1.2467.1.25.2.1';

my $_apOwnEntry =
{
    1 => '_Name',
    2 => '_Index',
    3 => '_MaxFPBwdth',    
    4 => '_FPBurstTolerance',
    5 => '_MaxPrioritizedFlow',
    6 => '_BillingInfo ',
    7 => '_Address',   
    8 => '_EmailAddress',    
    9 => '_FPBwdthAlloc',
    10 => '_FPActiveFlows',
    11 => '_FPTotalFlows',
    12 => '_FPTotalMisses',
    13 => '_QosBwdthAlloc',
    14 => '_BEBwdthAlloc',
    15 => '_Hits',   
    16 => '_Redirects',
    17 => '_Drops',      
    18 => '_RejNoServices',
    19 => '_RejServOverload',
    20 => '_Spoofs',
    21 => '_Nats',   
    22 => '_ByteCount',
    23 => '_FrameCount',
    24 => '_DNSPolicy',
    25 => '_Status',    
    26 => '_CaseSensitive',
    27 => '_DNSBalance',
};

my $__Status =
{
    1 => 'active',
    2 => 'notInService',
    3 => 'notReady',
    4 => 'createAndGo',
    5 => 'createAndWait',
    6 => 'destroy',
};

my $__DNSPolicy =
{
    0 => 'none',
    1 => 'accept',
    2 => 'push',
    3 => 'both',
};

my $__CaseSensitive =
{
    0 => 'insensitive',
    1 => 'sensitive',
};

my $__DNSBalance =
{
    1 => 'preferlocal',
    2 => 'roundrobin',
    3 => 'leastloaded',
};

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    return $self;
}

sub clear_data
{
    my $self = shift;
    $self->[APOWNENTRY] = {};
};

sub rrd_result
{
    return $_[0]->[RRD_RESULT];
}

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);

    my $entity = shift;

    $self->[RRD_RESULT] = $self->rrd_config;
    my $rru = $self->[RRD_RESULT];
    @$rru{ keys %$rru } = ('U') x scalar keys %$rru;

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

    my $index = $entity->params('index');
    throw EEntityMissingParameter(sprintf( qq|index in entity %s|, $id_entity))
        unless $index;

    my $name = join '.', unpack( 'c*', $entity->name );

    #my $oids_disabled = $entity->params('oids_disabled');
    my $oids_disabled = $entity->params_own->{'oids_disabled'};

    log_debug(sprintf(qq|entity %s oids_disabled: %s|, $id_entity, $oids_disabled), _LOG_DEBUG)
        if $LogEnabled && $oids_disabled;

    my $snmp_split_request = $entity->params_own->{'snmp_split_request'};
    log_debug(sprintf(qq|entity %s snmp_split_request: %s|, $id_entity, $snmp_split_request), _LOG_DEBUG)
        if $LogEnabled && $snmp_split_request;
    $snmp_split_request = 1
        unless $snmp_split_request;

    $self->clear_data;

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error) 
    {
        $session->max_msg_size(2944);

        my $oids = $self->oids_build($oids_disabled, $snmp_split_request, $name, $index);

        my $result;

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

        $error = $session->error_status;

        if ($error == 1)
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
        elsif ($error == 2)
        {
            my $bad_oid = $oids->[0]->[$session->error_index - 1];

        }
#use Data::Dumper; print Dumper $result;
        $self->result_dispatch($result, $name, $index);
#print Dumper $self->apOwnEntry;

        $self->errors_and_utilization_status($entity);
         
        $session->close
            if $session;
    }
    else
    {
        $self->errmsg($error);
        $self->status(_ST_DOWN);
    }

    #zapisanie danych do pliku
    $self->save_data($id_entity);
    $self->rrd_save($id_entity, $self->status)
        if $self->status < _ST_DOWN;
}

sub errors_and_utilization_status
{
    my $self = shift;
    my $entity = shift;
    my $apOwnEntry = $self->apOwnEntry;

    if (! keys %$apOwnEntry)
    {
        $self->errmsg('owner unavailable');
        $self->status(_ST_DOWN);
        return;
    }    
}

sub rrd_config
{
    return
    {
        '_MaxFPBwdth' => 'COUNTER',
        '_FPBurstTolerance' => 'COUNTER',
        '_MaxPrioritizedFlow' => 'COUNTER',
        '_FPBwdthAlloc' => 'COUNTER',
        '_FPActiveFlows' => 'COUNTER',
        '_FPTotalFlows' => 'COUNTER',
        '_FPTotalMisses' => 'COUNTER',
        '_QosBwdthAlloc' => 'COUNTER',
        '_BEBwdthAlloc' => 'COUNTER',
        '_Hits' => 'COUNTER',
        '_Redirects' => 'COUNTER',
        '_Drops' => 'COUNTER',
        '_RejNoServices' => 'COUNTER',
        '_RejServOverload' => 'COUNTER',
        '_Spoofs' => 'COUNTER',
        '_Nats' => 'COUNTER',
        '_ByteCount' => 'COUNTER',
        '_FrameCount' => 'COUNTER',
    };
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;

    my $data_dir = $DataDir;

    my $h;

    open F, ">$data_dir/$id_entity";

    $h = $self->apOwnEntry;

    for ( map { "$_\|$h->{$_}\n" } keys %$h )
    {   
        print F $_;
    }

    close F;
}

sub result_dispatch
{
    my $self = shift;

    my $result = shift;
    my $name = shift;
    my $index = shift;

    return
        unless defined $result;

    my $key;
    my $rru = $self->rrd_result;

    for (keys %$result)
    {
        $key = $_; 
        if (/^$OID\./)
        {
            s/^$OID\.//g;
            s/\.$index.$name$//g;

            if ($_apOwnEntry->{$_} eq '_DNSPolicy')
            {
                $self->[APOWNENTRY]->{ $_apOwnEntry->{$_} } = $__DNSPolicy->{ $result->{$key} };
            }
            elsif ($_apOwnEntry->{$_} eq '_Status')
            {
                $self->[APOWNENTRY]->{ $_apOwnEntry->{$_} } = $__Status->{ $result->{$key} };
            }
            elsif ($_apOwnEntry->{$_} eq '_CaseSensitive')
            {
                $self->[APOWNENTRY]->{ $_apOwnEntry->{$_} } = $__CaseSensitive->{ $result->{$key} };
            }
            elsif ($_apOwnEntry->{$_} eq '_DNSBalance')
            {
                $self->[APOWNENTRY]->{ $_apOwnEntry->{$_} } = $__DNSBalance->{ $result->{$key} };
            }
            elsif (defined $_apOwnEntry->{$_})
            {
                $result->{$key} = 3000000000 + $result->{$key}
                    if $result->{$key} && defined $rru->{ $_apOwnEntry->{$_} } && $result->{$key} < 0; 
                    # liczniki w SNMP typu Integer32 przekrecaja sie i podaja ujemne wartosci!

                $self->[APOWNENTRY]->{ $_apOwnEntry->{$_} } = $result->{$key};

                $rru->{ $_apOwnEntry->{$_} } = $result->{$key}
                    if defined $rru->{ $_apOwnEntry->{$_} };
            }
        }
    }
}

sub apOwnEntry
{
    return $_[0]->[APOWNENTRY];
}

sub oids_build
{
    my $self = shift;

    my $oids_disabled = {};

    defined $_[0]
        ? @$oids_disabled{ (split /:/, shift) } = undef
        : shift;

    my $snmp_split_request = shift;
    my $name = shift;
    my $index = shift;

    my (@oids, $s);

    for $s (sort { $a <=> $b} keys %$_apOwnEntry)
    {
        next
            if $s == 1;
        $s = "$OID.$s";
        next
            if exists $oids_disabled->{$s};
        push @oids, sprintf(qq|%s.%s.%s|, $s, $index, $name);
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

        my $result;
        my $new;

        my $st; #tmp string
        my $oid = $OID . ".1";

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
            $new->{ $st } = (split /\./, $_)[0];
        }  
   
        return
            unless $new; 

        my $old = $self->_discover_get_existing_entities($entity);

        for my $name (keys %$old)
        {
            next
                unless  defined $new->{$name};

            $old->{$name}->{entity}->params('index', $new->{$name})
                if $new->{$name} ne $old->{$name}->{index};

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

sub _discover_add_new_entity
{
    my ($self, $parent, $name, $index) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s index %d|, $parent->id_entity, $name, $index), _LOG_DEBUG)
        if $LogEnabled;

    $name =~ s/\000$//;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {
           index => $index,
       }, 
       };


    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {       
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s|,
            $parent->id_entity, $entity->id_entity, $name,), _LOG_INFO)
            if $LogEnabled;
    }                   
}

sub _discover_get_existing_entities
{

    my $self = shift;

    my @list = $self->SUPER::_discover_get_existing_entities(@_);

    my $result;

    for (@list)
    {

        my $entity = Entity->new($self->dbh, $_);
        my $name = $entity->name;

        $result->{ $name }->{entity} = $entity;
        $result->{ $name }->{index} = $entity->params('index');
    };
    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $s;
    my $t;

    my $rrc = $self->rrd_config;

    my @tracks = 
    (
        '_Status',    
        '_CaseSensitive',
        '_DNSPolicy',
        '_DNSBalance',
        '_BillingInfo ',
        '_Address',   
        '_EmailAddress',

        '_ByteCount',
        '_FrameCount',
        '_Hits',   
        '_Drops',      
        '_RejNoServices',
        '_RejServOverload',
        '_Redirects',
        '_Spoofs',
        '_Nats',   

        '_MaxFPBwdth',
        '_FPBurstTolerance',
        '_MaxPrioritizedFlow',
        '_FPBwdthAlloc',
        '_FPActiveFlows',
        '_FPTotalFlows',
        '_FPTotalMisses',
        '_QosBwdthAlloc',
        '_BEBwdthAlloc',
    );

    for (@tracks)
    {
        $t = $_;
        $t =~ s/^_//g;
        $t =~ s/FP/FlowPipe/g;
        $t =~ s/(\p{upper})/ $1/g;
        $s = $data->{$_}; 

        $s = format_bytes($s)
            if defined $rrc->{$_};

        $table->addRow(lc("$t:"), $s);
    };

    $table->addRow("");
    $table->setCellColSpan($table->getTableRows, 1, 2);
}

sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;
}

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;

    return sprintf(qq|%s%s|,
        $entity->name,
        $entity->status_weight == 0
            ? '*'
            : '');
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
    my $default_only = defined @_ ? shift : 0;
    my $cgi = CGI->new();

    my $url;
    $url_params->{probe} = 'cisco_css_owner';

    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = '_ByteCount';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    return
        if $default_only;

    for (keys %{ $self->rrd_config} )
    {
        next
            if $_ eq '_ByteCount';
        $url_params->{probe_prepare_ds} = 'prepare_ds';
        $url_params->{probe_specific} = $_;
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    }
}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $url_params = $rrd_graph->url_params;
    $rrd_graph->unit('');

    my $title = $url_params->{probe_specific};
    $rrd_graph->title($title);
}

sub snmp
{
    return 1;
}

1;
