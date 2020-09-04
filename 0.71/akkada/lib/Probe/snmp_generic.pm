package Probe::snmp_generic;

use vars qw($VERSION);

$VERSION = 0.1;

use base qw(Probe);
use strict;

use Net::SNMP;
use Data::Dumper;
use Math::RPN;
use Number::Format qw(:subs);

$Number::Format::DECIMAL_FILL = 1;

use Constants;
use Configuration;
use Log;
use Entity;
use Common;
use URLRewriter;

use constant _MODE_BRIEF_OK => 0b0010;
use constant _MODE_BRIEF_BAD => 0b0001;
use constant _MODE_FULL_OK => 0b1000;
use constant _MODE_FULL_BAD => 0b0100;
use constant _MODE_ALL => 0b1111;


our $DataDir = CFG->{Probe}->{DataDir};
our $RRDDir = CFG->{Probe}->{RRDDir};
our $LogEnabled = CFG->{LogEnabled};
our $MaxSNMPSplitRequest = CFG->{MaxSNMPSplitRequest};
our $DEFDir = CFG->{Probes}->{snmp_generic}->{DEFDir};
our $LowLevelDebug = CFG->{Probes}->{snmp_generic}->{LowLevelDebug};
our $ComputeDebug = CFG->{Probes}->{snmp_generic}->{ComputeDebug};
our $ThresholdDefaults = CFG->{Probes}->{snmp_generic}->{ThresholdDefaults};

use constant
{
    DATA => 11,
    SESSION => 13,
    ENTITY => 14,
    RRD_DATA => 15,
    DEF => 17,
    OIDS => 18,
    TRACKMAP => 19,
    CACHE_KEYS => 20,
    RRD_CONFIG => 21,
    CACHE_STRING_KEYS => 22,
};

sub id_probe_type
{
    return 21;
}

sub clear_data
{
    my $self = shift;
    $self->[DATA] = {};
    $self->[RRD_DATA] = {};
    $self->[RRD_CONFIG] = {};
    $self->[ENTITY] = undef;
    $self->[OIDS] = [];
    $self->[TRACKMAP] = {};
    $self->[CACHE_KEYS] = [];
    $self->[CACHE_STRING_KEYS] = [];
};

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->[SESSION] = undef;

    $self->def_load;

    return $self;
}

sub def_load
{
    my $self = shift;
    my $file;

    $self->[DEF] = {};

    opendir(DIR, $DEFDir);
    while (defined($file = readdir(DIR)))
    {
        next
            if $file =~ /^\.|^CVS$|^template$/;
        $self->[DEF]->{$file} = do sprintf(qq|%s/%s|, $DEFDir, $file);
        $self->def_test($self->[DEF]->{$file}, $file);
    }
    closedir(DIR);
}

sub name
{
    my $self = shift;

    if (! @_ || ! $_[0])
    {
#use Data::Dumper; warn Dumper([caller(0)]);
#use Data::Dumper; warn Dumper([caller(1)]);
#use Data::Dumper; warn Dumper([caller(2)]);
#use Data::Dumper; warn Dumper([caller(3)]);
#use Data::Dumper; warn Dumper([caller(4)]);
        die 'missing snmp_generic_definition_name';
    }

    my $snmp_generic_definition_name = shift;
    my $def = $self->def->{$snmp_generic_definition_name};

    return $def->{NAME};
}

sub def_test
{
    my $self = shift;
    my $def = shift;
    my $name = shift;

    if (! defined $def->{TRACKS} || ref($def->{TRACKS}) ne 'HASH')
    {
        log_debug("bad definition $name: bad TRACKS data structure;", _LOG_ERROR);
        exit;
    }

    if (defined $def->{DISCOVER_CONDITION})
    {
        if (ref($def->{DISCOVER_CONDITION}) ne 'HASH')
        {
            log_debug("bad definition $name: DISCOVER_CONDITION must be a hash reference", _LOG_ERROR);
            exit;
        }
        for (keys %{ $def->{DISCOVER_CONDITION} })
        {
            if (ref($def->{DISCOVER_CONDITION}->{$_}) ne 'HASH')
            {
                log_debug("bad definition $name: {DISCOVER_CONDITION}->{$_} must be a hash reference", _LOG_ERROR);
                exit;
            }
        }
    }

    my $tr;

    for my $tr_name (keys %{ $def->{TRACKS} })
    {
        if (! $tr_name || ref($def->{TRACKS}->{$tr_name}) ne 'HASH')
        {
            log_debug("bad definition $name: missing base_oid in data structure", _LOG_ERROR);
            exit;
        }

        $tr = $def->{TRACKS}->{$tr_name};

        if (defined $tr->{text_test})
        {
            if (ref($tr->{text_test}) ne 'HASH')
            {
                log_debug("bad text_test data structure in track $tr_name. it must be a hash reference:"
                    . Dumper($tr->{text_test}), _LOG_ERROR);
                exit;
            }
            if (defined $tr->{text_test}->{expected})
            {
                if (ref($tr->{text_test}->{expected}) ne 'ARRAY')
                {
                    log_debug("bad text_test->{expected} data structure in track $tr_name. it must be an array reference:"
                        . Dumper($tr->{text_test}), _LOG_ERROR);
                    exit;
                }
                for (@{$tr->{text_test}->{expected}})
                {
                    if (ref($_) ne 'HASH')
                    {
                        log_debug("bad text_test->{expected} data structure in track $tr_name. each element must be an array reference:"
                            . Dumper($tr->{text_test}), _LOG_ERROR);
                        exit;
                    }
                    if ($_->{alarm_level} =~ /\D/ || ! defined status_name($_->{alarm_level}))
                    {
                        log_debug("bad text_test->{expected} data structure in track $tr_name. element with bad status"
                            . Dumper($tr->{text_test}), _LOG_ERROR);
                        exit;
                    }
                }
            }
            if (defined $tr->{text_test}->{bad})
            {
                if (ref($tr->{text_test}->{bad}) ne 'ARRAY')
                {
                    log_debug("bad text_test->{bad} data structure in track $tr_name. it must be an array reference:"
                        . Dumper($tr->{text_test}), _LOG_ERROR);
                    exit;
                }
                for (@{$tr->{text_test}->{bad}})
                {
                    if (ref($_) ne 'HASH')
                    {
                        log_debug("bad text_test->{bad} data structure in track $tr_name. each element must be an array reference:"
                            . Dumper($tr->{text_test}), _LOG_ERROR);
                        exit;
                    }
                    if ($_->{alarm_level} =~ /\D/ || ! defined status_name($_->{alarm_level}))
                    {
                        log_debug("bad text_test->{bad} data structure in track $tr_name. element with bad status"
                            . Dumper($tr->{text_test}), _LOG_ERROR);
                        exit;
                    }
                }  
            }
        }
    }
}

sub cache_keys
{
    return $_[0]->[CACHE_KEYS];
}

sub cache_string_keys
{
    return $_[0]->[CACHE_STRING_KEYS];
}

sub data
{
    return $_[0]->[DATA];
}

sub rrd_data
{
    return $_[0]->[RRD_DATA];
}

sub session
{
    my $self = shift;
    $self->[SESSION] = shift
        if @_;
    return $self->[SESSION];
}

sub def
{
    return $_[0]->[DEF];
}

sub trackmap
{
    return $_[0]->[TRACKMAP];
}

sub entity
{
    my $self = shift;
    $self->[ENTITY] = shift
        if @_;
    return $self->[ENTITY];
}

sub oids_build
{
    my $self = shift;

    my $oid_src = shift || '';

    my $oids_disabled = {};
    @$oids_disabled{ (split /:/, $oid_src) } = undef;

    my $snmp_split_request = shift;
    my $def = shift;
    my $index = shift;

    my $oids;

    for (keys %{$def->{TRACKS}})
    {
        next
             if exists $oids_disabled->{$_};
        push @$oids, sprintf(qq|%s.%s|, $_, $index);
    }

    return [$oids]
        if $snmp_split_request == 1;

    my $split = 0;
    my $result;

    for ( @{ $oids } )
    {
        push @{$result->[$split]}, $_;
        ++$split;
        $split = 0
            if $split == $snmp_split_request;
    }
    return $result;
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

    my $index = $entity->params('index');
    if (! defined $index || $index eq '')
    {
        $self->clear_data;
        $self->errmsg('index not defined');
        $self->status(_ST_BAD_CONF);
        return;
    }

    my $snmp_generic_definition_name = $entity->params('snmp_generic_definition_name');
    if (! defined $snmp_generic_definition_name || ! $snmp_generic_definition_name)
    {
        $self->clear_data;
        $self->errmsg('snmp_generic_definition_name not defined');
        $self->status(_ST_BAD_CONF);
        return;
    }

    my $def = $self->def->{$snmp_generic_definition_name};
    if (! defined $def || ! $def)
    {
        $self->clear_data;
        $self->errmsg("definition $snmp_generic_definition_name not found");
        $self->status(_ST_BAD_CONF);
        return;
    }


    my $oids_disabled = $entity->params_own->{'oids_disabled'};

    log_debug(sprintf(qq|entity %s oids_disabled: %s|, $id_entity, $oids_disabled), _LOG_DEBUG)
        if $LogEnabled && $oids_disabled;

    my $snmp_split_request = $entity->params_own->{'snmp_split_request'};
    log_debug(sprintf(qq|entity %s snmp_split_request: %s|, $id_entity, $snmp_split_request), _LOG_DEBUG)
        if $LogEnabled && $snmp_split_request;
    $snmp_split_request = 1
        unless $snmp_split_request;

    my ($session, $error) = snmp_session($ip, $entity);

    if (! $error) 
    {
        $session->max_msg_size(2944);

        my $oids = $self->oids_build($oids_disabled, $snmp_split_request, $def, $index);
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
            if ($snmp_split_request <= $MaxSNMPSplitRequest)
            {
                ++$snmp_split_request;
                $entity->params('snmp_split_request', $snmp_split_request);
            }
            else
            {
                log_debug(sprintf(qq|maximum snmp_split_request value %s already set. cannot fix that!!! check configuration|, 
                    $MaxSNMPSplitRequest), _LOG_ERROR);
            }
        }
        elsif ($error == 2)
        {
            my $bad_oid = $oids->[0]->[$session->error_index - 1];

            $bad_oid =~ s/\.$index$//g;

            $oids_disabled = defined $oids_disabled
                ? join(":", $oids_disabled, $bad_oid)
                : $bad_oid;

            $entity->params('oids_disabled', $oids_disabled);
        }
        else
        #elsif (! $error )
        {
            log_debug("result: " . Dumper($result), _LOG_ERROR)
                if $LogEnabled && $LowLevelDebug;

            $self->result_dispatch($result, $def, $index);

            log_debug("data: " . Dumper($self->data), _LOG_ERROR)
                if $LogEnabled && $LowLevelDebug;
            log_debug("cache_keys: " . Dumper($self->cache_keys), _LOG_ERROR)
                if $LogEnabled && $LowLevelDebug;
            log_debug("cache_string_keys: " . Dumper($self->cache_string_keys), _LOG_ERROR)
                if $LogEnabled && $LowLevelDebug;
            log_debug("rrd_config: " . Dumper($self->rrd_config), _LOG_ERROR)
                if $LogEnabled && $LowLevelDebug;
            log_debug("rrd_data: " . Dumper($self->rrd_data), _LOG_ERROR)
                if $LogEnabled && $LowLevelDebug;
            log_debug("trackmap: " . Dumper($self->trackmap), _LOG_ERROR) 
                if $LogEnabled && $LowLevelDebug;

            $self->cache_update($id_entity, $self->data);
            $self->cache_string_update($id_entity, $self->data);
            $self->utilization_status($def);
            $self->rrd_save($id_entity, $self->status);
        }
        #else
        #{
        #    $self->errmsg('snmp error: ' . $session->error . ":" . $session->error_status . ":" . $session->error_index . Dumper($oids));
        #    $self->status(_ST_MAJOR);
        #}
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

sub cache_string_update
{
    my $self = shift;
    my $id_entity = shift;
    my $data = shift;
    my $cache_string_keys = $self->cache_string_keys;
    $self->cache_string($id_entity, $_, $data->{$_})
        for @$cache_string_keys;
}

sub result_dispatch
{
    my $self = shift;
    my $result = shift;
    my $def = shift;
    my $index = shift;

    if (scalar keys %$result == 0)
    {
        $self->errmsg('data information not found');
        $self->status(_ST_MAJOR);
        return;
    }

    my $data = $self->data;
    my $cache_keys = $self->cache_keys;
    my $cache_string_keys = $self->cache_string_keys;
    my $trackmap = $self->trackmap;
    my $rrd_data = $self->rrd_data;
    my $rrd_config = $self->rrd_config;

    my $key;
    my $track;

    for (keys %{$def->{TRACKS}})
    {
        $track = $def->{TRACKS}->{$_};
        $key = sprintf("%s.%s", $_, $index);

        $data->{ $track->{track_name} } = defined $result->{$key} ? $result->{$key} : '';

        if ($track->{compute})
        {
            $data->{ $track->{track_name} . "_absolute" } = $data->{ $track->{track_name} };
            $data->{ $track->{track_name} } = ($self->compute($data, \@{$track->{compute}}, _MODE_ALL))[0];
        }

        if (defined $track->{text_translator})
        {
            $data->{ $track->{track_name} } = $track->{text_translator}->{ $data->{ $track->{track_name} } }
                if defined $track->{text_translator}->{ $data->{ $track->{track_name} } };
        }

        if (defined $track->{rrd_track_type})
        {
            push @$cache_keys, $track->{track_name}
                if $track->{rrd_track_type} eq 'COUNTER' || $track->{rrd_track_type} eq 'DERIVE';
            $rrd_data->{ $track->{track_name} } = $data->{ $track->{track_name} };
            $rrd_config ->{ $track->{track_name} } = $track->{rrd_track_type};
        }
        $trackmap->{ $track->{track_name} } = $_;
        push @$cache_string_keys, $track->{track_name}
            if $track->{change_detect};
    }
}

sub compute
{
    my $self = shift;
    my $data = shift;
    my $computes = shift;
    my $res = {};
    my $mask = shift;

    if ($ComputeDebug)
    {
        warn("START COMPUTES: mask: $mask:" . Dumper($computes));
        log_debug("START COMPUTES: mask: $mask" . Dumper($computes), _LOG_ERROR);
    }

    my $tmp;

    for my $compute (@$computes)
    {
        $compute->[2] = _MODE_ALL
             unless $compute->[2];

        if ($ComputeDebug)
        {
            warn("CURR COMPUTE:" . Dumper($compute));
            log_debug("CURR COMPUTE:" . Dumper($compute), _LOG_ERROR);
        }

        if ($compute->[1] =~ /^REG::/ && $compute->[2] & $mask)
        {
            $tmp = $self->compute_reg($compute, $data);
            $res = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^ABS::/ && $compute->[2] & $mask)
        { 
            $tmp = $self->compute_abs($compute, $data);
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^RPN::/ && $compute->[2] & $mask)
        { 
            $tmp = $self->compute_rpn($compute, $data);
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^MAC::/ && $compute->[2] & $mask)
        {
            $compute->[1] =~ /^MAC::%%(.*)%%$/;
            $tmp = decode_mac( $data->{ $1 } );
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^VALUES::/ && $compute->[2] & $mask)
        {
            $tmp = $self->compute_values($compute, $data);
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^FORMAT::/ && $compute->[2] & $mask)
        {
            $tmp = $self->compute_format($compute, $data);
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^PERCRAW::/ && $compute->[2] & $mask)
        {
            $tmp = $self->compute_percraw($compute, $data);
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^PERCDEFL::/ && $compute->[2] & $mask)
        {
            $tmp = $self->compute_perldefl($compute, $data);
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^PERCENT::/ && $compute->[2] & $mask)
        {
            $tmp = $self->compute_percent($compute, $data);
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^LC::/ && $compute->[2] & $mask)
        {
            $tmp = $self->compute_case($compute, $data, 'LC');
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^UC::/ && $compute->[2] & $mask)
        {
            $tmp = $self->compute_case($compute, $data, 'UC');
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[1] =~ /^%%.*%%$/ && $compute->[2] & $mask)
        {
            $tmp = $self->compute_raw($compute, $data);
            $res->{value} = $tmp
                unless $compute->[0];
        }
        elsif ($compute->[2] & $mask)
        {
            warn("bad compute definition: $compute->[1]");
            log_debug("bad compute definition: $compute->[1]", _LOG_ERROR);
        }
    }

    return ($res->{value}, $res->{name}, $res->{unit});
}

sub compute_perldefl
{
    my $self = shift;
    my $compute = shift;
    my $data = shift;

    my $data_key;
    $data_key = $compute->[0]
        if $compute->[0];
    $compute = $compute->[1];

    if ($ComputeDebug)
    {
        warn "PERCDEFL START: $compute";
        log_debug("PERCDEFL START: $compute", _LOG_ERROR);
    }

    my @v = split /::/, $compute;
    shift @v;

    my $i = 0;
    for (@v)
    {
        $v[$i] = $data->{$1}
            if $_ =~ /^%%(.*)%%$/;
        ++$i;
    }

    my $value = $v[0];
    my $vlow = $v[1];
    my $vhigh = $v[2];
    my $deflection = $v[2];
    my $units = $v[4];

    my $simple = $v[2] ? 0 : 1;

    my $z = $value;

    if ($ComputeDebug)
    {
        warn "PERCDEFL ARGS: " . Dumper(\@v);
        log_debug("PERCDEFL ARGS: " . Dumper(\@v), _LOG_ERROR);
    }

    $vhigh = ( $self->compute($data, \@$vhigh, _MODE_ALL) )[0]
        if ref($vhigh) eq 'ARRAY';
        
    $vlow = ( $self->compute($data, \@$vlow, _MODE_ALL) )[0]
        if ref($vlow) eq 'ARRAY';

    my ($flag, $x, $y);

    $z = $vlow
        if $z < $vlow;
    $z = $vhigh
        if $z > $vhigh;

    $z = $value - $vlow;
#warn "XXXX: $vhigh";
    $vhigh = $vhigh - $vlow;
#warn "XXXX: $vhigh";
    $y = $vhigh/2;
#warn "XXXX: $y";

    $flag = $z < $y ? 0 : 1;

    if ($flag)
    {
        $z = $z - $y;
        $x = $z *100/$y;
    }
    else
    {
        $x = 100 - $z*100/$y;
    }

    $x = $x*-1
        if $x < 0;
#warn "XXXX: $vlow $vhigh $value: vl: $vlow vh: $vhigh y $y flag: $flag z $z x $x";

    if ($flag && ! $simple)
    {
        if ($deflection)
        {
            $value = $x
                ? sprintf(qq|<font class="%s">%s %s (deflection +%.2f%)</font>|, percent_bar_style_select($x), $value, $units, $x)
                : sprintf(qq|<font class="%s">%s %s (deflection %.2f%)</font>|, percent_bar_style_select($x), $value, $units, $x);
        }
        else
        {
            $value = sprintf(qq|<font class="%s">%s %s</font>|, percent_bar_style_select($x), $value, $units);
        }
    }
    elsif (! $simple)
    {
        if ($deflection)
        {
            $value = sprintf(qq|<font class="%s">%s %s (deflection -%.2f%)</font>|, percent_bar_style_select($x, 'low'),$value, $units, $x);
        }
        else
        {
            $value = sprintf(qq|<font class="%s">%s %s</font>|, percent_bar_style_select($x, 'low'),$value, $units);
        }
    }
    else
    {
        $value = sprintf(qq|%s %s|, $value, $units);
    }

    $data->{$data_key} = $value
        if $data_key;

    if ($ComputeDebug)
    {
        warn "PERCDEFL END: $value";
        log_debug("PERCDEFL END: $value", _LOG_ERROR);
    }

    return $value;
}

sub compute_raw
{
    my $self = shift;
    my $value = shift;
    my $data = shift;

    my $data_key;
    $data_key = $value->[0]
        if $value->[0];
    $value = $value->[1];

    if ($ComputeDebug)
    {
        warn "RAW START: $value";
        log_debug("RAW START: $value", _LOG_ERROR);
    }

    $value =~ /^%%(.*)%%/;

    $value = $data->{ $1 };

    $data->{$data_key} = $value
        if $data_key;

    if ($ComputeDebug)
    {
        warn "RAW END: $data_key#: $value";
        log_debug("RAW END: $data_key#: $value", _LOG_ERROR);
    }

    return $value;
}

sub compute_reg
{
    my $res = {};

    my $self = shift;
    my $value = shift;
    my $data = shift;

    my $data_key;
    $data_key = $value->[0]
        if $value->[0];
    $value = $value->[1];   

    $res->{name} = '';
    $res->{unit} = '';
    $res->{value} = '';

    my $i;

    my @ar = split /::/, $value;
    shift @ar;
    $ar[0] =~ s/\%//g;
    $res->{value} = $data->{ $ar[0] };

    if ($ComputeDebug)
    {
        warn "REG START: key $ar[0]; value: " . $res->{value};
        log_debug("REG START: key $ar[0]; value: " . $res->{value}, _LOG_ERROR);
    }

    shift @ar;

    $res->{value} =~ /$ar[0]/;

    shift @ar;

    my @n;
    my %t;

    for (@ar)
    {
        ++$i;
        @n = split /\|\|/, $_;

        next
            unless defined $res->{ $n[0] };

        $t{$n[0]} = $n[1];

        if ($i == 1)
        {
            $res->{ $n[0] } = $1;
        }
        elsif ($i == 2)
        {
            $res->{ $n[0] } = $2;
        }
        elsif ($i == 3)
        {
            $res->{ $n[0] } = $3;
        }
    }

    for (keys %$res)
    {
        $res->{ $_ } =~ s/$t{$_}//g
            if defined $t{$_} && $t{$_};
    }

    $data->{$data_key} = $res->{value}
        if $data_key;

    if ($ComputeDebug)
    {
        warn "REG END: $data_key#: " . Dumper($res);
        log_debug("REG END: $data_key#: " . Dumper($res), _LOG_ERROR);
    }

    return $res;
}

sub thresholds_get
{
    my $self = shift;
    my $entity = $self->entity;
    my $trackmap = $self->trackmap;
    my $thls;

    my $threshold;
    my $s;
    my @tmp;

    for (qw|threshold_medium threshold_high threshold_too_low|)
    {
        $threshold = $entity->params($_);
        if (defined $threshold)
        {
            $s = $_;
            $s =~ s/^threshold\_//g;
            for (split /\|\|/, $threshold)
            {
                @tmp = split /::/, $_, 2; 
                next
                    unless defined $tmp[0] && defined $trackmap->{$tmp[0]};
                $thls->{$s}->{$tmp[0]} = $tmp[1]
                    if defined $tmp[1] && $tmp[1] ne '';
            }
        }
    }

    return $thls;
}

sub compute_percent
{
    my $self = shift;
    my $value = shift;
    my $data = shift;

    my $data_key;
    $data_key = $value->[0]
        if $value->[0];
    $value = $value->[1];

    if ($ComputeDebug)
    {
        warn "PERCENT START: $value";
        log_debug("PERCENT START: $value", _LOG_ERROR);
    }


    $value =~ /^PERCENT::%%(.*)%%/;

    $value = $data->{ $1 } ne 'n/a'
        ? sprintf(qq|<font class="%s">%s %%</font>|, percent_bar_style_select($data->{$1}),$data->{$1})
        : 'n/a';

    $data->{$data_key} = $value
        if $data_key;

    if ($ComputeDebug)
    {
        warn "PERCENT END: $data_key#: $value";
        log_debug("PERCENT END: $data_key#: $value", _LOG_ERROR);
    }

    return $value;
}

sub compute_case
{
    my $self = shift;
    my $value = shift;
    my $data = shift;
    my $case = shift;

    my $data_key;
    $data_key = $value->[0]
        if $value->[0];
    $value = $value->[1];

    if ($ComputeDebug)
    {
        warn "CASE START: $value $case";
        log_debug("CASE START: $value $case", _LOG_ERROR);
    }


    if ($case eq 'UC')
    {
        $value =~ /^UC::%%(.*)%%/;
        $value = uc $data->{ $1 };
    }
    elsif ($case eq 'LC')
    {
        $value =~ /^LC::%%(.*)%%/;
        $value = lc $data->{ $1 };
    }

    $data->{$data_key} = $value
        if $data_key;

    if ($ComputeDebug)
    {
        warn "CASE END: $data_key#: $value $case";
        log_debug("CASE END: $data_key#: $value $case", _LOG_ERROR);
    }

    return $value;
}

sub compute_percraw
{
    my $self = shift;
    my $value = shift;
    my $data = shift;

    my $data_key;
    $data_key = $value->[0]
        if $value->[0];
    $value = $value->[1];

    if ($ComputeDebug)
    {
        warn "PERCRAW START: $value";
        log_debug("PERCRAW START: $value", _LOG_ERROR);
    }

    $value =~ s/^PERCRAW:://;

    my $base;

    ($value, $base) = split /::/, $value;

    $value = $data->{ $1 }
        if $value =~ /^%%(.*)%%$/;
    $base = $data->{ $1 } 
        if $base =~ /^%%(.*)%%$/;

    $value = $base ? $value*100/$base : 'n/a';

    $data->{$data_key} = $value
        if $data_key;

    if ($ComputeDebug)
    {
        warn "PERCRAW END: $data_key#: $value";
        log_debug("PERCRAW END: $data_key#: $value", _LOG_ERROR);
    }

    return $value;
}


sub compute_format
{
    my $self = shift;
    my $value = shift;

    my $data_key;
    $data_key = $value->[0]
        if $value->[0];
    $value = $value->[1];   

    if ($ComputeDebug)
    {
        warn "FORMAT START: $value";
        log_debug("FORMAT START: $value", _LOG_ERROR);
    }

    my $data = shift;
    my $format;

    if ($value =~ /^FORMAT::BYTES::/)
    {
        $value =~ /^FORMAT::BYTES::%%(.*)%%/;
        $value = format_bytes($data->{ $1 });

    }
    elsif ($value =~ /^FORMAT::NUMBER\.+\d+::/)
    {
        $value =~ /^FORMAT::(.*)::%%(.*)%%/;
        $format = $1;
        $value = $data->{ $2 };

        $value = format_number($value, ((split /\./, $format)[1] || 0));
    }
    elsif ($value =~ /^FORMAT::STRING::/)
    {
        $value =~ /^FORMAT::STRING::(.*)::%%(.*)%%/;
        $value = sprintf(qq|$1|, $data->{ $2 });
    }
    elsif ($value =~ /^FORMAT::UNIXDATE::/)
    {
        $value =~ /^FORMAT::UNIXDATE::%%(.*)%%/;
        $value = scalar localtime($data->{ $1 });
    }
    else
    {
        warn("FORMAT: unknown format: $value");
        log_debug("FORMAT: unknown format: $format", _LOG_ERROR);
    }
    
    $data->{$data_key} = $value
        if $data_key;

    if ($ComputeDebug)
    {
        warn "FORMAT END: $data_key#: $value";
        log_debug("FORMAT END: $data_key#: $value", _LOG_ERROR);
    }

    return $value;
}

sub compute_interested
{
    my $self = shift;
    my $value = shift;
    my $mask = shift;
    $value = unpack("B*", pack("N", $value));
    return $value & $mask;
}

sub compute_values
{
    my $self = shift;
    my $value = shift;

    my $data_key;
    $data_key = $value->[0]
        if $value->[0];
    $value = $value->[1];   

    my $data = shift;
    my $data_value;
    my @ar;
    my $x;
    my $key;

    $value =~ s/^VALUES:://;

    while ($value =~ /(\%\%[\_\.,a-z,A-Z,\%,0-9]*\%\%)/)
    { 
        $key = $1;

        $data_value = $1;
        $data_value =~ s/\%\%//g;

        @ar = split /\./, $data_value;

        if ($ComputeDebug)
        {
            warn "VALUES IN: $data_value" . Dumper(\@ar);
            log_debug("VALUES IN: " . Dumper(\@ar), _LOG_ERROR);
        }

        $ar[0] = $data->{ $ar[0] };

        if (@ar > 1 && $ar[1] eq '%')
        {
            $x = ($ar[0] - $ar[2])*100 /($ar[3] - $ar[2]);
            $x *= -1
                if $x < 0;
            $x = 100 - $x;
            if (defined $ar[4])
            {
                $ar[0] = sprintf("%0*d", $ar[4], $ar[0]);
            }

            $ar[0] = sprintf(qq|<font class="%s">%s</font>|, percent_bar_style_select($x),$ar[0]);
        }
       
        $value =~ s/$key/$ar[0]/g;
    }
    $data->{$data_key} = $value
        if $data_key;

    if ($ComputeDebug)
    {
        warn "VALUES END: $data_key#: $value";
        log_debug("VALUES END: $data_key#: $value", _LOG_ERROR);
    }

    return $value;
}

sub compute_rpn
{
    my $self = shift;
    my $value = shift;

    my $data_key;
    $data_key = $value->[0]
        if $value->[0];
    $value = $value->[1];   

    if ($ComputeDebug)
    {
        warn "RPN START: $value";
        log_debug("RPN START: $value", _LOG_ERROR);
    }

    my $data = shift;
    my $data_value;

    $value =~ s/^RPN:://;

    for (keys %$data)
    {
        $data_value = $data->{ $_ };
        $value =~ s/\%\%$_\%\%/$data_value/g;
    }

    $value = rpn($value);

    $data->{$data_key} = $value
        if $data_key;

    if ($ComputeDebug)
    {
        warn "RPN END: $data_key#: $value";
        log_debug("RPN END: $data_key#: $value", _LOG_ERROR);
    }

    return $value;
}

sub compute_abs
{
    my $self = shift;
    my $value = shift;
    my $data = shift;

    my $data_key;
    $data_key = $value->[0]
        if $value->[0];
    $value = $value->[1];

    if ($ComputeDebug)
    {
        warn "ABS START: $value";
        log_debug("ABS START: $value", _LOG_ERROR);
    }

    $value =~ /^ABS::%%(.*)%%/;
    $value = $data->{ $1 . "_absolute" };

    $data->{$data_key} = $value
        if $data_key;

    if ($ComputeDebug)
    {
        warn "ABS END: $data_key#: $value";
        log_debug("ABS END: $data_key#: $value", _LOG_ERROR);
    }

    return $value;
}

sub dispatch_message
{
    my $self = shift;
    my $string = shift;

    return $string
        unless $string =~ /\%\%.*\%\%/;

    my $data = $self->data;
    my $cache = $self->cache->{ $self->entity->id_entity };

    my $data_value;

    for my $track_name (keys %$data)
    {
        last
            unless $string =~ /\%\%.*\%\%/;
        next
            unless $string =~ /\%\%$track_name\%\%/;

        $data_value = defined $cache->{ $track_name }
            ? $cache->{$track_name}->[1]
            : $data->{$track_name};

        $string =~ s/\%\%$track_name\%\%/$data_value/g;
    }

    return $string;
}

sub utilization_status
{  
    my $self = shift;
    my $def = shift;
    my $data = $self->data;
    my $cache = $self->cache->{ $self->entity->id_entity };
    my $trackmap = $self->trackmap;

    my $entity = $self->entity;

    my $thls = $self->thresholds_get;

    log_debug("thls: " . Dumper($thls), _LOG_ERROR)
        if $LogEnabled && $LowLevelDebug;

    my $value;
    my $error;
    my $th_default_name;
    my $data_value;
    my $alarm_level;
    my $message;

    my $high_set;

    my $text_test;
    my $snmp_generic_text_test_disable;
    my @ar;

    for my $track_name (keys %$data)
    {
        next
            unless defined $def->{TRACKS}->{ $trackmap->{$track_name} };

        $data_value = defined $cache->{ $track_name } 
            ? $cache->{$track_name}->[1]
            : $data->{$track_name};

        log_debug("track_name: " . Dumper($track_name), _LOG_ERROR)
            if $LogEnabled && $LowLevelDebug;
        log_debug("data_value: " . Dumper($data_value), _LOG_ERROR)
            if $LogEnabled && $LowLevelDebug;

        $text_test = defined $def->{TRACKS}->{ $trackmap->{$track_name} }->{text_test}
                ? $def->{TRACKS}->{ $trackmap->{$track_name} }->{text_test}
                : undef;
      
        log_debug("text_test: " . Dumper($text_test), _LOG_ERROR)
            if $LogEnabled && $LowLevelDebug;

        if (defined $def->{TRACKS}->{ $trackmap->{$track_name} }->{change_detect})
        {
            if ($self->cache_string($entity->id_entity, $track_name)->[0])
            {
                $self->errmsg(sprintf(qq|%s value changed to %s|, $track_name, $data->{$track_name}));
            }
        }

        if (! defined $text_test)
        {
            $high_set = 0;
            for my $th (qw|high medium too_low|)
            {
                $error = 0;
                $th_default_name = "threshold_$th";

                $value = defined $thls->{$th} && defined $thls->{$th}->{$track_name}
                    ? $thls->{$th}->{$track_name}
                    : $def->{TRACKS}->{ $trackmap->{$track_name} }->{$th_default_name}->{value};

                log_debug("th: " . Dumper($th), _LOG_ERROR)
                    if $LogEnabled && $LowLevelDebug;
                log_debug("value: " . Dumper($value), _LOG_ERROR)
                    if $LogEnabled && $LowLevelDebug;

                next
                    unless defined $value && $value;

                $value = ( $self->compute($data, \@$value, _MODE_ALL) )[0]
                    if ref($value) eq 'ARRAY';

                log_debug("thl value after compute_rpn: " . Dumper($value), _LOG_ERROR)
                    if $LogEnabled && $LowLevelDebug;

                if (defined $def->{TRACKS}->{ $trackmap->{ $track_name } }->{threshold_compute_modulus}
                    && $def->{TRACKS}->{ $trackmap->{ $track_name } }->{threshold_compute_modulus})
                {
                    $data_value *= -1
                        if $data_value < 0;
                    $value *= -1
                        if $value < 0;
                }

                if ($th eq 'high' && $data_value > $value)
                {
                    ++$error;
                    ++$high_set;
                }
                elsif ($th eq 'medium' && $data_value > $value)
                {
                    ++$error;
                }
                elsif ($th eq 'too_low' && $data_value < $value)
                {
                    ++$error;
                }

                next
                    if $th eq 'medium' && $error && $high_set;

                if ($error)
                {
                    $message = defined $def->{TRACKS}->{ $trackmap->{$track_name} }->{$th_default_name}->{message}
                        ? $def->{TRACKS}->{ $trackmap->{$track_name} }->{$th_default_name}->{message}
                        : $ThresholdDefaults->{$th_default_name}->{message};

                    $self->errmsg( sprintf("%s: %s", $track_name, $message) );

                    $alarm_level = defined $def->{TRACKS}->{ $trackmap->{$track_name} }->{$th_default_name}->{alarm_level}
                        ? $def->{TRACKS}->{ $trackmap->{$track_name} }->{$th_default_name}->{alarm_level}
                        : $ThresholdDefaults->{$th_default_name}->{alarm_level};

                    $self->status( $alarm_level );

                    log_debug("errmsg: " . Dumper($self->errmsg), _LOG_ERROR)
                        if $LogEnabled && $LowLevelDebug;
                    log_debug("status: " . Dumper($self->status), _LOG_ERROR)
                        if $LogEnabled && $LowLevelDebug;
                }
            }        
        }
        else
        {
            $snmp_generic_text_test_disable = $entity->params('snmp_generic_text_test_disable');

            next
                if defined $snmp_generic_text_test_disable && $snmp_generic_text_test_disable;

            if (defined $text_test->{expected})
            {
                for my $s (@{$text_test->{expected}})
                {
                    if ($data_value !~ /$s->{value}/i)
                    {
                        $message = $self->dispatch_message($s->{message});
                        $self->errmsg($message);
                        $self->status($s->{alarm_level});
                    }
                }
            }
            if (defined $text_test->{bad} && $data_value ne '')
            {
                for my $s (@{$text_test->{bad}})
                {
                    if ($data_value =~ /$s->{value}/i)
                    {
                        $message = $self->dispatch_message($s->{message});
                        $self->errmsg($message);
                        $self->status($s->{alarm_level});
                    }
                }
            }
        }
    }
}

sub rrd_config
{   
    return $_[0]->[RRD_CONFIG];
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

sub discover_mandatory_parameters
{
    my $self = shift;
    my $mp = $self->SUPER::discover_mandatory_parameters();

    push @$mp, ['snmp_community_ro', 'snmp_user'];

    return $mp;
}

sub discover_mode
{
    return _DM_AUTO;
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

    if ($error)
    {
        log_debug($error, _LOG_WARNING)
            if $LogEnabled;
        return;
    }

    my $sysObjectID = '1.3.6.1.2.1.1.2.0';

    my $result = $session->get_request( -varbindlist => [$sysObjectID]);
    $error = $session->error();
    if ($error)
    {   
        $session->close
            if $session;
        log_debug($error, _LOG_WARNING)
            if $LogEnabled;
        return;
    }

    $session->close
        if $session;

    if (! defined $result)
    {
        log_debug("cannot fetch sysObjectID. entity ignored", _LOG_WARNING)
            if $LogEnabled;
        return;
    } 

    $sysObjectID = $result->{$sysObjectID};

    my $def = $self->def;

    my $affected;

    for my $definition (keys %$def)
    {
        $affected = 0;
        for (@{ $def->{$definition}->{DISCOVER_AFFECTED_SYSOBJECTID}})
        {
            ++$affected
                if $sysObjectID =~ /^$_/; 
        }
        $self->discover_def($entity, $definition)
            if $affected;
    }
}

sub discover_def
{
    my $self = shift;
    my $entity = shift;
    my $definition_name = shift;
    my $definition = $self->def->{$definition_name};

    log_debug("discover snmp_generic definition $definition_name", _LOG_INFO)
        if $LogEnabled;

    my $id_entity = $entity->id_entity;

    my $ip = $entity->params('ip');

    my ($session, $error) = snmp_session($ip, $entity);

    if ($error)
    {
        log_debug($error, _LOG_WARNING)
            if $LogEnabled;
        return;
    }

    $session->max_msg_size(8128);

    my $result;
    my $new = {};

    my $discover_name;
    my $name;
    my $discover_index;
    my $st;
    my $tmp = {};

    log_debug(sprintf(qq|discover of %s started|, $definition_name), _LOG_DEBUG)
        if $LogEnabled;

    for my $oid (@{ $definition->{DISCOVER} })
    {
        log_debug(sprintf(qq|fetching data for oid %s|, $oid), _LOG_INTERNAL)
            if $LogEnabled;

        $result = $session->get_table(-baseoid => $oid );
        $error = $session->error();
        if ($error)
        {
            log_debug("fetched data: " . Dumper($result), _LOG_INTERNAL)
                if $LogEnabled;
            log_debug($error, _LOG_WARNING)
                if $LogEnabled;
            return;
        }

        for (keys %$result)
        {
            $st = $result->{$_};
            s/^$oid\.//g;
            $st =~ s/\'//g;
            $st =~ s/\000//g;
            $st =~ s/\s+$//;        
            push @{ $tmp->{ $_ } }, $st;
        }
    }

    my $the_same_names = 0;
    my $dc;
    my $dcount;

    for $discover_index (keys %$tmp)
    {
        $dc = 0;
        $dcount = 0;

        if (defined $definition->{DISCOVER_CONDITION})
        {
        for my $dcon (keys %{$definition->{DISCOVER_CONDITION}})
        {

            if ($dcon eq 'eq')
            {
                for ( keys %{ $definition->{DISCOVER_CONDITION}->{eq} } )
                {
                    ++$dcount;
                    ++$dc
                        if $tmp->{$discover_index}->[ $_ ] eq $definition->{DISCOVER_CONDITION}->{eq}->{$_};
                }
            }
            elsif ($dcon eq 'ne')
            {
                for ( keys %{ $definition->{DISCOVER_CONDITION}->{ne} } )
                {
                    ++$dcount;
                    ++$dc
                        if $tmp->{$discover_index}->[ $_ ] ne $definition->{DISCOVER_CONDITION}->{ne}->{$_};
                }
            }
            elsif ($dcon eq 'gt')
            {
                for ( keys %{ $definition->{DISCOVER_CONDITION}->{gt} } )
                {
                    ++$dcount;
                    ++$dc
                        if $tmp->{$discover_index}->[ $_ ] > $definition->{DISCOVER_CONDITION}->{gt}->{$_};
                }
            }
            elsif ($dcon eq 'lt')
            {
                for ( keys %{ $definition->{DISCOVER_CONDITION}->{lt} } )
                {
                    ++$dcount;
                    ++$dc
                        if $tmp->{$discover_index}->[ $_ ] < $definition->{DISCOVER_CONDITION}->{lt}->{$_};
                }
            }
            elsif ($dcon eq 'begin')
            {
                for ( keys %{ $definition->{DISCOVER_CONDITION}->{begin} } )
                {
                    ++$dcount;
                    ++$dc
                        if $tmp->{$discover_index}->[ $_ ] =~ /^$definition->{DISCOVER_CONDITION}->{begin}->{$_}/;
                }
            }
            elsif ($dcon eq 'end')
            {
                for ( keys %{ $definition->{DISCOVER_CONDITION}->{end} } )
                {
                    ++$dcount;
                    ++$dc
                        if $tmp->{$discover_index}->[ $_ ] =~ /$definition->{DISCOVER_CONDITION}->{end}->{$_}$/;
                }
            }
            elsif ($dcon eq 'contain')
            {
                for ( keys %{ $definition->{DISCOVER_CONDITION}->{contain} } )
                {
                    ++$dcount;
                    ++$dc
                        if $tmp->{$discover_index}->[ $_ ] =~ /$definition->{DISCOVER_CONDITION}->{contain}->{$_}/;
                }
            }

        }
        }

        next
            unless $dc == $dcount;

        $discover_name = join (".", @{ $tmp->{ $discover_index } });
        if (! $definition->{DISCOVER_NAME_OVERRIDE} )
        {
            $name = $discover_name;
        }
        else
        {
            $name = $definition->{DISCOVER_NAME_OVERRIDE};
            while ($name =~ /%/)
            {

            if ($name =~ /%%DISCOVER_NAME%%/)
            {
                $name =~ s/%%DISCOVER_NAME%%/$discover_name/;
            }
            elsif ($name =~ /%%DISCOVER_INDEX%%/)
            {
                $name =~ s/%%DISCOVER_INDEX%%/$discover_index/;
            }
            elsif ($name =~ /%%DISCOVER_INDEX_CHR%%/)
            {
                my $idx = 0;
                my $s = $discover_index;
                $s =~ s/^\d+\.//g;
                $s = pack("C*", split(/\./, $s));
                $name =~ s/%%DISCOVER_INDEX_CHR%%/$s/;
            }
            elsif ($name =~ /(%%\d+\.DISCOVER_INDEX_CHR\.\d+%%)/)
            {
                my $idx = $1;
                my $s = $discover_index;

                my $pre = $idx;
                $pre =~ s/%//g;
                $pre = [ split /\./, $pre ];

                my $pos = $pre->[2];
                $pre = $pre->[0];

                $s =~ s/^\d+\.//
                    for (1..$pre);
                $s =~ s/\.\d+$//
                    for (1..$pos);

                $s =~ s/^\d+\.//g;
                $s = pack("C*", split(/\./, $s));
                $name =~ s/$idx/$s/;
            }
            elsif ($name =~ /(%%DISCOVER_INDEX_LAST\.\d+\.\d+%%)/)
            {
                my $idx = $1;
                my $s = $discover_index;

                my $count = $idx;
                $count =~ s/%//g;
                $count = [ split /\./, $count ];
                my $offset = $count->[2];
                $count = $count->[1];

                $s =~ (/((\.\d+){$count})$/);
                $s = $1;
                $s =~ s/^\.//;

                if ($offset)
                {
                    $s =~ s/\.\d+$//
                        for (1..$offset);
                }

                $name =~ s/$idx/$s/;
            }

            my $i = $#{ $tmp->{ $discover_index } };

            while ($i > -1)
            {
                if ($name =~ /%%DISCOVER_NAME\.$i%%/)
                {
                    $name =~ s/%%DISCOVER_NAME\.$i%%/$tmp->{ $discover_index }->[$i]/;
                }
                --$i;
            }

            }
        } 

        if (defined $new->{$name} && ! $the_same_names)
        {
            ++$the_same_names;
            my $s = sprintf(qq|%s.%s|, $name, $new->{$name}->{discover_index});
            $new->{$s} = $new->{$name};
            delete $new->{$name};
       
            $name = sprintf(qq|%s.%s|, $name, $discover_index);
        }
        elsif ($the_same_names)
        {
            $name = sprintf(qq|%s.%s|, $name, $discover_index);
        }

        $new->{ $name } =
        {
            discover_name => $discover_name,
            definition_name => $definition_name,
            function => $definition->{ENTITY_ICON},
            discover_index =>  $discover_index,
        };


    }

    my $old = $self->_discover_get_existing_entities($entity, $definition_name);

    for $name (keys %$old)
    {
        next
            unless defined $new->{$name};
        next
            unless defined $new->{$name}->{discover_index};

        $old->{$name}->{entity}->params('index', $new->{$name}->{discover_index})
             if $discover_index ne '' && $new->{$name}->{discover_index} ne $old->{$name}->{index};
        $old->{$name}->{entity}->params('function', $definition->{ENTITY_ICON})
             if $old->{$name}->{function} ne $definition->{ENTITY_ICON};

        delete $new->{$name};
        delete $old->{$name};
    }

    for (keys %$new)
    {
        $self->_discover_add_new_entity($entity, $_, $new->{$_})
            if $_ ne '';
        delete $new->{$_};
    }

    log_debug(sprintf(qq|discover of %s finished|, $definition_name), _LOG_DEBUG)
        if $LogEnabled;
}

sub _discover_get_existing_entities
{   

    my $self = shift;

    my @list = $self->SUPER::_discover_get_existing_entities(@_);

    my $parent = shift;
    my $snmp_generic_definition_name = shift;

    my $result;
    my $name;

    for (@list)
    {   

        my $entity = Entity->new($self->dbh, $_);
        if (defined $entity)
        {   

            next
                unless $entity->params('snmp_generic_definition_name') eq $snmp_generic_definition_name;

            $name = $entity->name;

            $result->{ $name }->{entity} = $entity;

            my $index = $entity->params('index');
            $result->{ $name }->{index} = $index
                if defined $index;
            $result->{ $name }->{function} = $entity->params('function');
        };
    };
    return $result;
}


sub _discover_add_new_entity
{
    my ($self, $parent, $name, $new) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s %s %s|, $parent->id_entity, $name, $new->{discover_index}, $new->{definition_name}), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = {
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {
           function => $new->{function},
           index => $new->{discover_index},
           snmp_generic_definition_name => $new->{definition_name},
       },
       };

    $entity->{params}->{snmp_instance} = $parent->params('snmp_instance')
        if $parent->params('snmp_instance');

    $entity = $self->_entity_add($entity, $self->dbh);

    if (ref($entity) eq 'Entity')
    {
        #$self->dbh->exec(sprintf(qq|INSERT INTO links VALUES(%s, %s)|, $id_entity, $entity->id_entity));
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s %s %s|,
            $parent->id_entity, $entity->id_entity, $name, $new->{discover_index}, $new->{definition_name}), _LOG_INFO)
            if $LogEnabled;
    }
}



sub save_data
{       
    my $self = shift;

    my $id_entity = shift;
    
    my $data_dir = $DataDir;

    my $data = $self->data;

    my $data_value;


    my $cache = $self->cache;

    $cache = defined $cache->{$id_entity}
        ? $cache->{$id_entity}
        : undef;

    open F, ">$data_dir/$id_entity";

    if (defined $cache)
    {
        print F sprintf(qq|delta\|%s\n|, $cache->{ delta });
    }

    for my $track_name (keys %$data)
    {
        if (defined $cache->{ $track_name })
        {
            $data_value = $cache->{ $track_name }->[1];
            $data_value = ''
                if $data->{ $track_name } eq '' && ($data_value eq 'U' || $data_value eq '0');
            print F sprintf(qq|%s_absolute\|%s\n|, $track_name, $data->{ $track_name });
        }
        else
        {
            $data_value = $data->{ $track_name };
        }

        print F sprintf(qq|%s\|%s\n|, $track_name, $data_value);
    }   

    close F;
}  

sub data_value_format
{
    my $self = shift;
    my $data = shift;
    my $def = shift;
    my $track_name = shift;
    my $mask = shift;

    my $name = '';
    my $units = '';
    my $value = '';

    if (ref($def->{compute}) eq 'ARRAY')
    {
        ($value, $name, $units) = ( $self->compute($data, \@{$def->{compute}}, $mask) );
    }
    else
    {
        $value = $data->{$track_name};
    }

    $value = 'n/a'
        if $value eq '';

    return ($name, $value);
}

sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $def = $self->def->{ $entity->params('snmp_generic_definition_name') };
    $def = defined $def->{DESC}
        ? $def->{DESC}
        : undef;

    return
        unless defined $def;

    my $brief;
    for my $d (sort { $def->{$a}->{order} <=> $def->{$b}->{order} } keys %{$def})
    {
        next
            unless defined $data->{$d};
        next
            unless defined $def->{$d}->{brief} 
                && $def->{$d}->{brief};
        next
            unless $self->desc_conditions($def->{$d}, $entity);
        push @$result, sprintf(qq|%s: %s|, 
            $def->{$d}->{title}, 
            ($self->data_value_format($data, $def->{$d}, $d, $self->compute_get_mask($entity->status, 1)))[1]
            );
    }

    return $result;
} 

sub desc_conditions
{
    my $self = shift;
    my $def = shift;
    return 1
        unless defined $def->{conditions};
    my $conditions = $def->{conditions};
    my $entity = shift;
    my $data = $entity->data;
    for (keys %$conditions)
    {
        if (/^entity_name$/)
        {
            if ( $conditions->{$_}->[0] eq 'eq')
            {
                return 0
                    unless $entity->name =~ /$conditions->{$_}->[1]/;
            }
            elsif ( $conditions->{$_}->[0] eq 'ne')
            {
                return 0
                    if $entity->name =~ /$conditions->{$_}->[1]/;
            }
        }
        else
        {
            return 0
                unless defined $data->{$_};
            if ( $conditions->{$_}->[0] eq 'eq')
            {
                return 0
                    unless $data->{$_} =~ /$conditions->{$_}->[1]/;
            }
            elsif ( $conditions->{$_}->[0] eq 'ne')
            {
                return 0
                    if $data->{$_} =~ /$conditions->{$_}->[1]/;
            }
        }
    }
    return 1;
}


sub compute_get_mask
{
    my ($self, $status, $brief)  = @_;

    if ($status > _ST_OK && $status < _ST_NOSNMP)
    {
        return $brief
            ? _MODE_BRIEF_BAD
            : _MODE_FULL_BAD;
    } 
    else
    {
        return $brief
            ? _MODE_BRIEF_OK
            : _MODE_FULL_OK;
    }
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    my $def = $self->def->{ $entity->params('snmp_generic_definition_name') };
    $def = defined $def->{DESC}
        ? $def->{DESC}
        : undef;

    return
        unless defined $def;

    my ($name, $value);

    for my $d (sort { $def->{$a}->{order} <=> $def->{$b}->{order} } keys %{$def})
    {
        if ($d =~ /^hr\d+$/)
        {
            $table->addRow('');
            next;
        }

        next
            unless defined $data->{$d};
        next
            unless $self->desc_conditions($def->{$d}, $entity);

        ($name, $value) = $self->data_value_format($data, $def->{$d}, $d, $self->compute_get_mask($entity->status, 0));
        $table->addRow($name ? $name : $def->{$d}->{title}, $value);
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
    return ($_[0]->rrd_config, $_[0]->rrd_data);
}

sub menu_stat
{ 
    my $self = shift;
    return 1
        unless @_;
    my $entity = shift;
    my $def = $self->def->{ $entity->params('snmp_generic_definition_name') };
    return 0
        unless defined $def && defined $def->{GRAPHS};

    return @{$def->{GRAPHS}} > 0
        ? 1
        : 0;
}   

sub stat
{       
    my $self = shift;
    my $table = shift;
    my $entity = shift;
    my $url_params = shift;
    my $default_only = defined @_ ? shift : 0;

    my $cgi = CGI->new();
    
    my $def = $self->def->{ $entity->params('snmp_generic_definition_name') };
    return 
        unless defined $def && defined $def->{GRAPHS};

    my $url;
    $url_params->{probe} = 'snmp_generic';

    my $i = -1;

    for (@{$def->{GRAPHS}})
    {
        ++$i;
        next
            unless $self->desc_conditions($_, $entity);
        next
            if $default_only && (! defined $_->{default} || ! $_->{default});

        $url_params->{probe_prepare_ds} = 'prepare_ds_graph';
        $url_params->{probe_specific} = $i;
        $table->addRow( $self->stat_cell_content($cgi, $url_params) );
    }
}           
    
sub prepare_ds_graph_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $entity = $rrd_graph->entity;

    my $url_params = $rrd_graph->url_params;

    my $def = $self->def->{ $entity->params('snmp_generic_definition_name') };
    return 
        unless defined $def 
        && defined $def->{GRAPHS}
        && defined $def->{GRAPHS}->[ $url_params->{probe_specific} ];

    my $d = $def->{GRAPHS}->[ $url_params->{probe_specific} ];

    if (ref($d->{title}) eq 'ARRAY')
    {
        my ($value, $name, $units) = ( $self->compute($entity->data, \@{$d->{title}}, _MODE_ALL ));
        $rrd_graph->unit( $units ? $units : $d->{units} );
        $rrd_graph->title( $name ? $name : $d->{tracks}->[0]->{name} );
    }
    else
    {
        $rrd_graph->unit( $d->{units} );
        $rrd_graph->title( $d->{title} );
    }
}

sub prepare_ds_graph
{
    my $self = shift;
    my $rrd_graph = shift;
    my $cf = shift;

    my $entity = $rrd_graph->entity;

    my $url_params = $rrd_graph->url_params;

    my $def = $self->def->{ $entity->params('snmp_generic_definition_name') };
    return
        unless defined $def 
        && defined $def->{GRAPHS}
        && defined $def->{GRAPHS}->[ $url_params->{probe_specific} ];

    my $d = $def->{GRAPHS}->[ $url_params->{probe_specific} ];

    return
        unless defined $d->{tracks} && ref($d->{tracks}) eq 'ARRAY';

    $d = $d->{tracks};

    my $args = $rrd_graph->args;
    
    my $rrd_file = sprintf(qq|%s/%s.%s|, $RRDDir, $entity->id_entity, $url_params->{probe});
    
    my $up = 1;
    my $down = 0;

    my $i = -1;
    for (@$d)
    {
        ++$i;
        push @$args, sprintf(qq|DEF:ds%s=%s:%s:%s|, $i, $rrd_file, $_->{name}, $cf);
        if (defined $_->{cdef})
        {
            $_->{cdef} =~ s/%%DS_NAME%%/ds$i/g;
            push @$args, sprintf(qq|CDEF:ds%sc=%s|, $i, $_->{cdef});
            push @$args, sprintf(qq|%s:ds%sc#%s:%s|, $_->{style}, $i, $_->{color}, $_->{title});
        }
        else
        {
            push @$args, sprintf(qq|%s:ds%s#%s:%s|, $_->{style}, $i, $_->{color}, $_->{title});
        }
    }

    return ($up, $down, "ds$i");
}

sub snmp
{
    return 1;
}

1;
