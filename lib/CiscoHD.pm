package CiscoHD;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION );

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( get_hd );
%EXPORT_TAGS = ( default => [qw( get_hd )] );

use strict;
use Data::Dumper;
use Net::Telnet::Cisco;
use Net::SSH::Perl;

sub get_hd
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

    my @ti = $session->cmd("show interfaces status | in Duplex");
    push @ti, '        ';
    my $result = { parsed => [], title => \@ti };

    @type = $session->cmd("show interfaces status | in half");

    my @err = $session->cmd("show interfaces counter error");

    $session->close;



    my @h;

    my %g;
    my ($o, $p);
    for (@err)
    {
        chomp;
        next
            unless $_;

        /(^[a-z,A-Z,0-9,\/,\:,\.]+)( .*)/;
        $o = $1;
        $p = $2;
        push @{$result->{title}}, $_
            if $p !~ /[0-9]/;
        $g{$o} = []
            unless defined $g{$o};
        push @{$g{$o}}, $_;
    }

    for my $i (0..$#type)
    {
        chomp $type[$i];
        next
            unless $type[$i];
        $type[$i] =~ /(^[a-z,A-Z,0-9,\/,\:,\.]+)( .*)/;
        $type[$i] .= "  " . join("  ", @{$g{$1}});
    }

    my @c = @type;

    for my $s (@c)
    {
        chomp $s;
        next
            unless $s;
        $s =~ s/ +/ /g;
        @h = split / /,  $s;

        push @{$result->{parsed}}, { interface => $h[0], desc => $h[1], status => $h[2], vlan => $h[3], duplex => $h[4], speed => $h[5], type => $h[6], };
    }

    $result->{raw} = \@type;

#use Data::Dumper; die "<pre>" . Dumper($result) . "</pre>";

    return[0, $result];
}


1;
