package Probe::tcp_generic;

use vars qw($VERSION);

$VERSION = 0.4;

use base qw(Probe);
use strict;

use IO::Socket qw(:DEFAULT :crlf);

use Time::HiRes qw(gettimeofday tv_interval);
use IPC::Open3;
use File::Spec;
use Symbol qw(gensym);

use Constants;
use Configuration;
use Log;
use Entity;
use URLRewriter;

use RRDGraph;

our $DataDir = CFG->{Probe}->{DataDir};
our $LogEnabled = CFG->{LogEnabled};
our $Table = CFG->{Probes}->{tcp_generic}->{Table};
our $IgnoreMode = CFG->{Probes}->{tcp_generic}->{IgnoreMode};
our $ThresholdMediumDefault = CFG->{Probes}->{dns_server}->{ThresholdMediumDefault};
our $ThresholdHighDefault = CFG->{Probes}->{dns_server}->{ThresholdHighDefault};

our $GotTimeout;

$|=1;

use constant 
{
    RRD_RESULT => 10,
    TCP_SCRIPT => 11,
    CHAT => 12,
};

sub id_probe_type
{
    return 2;
}

sub name
{
    return 'TCP socket';
}


sub snmp
{
    return 0;
}

sub mandatory_fields
{
    return
    [   
        'port',
    ]
}

sub chat
{   
    return $_[0]->[CHAT];
}

sub manual
{   
    return 1;
}

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    
    $self->[TCP_SCRIPT] = [];
        
    return $self;
}

sub clear_data
{
    my $self = shift;
    $self->[TCP_SCRIPT] = [];
    $self->[RRD_RESULT] = undef;
    $self->[CHAT] = [];
};

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);

    $self->clear_data;
    my $entity = shift;

    my ($t0, $t1, $session);

    my $ip = $entity->params('ip');
    throw EEntityMissingParameter('ip')
        unless $ip;

    my $port = $entity->params('port');
    throw EEntityMissingParameter('port')
        unless $port;

    my $timeout = $entity->params('timeout');
    $timeout = 3
        unless defined $timeout;

    $self->threshold_high($entity->params('threshold_high') || $ThresholdHighDefault);
    $self->threshold_medium($entity->params('threshold_medium') || $ThresholdMediumDefault);

    $self->tcp_script($entity->params('tcp_generic_script'));

    $t0 = [gettimeofday];

    $session = new IO::Socket::INET(PeerAddr=>$ip, PeerPort=>$port, Timeout => $timeout, Proto => 'tcp');

    if (! defined $session)
    {
        $self->errmsg('unable to open TCP session: ' . $@);
        $self->status(_ST_DOWN);
    }
    else
    {
        $self->script_play($session, $timeout);
    }

    $session->close unless ! $session;

    $t1 = [gettimeofday];

    $t0 = tv_interval($t0, $t1);

    my $status = $self->status;

    if ($status == _ST_OK && $t0 > $self->threshold_high ) 
    {
        $self->errmsg("threshold high exceeded; answer too long");
        $self->status(_ST_MINOR);
    }
    elsif ($status == _ST_OK && $t0 > $self->threshold_medium ) 
    {
        $self->errmsg("threshold medium exceeded; answer too long");
        $self->status(_ST_WARNING);
    }

    $self->rrd_result($t0)
        if $self->status < _ST_DOWN;

    my $id_entity = $entity->id_entity;
    $self->rrd_save($id_entity, $self->status)
        if $self->status < _ST_DOWN;
    $self->save_data($id_entity, $t0);
}

sub tcp_script
{
    my $self = shift;

    if (@_ && defined $_[0])
    {
        my $script = shift;
        my @scr;
        for (split /\|\|/, $script)
        {
            @scr = split /::/, $_, 2;
            last
                if @scr < 2;
            if ($scr[0] ne 'send' && $scr[0] ne 'wait')
            {
                log_debug(sprintf(qq|bad tcp_script: %s|, $script), _LOG_WARNING);
                last;
            }
            push @{$self->[TCP_SCRIPT]}, [@scr]
                if @scr;
        }
    }
    return $self->[TCP_SCRIPT];
}

sub cmd_dispatch
{
    my $self = shift;
    my $result = shift;

    $result =~ s/\%NL\%/$CRLF/g;

    return $result;
}

sub waitfor
{   
    my $self = shift;
    my $session = shift;
    my $str = shift;
    my $chat = $self->chat;
 
    my $result = '';
    while (<$session>)
    {
#        s/$CRLF/\n/g;
        push @$chat, "<$_";
        $result = $_;
        return (0, '')
            if $_ =~ /$str/i;
    }
    return (1, $result);
}   

sub timeout
{
    $GotTimeout = 1;
}
        
sub script_play
{       
    my $self = shift;
    my $session = shift;
    my $timeout = shift;

    my $chat = $self->chat;
            
    my $script = $self->tcp_script;
                
    return  
        unless @$script;
                
    my $error;
    my $err;    
    my $scr_result;
    my $cmd;
    
    local $SIG{ALRM} = \&timeout;
    $GotTimeout = 0;
    alarm $timeout;
#wieszac sie na alarmie, bo nie ma evala, bo eval nie przechodzi przez wyjatki ;/ trzeba to zmienic.
    for my $line (@$script)
    {
        if ($line->[0] eq 'wait')
        {
            #$/ = CRLF;
            ($err, $scr_result) = $self->waitfor($session, $line->[1]);
            #$/ = "\n";
            if ($err)
            {
                $error = sprintf(qq|regexp /%s/i not found; last recived line: %s|, $line->[1], $scr_result);
                last;
            };
        }
        elsif ($line->[0] eq 'send')
        {
            $cmd = $self->cmd_dispatch($line->[1]);
            push @$chat, ">$cmd";
            print $session $cmd;
        }
    }
    alarm 0;

    if ($error)
    {
        $self->errmsg(sprintf(qq|script play error: %s|, $error));
        $self->status(_ST_DOWN);
    }
    elsif ($GotTimeout)
    {
        $self->errmsg(qq|script play error: timeout|);
        $self->status(_ST_DOWN);
    }

}

sub rrd_result
{
    my $self = shift;

    if (@_)
    {
        $self->[RRD_RESULT] = shift;
    }
    
    return
    {   
        'tcp_open_time' => defined $self->[RRD_RESULT] ? $self->[RRD_RESULT] : 'U',
    };
}

sub rrd_config
{   
    return
    {   
        'tcp_open_time' => 'GAUGE',
    };
}

sub discover 
{
    my $self = shift;
    $self->SUPER::discover(@_);
    my $entity = shift;

    my $cmd = CFG->{Probes}->{'tcp_generic'}->{nmap};
    $cmd .= "," . join(",", @$Table)
        if $IgnoreMode && @$Table > 0;
    $cmd .= " " . $entity->params('ip');

    open(NULL, ">", File::Spec->devnull);
    my $pid = open3(gensym, \*PH, ">&NULL", $cmd);
    my @result = <PH>;

    waitpid($pid, 0);
    close NULL;

    shift @result
        until $result[0] =~ /^Port/i || ! $#result;

    if (@result && $#result < 33)
    {
        my $discovered_ports;
        shift @result;

        my $existing_entities = $self->_discover_get_existing_entities($entity);

        my $ignore;

        for (@result)
        {
            $ignore = $IgnoreMode;
            last if /^\n/;
            $discovered_ports = [split /\s+/, $_];
            next if $discovered_ports->[1] ne 'open';
            $discovered_ports->[0] = (split /\//, $discovered_ports->[0])[0];

            for (@$Table)
            {
                $ignore = ! $ignore
                    if $_ eq $discovered_ports->[0];
            }

            if (defined $existing_entities->{ $discovered_ports->[0] } && ! $ignore)
            {
                next
                    if ($existing_entities->{ $discovered_ports->[0] }->params('tcp_generic_service_name') eq $discovered_ports->[2]);

                log_debug(sprintf(qq|entity %s: tcp_generic_service_name change from: %s to: %s|,
                    $existing_entities->{ $discovered_ports->[0] }->id_entity,
                    $existing_entities->{ $discovered_ports->[0] }->params('tcp_generic_service_name'),
                    $discovered_ports->[2]), _LOG_DEBUG)
                    if $LogEnabled;

                $existing_entities->{ $discovered_ports->[0] }->params('tcp_generic_service_name', $discovered_ports->[2] );
                $existing_entities->{ $discovered_ports->[0] }->db_update_entity;
            }
            elsif (! $ignore)
            {
                $self->_discover_add_new_entity($entity, $discovered_ports);
            }
            else
            {
                log_debug(sprintf(qq|discovered port %s: ignored because of the configuration (akkada.conf)|,
                    $discovered_ports->[0]), _LOG_DEBUG)
                    if $LogEnabled;
            }
        }
    }
    elsif (@result && $#result > 32)
    {
        log_debug(sprintf(qq|entity %s: discovered %s open ports. probably fake from firewall. all ports ignored. try to add manualy interesting ports.|, $entity->id_entity, scalar @result), _LOG_WARNING)
            if $LogEnabled;
    }
    else 
    {
        log_debug(sprintf(qq|entity %s: no open tcp ports discovered|, $entity->id_entity), _LOG_INFO)
            if $LogEnabled;
    }
}

sub _discover_add_new_entity
{
    my ($self, $parent, $new) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s/%s|, $parent->id_entity, $new->[0], $new->[2]), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = $self->_entity_add({
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $new->[2],
       params => {
           port => $new->[0],
           tcp_generic_service_name => $new->[2],
       },
       }, $self->dbh);

    if (ref($entity) eq 'Entity')
    {
        #$self->dbh->exec(sprintf(qq|INSERT INTO links VALUES(%s, %s)|, $id_entity, $entity->id_entity));
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s/%s|, 
            $parent->id_entity, $entity->id_entity, $new->[0], $new->[2]), _LOG_INFO)
            if $LogEnabled;
    }
}

sub _discover_get_existing_entities
{

    my $self = shift;

    my @list = $self->SUPER::_discover_get_existing_entities(@_);

    my $result;
    my $port;

    for (@list)
    {   
        my $entity = Entity->new($self->dbh, $_);                                   
        if (defined $entity)
        {
            $port = $entity->params('port');
            if ( $port )
            {
                $result-> { $port } = $entity;
            }
            else
            {
                throw EEntityMissingParameter('port');
            }
        };
    };
    return $result;
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;

    my $time = shift;

    my $data_dir = $DataDir;

    open F, ">$data_dir/$id_entity";

    print F sprintf(qq|duration\|%s|, $time);

    close F;

    my $chat = $self->chat;
   
    return
        unless @$chat;

    open F, ">$data_dir/$id_entity.chat"; 
    print F @$chat;
    close F;
}


sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    push @$result, sprintf(qq|port tcp/%d|, $entity->params('port'));

    if (defined $data->{duration})
    {   
        push @$result, sprintf(qq|duration: %s sec|, $data->{duration});
    }
    else
    {   
        push @$result, qq|duration: n/a|;
    }

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity, $url_params) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    $table->addRow('port', sprintf(qq|tcp/%d|, $entity->params('port')));

    my $data = $entity->params('tcp_generic_script');

    if ($data)
    {
        use Window::Buttons;
        my $buttons = Window::Buttons->new();
        $buttons->button_refresh(0);
        $buttons->button_back(0);
        $buttons->add({ caption => '-= show result =-', target => $entity->id_entity,
            url => url_get({ id_entity => $entity->id_entity, section => 'utils', id_probe_type => $self->id_probe_type, form_id => 1 }, $url_params)});
        $table->addRow('script', $data, $buttons->get);
    }

    $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    $table->addRow('duration', sprintf(qq|%s sec|, $data->{duration}));

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

   #$result .= "&nbsp;[SCRIPT]"
   #     if $entity->params('tcp_generic_script');

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
    $url_params->{probe} = 'tcp_generic';
    $url_params->{probe_prepare_ds} = 'prepare_ds';
    $url_params->{probe_specific} = 'tcp_open_time';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;

    my $entity = $rrd_graph->entity;
    my $url_params = $rrd_graph->url_params;

    my $args = $rrd_graph->args;

    my $begin = $rrd_graph->begin;
    my $end = $rrd_graph->end;

    $rrd_graph->title(sprintf(qq|%s [%s-%s]|, $entity->name, $begin, $end));
    $rrd_graph->unit('sec');

    push @$args, 'COMMENT:\n';
    push @$args, 'COMMENT:open socket duration\n';

}

1;
