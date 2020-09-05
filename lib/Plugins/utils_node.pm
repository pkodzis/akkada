package Plugins::utils_node;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;
use Net::SNMP qw(:snmp);
use Entity;
use Plugins::utils_node::route_table;
use Plugins::utils_node::net_to_media;
use Plugins::utils_node::tcp_conn;
use Plugins::utils_node::ping;
use Plugins::utils_node::nmap;
use Plugins::utils_node::processes;
use Plugins::utils_node::software;
use Plugins::utils_node::devices;
use Plugins::utils_node::cisco_processes;
use Plugins::utils_node::cisco_inventory;

our $FormDispatcher =
{
    1 => \&Plugins::utils_node::route_table::get,
    2 => \&Plugins::utils_node::net_to_media::get,
    3 => \&Plugins::utils_node::tcp_conn::get,
    4 => \&Plugins::utils_node::ping::get,
    5 => \&Plugins::utils_node::nmap::get,
    6 => \&Plugins::utils_node::processes::get,
    7 => \&Plugins::utils_node::software::get,
    8 => \&Plugins::utils_node::devices::get,
    9 => \&Plugins::utils_node::cisco_processes::get,
    10 => \&Plugins::utils_node::cisco_inventory::get,
};

our $FormID = 
{
    'route_table' => 1,
    'net_to_media' => 2,
    'tcp_conn' => 3,
    'ping' => 4,
    'nmap' => 5,
    'processes' => 6,
    'software' => 7,
    'devices' => 8,
    'cisco_processes' => 9,
    'cisco_inventory' => 10,
};

sub get_list
{
    my $id_entity = shift;
    my $result = {};

    my $entity = Entity->new(DB->new(), $id_entity, 1);
    my $sysObjectID = $entity->data->{sysObjectID};

    my $file;
    my $av;
    opendir(DIR, sprintf(qq|%s/Plugins/utils_node|, CFG->{LibDir}));
    while (defined($file = readdir(DIR)))
    {
        next
            unless $file =~ /\.pm$/;
        $file =~ s/\.pm$//g;
        $av  = 0;
        eval qq|require Plugins::utils_node::${file};
           \$av = Plugins::utils_node::${file}::available('${sysObjectID}');
           |;
        $result->{$file} = { name => $av, form_id => $FormID->{$file} }
            if $av;
    }
    closedir(DIR);

    return $result;
}

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );
#use Data::Dumper; return [1, Dumper($ENV{'PATH_INFO'}) . Dumper($ENV{REQUEST_URI}) . Dumper($url_params)];

    my $id = $url_params->{form_id};
    return [1, 'unknown form']
        unless $id;
    return [1, 'unknown form']
        if $id =~ /\D/;

    return [0, $FormDispatcher->{$id}($url_params)];

}

1;
