package Tools::find_mac_address;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use URLRewriter;
use Common;
use Desktop::GUI;
use IP;
use HTML::Table;
use Configuration;
use CGI;
use Forms;

use Data::Dumper;
use Log;

sub desc
{
    return <<EOF;
This tool allows finding MAC address related to provided IP address 
<br>base on ARP cache tables kept by all monitored hosts. 
<br>Success is possible only if sought MAC address is kept in ARP cache
<br>table at least by one of monitored hosts.<p>
EOF
}

sub button_start
{
    my $url_params = shift;
    $url_params = url_dispatch( $url_params );

    my $cgi = CGI->new();

    my $cont;
    $cont->{form_name} = 'fakeform_mac_find';
    $cont->{no_border} = 1;

    push @{ $cont->{buttons} }, { caption => "find", url => "javascript:document.forms['fakeform_mac_find'].submit()" };

    push @{ $cont->{rows} },
    [
        'ip address',
        $cgi->textfield({ name => 'ipaddr', value => '', class => "textfield",}),
    ];

    return form_create($cont);
}


sub make_col_title
{
    my ($name ) = @_;
    return sprintf(qq|<font class="g4">%s</font>|, $name);
}

sub run
{
    my $url_params = shift;
    $url_params = url_dispatch( $url_params );

    my $ip = $url_params->{form}->{ipaddr};

    my $result = find_mac_address($ip);

    #return [0, 'not found']
    #    if $result->[0] eq 'not found' && ref($result->[5]) ne 'ARRAY';

    my $res = "<b>$ip</b> MAC address: <b>" . $result->[0] . "</b><p>";
    $res .= "found at " . $result->[2] . "<p>"
        if defined $result->[2];

    return [0, $res]
        if ref($result->[5]) ne 'ARRAY' || ! @{$result->[5]};

    my $table = table_begin("checked hosts", 2);
    $table->setAttr('class="w"');
    $table->setAlign("LEFT");

    $table->addRow
    (
         make_col_title("name"),
         make_col_title("ip"),
    );

    for (@{$result->[5]})
    {
        $table->addRow(@$_);
    }

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return [0, $res . $table];
}

1;
