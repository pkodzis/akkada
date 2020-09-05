package CiscoCAMTable;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION );

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( get_cam_table );
%EXPORT_TAGS = ( default => [qw( get_cam_table )] );

use strict;
use Data::Dumper;
use Net::Telnet::Cisco;
use Net::SSH::Perl;

sub get_cam_table
{
    my ($ip, $login, $passwd, $type) = @_;

    my (@output,$session, @desc, @type);

    if ($type eq 'ssh1')
    {
        eval
        {
            $session = Net::SSH::Perl->new($ip, debug => 1, cipher => 'DES', interactive => 0, protocol => 1);
            $session->login($login, $passwd);
        } 
            or return [$@, {}];
    }
    elsif ($type eq 'ssh2')
    {
        eval
        {
            $session = Net::SSH::Perl->new($ip, debug => 1, protocol => '2,1');
            $session->login($login, $passwd);
        } 
            or return [$@, {}];
    }
    elsif ($type eq 'telnet')
    {
        eval
        {
            $session = Net::Telnet::Cisco->new(Host => $ip,Prompt => '/\s*[\w().-]*[\$#>]\s?(?:\(enable\))?\s*$/');
            $login
                ? $session->login($login, $passwd)
                : $session->login(Password => $passwd);
        } 
            or return [$@, {}];
    }

    $session->cmd("terminal length 0");
    @output = $session->cmd("show mac-address-table dynamic");
    @desc = $session->cmd("show interfaces description");
    @type = $session->cmd("show interfaces status");
    $session->close;

    my $result = {};
    my $dsc = {};
    my $tpe = {};
    my $mac;
    my @tmp;

    shift @desc;
    for (@desc)
    {
        chomp;
        @tmp = split /   /, $_;
        $tmp[$#tmp] =~ s/^ *| *$//;
        $dsc->{$tmp[0]} = $tmp[$#tmp]; 
    }

    for (@type)
    {
        @tmp = split /disabled|connected|notconnected/, $_;
        $tmp[0] = (split / /, $tmp[0])[0];
        $tmp[1] =~ s/^ *//;
        $tmp[1] = (split / /, $tmp[1])[0];

        $tpe->{$tmp[0]} = $tmp[1];
    }

    for (@output) 
    {
        next 
            unless /([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})/i;
        $mac = lc $1;
        chomp;
        @tmp = split / /, $_;
        $result->{$mac} = []
            unless defined $result->{$mac};
        $tmp[$#tmp] =~ s/GigabitEthernet/Gi/ig;
        $tmp[$#tmp] =~ s/FastEthernet/Fa/ig;
        push @{$result->{$mac}}, [ 
            $tmp[$#tmp], 
            defined $tpe->{ $tmp[$#tmp] } ? $tpe->{ $tmp[$#tmp] } : '',
            defined $dsc->{ $tmp[$#tmp] } ? $dsc->{ $tmp[$#tmp] } : ''
        ];
    }

    return[0, $result];
}


1;
