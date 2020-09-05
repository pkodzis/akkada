package Probe::cisco_pix_ipsec_traffic;

use vars qw($VERSION);

$VERSION = 0.4;

use base qw(Probe);
use strict;

use Time::HiRes qw(gettimeofday tv_interval);

use Constants;
use Configuration;
use Log;
use Entity;
use URLRewriter;
use Common;
use Number::Format qw(:subs);
use Net::SSH::Perl;
use Data::Dumper;

our $DataDir = CFG->{Probe}->{DataDir};
our $LogEnabled = CFG->{LogEnabled};

$|=1;


use constant
{
    DATA => 10,
    ENTITY_NAME => 11,
};

sub entity_name
{
    return $_[0]->[ENTITY_NAME];
}

sub entity_name_set
{
    return $_[0]->[ENTITY_NAME] = $_[1];
}

sub name
{
    return 'PIX interface traffic';
}

sub id_probe_type
{
    return 28;
}

sub snmp
{
    return 0;
}

sub clear_data
{
    my $self = shift;
    $self->[DATA] = {timestamp => '', data => {} };
};

sub data
{
    return $_[0]->[DATA]->{data};
}

sub data_timestamp
{
    return $_[0]->[DATA]->{timestamp};
}

sub set_data
{
    my $self = shift;
    my $data_new = shift;
    my $data_old = $self->data;
    my $time_new = time;
    my $time_old = $self->data_timestamp;

    my $delta = defined $time_old && $time_old 
        ? $time_new - $time_old 
        : 0;

    my $traffic_delta;
    my $ps;

    for my $interface (keys %$data_new)
    {
        for my $type (keys %{$data_new->{$interface}})
        {
            $traffic_delta = defined $data_old->{$interface}->{$type} 
                #&& $data_old->{$interface}->{$type}
                && defined $data_old->{$interface}->{$type}->{counter}
                #&& $data_old->{$interface}->{$type}->{counter}
                ? $data_new->{$interface}->{$type} - $data_old->{$interface}->{$type}->{counter}
                : 'n/a';
                if ($traffic_delta ne 'n/a' && $traffic_delta < 0)
                {
                    $traffic_delta = $data_old->{$interface}->{$type}->{delta};
                    $ps = $data_old->{$interface}->{$type}->{ps};
                }
                elsif ($delta && $traffic_delta ne 'n/a')
                {
                    $ps = $traffic_delta/$delta;
                }
                elsif ($delta && $traffic_delta == 0)
                {
                    $ps = 0;
                }
                else
                {
                    $ps = 'n/a';
                }
                $data_new->{$interface}->{$type} = 
                {
                    counter => $data_new->{$interface}->{$type},
                    delta => $traffic_delta,
                    ps => $ps,
                }
            }
    }
    
    $self->[DATA] = {timestamp => $time_new, data => $data_new};

}

sub manual
{
    return 0;
}
   
sub mandatory_fields
{
    return
    [
        'cisco_pix_ipsec_username',
        'cisco_pix_ipsec_password',
        'cisco_pix_ipsec_enable',
    ]
}


sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);

    my $entity = shift;

    my $result;

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter('ip')
        unless $ip;

    my $username = $entity->params('cisco_pix_ipsec_username');
    throw EEntityMissingParameter('cisco_pix_ipsec_username')
        unless $username;

    my $password = $entity->params('cisco_pix_ipsec_password');
    throw EEntityMissingParameter('cisco_pix_ipsec_password')
        unless $password;

    my $enable = $entity->params('cisco_pix_ipsec_enable');
    throw EEntityMissingParameter('cisco_pix_ipsec_enable')
        unless $enable;

    $result = $self->get_data($ip, $username, $password, $enable);

    if (! defined $result || ! $result)
    {
        $self->errmsg("service missconfigured. cannot get data from device.");
        $self->status(_ST_BAD_CONF);
    }

    $self->entity_name_set( $entity->name );
    $self->utilization_status( $entity );
    $self->rrd_save($entity->id_entity, $self->status);
    $self->save_data($entity->id_entity);
}

sub utilization_status
{
    my $self = shift;
    my $entity = shift;
    my $data = $self->data;

    if (defined $data->{ $entity->name })
    {
        $data = $data->{ $entity->name };
    } 
    else
    {
        $self->errmsg(qq|tunnel not found|);
        $self->status(_ST_UNKNOWN);
    }

    if (defined $data->{send_errors}->{ps} && $data->{send_errors}->{ps} ne 'n/a' && $data->{send_errors}->{ps} > 0)
    {
        $self->errmsg(qq|send error pkts|);
        $self->status(_ST_MINOR);
    }
    if (defined $data->{recv_errors}->{ps} && $data->{recv_errors}->{ps} ne 'n/a' && $data->{recv_errors}->{ps} > 0)
    {
        $self->errmsg(qq|send error pkts|);
        $self->status(_ST_MINOR);
    }
}


sub rrd_result
{
    my $self = shift;
    my $data = $self->data;

    my $entity_name = $self->entity_name;

    my @list = (
        'compr_failed',
        'compressed',
        'decaps',
        'decompress_failed',
        'decompressed',
        'decrypt',
        'digest',
        'encaps',
        'encrypt',
        'not_compressed',
        'recv_errors',
        'send_errors',
        'verify',
    );

    my $res = {};
    my $n;
    for (@list)
    {
        $res->{$_} = defined $data->{$entity_name} && defined $data->{$entity_name}->{$_} && defined $data->{$entity_name}->{$_}->{counter} ? $data->{$entity_name}->{$_}->{counter} : 'U';
    }

    return $res;
}

sub rrd_config
{
    return
    {
        'compr_failed' => 'COUNTER',
        'compressed' => 'COUNTER',
        'decaps' => 'COUNTER',
        'decompress_failed' => 'COUNTER',
        'decompressed' => 'COUNTER',
        'decrypt' => 'COUNTER',
        'digest' => 'COUNTER',
        'encaps' => 'COUNTER',
        'encrypt' => 'COUNTER',
        'not_compressed' => 'COUNTER',
        'recv_errors' => 'COUNTER',
        'send_errors' => 'COUNTER',
        'verify' => 'COUNTER',
    };
}

sub get_data
{
    my $self = shift;
    my $ip = shift;
    my $username = shift;
    my $password = shift;
    my $enable = shift;

    my ($stdout, $stderr, $exit, $session);

    my $time = time;
    my $data_time = $self->data_timestamp;

    if ($time - $data_time < 300)
    {
        log_debug("data is taken from the cache", _LOG_DEBUG)
            if $LogEnabled;
        return $self->data;
    }

    #$self->clear_data;

    log_debug("data is taken from the firewall", _LOG_DEBUG)
        if $LogEnabled;

    eval
    {
        my $session = Net::SSH::Perl->new
        (
            $ip, 
            cipher => 'DES',
            protocol => 1,
            debug => 0, 
            interactive => 0, 
            options => ["BatchMode yes"]
        );

        $session->login($username, $password);

        my $cmd = "enable";
        ($stdout, $stderr, $exit) = $session->cmd($cmd, sprintf(qq|\n%s\npager lines 0\nshow crypto ipsec sa\npager lines 24\nq\n|, $enable));
    };

    return $@
        if $@;
    return $stderr
        if $stderr;

    my $res={};
    my $peer = '';
    my @s;
    my @t;

    for (split(/\n/, $stdout)) 
    {
        if (/current_peer: (.*):/)
        {
            $peer = $1;
        }
        elsif (/local crypto endpt/)
        {
            $peer = '';
        }
        elsif ($peer && /#/)
        {
            chomp;
            @t = split /#/, $_;
            shift @t;
            for (@t)
            {
                s/,|://g;
                s/      / /g;
                @s = split / /, $_;
                if ($s[2] =~ /\d/)
                {
                    $s[0] = "$s[0] $s[1]";
                    $s[0] =~ s/pkts |\.//g;
                    $s[0] =~ s/ |	/_/g;
                    $res->{$peer}->{$s[0]} += $s[2];
                }
                else
                {
                    $s[0] = "$s[0] $s[1] $s[2]";
                    $s[0] =~ s/pkts |\.//g;
                    $s[0] =~ s/ |	/_/g;
                    $res->{$peer}->{$s[0]} += $s[3];
                }
            }
        }
    }

    $self->set_data($res);

    return $self->data;
}

sub discover_mode
{
    return _DM_MIXED;
}

sub discover_mandatory_parameters
{
    my $self = shift;
    my $mp = $self->SUPER::discover_mandatory_parameters();

    push @$mp, 'cisco_pix_ipsec_username';
    push @$mp, 'cisco_pix_ipsec_password';
    push @$mp, 'cisco_pix_ipsec_enable';

    return $mp;
}

sub discover
{
    my $self = shift;
    $self->SUPER::discover(@_);
    my $entity = shift;

    my $cisco_pix_ipsec_username = $entity->params('cisco_pix_ipsec_username');
    throw EEntityMissingParameter('cisco_pix_ipsec_username')
        unless $cisco_pix_ipsec_username;

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter('ip')
        unless $ip;

    my $cisco_pix_ipsec_password = $entity->params('cisco_pix_ipsec_password');
    throw EEntityMissingParameter('cisco_pix_ipsec_password')
        unless $cisco_pix_ipsec_password;

    my $cisco_pix_ipsec_enable = $entity->params('cisco_pix_ipsec_enable');
    throw EEntityMissingParameter('cisco_pix_ipsec_enable')
        unless $cisco_pix_ipsec_enable;

    my $result = $self->get_data($ip, $cisco_pix_ipsec_username, $cisco_pix_ipsec_password, $cisco_pix_ipsec_enable);

    if (ref($result) ne 'HASH')
    {
        log_debug("bad discover result $ip" . Dumper($result), _LOG_WARNING)
            if $LogEnabled;
    }

    my $new;
    my $old;

    for (keys %$result)
    {
         $new->{ $_ }->{name} = $_;
    }

    $old = $self->_discover_get_existing_entities($entity);

    for (keys %$new)
    {
        $self->_discover_add_new_entity($entity, $_)
            if ! defined $old->{$_};
    }

}

sub _discover_add_new_entity
{
    my ($self, $parent, $name) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s|, $parent->id_entity, $name), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = $self->_entity_add({
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {
       },
       }, $self->dbh);

    if (ref($entity) eq 'Entity')
    {
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s|,
            $parent->id_entity, $entity->id_entity, $name), _LOG_INFO)
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
            $result->{$name}->{entity} = $entity;
        };
    };
    return $result;
}


sub save_data
{
    my $self = shift;

    my $id_entity = shift;

    my $entity_name = $self->entity_name;
    
    my $data_dir = $DataDir;
    my $data = $self->data;
    
    return 
        unless defined $data->{$entity_name};

    $data = $data->{$entity_name};

    open F, ">$data_dir/$id_entity";
 
    for my $key (sort keys %$data)
    { 
        print F "${key}_counter\|$data->{$key}->{counter}\n";
        print F "${key}_delta\|$data->{$key}->{delta}\n";
        print F "${key}_ps\|$data->{$key}->{ps}\n";
    }
 
    close F;
}

sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    push @$result, sprintf(qq|traffic %s/%s pps (tx/rx), errors %s/%s pps (tx/rx), total: %s/%s pkts (tx/rx)|, 
        defined $data->{decrypt_ps} && $data->{decrypt_ps} =~ /^[0-9\.]*$/ ? format_bytes($data->{decrypt_ps},2) : 'n/a', 
        defined $data->{encrypt_ps} && $data->{encrypt_ps} =~ /^[0-9\.]*$/ ? format_bytes($data->{encrypt_ps},2) : 'n/a', 
        defined $data->{send_errors_ps} && $data->{send_errors_ps} =~ /^[0-9\.]*$/ ? format_bytes($data->{send_errors_ps},2) : 'n/a', 
        defined $data->{recv_errors_ps} && $data->{recv_errors_ps} =~ /^[0-9\.]*$/ ? format_bytes($data->{recv_errors_ps},2) : 'n/a',
        defined $data->{decrypt_counter} && $data->{decrypt_counter} =~ /^[0-9\.]*$/ ? format_bytes($data->{decrypt_counter},2) : 'n/a', 
        defined $data->{encrypt_counter} && $data->{encrypt_counter} =~ /^[0-9\.]*$/ ? format_bytes($data->{encrypt_counter},2) : 'n/a');

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity, $url_params) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    my $key;
    my $keyc;

    for (keys %$data)
    {
        next
            unless /_ps$/;
        $key = $_;
        s/_ps$//;
        $keyc = $_ . "_counter";
        s/_/ /g;

        $table->addRow($_, sprintf(qq|%s pps (total: %s pkts)|,  
            defined $data->{$key} && $data->{$key} =~ /^[0-9\.]*$/ ? format_bytes($data->{$key},2) : 'n/a',
            defined $data->{$keyc} && $data->{$keyc} =~ /^[0-9\.]*$/ ? format_bytes($data->{$keyc},2) : 'n/a'));
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
    $url_params->{probe} = 'cisco_pix_ipsec_traffic';

    $url_params->{probe_prepare_ds} = 'prepare_ds_crypt';
    $url_params->{probe_specific} = 'decrypt';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds_errors';
    $url_params->{probe_specific} = 'send_errors';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    return
        if $default_only;

    $url_params->{probe_prepare_ds} = 'prepare_ds_caps';
    $url_params->{probe_specific} = 'decaps';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds_compress';
    $url_params->{probe_specific} = 'compressed';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_prepare_ds} = 'prepare_ds';

    $url_params->{probe_specific} = 'compr_failed';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'decompress_failed';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'digest';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'not_compressed';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    $url_params->{probe_specific} = 'verify';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $url_params = $rrd_graph->url_params;

    if ($url_params->{probe_specific} eq 'compr_failed')
    {
        $rrd_graph->unit('pps');
        $rrd_graph->title('compression failed pkts');
    }
    elsif ($url_params->{probe_specific} eq 'decompress_failed')
    {
        $rrd_graph->unit('pps');
        $rrd_graph->title('decompression failed pkts');
    }
    elsif ($url_params->{probe_specific} eq 'digest')
    {
        $rrd_graph->unit('pps');
        $rrd_graph->title('digest pkts');
    }
    elsif ($url_params->{probe_specific} eq 'not_compressed')
    {
        $rrd_graph->unit('pps');
        $rrd_graph->title('not compressed pkts');
    }
    elsif ($url_params->{probe_specific} eq 'verify')
    {
        $rrd_graph->unit('pps');
        $rrd_graph->title('verify pkts');
    }
}

sub prepare_ds_compress_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    $rrd_graph->unit('pps');
    $rrd_graph->title('compression');
}

sub prepare_ds_caps_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    $rrd_graph->unit('pps');
    $rrd_graph->title('encapsulation');
}

sub prepare_ds_crypt_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    $rrd_graph->unit('pps');
    $rrd_graph->title('encryption');
}

sub prepare_ds_errors_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    $rrd_graph->unit('pps');
    $rrd_graph->title('errors');
}

sub prepare_ds_compress
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

    push @$args, "DEF:dsIn=$rrd_file:decompressed:$cf";
    push @$args, "DEF:dsOut=$rrd_file:compressed:$cf";
    push @$args, "CDEF:dsOut2=dsOut,-1,*";
    push @$args, "AREA:dsOut2#00FF00:compressed pkts";
    push @$args, "AREA:dsIn#FF0000:decompressed pkts";

    return ($up, $down, "dsIn");
}

sub prepare_ds_caps
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

    push @$args, "DEF:dsIn=$rrd_file:decaps:$cf";
    push @$args, "DEF:dsOut=$rrd_file:encaps:$cf";
    push @$args, "CDEF:dsOut2=dsOut,-1,*";
    push @$args, "AREA:dsOut2#00FF00:encapsulated pkts";
    push @$args, "AREA:dsIn#FF0000:decapsulated pkts";

    return ($up, $down, "dsIn");
}


sub prepare_ds_crypt
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

    push @$args, "DEF:dsIn=$rrd_file:decrypt:$cf";
    push @$args, "DEF:dsOut=$rrd_file:encrypt:$cf";
    push @$args, "CDEF:dsOut2=dsOut,-1,*";
    push @$args, "AREA:dsOut2#00FF00:encrypted pkts";
    push @$args, "AREA:dsIn#FF0000:decrypted pkts";

    return ($up, $down, "dsIn");
}

sub prepare_ds_errors
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

    push @$args, "DEF:dsIn=$rrd_file:send_errors:$cf";
    push @$args, "DEF:dsOut=$rrd_file:recv_errors:$cf";
    push @$args, "CDEF:dsOut2=dsOut,-1,*";
    push @$args, "AREA:dsIn#FF0000:send error pkts";
    push @$args, "AREA:dsOut2#00FF00:recv error pkts";

    return ($up, $down, "dsIn");
}


1;
