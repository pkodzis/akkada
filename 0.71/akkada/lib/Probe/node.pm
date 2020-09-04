package Probe::node;

use vars qw($VERSION);

$VERSION = 0.4;

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
our $IMG_VENDOR = CFG->{Probes}->{node}->{IMG_VENDOR};
our $IMG_FUNCTION = CFG->{Probes}->{node}->{IMG_FUNCTION};
our $FlagsNoSNMPDir = CFG->{FlagsNoSNMPDir};


sub id_probe_type
{
    return 1;
}

sub name
{
    return 'node';
}


use constant
{
    SYSTEM => 10,
};

my $_System = {
            1 => 'sysDescr',
            2 => 'sysObjectID',
            3 => 'sysUpTime',
            4 => 'sysContact',
            5 => 'sysName',
            6 => 'sysLocation',
};

my $_ipForwarding = {
            0 => 'unknown',
            1 => 'forwarding',
            2 => 'notForwarding', 
};

my $O_SYSTEM = '1.3.6.1.2.1.1';
my $O_IPFORWARDING = '1.3.6.1.2.1.4.1.0';

sub clear_data
{
    my $self = shift;
    $self->[SYSTEM] = {};
};

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);

    my $entity = shift;
    my $id_entity = $entity->id_entity;

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter(sprintf( qq|ip in entity %s|, $id_entity))
        unless $ip;

    my $oids_disabled = $entity->params('oids_disabled');
    log_debug(sprintf(qq|entity %s oids_disabled: %s|, $id_entity, $oids_disabled), _LOG_DEBUG)
        if $LogEnabled && $oids_disabled;

    $self->clear_data;

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error) 
    {
        $session->max_msg_size(2944);

        my $oids = $self->oids_build($oids_disabled, 1);

        my $result = $session->get_request( -varbindlist => $oids->[0] );

        $error = $session->error_status;

        if ($error == 2)
        {
            my $bad_oid = $oids->[0]->[$session->error_index - 1];

            $oids_disabled = defined $oids_disabled
                ? join(":", $oids_disabled, $bad_oid)
                : $bad_oid;

            $entity->params('oids_disabled', $oids_disabled);

        }

        $result->{$O_IPFORWARDING} = '0'
            unless $result->{$O_IPFORWARDING};
            
        $self->result_dispatch($result);

        my $s = $self->System;
        $entity->name($s->{sysName})
            if $s && defined $s->{sysName} && $s->{sysName};

        my $flag;
        my $tmp = $s->{sysDescr};
        my $oid  = $s->{sysObjectID};

        my $vendor = $entity->params('vendor');

#use Data::Dumper; log_debug("1 $vendor :::: $oid", _LOG_ERROR);

        if (! $vendor && defined $oid)
        {
            $oid =~ s/^1\.3\.6\.1\.4\.1\.//g;
            $oid = (split /\./, $oid)[0];
            foreach my $i (@$IMG_VENDOR)
            {
                $flag = 0;

                next
                    unless defined $i->{oids};

                foreach (@{$i->{oids}})
                {
                    if ($oid == $_)
                    {
                        foreach (@{$i->{keys}})
                        {
                            $flag = 1
                                if $tmp =~ /$_/i;
                        }
                    }
                }
                if ($flag)
                {
                   $vendor = $i->{img};
                   last;
                }
            }
        }
        if (! $vendor && $flag != 1 && defined $oid)
        {   
#use Data::Dumper; log_debug("2 $vendor :::: $oid", _LOG_ERROR);
            foreach my $i (@$IMG_VENDOR)
            {   
                $flag = 0;

                next
                    unless defined $i->{oids};

                foreach (@{$i->{oids}})
                {
                    $flag = 1
                        if $oid == $_;
                }
                if ($flag)
                {
                    $vendor = $i->{img};
                    last;
                }
            }
        }
#use Data::Dumper; log_debug("3 $vendor :::: $oid", _LOG_ERROR);
        if (! $vendor && defined $tmp && $flag != 1)
        {
            foreach my $i (@$IMG_VENDOR) 
            {
                $flag = 0;

                next
                    unless defined $i->{keys};

                foreach (@{$i->{keys}})
                {
                    $flag = 1
                        if $tmp =~ /$_/i;
                }
                if ($flag) 
                {
                    $vendor = $i->{img};
                    last;
                }
            }
        }
#use Data::Dumper; log_debug("4 $vendor :::: $oid", _LOG_ERROR);
        $entity->params('vendor', $vendor);

        if (defined $tmp)
        {
            my $ipF = $s->{ipForwarding};
#use Data::Dumper; print Dumper $s;
            foreach my $i (@$IMG_FUNCTION) 
            {
                if ($i->{fwd} eq $ipF)
                {
                    $flag = 0;
                    foreach (@{$i->{keys}})
                    {
                        $flag = 1
                            if $tmp =~ /$_/i;
                    }
                    if ($flag) 
                    {
                        $entity->params('function', $i->{img});
                        last;
                    }
                }
#print Dumper $flag, $i->{img};
            }
            $entity->params('function', $ipF eq 'forwarding' ? 'router' : 'host' )
                unless $flag;
            $self->errmsg('');
            $self->status(_ST_OK);
            $self->nosnmp_clear( $id_entity );
        }
        else
        {
            $self->errmsg('check hosts snmp configuration');
            $self->status(_ST_NOSNMP);
            $self->nosnmp_set( $id_entity );
        }

        $session->close
            if $session;
    }
    elsif ($error ne "missing community_ro")
    {
        $self->errmsg($error);
        $self->status(_ST_NOSNMP);
        $self->nosnmp_set( $id_entity );
    }

    #zapisanie danych do pliku
    if ($self->status eq _ST_OK)
    {
        $self->save_data($id_entity);
        $self->rrd_save($id_entity, $self->status);
    }
    elsif ($self->status eq _ST_NOSNMP)
    {
        $entity->update_data_file_timestamp;
    }
}

sub nosnmp_clear
{
    flag_file_check($FlagsNoSNMPDir, $_[1], 1); 
}

sub nosnmp_set
{
    flag_files_create($FlagsNoSNMPDir, $_[1]); 
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;

    my $data_dir = $DataDir;

    my $h;

    open F, ">$data_dir/$id_entity";

    $h = $self->System;
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

    return
        unless defined $result;

    my $key;

    for (keys %$result)
    {
        $key = $_;
        next
            unless defined $result->{$key};
        if (/^$O_SYSTEM\./)
        {
            s/^$O_SYSTEM\.//g;
            s/\.0$//g;

            $result->{$key} =~ s/\n//g;
            $self->[SYSTEM]->{ $_System->{$_} } = $result->{$key};
        }
        elsif (/^$O_IPFORWARDING$/)
        {
            $self->[SYSTEM]->{ipForwarding} = $_ipForwarding->{ $result->{$key} };
        }
    }
}

sub System
{
    return $_[0]->[SYSTEM];
}

sub rrd_result
{
    my $data = $_[0]->System;

    return
    {
        'sysUpTime' => defined $data->{sysUpTime} ? $data->{sysUpTime} : 'U',
    };
}

sub rrd_config
{
    return
    {
        'sysUpTime' => 'GAUGE',
    };
}

sub oids_build
{
    my $self = shift;
        
    my $oids_disabled = {};
    
    my $oid_src = shift || '';
    
    @$oids_disabled{ (split /:/, $oid_src) } = undef;

    my $snmp_split_request = shift;

    my (@oids, $s);
    
    for $s (sort { $a <=> $b} keys %$_System)
    {       
        $s = "$O_SYSTEM.$s.0";
        push @oids, $s
            unless exists $oids_disabled->{$s};
    }
    push @oids, $O_IPFORWARDING
        unless exists $oids_disabled->{$O_IPFORWARDING};

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

sub discover_mode
{
    return _DM_NODISCOVER;
}

sub discover
{
# ta sonda nie ma procedury discover
}

sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    push @$result, sprintf(qq|uptime: %s|, (split /\) /, timeticks_2_duration($data->{sysUpTime}))[1])
        if defined $data->{sysUpTime} && $data->{sysUpTime};

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity, $url_params) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $tracks = [ 'sysName', 'sysDescr', 'sysUpTime', 'sysContact', 'sysLocation', 'ipForwarding' ];
    my $t;

    for (@$tracks)
    {
        $t = $_;
        $t =~ s/^sys//g;
        $t =~ s/(\p{upper})/ $1/g;
        $table->addRow(lc("$t:"), $_ eq 'sysUpTime' ? timeticks_2_duration($data->{$_}) : $data->{$_})
            if $data->{$_};
    }
}

sub popup_items
{
    my $self = shift;

    $self->SUPER::popup_items(@_);

    my $buttons = $_[0]->{buttons};
    my $class = $_[0]->{class};
    my $section = $_[0]->{section};
    my $view_mode = $_[0]->{view_mode};

    $buttons->add({ caption => "utilities", url => "javascript:open_location('7','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class');",});
    $buttons->add({ caption => "discover node", 
        url => "javascript:open_location('1,1','?form_name=form_entity_discover&id_probe_type=0&id_entity=','','$class');",});
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "set calculated status weight = 0", 
        url => "javascript:open_location($section,'?form_name=form_options_mandatory&calculated_status_weight=0&id_entity=','current','$class');",});
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "add service", url => "javascript:open_location('0','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class','3');",});
}

sub menu_stat
{
    return 2;
}

sub stat
{       
    my $self = shift; 
    my $table = shift;
    my $entity = shift;
    my $url_params = shift;

    my $cgi = CGI->new();
        
    my $url;
    $url_params->{probe} = 'node';

    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'sysUpTime';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    $rrd_graph->unit('ticks');
    $rrd_graph->title('system up time');
}

sub snmp
{
    return 1;
}

1;
