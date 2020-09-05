package Probe::cisco_css_content;

use vars qw($VERSION);

$VERSION = 0.21;

use base qw(Probe);
use strict;

use Net::SNMP;

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
    return 12;
}

sub name
{
    return 'Cisco CSS content rule';
}


use constant
{
    APCNTENTRY => 10,
};

my $OID = '1.3.6.1.4.1.2467.1.16.4.1';

my $_apCntEntry =
{
    1 => '_Owner',
    2 => '_Name',
    4 => '_IPAddress',
    5 => '_IPProtocol',
    6 => '_Port',
    7 => '_Url',
    8 => '_Sticky',
    9 => '_Balance',
    11 => '_Enable',
    12 => '_Redirect',
    15 => '_Persistence',
    16 => '_Author',
    18 => '_Hits',
    19 => '_Redirects',
    20 => '_Drops',
    21 => '_RejNoServices',
    22 => '_RejServOverload',
    23 => '_Spoofs',
    24 => '_Nats',
    25 => '_ByteCount',
    26 => '_FrameCount',
    41 => '_Status',
    43 => '_ContentType',
    47 => '_AppTypeBypasses',
    48 => '_NoSvcBypasses',
    49 => '_SvcLoadBypasses',
    50 => '_ConnCtBypasses',
    58 => '_PrimarySorryServer',
    59 => '_SecondSorryServer',
    65 => '_AvgLocalLoad',
    66 => '_AvgRemoteLoad',
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

my $__IPProtocol =
{
    0 => 'any',
    6 => 'tcp',
    17 => 'ucp',
};

my $__Sticky =
{
    1 => 'none',
    2 => 'ssl',
    3 => 'cookieurl',
    4 => 'url',
    5 => 'cookies',
    6 => 'sticky-srcip-dstport',
    7 => 'sticky-srcip',
    8 => 'arrowpoint-cookie',
    9 => 'wap-msisdn',
};

my $__Balance =
{
    1 => 'roundrobin',
    2 => 'aca',
    3 => 'destip',
    4 => 'srcip',
    5 => 'domain',
    6 => 'url',
    7 => 'leastconn',
    8 => 'weightedrr',
    9 => 'domainhash',
    10 => 'urlhash',
};

my $__Enable =
{   
    0 => 'disable',
    1 => 'enable',
};  

my $__Persistence =
{   
    0 => 'disable',
    1 => 'enable',
};  

my $__ContentType =
{
    1 => 'http',
    2 => 'ftp-control',
    3 => 'realaudio-control',
    4 => 'ssl',
    5 => 'bypass',
};

sub clear_data
{
    my $self = shift;
    $self->[APCNTENTRY] = {};
};

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);

    my $entity = shift;

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

    my $cisco_css_content_index_1 = $entity->params('cisco_css_content_index_1');
    throw EEntityMissingParameter(sprintf( qq|cisco_css_content_index_1 in entity %s|, $id_entity))
        unless $cisco_css_content_index_1;

    my $cisco_css_content_index_2 = $entity->params('cisco_css_content_index_2');
    throw EEntityMissingParameter(sprintf( qq|cisco_css_content_index_2 in entity %s|, $id_entity))
        unless $cisco_css_content_index_2;

    my ($owner, $name) = split /:/, $entity->name, 2;
    $name = join '.', unpack( 'c*', $name );
    $owner = join '.', unpack( 'c*', $owner);

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
#print "na: $name\n ow: $owner\n i1:  $cisco_css_content_index_1\n i2: $cisco_css_content_index_2\n";
        my $oids = $self->oids_build($oids_disabled, $snmp_split_request, $name, 
            $owner, $cisco_css_content_index_1, $cisco_css_content_index_2);

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
                #$parent->params('snmp_split_request', $snmp_split_request);
                $entity->params('snmp_split_request', $snmp_split_request);
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
        $self->result_dispatch($result, $name, $owner, $cisco_css_content_index_1, $cisco_css_content_index_2);
#print Dumper $self->apCntEntry;

        $self->errors_and_utilization_status($entity);
         
        $session->close
            if $session;
    }
    else
    {
        $self->errmsg($error);
        $self->status(_ST_DOWN);
    }

    $self->save_data($id_entity);
    $self->rrd_save($id_entity, $self->status)
         if $self->status < _ST_DOWN;
}

sub down_stats
{
    my $self = shift;
    my $apCntEntry = $self->apCntEntry;
    for (keys %{ $self->rrd_config })
    {
        $apCntEntry->{$_} = 'U';
    }
}

sub errors_and_utilization_status
{
    my $self = shift;
    my $entity = shift;
    my $apCntEntry = $self->apCntEntry;

    if (! keys %$apCntEntry)
    {
        $self->errmsg('content unavailable');
        $self->status(_ST_DOWN);
        return;
    }    

    if (defined $apCntEntry->{_Enable} && $apCntEntry->{_Enable} eq 'disable')
    {
        if (! $entity->params('cisco_css_content_stop_warning_suspended_state'))
        {
            $self->status(_ST_WARNING);
        }
        else
        {
            $self->status(_ST_NOSTATUS);
        }
        $self->errmsg(qq|content state: suspended|);
        $self->down_stats;
        return;
    }


    if (defined $apCntEntry->{_Status} && $apCntEntry->{_Status} ne 'createAndGo' && $apCntEntry->{_Status} ne 'active')
    {
        $self->errmsg(sprintf(qq|content row status: %s|, $apCntEntry->{_Status}));
        $self->status(_ST_DOWN);
        $self->down_stats;
        return;
    }

    my $u;

    if (defined $apCntEntry->{_AvgLocalLoad} && $apCntEntry->{_AvgLocalLoad} eq '255' && (! defined $apCntEntry->{_Redirect} || $apCntEntry->{_Redirect} eq '' ))
    {
        $self->errmsg(qq|all services down!|);
        $self->status(_ST_DOWN);
    }
    elsif (! $entity->params('cisco_css_content_stop_warning_high_load'))
    {
    if (defined $apCntEntry->{_AvgLocalLoad} && $apCntEntry->{_AvgLocalLoad} && (! defined $apCntEntry->{_Redirect} || $apCntEntry->{_Redirect} eq '' ))
    {
        $u = ($apCntEntry->{_AvgLocalLoad}*100)/255;
#print "#$u#\n";
#print "#", $self->threshold_high, "#\n";
        if ($u && $u > $self->threshold_high)
        {
            $self->errmsg(qq|high short load|);
            $self->status(_ST_MAJOR);
        }
        elsif ($u && $u > $self->threshold_medium)
        {
            $self->errmsg(qq|medium short load|);
            $self->status(_ST_WARNING);
        }
    }
    }
}

sub rrd_result
{
    my $self = shift;

    my $h = $self->apCntEntry;

    return
    {   
        '_Hits' => defined $h->{_Hits} ? $h->{_Hits} : 'U',
        '_Redirects' => defined $h->{_Redirects} ? $h->{_Redirects} : 'U',
        '_Drops' => defined $h->{_Drops} ? $h->{_Drops} : 'U',
        '_RejNoServices' => defined $h->{_RejNoServices} ? $h->{_RejNoServices} : 'U',
        '_RejServOverload' => defined $h->{_RejServOverload} ? $h->{_RejServOverload} : 'U',
        '_Spoofs' => defined $h->{_Spoofs} ? $h->{_Spoofs} : 'U',
        '_Nats' => defined $h->{_Nats} ? $h->{_Nats} : 'U',
        '_ByteCount' => defined $h->{_ByteCount} ? $h->{_ByteCount} : 'U',
        '_FrameCount' => defined $h->{_FrameCount} ? $h->{_FrameCount} : 'U',
        '_AppTypeBypasses' => defined $h->{_AppTypeBypasses} ? $h->{_AppTypeBypasses} : 'U',
        '_NoSvcBypasses' => defined $h->{_NoSvcBypasses} ? $h->{_NoSvcBypasses} : 'U',
        '_SvcLoadBypasses' => defined $h->{_SvcLoadBypasses} ? $h->{_SvcLoadBypasses} : 'U',
        '_ConnCtBypasses' => defined $h->{_ConnCtBypasses} ? $h->{_ConnCtBypasses} : 'U',
        '_AvgLocalLoad' => defined $h->{_AvgLocalLoad} ? $h->{_AvgLocalLoad} : 'U',
        '_AvgRemoteLoad' => defined $h->{_AvgRemoteLoad} ? $h->{_AvgRemoteLoad} : 'U',
    };
}

sub rrd_config
{
    return
    {
        '_Hits' => 'COUNTER',
        '_Redirects' => 'COUNTER',
        '_Drops' => 'COUNTER',
        '_RejNoServices' => 'COUNTER',
        '_RejServOverload' => 'COUNTER',
        '_Spoofs' => 'COUNTER',
        '_Nats' => 'COUNTER',
        '_ByteCount' => 'COUNTER',
        '_FrameCount' => 'COUNTER',
        '_AppTypeBypasses' => 'COUNTER',
        '_NoSvcBypasses' => 'COUNTER',
        '_SvcLoadBypasses' => 'COUNTER',
        '_ConnCtBypasses' => 'COUNTER',
        '_PrimarySorryHits' => 'COUNTER',
        '_SecondSorryHits' => 'COUNTER',
        '_AvgLocalLoad' => 'GAUGE',
        '_AvgRemoteLoad' => 'GAUGE',
    };
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;


    my $data_dir = $DataDir;

    my $h;

    open F, ">$data_dir/$id_entity";
    $h = $self->apCntEntry;

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
    my $owner = shift;
    my $cisco_css_content_index_1 = shift;
    my $cisco_css_content_index_2 = shift;

    return
        unless defined $result;

    my $key;

    for (keys %$result)
    {
        $key = $_; 
        if (/^$OID\./)
        {
            s/^$OID\.//g;
            s/\.$cisco_css_content_index_1.$owner.$cisco_css_content_index_2.$name$//g;

            if ($_apCntEntry->{$_} eq '_IPProtocol')
            {
                $self->[APCNTENTRY]->{ $_apCntEntry->{$_} } = defined $__IPProtocol->{ $result->{$key} }
                    ? $__IPProtocol->{ $result->{$key} }
                    : $result->{$key};
            }
            elsif ($_apCntEntry->{$_} eq '_Sticky')
            {
                $self->[APCNTENTRY]->{ $_apCntEntry->{$_} } = defined $__Sticky->{ $result->{$key} }
                    ? $__Sticky->{ $result->{$key} }
                    : $result->{$key};
            }
            elsif ($_apCntEntry->{$_} eq '_Balance')
            {
                $self->[APCNTENTRY]->{ $_apCntEntry->{$_} } = defined $__Balance->{ $result->{$key} }
                    ? $__Balance->{ $result->{$key} }
                    : $result->{$key};
            }
            elsif ($_apCntEntry->{$_} eq '_Enable')
            {
                $self->[APCNTENTRY]->{ $_apCntEntry->{$_} } = defined $__Enable->{ $result->{$key} }
                    ? $__Enable->{ $result->{$key} }
                    : $result->{$key};
            }
            elsif ($_apCntEntry->{$_} eq '_Persistence')
            {
                $self->[APCNTENTRY]->{ $_apCntEntry->{$_} } = defined $__Persistence->{ $result->{$key} }
                    ? $__Persistence->{ $result->{$key} }
                    : $result->{$key};
            }
            elsif ($_apCntEntry->{$_} eq '_ContentType')
            {
                $self->[APCNTENTRY]->{ $_apCntEntry->{$_} } = defined $__ContentType->{ $result->{$key} }
                    ? $__ContentType->{ $result->{$key} }
                    : $result->{$key};
            }
            elsif ($_apCntEntry->{$_} eq '_Status')
            {
                $self->[APCNTENTRY]->{ $_apCntEntry->{$_} } = defined $__Status->{ $result->{$key} }
                    ? $__Status->{ $result->{$key} }
                    : $result->{$key};
            }
            elsif (defined $_apCntEntry->{$_})
            {   
                $self->[APCNTENTRY]->{ $_apCntEntry->{$_} } = $result->{$key};
            }
        }
    }
}

sub apCntEntry
{
    return $_[0]->[APCNTENTRY];
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
    my $owner = shift;
    my $cisco_css_content_index_1 = shift;
    my $cisco_css_content_index_2 = shift;

    my (@oids, $s);

#print "na: $name\n ow: $owner\n i1:  $cisco_css_content_index_1\n i2: $cisco_css_content_index_2\n";
#print "\n===\n", sprintf(qq|%s %s %s %s|, $cisco_css_content_index_1, $owner, $cisco_css_content_index_2, $name), "\n";
    for $s (sort { $a <=> $b} keys %$_apCntEntry)
    {
        next
            if $s == 1;
        $s = "$OID.$s";
        next
            if exists $oids_disabled->{$s};
        push @oids, sprintf(qq|%s.%s.%s.%s.%s|, $s, $cisco_css_content_index_1, $owner, $cisco_css_content_index_2, $name);
    }
#use Data::Dumper; print Dumper $oids[0];

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

        my $oid = $OID . ".2";
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
            $new->{ $_ }->{cisco_css_content_index_1} = (split /\./, $_)[0];
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
            $new->{ $_ }->{owner} = $st;
            $st = join '.', unpack( 'c*', $st );
            $st = (split /$st/, $_, 2)[1];
            $new->{ $_ }->{cisco_css_content_index_2} = (split /\./, $st)[1];
        } 

        return
            unless $new; 

        for (keys %$new)
        {
            $st = sprintf(qq|%s:%s|, $new->{$_}->{owner}, $new->{$_}->{name});
            $new->{ $st }  = $new->{ $_ };
            delete $new->{ $_ };
        }

        my $old = $self->_discover_get_existing_entities($entity);

        for my $name (keys %$old)
        {
            next
                unless  defined $new->{$name};

            $old->{$name}->{entity}->params('cisco_css_content_index_1', $new->{$name}->{cisco_css_content_index_1})
                if $new->{$name}->{cisco_css_content_index_1} ne $old->{$name}->{cisco_css_content_index_1};

            $old->{$name}->{entity}->params('cisco_css_content_index_2', $new->{$name}->{cisco_css_content_index_2})
                if $new->{$name}->{cisco_css_content_index_2} ne $old->{$name}->{cisco_css_content_index_2};

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
            $self->_discover_add_new_entity($entity, $_, 
                $new->{$_}->{cisco_css_content_index_1}, $new->{$_}->{cisco_css_content_index_2});
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
    my ($self, $parent, $name, $cisco_css_content_index_1, $cisco_css_content_index_2) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s index_1 %d index_2 %d|, 
        $parent->id_entity, $name, $cisco_css_content_index_1, $cisco_css_content_index_2), _LOG_DEBUG)
        if $LogEnabled;

    $name =~ s/\000$//;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {
           'cisco_css_content_index_1' => $cisco_css_content_index_1,
           'cisco_css_content_index_2' => $cisco_css_content_index_2,
       }};

    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);      

    if (ref($entity) eq 'Entity')
    {       
        #$self->dbh->exec(sprintf(qq|INSERT INTO links VALUES(%s, %s)|, $id_entity, $entity->id_entity));
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
        $result->{ $name }->{cisco_css_content_index_1} = $entity->params('cisco_css_content_index_1');
        $result->{ $name }->{cisco_css_content_index_2} = $entity->params('cisco_css_content_index_2');
    };
    return $result;
}


sub desc_brief
{   
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    push @$result, $data->{_IPAddress}
        if defined $data->{_IPAddress} && $data->{_IPAddress};

    push @$result, sprintf(qq|status: <span class="%s">%s</span>|,
        $data->{_Status} eq 'active' || $data->{_Status} eq 'createAndGo' ? 'g8' : 'g9', $data->{_Status })
        if defined $data->{_Status} && $data->{_Status};
       
    if (defined $data->{_AvgLocalLoad} && $data->{_AvgLocalLoad} ne 'U')
    {
        my $p = ($data->{_AvgLocalLoad}*100)/255;
        push @$result, sprintf(qq|load avg: <font class="%s">%.2f%%</font>|, 
            percent_bar_style_select($p), $p, $data->{_AvgLocalLoad});
    }
    else
    {
        push @$result, qq|load avg: n/a|;
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

    $table->addRow("admin state:", sprintf(qq|<b>%s</b>|,$data->{_Enable}));
    $table->addRow("row status:", 
        sprintf(qq|<span class="%s">%s</span>|,
            $data->{_Status} eq 'active' || $data->{_Status} eq 'createAndGo' ? 'g8' : 'g9', $data->{_Status }));

    my ($s, $t, $p);

    my $tracks = 
    [ 
        '_Owner', '_Name', '_IPAddress', '_IPProtocol', '_Port',
        '_Sticky', '_Url', '_Balance',
    ];

    for (@$tracks)
    {
        $t = $_;
        $t =~ s/_//g;
        $t =~ s/(\p{upper})/ $1/g;
        $t =~ s/I P/IP/g;
        $s = $data->{$_}; 
        $s = 'any'
            if $_ eq '_Port' && ! $s;
        $table->addRow(lc("$t:"), $s);
    };
    $table->addRow("");
    $table->setCellColSpan($table->getTableRows, 1, 2);

    $tracks = [ '_AvgLocalLoad', '_AvgRemoteLoad' ];

    for (@$tracks)
    {
        $t = $_;
        $t =~ s/_//g;
        $t =~ s/(\p{upper})/ $1/g;
        $s = $data->{$_}; 
        if ($s ne 'U')
        {
            $p = ($s*100)/255;
            $p = ($s*100)/255;
            $s = sprintf(qq|<font class="%s">%.2f%% (raw: %s)</font>|, percent_bar_style_select($p), $p, $s);
        }
        $table->addRow(lc("$t:"), $s);
    };
    $table->addRow("");
    $table->setCellColSpan($table->getTableRows, 1, 2);
    
    $tracks = 
    [ 
        '_Redirect', '_Persistence', '_Author', 
        '_ContentType', '_PrimarySorryServer', '_SecondSorryServer', 
    ];

    for (@$tracks)
    {
        $t = $_;
        $t =~ s/_//g;
        $t =~ s/(\p{upper})/ $1/g;
        $s = $data->{$_};
        $table->addRow(lc("$t:"), $s);
    };
}

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;

    return sprintf(qq|%s%s|,
        $entity->name,
        $entity->status_weight == 0
        || $entity->params('cisco_css_content_stop_warning_suspended_state')
        || $entity->params('cisco_css_content_stop_warning_high_load')
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
    $url_params->{probe} = 'cisco_css_content';

    $url_params->{probe_prepare_ds} = 'prepare_ds_load';
    $url_params->{probe_specific} = 'perc';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    return
        if $default_only;

    $url_params->{probe_prepare_ds} = 'prepare_ds_load';
    $url_params->{probe_specific} = 'raw';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds';

     
     my $tracks = [  
        '_Hits',
        '_Redirects',
        '_Drops',
        '_RejNoServices',
        '_RejServOverload',
        '_Spoofs',
        '_Nats',
        '_ByteCount',
        '_FrameCount',
        '_AppTypeBypasses',
        '_NoSvcBypasses',
        '_SvcLoadBypasses',
        '_ConnCtBypasses',
        '_PrimarySorryHits',
        '_SecondSorryHits',
    ];

    for ( @$tracks )
    {
        $url_params->{probe_specific} = $_;
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    }
}

sub prepare_ds_load_pre
{   
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    if ( $url_params->{probe_specific} eq 'raw' )
    {   
        $rrd_graph->title('raw load');
        $rrd_graph->unit('no');
    }
    else
    {   
        $rrd_graph->title('percent load');
        $rrd_graph->unit('%');
    }
}

sub prepare_ds_load
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;

    my $rrd_file = sprintf(qq|%s/%s.%s|, CFG->{Probe}->{RRDDir}, $entity->id_entity, $url_params->{probe});

    my $up = 1;
    my $down = 0;

    if ($url_params->{probe_specific} eq 'raw')
    {
        push @$args, "DEF:ds0a=$rrd_file:_AvgLocalLoad:$cf";
        push @$args, "DEF:ds0s=$rrd_file:_AvgRemoteLoad:$cf";
        #push @$args, "LINE1:ds0s#CC3333:remote";
        push @$args, "LINE1:ds0a#CCCC33:average local";
    }
    elsif ($url_params->{probe_specific} eq 'perc')
    {
        push @$args, "DEF:ds0a=$rrd_file:_AvgLocalLoad:$cf";
        push @$args, "DEF:ds0s=$rrd_file:_AvgRemoteLoad:$cf";
        push @$args, "CDEF:ds0ap=ds0a,100,*,255,/";
        push @$args, "CDEF:ds0sp=ds0s,100,*,255,/";
        #push @$args, "LINE1:ds0sp#CC3333:remote";
        push @$args, "LINE1:ds0ap#CCCC33:average local";
    }

    return ($up, $down, "ds0a");

}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $url_params = $rrd_graph->url_params;
    $rrd_graph->unit('');

    my $title = $url_params->{probe_specific};
    $title =~ s/_//g;
    $rrd_graph->title($title);
}

sub popup_items
{
    my $self = shift;

    $self->SUPER::popup_items(@_);

    my $buttons = $_[0]->{buttons};
    my $class = $_[0]->{class};
    my $section = $_[0]->{section};
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "stop warning suspended state", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=cisco_css_content_stop_warning_suspended_state&add_value=1&id_entity=','current','$class');",}); 
    $buttons->add({ caption => "stop warning high load", url => "javascript:open_location($section,'?form_name=form_options_add&add_name=cisco_css_content_stop_warning_high_load&add_value=1&id_entity=','current','$class');",}); 
}

sub snmp
{
    return 1;
}

1;
