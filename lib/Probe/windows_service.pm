package Probe::windows_service;

use vars qw($VERSION);

$VERSION = 1.1;

use base qw(Probe);
use strict;

use Net::SNMP qw(snmp_dispatcher oid_lex_sort ticks_to_time);
use Time::HiRes qw( gettimeofday tv_interval );

use Constants;
use Configuration;
use Log;
use Entity;
use Common;

our $DataDir = CFG->{Probe}->{DataDir};
our $LogEnabled = CFG->{LogEnabled};
our $MaxSNMPSplitRequest = CFG->{MaxSNMPSplitRequest};

sub id_probe_type
{
    return 4;
}

use constant
{
    SVSVCENTRY => 10,
};

sub name
{
    return 'Windows service';
}


my $O_SVSVCENTRY = '1.3.6.1.4.1.77.1.2.3.1';

my $_svSvcEntry = 
{
    1 => 'svSvcName',
    2 => 'svSvcInstalledState',
    3 => 'svSvcOperatingState',
    4 => 'svSvcCanBeUninstalled',
    5 => 'svSvcCanBePaused',
};

my $_svSvcInstalledState = 
{
    1 => 'uninstalled',
    2 => 'install-pending',
    3 => 'uninstall-pending',
    4 => 'installed',
};

my $_svSvcOperatingState =
{
    1 => 'active',
    2 => 'continue-pending',
    3 => 'pause-pending',
    4 => 'paused',
};

my $_svSvcCanBeUninstalled =
{
    1 => 'cannot-be-uninstalled',
    2 => 'can-be-uninstalled',
};

my $_svSvcCanBePaused =
{
    1 => 'cannot-be-paused',
    2 => 'can-be-paused',
};

sub clear_data
{
    my $self = shift;
    $self->[SVSVCENTRY] = {};
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

    my ($t0, $t1);

    $t0 = [gettimeofday];

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter(sprintf( qq|ip in entity %s|, $id_entity))
        unless $ip;

    my $windows_service_oid_name = $entity->params('windows_service_oid_name');
    my $windows_service_hex = $entity->params('windows_service_hex');

    my $name;

    if ($windows_service_hex)
    {
        my @tmp = unpack( 'C*', pack("H*", $windows_service_hex) );
        shift @tmp;
        $name = join '.', @tmp;
    }
    elsif ($windows_service_oid_name)
    {
        $name = $windows_service_oid_name;
    }
    else
    {
        $name = $entity->name;
        $name = length($name) . "." . join('.', unpack( 'c*', $name ));
    }

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
        $session->max_msg_size(8128);

        my $oids = $self->oids_build($oids_disabled, $snmp_split_request, $name);

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
               # my $parent = Entity->new($self->dbh, $entity->id_parent);
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

        $self->result_dispatch($result, $name);

        my $windows_service_invert = $entity->params('windows_service_invert');

        if (! keys %{ $self->svSvcEntry})
        {
             if (! $windows_service_invert)
             {
                 $self->errmsg('service unavailable (stopped or not exists)');
                 $self->status(_ST_DOWN);
             }
             else
             {
                 $self->errmsg('service unavailable (stopped or not exists); alarm inverted');
             }
        }
        elsif (! $windows_service_invert)
        {
             
             my $svSvcOperatingState = $self->svSvcEntry->{svSvcOperatingState};
             if ($svSvcOperatingState ne 'active')
             {
                 $self->errmsg(sprintf(qq|service operating state: %s|, $svSvcOperatingState));
                 $self->status( $svSvcOperatingState eq 'paused'
                     ? _ST_WARNING
                     : _ST_MINOR);
             }
        }
        else
        {
             my $windows_service_invert_msg = $entity->params('windows_service_invert_msg');
             $self->errmsg(sprintf(qq|service works fine; %s|, 
                 $windows_service_invert_msg ? $windows_service_invert_msg : 'alarm inverted'));
             $self->status(_ST_DOWN);
        }

        $session->close
            if $session;
    }
    else
    {
        $self->errmsg($error);
        $self->status(_ST_DOWN);
    }

    $t1 = [gettimeofday];
    $t0 = tv_interval($t0, $t1);

    #zapisanie danych do pliku
    $self->save_data($id_entity);
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;


    my $data_dir = $DataDir;

    my $h;

    open F, ">$data_dir/$id_entity";

    $h = $self->svSvcEntry;
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

    return
        unless defined $result;

    my $key;

    for (keys %$result)
    {
        $key = $_; 
        if (/^$O_SVSVCENTRY\./)
        {
            s/^$O_SVSVCENTRY\.//g;
            s/\.$name$//g;

            if ($_svSvcEntry->{$_} eq 'svSvcInstalledState')
            {
                $self->[SVSVCENTRY]->{ $_svSvcEntry->{$_} } = $_svSvcInstalledState->{ $result->{$key} };
            }
            elsif ($_svSvcEntry->{$_} eq 'svSvcOperatingState')
            {
                $self->[SVSVCENTRY]->{ $_svSvcEntry->{$_} } = $_svSvcOperatingState->{ $result->{$key} };
            }
            elsif ($_svSvcEntry->{$_} eq 'svSvcCanBeUninstalled')
            {
                $self->[SVSVCENTRY]->{ $_svSvcEntry->{$_} } = $_svSvcCanBeUninstalled->{ $result->{$key} };
            }
            elsif ($_svSvcEntry->{$_} eq 'svSvcCanBePaused')
            {
                $self->[SVSVCENTRY]->{ $_svSvcEntry->{$_} } = $_svSvcCanBePaused->{ $result->{$key} };
            }
        }
    }
}

sub svSvcEntry
{
    return $_[0]->[SVSVCENTRY];
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

    my (@oids, $s);

    for $s (sort { $a <=> $b} keys %$_svSvcEntry)
    {
        next
            if $s == 1;
        $s = "$O_SVSVCENTRY.$s";
        next
            if exists $oids_disabled->{$s};
        push @oids, sprintf(qq|%s.%s|, $s, $name);
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

    my $discovery_exclude = CFG->{Probes}->{windows_service}->{DiscoveryExclude};

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error)
    {
        $session->max_msg_size(8128);
        $session->translate(['-null']);

        my $result;
        my $new;

        my $st; #tmp string
        my $oid_name; #tmp string
        my $tmp;
        my $oid = $O_SVSVCENTRY . ".1";

        $result = $session->get_table(-baseoid => $oid);
        $error = $session->error();

#use Data::Dumper; print Dumper $error;
        if ($error)
        {
            log_debug($error, _LOG_WARNING)
                if $LogEnabled;
            return;
        }
#use Data::Dumper; print Dumper $result;
        for (keys %$result)
        {
            $st = $result->{$_};
            $oid_name = $_;
            $oid_name =~ s/^$oid\.//;

            next
                unless $st;

            if ($st =~ /^0x/)
            {
                $tmp = $st;
                $st = pack "H*", $st;
                $new->{ $oid_name }->{name} = $st;
                $new->{ $oid_name }->{windows_service_hex} = $tmp;
            }
            else
            {
#my @w = split //, $st;
#log_debug($st . ": " . join(".", map { ord($_); } @w), _LOG_ERROR);

                $new->{ $oid_name }->{name} = $st;
                $new->{ $oid_name }->{windows_service_oid_name} = $oid_name;
            }

        }  
   
        return
            unless $new; 

        my $old = $self->_discover_get_existing_entities($entity);

        for my $name (keys %$old)
        {
            next
                unless  defined $new->{$name};

            $old->{$name}->{entity}->params('windows_service_hex', $new->{$name}->{windows_service_hex})
                if defined $new->{$name}->{windows_service_hex} 
                && $new->{$name}->{windows_service_hex} ne $old->{$name}->{windows_service_hex};
            $old->{$name}->{entity}->params('windows_service_oid_name', $new->{$name}->{windows_service_oid_name})
                if defined $new->{$name}->{windows_service_oid_name} 
                && $new->{$name}->{windows_service_oid_name} ne $old->{$name}->{windows_service_oid_name};

            if ($old->{$name}->{entity}->status eq _ST_BAD_CONF)
            {
                $old->{$name}->{entity}->errmsg('');
                $old->{$name}->{entity}->status(_ST_UNKNOWN);
            }

            delete $new->{$name};
            delete $old->{$name};
        }

#use Data::Dumper; log_debug(Dumper($new), _LOG_ERROR);
        for (keys %$new)
        {
            defined $discovery_exclude->{ $new->{$_}->{name} } && $discovery_exclude->{ $new->{$_}->{name} }
                ? log_debug(sprintf("service %s in excludes table. service ignored", $_), _LOG_INFO)
                : $self->_discover_add_new_entity($entity, $new->{$_});
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
    my ($self, $parent, $new) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s index %s|, $parent->id_entity, $new->{name}, $new->{windows_service_oid_name}), _LOG_DEBUG)
        if $LogEnabled;

    $new->{name} =~ s/\000$//;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $new->{name},
       params => {}};      
    $entity->{params}->{windows_service_hex} = $new->{windows_service_hex}
        if defined $new->{windows_service_hex}
        && $new->{windows_service_hex};
    $entity->{params}->{windows_service_oid_name} = $new->{windows_service_oid_name}
        if defined $new->{windows_service_oid_name}
        && $new->{windows_service_oid_name};

    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {       
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s|,
            $parent->id_entity, $entity->id_entity, $new->{name},), _LOG_INFO)
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
#to ladowanie entitow mogloby sie robic masowowo
        my $entity = Entity->new($self->dbh, $_);
        my $windows_service_oid_name = $entity->params('windows_service_oid_name');
        my $windows_service_hex = $entity->params('windows_service_hex');

        my $name;

        if ($windows_service_hex)
        {
            my @tmp = unpack( 'C*', pack("H*", $windows_service_hex) );
            shift @tmp;
            $name = join '.', @tmp;
        }
        elsif ($windows_service_oid_name)
        {
            $name = $windows_service_oid_name;
        }
        else
        {
            $name = $entity->name;
            $name = length($name) . "." . join('.', unpack( 'c*', $name ));
        }

        $result->{ $name }->{entity} = $entity;
        $result->{ $name }->{windows_service_hex} = $windows_service_hex
            if defined $windows_service_hex;
        $result->{ $name }->{windows_service_oid_name} = $windows_service_oid_name
            if defined $windows_service_oid_name;
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

    $table->addRow("svSvcOperatingState:", sprintf(qq|<b>%s</b>|,$data->{svSvcOperatingState}))
        if $data->{svSvcOperatingState};
    $table->addRow("svSvcInstalledState:", $data->{svSvcInstalledState})
        if $data->{svSvcInstalledState};
    $table->addRow("svSvcCanBeUninstalled:", $data->{svSvcCanBeUninstalled})
        if $data->{svSvcCanBeUninstalled};
    $table->addRow("svSvcCanBePaused:", $data->{svSvcCanBePaused})
        if $data->{svSvcCanBePaused};

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

sub snmp
{
    return 1;
}

1;
