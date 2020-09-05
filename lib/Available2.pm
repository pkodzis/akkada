package Available2;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;

use IPC::Open3;
use File::Spec;
use Symbol qw(gensym);
use Graph::Undirected;
use Graph::Easy;
use NetAddr::IP;
use Digest::MD5 qw(md5_hex);
use Data::Dumper;

use Common;
use Entity;
use Configuration;
use Constants;
use DB;
use Log;
use MyException qw(:try);

use constant
{
    DBH => 0,
    NETS => 1,
    HOSTS => 2,
    GRAPH => 3,
    UNREACHABLES => 4,
    VX_2_DOWNS => 5,
    IPS => 6,
    IP_EDGES => 7,
    IP_EDGES_TMP => 8,
    MYIPS => 9,
    CHECKING_FLAGS => 10,
};

our $LogEnabled;
our $FlagsControlDir;
our $FPing;
our $Period;
our $PingCount;
our $GraphDebug;
our $GraphDebugPath;
our $CorrelationsDir;
our $UseTestData;
our $LowLevelDebug;
our $ifconfig;
our $ifconfig_addr;
our $ifconfig_mask;
our $CheckingFlagsDir;
our $DOTranksep;
our $DOT;
our $FlagsUnreachableDir;
our $Probes;
our $ProbesMapRev;
our $DisabledIPAddr;
our $PreferredNetworks;
our $NetDesc;


our $CORRELATIONS = {};

sub cfg_init
{
    Configuration->reload_cfg;

    $LogEnabled = CFG->{LogEnabled};
    $FlagsControlDir = CFG->{FlagsControlDir};
    $FPing = CFG->{Available2}->{fping};
    $Period = CFG->{Available2}->{Period};
    $PingCount = CFG->{Available2}->{PingCount};
    $GraphDebug = CFG->{Available2}->{GraphDebug};
    $GraphDebugPath = CFG->{Available2}->{GraphDebugPath};
    $UseTestData = CFG->{Available2}->{UseTestData};
    $LowLevelDebug = CFG->{Available2}->{LowLevelDebug};
    $ifconfig = CFG->{Available2}->{ifconfig};
    $ifconfig_addr = CFG->{Available2}->{ifconfig_addr};
    $ifconfig_mask = CFG->{Available2}->{ifconfig_mask};
    $CheckingFlagsDir = CFG->{Available2}->{CheckingFlagsDir};
    $CorrelationsDir = CFG->{Probe}->{CorrelationsDir};
    $DOTranksep = CFG->{Available2}->{DOTranksep};
    $DOT = CFG->{Available2}->{DOT};
    $FlagsUnreachableDir = CFG->{FlagsUnreachableDir};
    $Probes = CFG->{Probes};
    $ProbesMapRev = CFG->{ProbesMapRev};
    $DisabledIPAddr = CFG->{Available2}->{DisabledIPAddr};
    $PreferredNetworks = CFG->{Available2}->{PreferredNetworks};
    $NetDesc = CFG->{Available2}->{NetDesc};

    log_debug("configuration initialized", _LOG_WARNING)
        if $LogEnabled;
};

sub new
{
    cfg_init();

    my $this = shift;
    my $class = ref($this) || $this;
    my $self = [];

    $self->[DBH] = DB->new();

    bless $self, $class;

    ! $UseTestData
        ? $self->get_my_ips_real
        : $self->get_my_ips_test;

    $SIG{USR1} = \&got_sig_usr1;
    $SIG{USR2} = \&got_sig_usr2;
    $SIG{HUP} = \&cfg_init;

    correlations_clear();

    $self->init_remove_unreachable_states;

    return $self;
}

sub dbh
{
    return $_[0]->[DBH];
}

sub ip_edges
{
    return $_[0]->[IP_EDGES];
}

sub myips
{
    return $_[0]->[MYIPS];
}

sub checking_flags
{
    return $_[0]->[CHECKING_FLAGS];
}

sub ips
{
    return $_[0]->[IPS];
}

sub nets
{
    return $_[0]->[NETS];
}

sub hosts
{
    return $_[0]->[HOSTS];
}

sub graph
{
    $_[0]->[GRAPH];
}

sub unreachables
{
    $_[0]->[UNREACHABLES];
}

sub correlations
{
    return $CORRELATIONS;
}

sub vx_2_downs
{
    $_[0]->[VX_2_DOWNS];
}

sub checking_flags_load
{
#
# flag postaci ip:1.1.1.1-24:0:1 lub ip:1.1.1.1-null:1234:4
# jesli flagi nie ma tzn, ip jest sprawdzane pierwszy raz i jesli 
# nie odpowiada na pingi to nie jest testowane - ustawiany 
# jest status _A_STATIC_OK
# 
# jesli flaga jest to pobierany jest status _A_STATIC_OK albo _A_OK - inne nie powinny wystepowac
# _A_INIT jest ustawiany w pamieci przez procedure set_ip_statuses jestli nie istnieje plik flagowy

    my $self = shift;

    my $file;
    my $result = {};

    opendir(DIR, $CheckingFlagsDir)
        or log_exception( EFileSystem->new($!), _LOG_ERROR);

    my ($ip, $status);

    while (defined($file = readdir(DIR)))
    {
        next
            unless $file =~ /^(ip:.*-.*:.*):(.*)/;
        $ip = $1;
        $status = $2;

        if ($status != _A_OK && $status != _A_STATIC_OK)
        {
            unlink "$CheckingFlagsDir/$file";
            log_debug("flag file $file is damaged. deleted", _LOG_WARNING)
                if $LogEnabled;
            next;
        }
       
        $ip =~ /-null/
            ? $ip =~ s/-null//g
            : $ip =~ s/-/\//g;

        $result->{$ip} = $status;
    }

    closedir DIR;

    $self->[CHECKING_FLAGS] = $result;
}

sub get_my_ips_test
{
    my $self = shift;

    my $ips = {};
    my @s;

    open F, "/tmp/av2_myips";
    while (<F>)
    {
        s/\n//g;
        @s = split / /, $_;
        $ips->{$s[0]} = $s[1];
    }
    close F;

    if (! keys %$ips)
    {
        log_debug("get_my_ips_test: unable to detect akkada's own ip addresses", _LOG_ERROR);
        exit;
    }

    $self->[MYIPS] = $ips;
}

sub get_my_ips_real
{
    my $self = shift;

    my $ips = {};
    my $ip;

    for (grep { /$ifconfig_addr/ } `$ifconfig`)
    {
        /$ifconfig_addr(\S+)/;
        $ip = $1;

        /$ifconfig_mask(\S+)/;
        $ips->{$ip} = $1;
    }

    if (! keys %$ips)
    {
        log_debug("get_my_ips_real: unable to detect akkada's own ip addresses", _LOG_ERROR);
        exit;
    }

    $self->[MYIPS] = $ips;
}

sub init_remove_unreachable_states
{
    my $self = shift;

    my $dbh = $self->dbh;

    my $req = $self->dbh->exec(qq|SELECT id_entity FROM entities where id_probe_type<2 and status=6|)->fetchall_arrayref();

    my $entity;

    for (@$req)
    {
        $entity = Entity->new($dbh, $_->[0]);

        if (defined $Probes->{ $ProbesMapRev->{ $entity->id_probe_type } }->{not_tested})
        {
            $entity->set_status(_ST_OK, '');
        }
        else
        {
            $entity->set_status(_ST_UNKNOWN, '');
        }

        if (flag_file_check($FlagsUnreachableDir, $_->[0], 1))
        {
            flag_files_create_ow($FlagsUnreachableDir, sprintf(qq|%s.last|, $_->[0]));
            log_debug(sprintf(qq|entity %s unreachable flag deleted!|, $_->[0]), _LOG_INFO);
        }
    }
}

sub load_ips_real
{
    my $self = shift;

    my $nets = $self->nets;
    my $hosts = $self->hosts;
    my $ips = $self->ips;
    my $myips = $self->myips;

    my $db = $self->dbh;

    #LOAD ip AND hosts
    my $req = $self->dbh->exec(qq|SELECT entities.id_entity,value FROM entities,entities_2_parameters,parameters
        WHERE entities.id_entity=entities_2_parameters.id_entity
        AND entities_2_parameters.id_parameter=parameters.id_parameter
        AND parameters.name='ip'
        AND monitor=1
        AND entities.id_entity NOT IN (SELECT id_entity FROM entities_2_parameters,parameters
        WHERE parameters.id_parameter=entities_2_parameters.id_parameter
        AND parameters.name='availability_check_disable')|)->fetchall_arrayref();

    for (@$req)
    {
        next
            if defined $myips->{$_->[1]};

        if (! defined $hosts->{$_->[0]})
        {
            $hosts->{$_->[0]}->{ips} = {};
            $hosts->{$_->[0]}->{fwd} = _FWD_UNKNOWN;
            $hosts->{$_->[0]}->{status} = _A_OK;
        }

        next
            if defined $DisabledIPAddr->{$_->[1]};

        $hosts->{$_->[0]}->{ips}->{$_->[1]} = 
        { 
            ip => $_->[1], 
            id => $_->[0],
            primary => _IP_PRIMARY,
            status => _A_INIT,
        };
        $ips->{$_->[1]}->{$_->[0]} = $_->[0];
    }

    #LOAD ip_forwarding
    $req = $self->dbh->exec(qq|SELECT entities.id_entity,value FROM entities,entities_2_parameters,parameters
        WHERE entities.id_entity=entities_2_parameters.id_entity
        AND entities_2_parameters.id_parameter=parameters.id_parameter
        AND parameters.name='ip_forwarding'|)->fetchall_arrayref();
    for (@$req)
    {
        next
            unless defined $hosts->{$_->[0]};
        $hosts->{$_->[0]}->{fwd} = $_->[1];
    };

    #LOAD links
    my $links = $db->dbh->selectall_hashref("select * from links", "id_child");

    #LOAD ip_addresses
    $req = $self->dbh->exec(qq|SELECT entities.id_entity,value FROM entities,entities_2_parameters,parameters
        WHERE entities.id_entity=entities_2_parameters.id_entity
        AND entities_2_parameters.id_parameter=parameters.id_parameter
        AND parameters.name='ip_addresses'|)->fetchall_arrayref();

    my ($id_entity, $id_parent, @s, $net);
    for (@$req)
    {
        next
            unless defined $links->{$_->[0]} && defined $hosts->{$links->{$_->[0]}->{id_parent}};


        $id_entity = $_->[0];
        $id_parent = $links->{$_->[0]}->{id_parent};

        for (split /#/, $_->[1])
        {
            @s = split /:/, $_;
            next
                if @s < 3
                || $s[0] =~ /^127/
                || $s[0] =~ /^169\.254\./
                || $s[0] =~ /^0\./
                || $s[1] =~ /^0\./;

            next
                if defined $myips->{$s[0]};

            next
                if defined $DisabledIPAddr->{$s[0]};

            if (defined $hosts->{$id_parent}->{ips}->{$s[0]})
            {
                delete $hosts->{$id_parent}->{ips}->{$s[0]};
                delete $ips->{$s[0]}->{$id_parent}; #kasuje ip, ktore pojawilo sie po zaladowaniu hostow w pierwszym etapie wczesniej
                delete $ips->{$s[0]}
                    unless keys %{$ips->{$s[0]}};
            }

            $s[0] = NetAddr::IP->new($s[0], $s[1])
                if $s[1];

            $hosts->{$id_parent}->{ips}->{scalar $s[0]} =
            {
                ip => $s[0],
                id => $id_entity,
                primary => defined $s[2] ? $s[2] : 0,
                status => _A_OK,
            };

            $ips->{$s[0]}->{$id_entity} = $id_parent;

            $net = ref($s[0]) eq 'NetAddr::IP' ? $s[0]->network : '';

            if ($net)
            {
                $nets->{ $net }->{addr} = NetAddr::IP->new($net)
                    unless defined $nets->{ $net };
                $nets->{ $net }->{routers} += 1
                    if $hosts->{$id_parent}->{fwd} == _FWD_YES;
            }
        }
    }

    #removing hosts without ip addresses
    for (keys %$hosts)
    {
        delete $hosts->{$_}
            unless keys %{$hosts->{$_}->{ips}};
    }

    log_debug("hosts: " . Dumper($hosts), _LOG_ERROR)
        if $LowLevelDebug;
}

sub load_ips_test
{
    my $self = shift;

    my $nets = $self->nets;
    my $hosts = $self->hosts;
    my $ips = $self->ips;
    my $myips = $self->myips;

    my (@s, $ip, $net);
    open F, $UseTestData;
    while (<F>)
    {
        next
            if /^#/;
        s/\n//g;   
        s/ +/ /g;   
        @s = split / /, $_;
        next
            if $s[2] eq '0.0.0.0';
        $s[3] = ''
            if $s[3] eq '0.0.0.0';

        next
            if defined $myips->{$s[2]};

        $ip = @s == 8 && $s[3] ? NetAddr::IP->new($s[2], $s[3]) : $s[2];

        $ips->{$ip}->{$s[1]} = $s[0];

        $hosts->{$s[0]}->{ips} = {}
             unless defined $hosts->{$s[0]}->{ips};
        $hosts->{$s[0]}->{fwd} = {}
             unless defined $hosts->{$s[0]}->{fwd};
        $hosts->{$s[0]}->{status} = {}
             unless defined $hosts->{$s[0]}->{status};

        $hosts->{$s[0]}->{ips}->{scalar $ip} = 
        { 
            ip => $ip, 
            id => $s[1], 
            primary => @s == 8 ? $s[4] : $s[3], 
            status => _A_OK,
        };

        $hosts->{$s[0]}->{fwd} = @s == 8 ? ! $s[5] : ! $s[4];
        $hosts->{$s[0]}->{status} = @s == 8 ? $s[7] : $s[6];

        $net = ref($ip) eq 'NetAddr::IP' ? $ip->network : '';

        if ($net)
        {
            $nets->{ $net }->{addr} = NetAddr::IP->new($net)
                unless defined $nets->{ $net };
            $nets->{ $net }->{routers} += 1
                if $hosts->{$s[0]}->{fwd} == _FWD_YES;
        }
    }
    close F;

    log_debug("hosts: " . Dumper($hosts), _LOG_ERROR)
        if $LowLevelDebug;
}

sub init_graph
{
    my $self = shift;

    log_debug("initializing graph...", _LOG_DEBUG)
        if $LogEnabled;

    $self->[NETS] = {};
    $self->[HOSTS] = {};
    $self->[GRAPH] = Graph::Undirected->new();
    $self->[IPS] = {};
    $self->[UNREACHABLES] = {};
    $self->[VX_2_DOWNS] = {};
    $self->[IP_EDGES] = {};

    correlations_clear();

    $self->checking_flags_load;

    $UseTestData
        ? $self->load_ips_test
        : $self->load_ips_real;

    $self->fix_masks;

    $self->set_ip_statuses;

    $self->build_graph;

    log_debug(sprintf(qq|graph size: %s nets, %s hosts|, 
        scalar keys %{$self->nets},
        scalar keys %{$self->hosts},
        ), _LOG_INFO)
        if $LogEnabled;

    $self->create_png(1,0, 0)
        if $GraphDebug;

    $self->netdesc;

    log_debug("graph initialized", _LOG_DEBUG)
        if $LogEnabled;
}

sub netdesc
{
    my $self = shift;

    my $nd = load_netdesc;

    for (keys %{$self->nets})
    {
        $nd->{$_} = ''
            unless defined $nd->{$_};
    }

    save_netdesc($nd);
}

sub set_ip_statuses
{
    my $self = shift;

    my $hosts = $self->hosts;
    my $cf = $self->checking_flags;

    my $ip;
    my $s;

    for my $h (keys %$hosts)
    {
        $h = $hosts->{$h}->{ips};
        for $ip (keys %$h)
        {
            $s = "ip:$ip:$h->{$ip}->{id}";
            $h->{$ip}->{status} = defined $cf->{$s}
                ? $cf->{$s}
                : _A_INIT;
        }
    }
#log_debug(Dumper($hosts),_LOG_ERROR);
}

sub fix_masks
{
    my $self = shift;

    log_debug("fixing net masks...", _LOG_DEBUG)
        if $LogEnabled;

    my $nets = $self->nets;
    my $hosts = $self->hosts;
    my $ips = $self->ips;

    my @t;
    my $s;
    my $i;

    my $done = {};

    for my $idh (keys %$hosts)
    {
        for my $ip (keys %{$hosts->{$idh}->{ips}})
        {
            $i = 0;
            next
                if ref($hosts->{$idh}->{ips}->{$ip}->{ip}) eq 'NetAddr::IP';

            if (defined $done->{$ip})
            {
                $hosts->{$idh}->{ips}->{$ip}->{ip} = $done->{$ip};
                $hosts->{$idh}->{ips}->{scalar $done->{$ip}} = $hosts->{$idh}->{ips}->{$ip};
                delete $hosts->{$idh}->{ips}->{$ip};
                next;
            }

            @t = split /\./, $ip;
            $s = "$t[0].$t[1].$t[2]";
            @t = grep {/^$s/} keys %$nets;

            for (@t)
            {
                $s = NetAddr::IP->new($ip, $nets->{$_}->{addr}->mask);
                if ($nets->{$_}->{addr}->contains($s))
                {
                    log_debug("id $hosts->{$idh}->{ips}->{$ip}->{id} $ip belongs to " . $s->network, _LOG_ERROR)
                        if $LowLevelDebug;

                    $hosts->{$idh}->{ips}->{$ip}->{ip} = $s;
                    $hosts->{$idh}->{ips}->{scalar $s} = $hosts->{$idh}->{ips}->{$ip};
                    delete $hosts->{$idh}->{ips}->{$ip};
                    $ips->{scalar $s} = $ips->{$ip};         
                    delete $ips->{$ip};
                  
                    $done->{$ip} = $s; 

                    $i++;

                    last;
                }
            }

            log_debug("id $hosts->{$idh}->{ips}->{$ip}->{id} $ip mask unknown", _LOG_ERROR)
                if $LowLevelDebug && ! $i;
        }
    }

    log_debug("net masks fixed", _LOG_DEBUG)
        if $LogEnabled;
}

sub build_graph
{
    my $self = shift;

    log_debug("building graph...", _LOG_DEBUG)
        if $LogEnabled;

    my $nets = $self->nets;
    my $hosts = $self->hosts;
    my $g = $self->graph;

    my $ip;
    my $net;

    #dodaj sieci
    for (sort keys %$nets)
    {
        $g->add_vertices("net:$_");
    }

    $g->add_vertices("id:akkada");

    my $myips = $self->myips;

    for (keys %$myips)
    {
        $ip = NetAddr::IP->new($_, $myips->{$_});
        $net = "net:" . $ip->network; 
        $g->add_vertices($net)
            unless $g->has_vertex($net);
        $g->add_edge("id:akkada", $net);
    }

    if (! $g->has_vertex("net:127.0.0.0/8"))
    {
        $g->add_vertices("net:127.0.0.0/8");
        $g->add_edge("id:akkada", "net:127.0.0.0/8");
    }

    $g->add_vertices("id:vrouter"); #tutaj podlaczam rozlaczne czesci grafu
    $g->set_vertex_attribute("id:vrouter", "fwd", _FWD_YES);
    $g->add_edge("id:vrouter", "net:127.0.0.0/8");

    $g->add_vertices("net:vnet"); #tutaj podlaczam adresy IP bez maski
    $g->add_edge("net:vnet","id:vrouter");

    #dodaj hosty
    for my $idh (sort keys %$hosts)
    {
        $g->add_vertices("id:$idh");
        $g->set_vertex_attribute("id:$idh", "fwd", $hosts->{$idh}->{fwd});
        $g->set_vertex_attribute("id:$idh", "status", $hosts->{$idh}->{status});

        for (sort keys %{$hosts->{$idh}->{ips}})
        {
            $ip = join(":", "ip", scalar $hosts->{$idh}->{ips}->{$_}->{ip}, $hosts->{$idh}->{ips}->{$_}->{id});
            $net = ref($hosts->{$idh}->{ips}->{$_}->{ip}) eq 'NetAddr::IP'
                 ? "net:" . $hosts->{$idh}->{ips}->{$_}->{ip}->network
                 : "net:vnet";
            $self->add_ip("id:$idh", $net, $ip, $idh, $hosts->{$idh}->{ips}->{$_}->{primary}, $hosts->{$idh}->{ips}->{$_}->{status});
        }
    }

    $self->join_parts;

    if ($UseTestData)
    {
        open F, ">/tmp/av2";
        print F join("\n", keys %{$self->ip_edges}), "\n";
        close F;
    }

    log_debug("graph built", _LOG_DEBUG)
        if $LogEnabled;
}

sub add_ip
{
    my ($self, $host, $net, $ipe, $idh, $primary, $status) = @_;

    my $g = $self->graph;
    my $ipes = $self->ip_edges;

    my $ips_up = $g->get_edge_attribute($host, $net, "ips_up");

    ++$ips_up->{$ipe};

    $g->set_edge_attribute($host, $net, "ips_up", $ips_up);

    $ipes->{$ipe} = { host => $host, net => $net, status => $status, idh => $idh, primary => $primary };
}


sub join_parts
{
    my $self = shift;

    log_debug("joining parts...", _LOG_DEBUG)
        if $LogEnabled;

    my $g = $self->graph;

    my $max_net;

    for my $cc ($g->connected_components)
    {
        $max_net = '';

        next
            if grep { /^id:akkada$/ } @$cc;
        
        for my $pn (keys %$PreferredNetworks)
        {
            if (grep { /$pn/ } @$cc)
            {
                $max_net = "net:$pn";
                last;
            }
        } 

        $max_net = $self->get_max_degree_net($cc)
            unless $max_net;

        log_debug("part: " . Dumper($cc) . "joins: $max_net", _LOG_ERROR)
            if $LowLevelDebug;

        $g->add_edge("id:vrouter",$max_net);
    }

    log_debug("parts joined", _LOG_DEBUG)
        if $LogEnabled;
}

sub run
{
    my $self = shift;
    my $ppid = shift;

    $SIG{QUIT} = \&got_sig_quit;
    $SIG{INT} = \&got_sig_quit;
    $SIG{TERM} = \&got_sig_quit;
    $SIG{TRAP} = \&trace_stack;

    $self->init_graph;

    while (1)
    {

        exit
            if ! kill(0, $ppid);

        $self->init_graph
            if flag_file_check($FlagsControlDir, 'available2.init_graph', 1);

        $self->dump_data
            if flag_file_check($FlagsControlDir, 'available2.dump_data', 1);

        if (flag_file_check($FlagsControlDir, 'available2.create_png', 0))
        {
            $self->create_png(0,1,0);
            flag_file_check($FlagsControlDir, 'available2.create_png', 1);
        }
        if (flag_file_check($FlagsControlDir, 'available2.create_png2', 0))
        {
            $self->create_png(1,0,1);
            flag_file_check($FlagsControlDir, 'available2.create_png2', 1);
        }

        log_debug("ip_edges: " . Dumper($self->ip_edges), _LOG_ERROR)
            if flag_file_check($FlagsControlDir, 'available2.dump_ip_edges', 1);
        log_debug("hosts: " . Dumper($self->hosts), _LOG_ERROR)
            if flag_file_check($FlagsControlDir, 'available2.dump_hosts', 1);
        log_debug("vx_2_downs: " . Dumper( $self->vx_2_downs), _LOG_ERROR)
            if flag_file_check($FlagsControlDir, 'available2.vx_2_downs', 1);
        log_debug("graph: " . Dumper($self->graph), _LOG_ERROR)
            if flag_file_check($FlagsControlDir, 'available2.dump_graph', 1);

        $self->available_check;

        sleep $Period || 1;
    }
}

sub dump_data
{
     my $self = shift;
     my $hosts = $self->hosts;

     log_debug("dumping data...", _LOG_DEBUG)
         if $LogEnabled;

     open F, ">/tmp/av2_data";

     print F <<EOF;
# id_host id_nic ip mask primary forwarding status_ip status_host
# status: always 0
# ipForw = 0, notForw = 1
# primary: 1 primary ip, 0 secondary ip
EOF

     for my $h (keys %$hosts)
     {
         for (keys %{$hosts->{$h}->{ips}})
         {
             print F sprintf(qq|%s %s %s|,
                 $h,
                 $hosts->{$h}->{ips}->{$_}->{id},
                 ref($hosts->{$h}->{ips}->{$_}->{ip}) eq 'NetAddr::IP' ? $hosts->{$h}->{ips}->{$_}->{ip}->addr : $_
             );

             print F " ", $hosts->{$h}->{ips}->{$_}->{ip}->mask
                 if ref($hosts->{$h}->{ips}->{$_}->{ip}) eq 'NetAddr::IP';

             print F " ", $hosts->{$h}->{ips}->{$_}->{primary};
             print F " ", $hosts->{$h}->{fwd} == _FWD_YES ? 0 : 1;
             print F " 0 0\n";
         }
     }

     close F;

     open F, ">/tmp/av2_hosts";
     print F Dumper($self->hosts);
     close F;

     open F, ">/tmp/av2_ip_edges";
     print F Dumper($self->ip_edges);
     close F;

     open F, ">/tmp/av2_ips";
     print F Dumper($self->ips);
     close F;

     open F, ">/tmp/av2_myips";
     print F Dumper($self->myips);
     close F;

     log_debug("data dumped", _LOG_DEBUG)
         if $LogEnabled;
}

sub available_check
{
    my $self = shift;

    $self->clear_tmp_edges;

    my $flag_action = ! $UseTestData
        ? $self->available_check_real
        : $self->available_check_test;
    
    if ($flag_action)
    {
        $self->check_edges;
        $self->check_unreachable;
        $self->create_png(1,0)
            if $GraphDebug;
    }
}

sub available_check_real
{
    my $self = shift;
    my $flag_action = 0;

    my $ipes = $self->ip_edges;
    my $cf = $self->checking_flags;

    my $rel = {};
    my $ipe;

    for (keys %$ipes)
    {
        $ipe = $_;


        next
            if defined $cf->{$ipe} && $cf->{$ipe} == _A_STATIC_OK;
        next
            if $ipes->{$ipe}->{status} == _A_UNUSABLE
            || $ipes->{$ipe}->{status} == _A_STATIC_OK;

        s/^ip://;
        s/:.*$//;
        s/\/.*$//;
        $rel->{$_}->{$ipe} = 1;
    }

#log_debug(Dumper($ipes), _LOG_ERROR);
#log_debug(Dumper($rel), _LOG_ERROR);

    return $flag_action
        unless keys %$rel;

    my ($pid, $inh, $outh, $errh, @tmp, $ip);

    $pid = open3($inh, $outh, $errh, @$FPing, $PingCount, keys %$rel);

    for (<$outh>)
    {
        if (/^open3:/)
        {
            log_debug($_, _LOG_ERROR)
                 if $LogEnabled;
            next;
        }

        chomp;
        @tmp = split /\s+/;

        $ip = shift @tmp;

        if (! defined $rel->{$ip})
        {
            log_debug("available_check_real: internal error: unknown IP address: $ip - ignored", _LOG_ERROR);
            next;
        }

        shift @tmp;
        @tmp = grep { ! /^-$/ } @tmp;

#jest nie jest sdefiniowna edge ip w checking_flags to
#oznacza ze pierwszy raz jest testowana i wtedy jesli nie odpowiada na pingi nalezy ustawic flage _A_STATIC_OK
#inaczej nie nie nalezy robic

        if (@tmp ) # == $PingCount) - tak min 1 ping = ok;
        {        
            for (keys %{$rel->{$ip}})
            {
                if (! defined $cf->{$_})
                {
                    $self->checking_flag_create($_, _A_OK);
                    #$ipes->{$ipe}->{status} = _A_OK;
                }

                $flag_action += $self->action_up_ip($_)
                    if $ipes->{$_}->{status} == _A_DOWN 
                    || $ipes->{$_}->{status} == _A_INIT;

            }
        }
        else
        {
            for (keys %{$rel->{$ip}})
            {
                #jak nie ma ckecking_flag to ustawia automat static ok i nie downuje sie nigdy takiego wierzcholka
                if (! defined $cf->{$_})
                {
                    $self->change_from_init_to_static_ok($_);
                    $self->checking_flag_create($_, _A_STATIC_OK);
                }
                else
                {
                    $flag_action += $self->action_down_ip($_)
                        if $ipes->{$_}->{status} == _A_OK
                        || $ipes->{$_}->{status} == _A_INIT;
                }
            }
        }
    }

    waitpid($pid, 0);
    close $inh
        if defined $inh;
    close $outh
        if defined $outh;
    close $errh
        if defined $errh;

    return $flag_action;
}

sub checking_flag_create
{
# flag postaci ip:1.1.1.1-24:0:1 lub ip:1.1.1.1-null:1234:4
    my ($self, $ipe, $status) = @_;

    my $cf = $self->checking_flags;

    $ipe =~ /ip:(.*):(.*)/;
    my ($ip, $id) = ($1, $2);
    $ip .= "-null"
        unless $ip =~ /\//;
    $ip =~ s/\//-/g;

    my $name = "$CheckingFlagsDir/ip:$ip:$id:$status";

    open(F, ">$name")
        or log_exception( EFileSystem->new("$!: $name"), _LOG_ERROR);
    print F " ";
    close F;

    $cf->{$ipe} = $status;
}
   
sub available_check_test
{
    my $self = shift;
    my $flag_action = 0;

    my ($file, $eg, $action);

    my $g = $self->graph;
    my $ips = $self->ips;
    my $cf = $self->checking_flags;

    opendir(DIR, "/tmp");
    while (defined($file = readdir(DIR)))
    {
        next
            unless $file =~ /^av2-(.*)-(.*)/;

        unlink "/tmp/$file" or die $!;

        ($action, $eg) = ($1, $2);

        if ($eg !~ /^ip:/)
        {
            log_debug("$eg cannot be processed", _LOG_ERROR);
            next;
        }

        $eg =~ s/#/\//g;

        if (defined $cf->{$eg} && $cf->{$eg} == _A_STATIC_OK)
        {
            log_debug("$eg status is _A_STATIC_OK - cannot be processed", _LOG_ERROR);
            next;
        }

        $eg =~ /ip:(.*):(.*)/;

        if (! defined $ips->{$1} || ! defined $ips->{$1}->{$2})
        {
            log_debug("ip $1 id $2 doesn\'t exist", _LOG_ERROR);
            next;
        }

        if ($action eq 'down')
        {
            $flag_action += $self->action_down_ip($eg);
        }
        elsif ($action eq 'up')
        {
            $flag_action += $self->action_up_ip($eg);
        }
    }
    closedir(DIR);
    
    return $flag_action;
}

sub correlations_reset_counters
{
    my $self = shift;
    my $correlations = $self->correlations;
    $correlations->{$_}->{confirmation} = 0
        for keys %$correlations;
}

sub akk_colab_host_ok
{
    my ($self, $vx) = @_;

    my $dbh = $self->dbh;

    $vx =~ /^id:(.*)/;
    my $id_entity = $1;

    my $entity = Entity->new($dbh, $id_entity);

    if (defined $Probes->{ $ProbesMapRev->{ $entity->id_probe_type } }->{not_tested})
    {
        $entity->set_status(_ST_OK, '');
    }
    else
    {
        $entity->set_status(_ST_UNKNOWN, '');
    }

    if (flag_file_check($FlagsUnreachableDir, $id_entity, 1))
    {
        flag_files_create_ow($FlagsUnreachableDir, sprintf(qq|%s.last|, $id_entity));
        log_debug(sprintf(qq|entity %s unreachable flag deleted!|, $id_entity), _LOG_INFO);
    }
}

sub akk_colab_host_unreachable
{
    my ($self, $vx) = @_;

    my $dbh = $self->dbh;

    $vx =~ /^id:(.*)/;
    my $id_entity = $1;

    my $entity = Entity->new($dbh, $id_entity);

    node_set_status($dbh, $id_entity, _ST_UNKNOWN);

    $entity->set_status(_ST_UNREACHABLE, "node is unreachable");

    if ($entity->params('ip'))
    {
        log_debug(sprintf(qq|entity %s unreachable flag created!|, $id_entity), _LOG_INFO)
            if flag_files_create($FlagsUnreachableDir, $id_entity);
    }
}

sub check_unreachable
{
    my $self = shift;

    log_debug("checking unreachables...", _LOG_DEBUG)
        if $LogEnabled;

    my $g = $self->graph;
    my $unreachables = $self->unreachables;

    my $dg;
    my $h = {};

    $self->correlations_reset_counters;
    my $correlations = $self->correlations;

    for my $subg ($g->connected_components)
    {
        $h = {};
        if (grep { /^id:akkada$/ } @$subg)
        {
            #glowne poddrzewo - czyscimy unreach
            @$h{ @$subg } = @$subg; 
            for (keys %$unreachables)
            {
                if (defined $h->{$_})
                {
                    /^net:/
                        ? $self->net_set_ok($_)
                        : $self->host_set_ok($_);
                    delete $unreachables->{$_};
                    $self->akk_colab_host_ok($_)
                        if /^id:/;
                }
            }

        }
        else
        {
            for (@$subg)
            {
                /^net:/
                    ? $self->net_set_unreachable($_)
                    : $self->host_set_unreachable($_);
            }

            if (@$subg > 1)
            {
                my $ipes = $self->ip_edges;
                @$h{ @$subg } = @$subg; 
                my @egs = map { [$ipes->{$_}->{host}, $ipes->{$_}->{net}] } grep { defined $h->{$ipes->{$_}->{host}} && defined $h->{$ipes->{$_}->{net}} } keys %$ipes;

                $h = $self->build_correlation($subg, \@egs);
                $correlations->{ $h->{id} } = { confirmation => 1, correlation => $h->{correlation} };
            }
        }
    }

    $self->correlations_update;

    log_debug("correlations: " . Dumper($correlations), _LOG_ERROR)
        if $LowLevelDebug;

    log_debug("unreachables checked", _LOG_DEBUG)
        if $LogEnabled;

}

sub correlations_update
{
    my $self = shift;
    my $correlations = $self->correlations;

    for (keys %$correlations)
    {
        if (! $correlations->{$_}->{confirmation})
        {
            $self->correlation_delete($_);
        } 
        elsif (! -e "$CorrelationsDir/$_")
        {
            $self->correlation_create($_);
        }
    }
}

sub correlation_create
{
    my ($self, $c) = @_;
    my $correlations = $self->correlations;
    if (! defined $correlations->{$c})
    {
        log_debug("correlation_create: internal error: not existed correlation $c", _LOG_ERROR);
        exit;
    }
    else
    {
        my $file = "$CorrelationsDir/$c"; 
        if (-e "$file")
        {
            open F, "+<$file";
        }
        else
        {
            open F, ">$file";
        }
        seek(F, 0, 0);
        print F Dumper($correlations->{$c});
# !!!!
#tutaj musisz tresc korelacji zapisac
# !!!!
        truncate(F, tell(F));
        close F;
    }
}

sub got_sig_quit
{
    log_debug("stopping...", _LOG_WARNING);

    correlations_clear();

    log_debug("stopped", _LOG_WARNING);

    exit;
}

sub correlations_clear
{
    my $file;

    opendir(DIR, "$CorrelationsDir");
    while (defined ($file = readdir(DIR)))
    {
        next
            if $file =~ /^\./;

        log_debug("deleting correlation $file", _LOG_ERROR)
            if $LowLevelDebug;

        unlink "$CorrelationsDir/$file"
            or log_debug("correlation_clear: $! $@", _LOG_ERROR);
    }
    closedir DIR;
}

sub correlation_delete
{
    my ($self, $c) = @_;
    my $correlations = $self->correlations;
    if (! defined $correlations->{$c})
    {
        log_debug("correlation_delete: internal error: not existed correlation", _LOG_ERROR);
        exit;
    }
    else
    {
        delete $correlations->{$c};
        unlink "$CorrelationsDir/$c";
    }
}

sub build_correlation
{
    my ($self, $subg, $egs) = @_;

    my %root_causes = ();
    my %root_causes_candidates = ();

    my $g = $self->graph;
    my $ipes = $self->ip_edges;


    #jelsi w subg jest ip down, ktore jest primary i jest odlaczone od routera
    #to jest to jedno z root_causes

    my %h;
    @h{@$subg} = @$subg;

    log_debug("part: " . Dumper(\%h), _LOG_ERROR)
        if $LowLevelDebug;

    my @ns = grep { $ipes->{$_}->{status} == _A_DOWN && $ipes->{$_}->{primary} && defined $h{$ipes->{$_}->{net}} } keys %$ipes;
    my @hs = grep { $ipes->{$_}->{status} == _A_DOWN && $ipes->{$_}->{primary} && defined $h{$ipes->{$_}->{host}} } keys %$ipes;

    my $vx_2_downs = $self->vx_2_downs;
    my @d = map { keys %{$vx_2_downs->{$_}} } grep {defined $vx_2_downs->{$_}} @$subg;
    my $degs = {};
    @$degs{@d} = @$ipes{@d};
#$vx_2_downs->{$net}->{$ipe};

    for my $ipe (@ns)
    {
        log_debug("level1: $ipe $ipes->{$ipe}->{host} fwd " . $g->get_vertex_attribute($ipes->{$ipe}->{host}, "fwd"), _LOG_ERROR)
            if $LowLevelDebug;

        if ($g->get_vertex_attribute($ipes->{$ipe}->{host}, "fwd") == _FWD_YES
            && ! defined $h{ $ipes->{$ipe}->{host} })
        {
            log_debug("added as a root cause", _LOG_ERROR)
                if $LowLevelDebug;

            ++$root_causes{$ipe};
        }
        elsif (! defined $h{ $ipes->{$ipe}->{host} })
        {
            log_debug("added as a root cause candidate", _LOG_ERROR)
                if $LowLevelDebug;

            ++$root_causes_candidates{$ipe};
        }
    }

    for my $ipe (@hs)
    {
        log_debug("level2: $ipe $ipes->{$ipe}->{host} fwd " . $g->get_vertex_attribute($ipes->{$ipe}->{host}, "fwd") . " net: $ipe $ipes->{$ipe}->{net}", _LOG_ERROR)
            if $LowLevelDebug;

        if ($g->get_vertex_attribute($ipes->{$ipe}->{host}, "fwd") == _FWD_YES
            && ! defined $h{ $ipes->{$ipe}->{net} })
        {
            log_debug("added as a root cause", _LOG_ERROR)
                if $LowLevelDebug;

            ++$root_causes{$ipe};
        }
        elsif (! defined $h{ $ipes->{$ipe}->{net} })
        {
            log_debug("added as a root cause candidate", _LOG_ERROR)
                if $LowLevelDebug;

            ++$root_causes_candidates{$ipe};
        }
    }

    if (! keys %root_causes && ! keys %root_causes_candidates)
    {
        for my $ipe (@hs)
        {
            #next, jesli host mam tylko jeden adres ip
            next
                unless grep { $ipes->{$_}->{host} eq $ipes->{$ipe}->{host} } keys %$ipes > 1;

            log_debug("level3: $ipe $ipes->{$ipe}->{host} : " . $g->get_vertex_attribute($ipes->{$ipe}->{host}, "fwd"), _LOG_ERROR)
                if $LowLevelDebug;

            if ($g->get_vertex_attribute($ipes->{$ipe}->{host}, "fwd") == _FWD_YES)
            {
                log_debug("added as a root cause", _LOG_ERROR)
                    if $LowLevelDebug;

                ++$root_causes{$ipe};
            }
            elsif (! defined $h{ $ipes->{$ipe}->{net} })
            {
                log_debug("added as a root cause candidate", _LOG_ERROR)
                    if $LowLevelDebug;

                ++$root_causes_candidates{$ipe};
            }
        }
    }

    #jesli edge jest z hosta, ktory jest w odlaczonej czesci grafu to niedostepnosc hosta jest root cause
    for (keys %root_causes)
    {
        if (defined $h{ $ipes->{$_}->{host} })
        {
            delete $root_causes{$_};
            ++$root_causes{ $ipes->{$_}->{host} };
        }
    }

    for (keys %root_causes_candidates)
    {
        if (defined $h{ $ipes->{$_}->{host} })
        {
            delete $root_causes_candidates{$_};
            ++$root_causes_candidates{ $ipes->{$_}->{host} };
        }
    }

    my $correlation = { timestamp => time, root_causes => \%root_causes, root_causes_candidates => \%root_causes_candidates, vxs => $subg, egs => $egs, degs => \$degs }; 

    return { id => $self->correlation_generate_id($correlation), correlation => $correlation };
}

sub correlation_generate_id
{
    my ($self, $c) = @_;
    my $s = join ":", sort keys %{$c->{root_causes}};
    $s .= join ":", sort keys %{$c->{root_causes_candidates}};
    $s .= join ":", sort @{$c->{vxs}};
    return md5_hex($s);
}

sub net_set_ok
{
    my ($self, $vx) = @_;

    if ($vx !~ /^net:/)
    {
        log_debug("net_set_ok: internal error: expected object net but have: $vx", _LOG_ERROR);
        exit;
    }

    my $g = $self->graph;
    my $unreachables = $self->unreachables;

    $g->set_vertex_attribute($vx, "status", 0);
    delete $unreachables->{$vx};
}

sub host_set_ok
{
    my ($self, $vx) = @_;

    if ($vx !~ /^id:/)
    {
        log_debug("host_set_ok: internal error: expected object host but have: $vx", _LOG_ERROR);
        exit;
    }

    my $g = $self->graph;
    my $unreachables = $self->unreachables;

    $g->set_vertex_attribute($vx, "status", 0);
    delete $unreachables->{$vx};
    
}


sub net_set_unreachable
{
    my ($self, $vx) = @_;

    if ($vx !~ /^net:/)
    {
        log_debug("net_set_ok: internal error: expected object net but have: $vx", _LOG_ERROR);
        exit;
    }

    my $g = $self->graph;
    my $unreachables = $self->unreachables;

    $g->set_vertex_attribute($vx, "status", 6);
    ++$unreachables->{$vx};
}

sub host_set_unreachable
{
    my ($self, $vx) = @_;

    if ($vx !~ /^id:/)
    {
        log_debug("host_set_ok: internal error: expected object host but have: $vx", _LOG_ERROR);
        exit;
    }

    my $g = $self->graph;
    my $unreachables = $self->unreachables;

    $g->set_vertex_attribute($vx, "status", 6);
    ++$unreachables->{$vx};
    $self->akk_colab_host_unreachable($vx);
}

sub ip_edges_tmp
{
    return $_[0]->[IP_EDGES_TMP];
}

sub clear_tmp_edges
{
    my $self = shift;

    my $g = $self->graph;
    my $ipes_tmp = $self->ip_edges_tmp;

    $g->delete_edge(@$_)
        for (@$ipes_tmp);
    $self->[IP_EDGES_TMP] = [];
}

sub get_akkadas_part
{
    my $self = shift;
    my $g = $self->graph;

    for ($g->connected_components)
    {
        return $_
            if grep { /^id:akkada$/ } @$_;
    }
    return undef;
}

sub does_it_see_akkada
{
    my $self = shift;
    my $vx = shift;
    my $akkadas_part = $self->get_akkadas_part;
    return grep { $vx } @$akkadas_part
        ? 1
        : 0;
}

sub check_edges
{
    my $self = shift;

    log_debug("checking edges...", _LOG_DEBUG)
        if $LogEnabled;

    my $g = $self->graph;
    my $ipes = $self->ip_edges;
    my $ipes_tmp = $self->ip_edges_tmp;

    my %disc;

    for ($g->connected_components)
    {
        next
            if grep { /^id:akkada$/ } @$_;
        @disc{@$_} = @$_;
    }

    for (grep { $ipes->{$_}->{status} != _A_OK } keys %$ipes)
    {
        next
            unless defined $disc{$ipes->{$_}->{host}}
            && defined $disc{$ipes->{$_}->{net}};
        next
            if $g->has_edge($ipes->{$_}->{host}, $ipes->{$_}->{net});

        log_debug("adding tmp edge $_: $ipes->{$_}->{host}, $ipes->{$_}->{net}", _LOG_ERROR)
            if $LowLevelDebug;

        $g->add_edge($ipes->{$_}->{host}, $ipes->{$_}->{net});
        push @$ipes_tmp, [ $ipes->{$_}->{host}, $ipes->{$_}->{net} ];
    }

    log_debug("edges checked", _LOG_DEBUG)
        if $LogEnabled;

}

sub action_down_ip
{
    my ($self, $ipe) = @_;

    my $g = $self->graph;
    my $ipes = $self->ip_edges;
    my $cf = $self->checking_flags;

    log_debug("action down: $ipe", _LOG_DEBUG)
        if $LogEnabled;

    if (! defined $ipes->{$ipe} || ! defined $ipes->{$ipe}->{status})
    {
        log_debug("action_down_ip: internal error: $ipe or its status not defined!", _LOG_ERROR);
        exit;
    }
    elsif (defined $cf->{$ipe} && $cf->{$ipe} == _A_STATIC_OK)
    {
        log_debug("action_down_ip: internal error: $ipe status is _A_STATIC_OK; cannot be downed!", _LOG_ERROR);
        exit;
    }

    if ($ipes->{$ipe}->{status} == _A_DOWN)
    {
        log_debug("$ipe already down", _LOG_ERROR)
            if $LowLevelDebug;
        return 0;
    }
    elsif ($ipes->{$ipe}->{status} == _A_UNUSABLE)
    {
        log_debug("$ipe status UNUSABLE - cannot down", _LOG_ERROR)
            if $LowLevelDebug;
        return 0;
    }

    my $vx_2_downs = $self->vx_2_downs;

    my $host = $ipes->{$ipe}->{host};
    my $net = $ipes->{$ipe}->{net};

    if (! defined $host || ! defined $net)
    {
        log_debug("action_down_ip: internal error: $ipe no defined net: $net or  host: $host", _LOG_ERROR);
        exit;
    }
    else
    {
        $ipes->{$ipe}->{status} = _A_DOWN;
        ++$vx_2_downs->{$net}->{$ipe};
        ++$vx_2_downs->{$host}->{$ipe};
    }

    my $ips_up = $g->get_edge_attribute($host, $net, "ips_up");

    if (! defined $ips_up || ! defined $ips_up->{$ipe})
    {
        log_debug("action_down_ip: internal error: $ipe has not defined attribute ips_up", _LOG_ERROR);
        exit;
    }
    else
    {
        delete $ips_up->{$ipe};

        log_debug("downing main IP $ipe", _LOG_WARNING)
            if $LowLevelDebug;

        keys %$ips_up
            ? $g->set_edge_attribute($host, $net, "ips_up", $ips_up)
            : $g->delete_edge($host, $net);
    }

    if (! defined $ipes->{$ipe}->{primary})
    {
        log_debug("action_down_ip: internal error: $ipe primary attribute not defined", _LOG_ERROR);
        exit;
    }
    else
    {
#log_debug("WARN2 $ipe", _LOG_ERROR);
        return 1
            unless $ipes->{$ipe}->{primary} == _IP_PRIMARY;
    }

    #to jest sekcja, zeby obsluzyc niedostepnosc hostow z ip adresami w stanie _A_STATIC_OK
    #dotyczy sytuacji gdy static_ok jest przy hoscie
    $self->check_static_ok($host);

    #dotyczy sutiacji gdy static_ok jest przy hostach zwiazanych z odlaczana siecia
    my @nbs = $g->neighbours($net);
    for (@nbs)
    {
#log_debug("XXXXXXXXXXXXXXXXX: $_", _LOG_ERROR);
        $self->check_static_ok($_);
    }
    #koniec sekcji

    @nbs = $g->neighbours($host);
    my $flag = 0;

#log_debug("WARN3", _LOG_ERROR);
    for (@nbs)
    {
#log_debug("WARN1" . Dumper(\@nbs), _LOG_ERROR);
        $ips_up = $g->get_edge_attribute($host, $_, "ips_up");
#log_debug("WARN11" . Dumper($ips_up), _LOG_ERROR);

        if (! defined $ips_up || ! keys %$ips_up)
        {
            log_debug("$ipe has not defined attribute ips_up; probable was added by check_edges procedure. deleting edge", _LOG_ERROR)
                if $LowLevelDebug;

            $g->delete_edge($ipes->{$ipe}->{host}, $ipes->{$ipe}->{net});
            ++$flag;
        }
        else
        {
            for (keys %$ips_up)
            {
#DUPA
#log_debug($_ . ": " .  $ipes->{$_}->{status}, _LOG_ERROR);
                next
                    if $ipes->{$_}->{status} == _A_STATIC_OK;
                return 1
                    if $ipes->{$_}->{primary} == _IP_PRIMARY;
            }
        }
    }
        
#log_debug("WARN4", _LOG_ERROR);
    @nbs = $g->neighbours($host)
         if $flag;
       
    for $net (@nbs)
    {
        $ips_up = $g->get_edge_attribute($host, $net, "ips_up");

        for $ipe (keys %$ips_up)
        {
            $ipes->{$ipe}->{status} = _A_UNUSABLE;
            ++$vx_2_downs->{$net}->{$ipe};
            ++$vx_2_downs->{$host}->{$ipe};

        log_debug("downing slave IP $ipe", _LOG_ERROR)
            if $LowLevelDebug;

        }

        $g->delete_edge($host, $net);
    }

    log_debug("action down: $ipe done", _LOG_WARNING)
        if $LogEnabled;

    return 1;
}

sub check_static_ok
{
    my $self = shift;
    my $host = shift;

    return
        if $host eq 'id:vrouter' || $host eq 'id:akkada';

    my $g = $self->graph;
    my $ipes = $self->ip_edges;
    my $vx_2_downs = $self->vx_2_downs;

#log_debug("A1 host: " . $host, _LOG_ERROR);
    my @nbs = $g->neighbours($host);
    my @tmp_nbs = ();
    my $tmp;

#log_debug("egs: " . Dumper(\@nbs), _LOG_ERROR);
    for $tmp (@nbs)
    {
        $tmp = [grep { $ipes->{$_}->{host} eq $host && $ipes->{$_}->{net} eq $tmp} keys %$ipes];
        $tmp = $tmp->[0];
#log_debug("temp: " . $tmp, _LOG_ERROR);
#log_debug("temp: status" . $ipes->{$tmp}->{status}, _LOG_ERROR);
        if (! defined $tmp)
        {
            log_debug("action_down_ip: internal error: $host <> $_ edge missing", _LOG_ERROR);
            exit;
        }

        if ($ipes->{$tmp}->{status} == _A_STATIC_OK)
        {
#log_debug("temp deleting: " . $tmp, _LOG_ERROR);
            push @tmp_nbs, [$tmp, $g->get_edge_attribute($host, $ipes->{$tmp}->{net}, "ips_up")];
            $g->delete_edge($host, $ipes->{$tmp}->{net});
        }
    }

#log_debug("A2 host: " . $host, _LOG_ERROR);
#log_debug("tmp_egs: " . Dumper(\@tmp_nbs), _LOG_ERROR);
    log_debug("reachable: 1", _LOG_DEBUG);
    log_debug("reachable: ". Dumper($self->does_it_see_akkada($host)), _LOG_DEBUG);
    #log_debug("reachable: ". Dumper($g->is_reachable($host, 'id:akkada')), _LOG_DEBUG);
    log_debug("reachable: 2", _LOG_DEBUG);
    #if ($g->is_reachable($host, 'id:akkada'))
    if ($self->does_it_see_akkada($host))
    {
        for (@tmp_nbs)
        {
#log_debug("temp adding: " . $_->[0], _LOG_ERROR);
            $g->add_edge($ipes->{$_->[0]}->{host}, $ipes->{$_->[0]}->{net});
            $g->set_edge_attribute($ipes->{$_->[0]}->{host}, $ipes->{$_->[0]}->{net}, "ips_up", $_->[1]);
        }
    }
    else
    {
        for (@tmp_nbs)
        {
#log_debug("permanent deleting (_A_UNUSABLE): " . $_->[0], _LOG_ERROR);
            $ipes->{$_->[0]}->{status} = _A_UNUSABLE;
            ++$vx_2_downs->{$ipes->{$_->[0]}->{net}}->{$_->[0]};
            ++$vx_2_downs->{$ipes->{$_->[0]}->{host}}->{$_->[0]};
        }
    }
#log_debug("A3 host: " . $host, _LOG_ERROR);
}

sub change_from_init_to_static_ok
{
    my $self = shift;
    my $ipe = shift;

    my $g = $self->graph;
    my $ipes = $self->ip_edges;

    my $host = $ipes->{$ipe}->{host};
    my $net = $ipes->{$ipe}->{net};

    $ipes->{$ipe}->{status} = _A_STATIC_OK;

    my $ips_up = $g->get_edge_attribute($host, $net, "ips_up");
    ++$ips_up->{$ipe};
    $g->set_edge_attribute($host, $net, "ips_up", $ips_up);
}


sub action_up_ip
{
    my ($self, $ipe) = @_;

    log_debug("action up: $ipe", _LOG_DEBUG)
        if $LogEnabled;

    my $g = $self->graph();
    my $ipes = $self->ip_edges;
    my $cf = $self->checking_flags;

    if (! defined $ipes->{$ipe} || ! defined $ipes->{$ipe}->{status})
    {
        log_debug("action_up_ip: internal error: $ipe or its status not defined", _LOG_ERROR);
        exit;
    }
    elsif (defined $cf->{$ipe} && $cf->{$ipe} == _A_STATIC_OK)
    {
        log_debug("action_up_ip: internal error: $ipe status is _A_STATIC_OK; cannot be up!", _LOG_ERROR);
        exit;
    }

    if ($ipes->{$ipe}->{status} == _A_OK)
    {
        log_debug("$ipe already OK", _LOG_ERROR)
            if $LowLevelDebug;

        return 0;
    }
    elsif ($ipes->{$ipe}->{status} == _A_UNUSABLE)
    {
        log_debug("$ipe is in a UNUSABLE state - cannot up it", _LOG_ERROR)
            if $LowLevelDebug;

        return 0;
    }

    my $vx_2_downs = $self->vx_2_downs;
#log_debug(Dumper($vx_2_downs),_LOG_ERROR);

    my $host = $ipes->{$ipe}->{host};
    my $net = $ipes->{$ipe}->{net};

    log_debug("up main $ipe", _LOG_ERROR)
        if $LowLevelDebug;

    $ipes->{$ipe}->{status} = _A_OK;
    delete $vx_2_downs->{$net}->{$ipe};
    delete $vx_2_downs->{$net}
        unless keys %{$vx_2_downs->{$net}};
    delete $vx_2_downs->{$host}->{$ipe};
    delete $vx_2_downs->{$host}
        unless keys %{$vx_2_downs->{$host}};

    my $ips_up = $g->get_edge_attribute($host, $net, "ips_up");
    ++$ips_up->{$ipe};
    $g->set_edge_attribute($host, $net, "ips_up", $ips_up);

    if (! defined $ipes->{$ipe}->{primary})
    {
        log_debug("action_up_ip: internal error: $ipe primary attribute not defined", _LOG_ERROR);
        exit;
    }
    else
    {
        return 1
            unless $ipes->{$ipe}->{primary} == _IP_PRIMARY;
    }
 
    #to jest do podniesienia zdownowanych static_ok
    #my @nbs = grep { $vx_2_downs->{} keys %$ipes; #$g->neighbours($net);
#log_debug(Dumper($vx_2_downs),_LOG_ERROR);
=pod
1204045662.732366: nm-available2.pl 30505 ERROR $VAR1 = {
          'net:10.136.182.20/30' => {
                                      'ip:10.136.182.22/30:4121' => 1
                                    },
          'id:3750' => {
                         'ip:10.136.182.18/30:4095' => 1,
                         'ip:10.136.182.22/30:4121' => 1
                       },
          'net:10.136.182.16/30' => {
                                      'ip:10.136.182.18/30:4095' => 1
                                    }
        };

1204045662.735371: nm-available2.pl 30505 ERROR ipe net net:10.136.182.20/30 neighbour id:2289
1204045662.774627: nm-available2.pl 30505 ERROR part: $VAR1 = {
          'net:10.136.44.128/26' => 'net:10.136.44.128/26',
          'net:10.136.44.64/26' => 'net:10.136.44.64/26',
          'net:10.136.45.64/26' => 'net:10.136.45.64/26',
          'id:3750' => 'id:3750',
          'net:10.136.45.192/26' => 'net:10.136.45.192/26',
          'net:10.136.45.0/26' => 'net:10.136.45.0/26',
          'net:10.136.45.128/26' => 'net:10.136.45.128/26',
          'net:10.136.44.0/26' => 'net:10.136.44.0/26',
          'net:10.136.44.192/26' => 'net:10.136.44.192/26'
        };

=cut
    
    #for ($g->neighbours($net))
    for ($g->neighbours( (map { $ipes->{$_}->{host} } grep { $ipes->{$_}->{net} eq $net } keys %$ipes)[0] ))
    {
#log_debug("ipe net $net neighbour $_", _LOG_ERROR);
        next
            unless defined $vx_2_downs->{$_};
#log_debug("ipe net $net neighbour $_ confirmed", _LOG_ERROR);
    for $ipe (keys %{$vx_2_downs->{$_}})
    {
#log_debug("ipe $ipe status $ipes->{$ipe}->{status}", _LOG_ERROR);
        next
            unless $ipes->{$ipe}->{status} == _A_UNUSABLE;

        $host = $ipes->{$ipe}->{host};
        $net = $ipes->{$ipe}->{net};

        $ipes->{$ipe}->{status} = $cf->{$ipe}; # musi byc z cf bo byc moze bedzie static_ok -> check_static_ok przy downowaniu
        delete $vx_2_downs->{$net}->{$ipe};
        delete $vx_2_downs->{$net}
            unless keys %{$vx_2_downs->{$net}};
        delete $vx_2_downs->{$host}->{$ipe};
        delete $vx_2_downs->{$host}
            unless keys %{$vx_2_downs->{$host}};

        log_debug("up slave $ipe; net: $net; host: $host", _LOG_ERROR)
            if $LowLevelDebug;

        $ips_up = $g->get_edge_attribute($host, $net, "ips_up");
        ++$ips_up->{$ipe};
        $g->set_edge_attribute($host, $net, "ips_up", $ips_up);
    }
    }
    #koniec sekcji

    for $ipe (keys %{$vx_2_downs->{$host}})
    {
        next
            unless $ipes->{$ipe}->{status} == _A_UNUSABLE;

        $host = $ipes->{$ipe}->{host};
        $net = $ipes->{$ipe}->{net};

        $ipes->{$ipe}->{status} = $cf->{$ipe}; # musi byc z cf bo byc moze bedzie static_ok -> check_static_ok przy downowaniu
        delete $vx_2_downs->{$net}->{$ipe};
        delete $vx_2_downs->{$net}
            unless keys %{$vx_2_downs->{$net}};
        delete $vx_2_downs->{$host}->{$ipe};
        delete $vx_2_downs->{$host}
            unless keys %{$vx_2_downs->{$host}};

        log_debug("up slave $ipe; net: $net; host: $host", _LOG_ERROR)
            if $LowLevelDebug;

        $ips_up = $g->get_edge_attribute($host, $net, "ips_up");
        ++$ips_up->{$ipe};
        $g->set_edge_attribute($host, $net, "ips_up", $ips_up);
    }


    log_debug("action up: $ipe done", _LOG_WARNING)
        if $LogEnabled;

    return 1;
}

sub get_max_degree_net
{
    my $self = shift;
    my $vs = shift;

    my $g = $self->graph;
    my $nets = $self->nets;

    my $max = -1;
    my $result = '';
    my $i;
    my $net;

    for my $vx (sort grep { /^net:/ } @$vs)
    {
        $vx =~ /net:(.*)/;
        $net = $1;

        next
            unless defined $net;
        next
            unless defined $nets->{$net};
        next
            unless defined $nets->{$net}->{routers};

        if ($nets->{ $net }->{routers} > $max)
        {
            $max = $nets->{ $net }->{routers};
            $result = $vx;
        }
        elsif ($nets->{ $net }->{routers} == $max && $result && $result ne $vx)
        {
            $result = $vx
                if $g->degree($vx) > $g->degree($result);
        }
    }
    
    return $result
        if $result;

    for (sort grep { /^net:/ } @$vs)
    {
	$i = $g->degree($_);
        if ($i > $max)
        {
            $max = $i;
            $result = $_;
        }
    }

    return $result;
}

sub get_edge_style
{
    my ($self, $g, $v, $u) = @_;
    my ($shape, $color);

    my $style = '';

=pod
    if (
        $v =~ /id:akkada/ 
        || $v =~ /127\.0\.0\./ 
        || $v =~ /id:vrouter/ 
        || $v =~ /-vnic/ 
        || $v =~ /net:vnet/
        || $v =~ /ip:vip/
        || $u =~ /^net:/
        )
    {
=cut
        $shape = 'none';
    #}
    #else
    #{
    #    $shape = $g->get_vertex_attribute($v, "primary") ? 'dot' : 'rbox';
    #}
=pod
    $color = $g->get_vertex_attribute($v, "status");

    if ($color == 0)
    {
        $color = 'black';
    }
    elsif ($color == 4)
    {
        $color = 'red';
        $style = 'setlinewidth(2)';
    }
    elsif ($color == 64)
    {
        $color = 'silver';
        $style = 'setlinewidth(2)';
    }
=cut
    $color = 'black';

    return ($shape, $color, $style);
}

sub get_vertix_style
{
    my ($self, $g, $v, $corr, $corrc) = @_;

    my $primary = $g->get_vertex_attribute($v, "primary");
    my $fwd = $g->get_vertex_attribute($v, "fwd");
    my $status = $g->get_vertex_attribute($v, "status");

    $status = _A_OK
        unless defined $status;

    if (! $status && $v =~ /^id:/)
    {
        my $ipes = $self->ip_edges;
        my @t = grep 
        { 
            defined $ipes->{$_}
            && defined $ipes->{$_}->{host}
            && defined $ipes->{$_}->{status}
            && $ipes->{$_}->{host} eq $v 
            && $ipes->{$_}->{status} != _A_OK 
            && $ipes->{$_}->{status} != _A_STATIC_OK
            && $ipes->{$_}->{status} != _A_INIT
        } keys %$ipes;

#log_debug("XXXXXXXXXXXXXXXXXXXXXXX: $v" . Dumper(\@t), _LOG_ERROR) if @t;
#log_debug("XXXXXXXXXX: $_" . Dumper($ipes->{$_}), _LOG_ERROR) for @t;

        $status = 4
            if @t;
    }

    my ($fill , $shape, $color);

    if (defined $corr->{$v})
    {
        $color = 'white';
        $fill = 'black';
    }
    elsif (defined $corrc->{$v})
    {
        $color = 'black';
        $fill = 'aqua';
    }
    elsif (
        $v =~ /id:akkada/ 
        || $v =~ /127\.0\.0\./ 
        || $v =~ /id:vrouter/ 
        || $v =~ /net:vnet/
        )
    {
        $color = 'black';
        $fill = 'white';
    }
    elsif ($status == 0)
    {
        $color = 'black';
        $fill = $v =~ /id:/ ? '#FFA07A' : 'lime';
    }
    elsif ($status == 4)
    {
        $color = 'black';
        #$color = 'white';
        $fill = 'red';
    }
    elsif ($status == 6)
    {
        #$color = 'white';
        $color = 'black';
        $fill = '#4444aa';
    }
    elsif ($status == 64)
    {
        $color = 'black';
        $fill = 'silver';
    }

    if ( $v =~ /id:akkada/)
    {
        $shape = 'doubleoctagon';
    }
    elsif ($v =~ /^net:/)
    {
        $shape = 'ellipse';
    }
    elsif ($fwd == _FWD_YES )
    {
        #$shape = 'Mdiamond';
        $shape = 'octagon';
    }
    else
    {
        $shape = 'box';
    }

    return ($shape, $color, $fill);
}

sub create_png
{
    my $self = shift;
    my $with_names = shift;
    my $with_ip_addr = shift;
    my $nohosts = shift;

    log_debug("generting png... ", _LOG_DEBUG)
        if $LogEnabled;

    my $g = $self->graph;

    my $ge = Graph::Easy->new();
    $ge->strict(undef);
    $ge->set_attribute("ranksep", "$DOTranksep equally");

    my ($s, $shape, $color, $fill, $style);

    my $name;
    my $ipes = $self->ip_edges;
    my @tmp;
    my $i;

    my $nd = {};
    $nd = load_netdesc
        if $with_names;

    my $names = $self->dbh->dbh->selectall_hashref("select id_entity,name from entities where id_probe_type=1", "id_entity");
    for my $n (keys %$names)
    {
        @tmp = grep {$names->{$_}->{name} eq $names->{$n}->{name}} keys %$names;
        next
            if @tmp == 1;
        $i = 0;
        for (@tmp)
        {
            $names->{$_}->{name} .= ".$i";
            ++$i;
        }
    }

    my $corr = {};
    my $corrc = {};
    for my $c (keys %{ $self->correlations} )
    {

        $c = $self->correlations->{$c}->{correlation};
        for (keys %{ $c->{root_causes}})
        {
            if ($_ =~ /^ip:/)
            {
                $corr->{$ipes->{$_}->{host}}++;
            }
            else
            {
                $corr->{$_}++;
            }
        }
        for (keys %{ $c->{root_causes_candidates}})
        {
            if ($_ =~ /^ip:/)
            {
                $corrc->{$ipes->{$_}->{host}}++;
            }
            else
            {
                $corrc->{$_}++;
            }
        }
    }

    $ge->set_attribute("root", "id:akkada");
    for my $vx ($g->vertices)
    {
        if ($vx =~ /^net/)
        {
            $name = $vx;
            $name =~ s/^net://
                if $with_names;
        }
        else
        {
            next
                if $nohosts && $g->neighbours($vx) == 1;

            if ($with_names)
            {
                $vx =~ /^id:(.*)/;
                $name = $names->{$1}->{name};
                $name = $vx
                    unless $name;
            }
            else
            {
                $name = $vx;
            }

            $name = join("\\n", $name, map { $_ } grep {$ipes->{$_}->{host} eq $vx}  keys %$ipes)
                if $with_ip_addr;
        }

        $s = $ge->add_node($name);
        ($shape, $color, $fill) = $self->get_vertix_style($g, $vx, $corr, $corrc);
        $s->set_attributes({ shape => $shape, fill => $fill, color => $color, style => "filled", label => defined $nd->{$name} ? "$name\\n$nd->{$name}" : ''});
    }

    my $c;
    for my $e ($g->edges)
    {
        if ($e->[0] =~ /^id:/)
        {
            next
                if $nohosts && $g->neighbours($e->[0]) == 1;
            if ($with_names)
            {
                $e->[0] =~ /^id:(.*)/;
                $name = $names->{$1}->{name};
                $name = $e->[0]
                    unless $name;
            }
            else
            {
                $name = $e->[0];
            }

            $name = join("\\n", $name, map { $_ } grep {$ipes->{$_}->{host} eq $e->[0]}  keys %$ipes)
                if $with_ip_addr;
#$name = $e->[0];
            
        }
        else
        {
            next
                if $nohosts && $g->neighbours($e->[1]) == 1;
            if ($with_names)
            {
                $e->[1] =~ /^id:(.*)/;
                $name = $names->{$1}->{name};
                $name = $e->[1]
                    unless $name;
            }
            else
            {
                $name = $e->[1];
            }

            $name = join("\\n", $name, map { $_ } grep {$ipes->{$_}->{host} eq $e->[1]}  keys %$ipes)
                if $with_ip_addr;
#$name = $e->[1];
        }

        
        if ($with_names)
        {
            $e->[0] =~ s/^net://;
            $e->[1] =~ s/^net://;
        }

#warn "E: " . Dumper($e) . "NAME: " . Dumper($name);

        if ($s = $ge->add_edge_once($name, $e->[0] =~ /^id:/ ? $e->[1] : $e->[0]))
        {
            ($shape, $color, $style) = $self->get_edge_style($g, $e, '');;
            $s->set_attributes({ arrowhead => $shape, color => $color, style => $style });
        }
    }

    my $graphviz = $ge->as_graphviz();

    log_debug("data structure for png done. creating png file...", _LOG_DEBUG)
        if $LogEnabled;

    #print $graphviz;

    open DOT, "|$DOT -Tpng -o $GraphDebugPath/graph.png" or die ("Cannot open pipe to $DOT: $!");

    print DOT $graphviz;
    close DOT;

    log_debug("png done", _LOG_DEBUG)
        if $LogEnabled;
}

1;
