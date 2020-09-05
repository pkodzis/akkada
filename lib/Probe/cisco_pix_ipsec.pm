package Probe::cisco_pix_ipsec;

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
use Net::SSH::Perl;
use Data::Dumper;

our $DataDir = CFG->{Probe}->{DataDir};
our $LogEnabled = CFG->{LogEnabled};

$|=1;


use constant
{
    DATA => 10,
};

sub name
{
    return 'IPSec tunnel';
}

sub id_probe_type
{
    return 27;
}

sub snmp
{
    return 0;
}

sub clear_data
{
    my $self = shift;
    $self->[DATA] = {};
};

sub data
{
    return $_[0]->[DATA];
}

sub manual
{
    return 1;
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

    $self->clear_data;
    my $entity = shift;

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

    my $result = $self->get_data($ip, $username, $password, $enable);
#log_debug($result, _LOG_ERROR);
    if (! defined $result || ! $result)
    {
        $self->errmsg("service missconfigured. cannot get data from device.");
        $self->status(_ST_BAD_CONF);
    }
    else
    {
        $self->result_dispatch($result);
        $self->utilization_status($entity)
            if $self->status != _ST_BAD_CONF;
    }
    $self->rrd_save($entity->id_entity, $self->status);
    $self->save_data($entity->id_entity);
}

sub rrd_result
{
    my $data = $_[0]->data;

    return
    {
        'ok' => defined $data->{ok} ? $data->{ok} : 'U',
        'bad' => defined $data->{bad} ? $data->{bad} : 'U',
    };
}

sub rrd_config
{
    return
    {
        'ok' => 'GAUGE',
        'bad' => 'GAUGE',
    };
}


sub utilization_status
{
    my $self = shift;
    my $entity = shift;
    my $data = $self->data;

    my $p = {};
    my @tmp;

    $data->{ok} = 0;
    $data->{bad} = 0;

    my $s = $entity->params('cisco_pix_ipsec_names') || '';
    for ((split /\|\|/, $s))
    {
        @tmp = split /::/, $_;
        $p->{$tmp[0]}->{name} = $tmp[1];
    }

    $s = $entity->params('cisco_pix_ipsec_alarm_down') || '';
    for ((split /\|\|/, $s))
    {
        $p->{$_}->{alarm_down} = 0;
    }

    $s = $entity->params('cisco_pix_ipsec_dont_alarm_wrong_state') || '';
    for ((split /\|\|/, $s))
    {
        $p->{$_}->{dont_alarm_wrong_state} = 1;
    }
#log_debug(Dumper($p), _LOG_ERROR);

    for my $conn (@{$data->{conns}})
    {
        $s = 'unknown';
        if (defined $p->{$conn->[0]} && $p->{$conn->[0]}->{name})
        {
            $s = $p->{$conn->[0]}->{name};
        }
        elsif (defined $p->{$conn->[1]} && $p->{$conn->[1]}->{name})
        {
            $s = $p->{$conn->[1]}->{name};
        }
        $conn->[5] = $s;

        ++$p->{$conn->[0]}->{alarm_down}
            if defined $p->{$conn->[0]} && defined $p->{$conn->[0]}->{alarm_down};
        ++$p->{$conn->[1]}->{alarm_down}
            if defined $p->{$conn->[1]} && defined $p->{$conn->[1]}->{alarm_down};

        if ($conn->[2] ne 'QM_IDLE')
        {
            ++$data->{bad};
            if (! (defined $p->{all} && ! defined $p->{all}->{dont_alarm_wrong_state})
                && ! ( defined $p->{$conn->[0]} && defined $p->{$conn->[0]}->{dont_alarm_wrong_state} )
                && ! ( defined $p->{$conn->[1]} && defined $p->{$conn->[1]}->{dont_alarm_wrong_state} ))
            {
                $conn->[6] = 1;
                $self->errmsg(sprintf(qq|tunnel %s SA state %s|, $s, $conn->[2]));
                $self->status(_ST_MAJOR);
            }
            else
            {
                $conn->[6] = 0
            }
        }
        else
        {
            ++$data->{ok};
        }
    }

    if ($data->{failover} eq 'active')
    {
        for (keys %$p)
        {
            next
                unless defined $p->{$_}->{alarm_down};
            next
                if $p->{$_}->{alarm_down};
            $self->errmsg(sprintf(qq|tunnel %s down|, $_, defined $p->{$_}->{name} ? $p->{$_}->{name} : "unknown")); 
            $self->status(_ST_DOWN);
        }
    }
    elsif ($data->{failover} eq 'standby' && @{$data->{conns}})
    {
        $self->errmsg("established SA sessions on standby firewall");
        $self->status(_ST_MINOR);
    }
#log_debug(Dumper($data), _LOG_ERROR);
}

sub result_dispatch
{
    my $self = shift;
    my $result = shift;

    if ($result =~ /Permission denied/)
    {
        $self->errmsg("SSH bad username or password");
        $self->status(_ST_BAD_CONF);
        return;
    }
    elsif ($result =~ /Access denied/)
    {
        $self->errmsg("bad enable password");
        $self->status(_ST_BAD_CONF);
        return;
    }

    $result =~ s/\r//g;

    my $flag = 0;
    my $data = $self->data;

    $data->{failover} = 'unknown';
    $data->{conns} = [];

    for ((split /\n/, $result))
    {
        if (/This host/)
        {
             if (/Standby/)
             {
                 $data->{failover} = "standby";
             }
             elsif (/Active/)
             {
                 $data->{failover} = "active";
             }
        }
        elsif (/dst/ && /src/)
        {
            $flag = 1;
            next;
        }

        next
            unless $flag;

        last
            if /#/;

        s/^ +//g;
        s/ +/ /g;

        push @{$data->{conns}}, [ split / /, $_ ];
    }
#log_debug(Dumper($data), _LOG_ERROR);
}

sub get_data
{
    my $self = shift;
    my $ip = shift;
    my $username = shift;
    my $password = shift;
    my $enable = shift;

    my ($stdout, $stderr, $exit, $session);

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
        ($stdout, $stderr, $exit) = $session->cmd($cmd, sprintf(qq|\n%s\n sh failover \| in This host\nshow crypto isakmp sa\nq\n|, $enable));
    };

    return $@
        if $@;
    return $stderr
        if $stderr;

    return $stdout;
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

sub save_data
{
    my $self = shift;

    my $id_entity = shift;
    
    my $data_dir = $DataDir;
    my $data = $self->data;

    open F, ">$data_dir/$id_entity";
   
    print F "failover\|$data->{failover}\n";
 
    my $h = $data->{conns};
    my $i = 0;
    for (@$h)
    {   
        print F sprintf(qq|tunnel%d\|%s\n|, $i, join("::", @$_));
        ++$i;
    }
    
    close F;
}

sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    for (grep {/^tunnel/} keys %$data)
    {
        $data->{$_} = [ split /::/, $data->{$_} ];
    }

    push @$result, sprintf(qq|failover: %s|, $data->{failover})
        if defined $data->{failover};
    push @$result, sprintf(qq|number of SA sessions: %s/%s (ok/bad) |, 
        (scalar grep { /^tunnel/ } keys %$data),
        (scalar grep { /1/ } map { $data->{$_}->[6] } grep { /^tunnel/ } keys %$data) );

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity, $url_params) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    my @tu;
    for (grep {/^tunnel/} keys %$data)
    {
        push @tu, [ split /::/, $data->{$_} ];
    }

    $table->addRow("failover", $data->{failover})
        if defined $data->{failover};
    $table->addRow("number of SA sessions", sprintf(qq|%s/%s (ok/bad)|, 
                                                (scalar @tu),
                                                (scalar grep { /1/ } map { $_->[6] } @tu)
                                            )
                  );
    if (@tu)
    {
        my $t = HTML::Table->new(-border=>1, -spacing=>0);
        $t = table_begin('', 6, $t);
        $t->addRow ( "<b>name</b>", "<b>dst</b>", "<b>src</b>", "<b>state</b>", "<b>pending</b>", "<b>created</b>",); 

        for my $i (0..$#tu)
        {
            $t->addRow($tu[$i]->[5], $tu[$i]->[0], $tu[$i]->[1], $tu[$i]->[2], $tu[$i]->[3], $tu[$i]->[4]);
            $t->setRowClass($t->getTableRows, "g")
                if $tu[$i]->[6];
        }
        $table->addRow($t->getTable);
    }
    else
    {
        $table->addRow("no established SA sessions");
    }
    $table->setCellColSpan($table->getTableRows, 1, 2);
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

    my $cgi = CGI->new();

    my $url;
    $url_params->{probe} = 'cisco_pix_ipsec';

    $url_params->{probe_prepare_ds} = 'prepare_ds_ob';
    $url_params->{probe_specific} = 'ok';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

}

sub prepare_ds_ob_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    $rrd_graph->unit('no');
    $rrd_graph->title('SA sessions status');
}

sub prepare_ds_ob
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

    push @$args, "DEF:ds0a=$rrd_file:ok:$cf";
    push @$args, "DEF:ds0s=$rrd_file:bad:$cf";
    push @$args, "AREA:ds0s#FF0000:bad state";
    push @$args, "LINE2:ds0a#00FF00:QM_IDLE state";

    return ($up, $down, "ds0a");
}

1;
