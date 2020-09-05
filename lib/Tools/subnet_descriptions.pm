package Tools::subnet_descriptions;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use URLRewriter;
use Common;
use Desktop::GUI;
use HTML::Table;
use Configuration;
use CGI;
use Forms;
use Data::Dumper;
use Log;

sub desc
{
    return <<EOF;
This tool allows making descriptions of subnets. This descriptions are visible
when network's graphs are displayed.<p>
EOF
}

sub button_start
{
    my $url_params = shift;
    $url_params = url_dispatch( $url_params );

    my $cgi = CGI->new();

    my $nd = load_netdesc;

    return "no subnets list. probably module available2 is not enabled."
        unless keys %$nd;
  
    my $cont;
    $cont->{form_name} = 'fakeform_subnet_descriptions';
    $cont->{no_border} = 1;

    push @{ $cont->{buttons} }, { caption => "save", url => "javascript:document.forms['fakeform_subnet_descriptions'].submit()" };

    push @{ $cont->{rows} },
    [
        make_col_title("subnet"),
        make_col_title("descrption"),
    ];

    for (sort { $a cmp $b } keys %$nd)
    {
        push @{ $cont->{rows} },
        [
            $_,
            $cgi->textfield({ name => $_, value => $nd->{$_}, class => "textfield", size => 64}),
        ];
    }

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

    my $nd = load_netdesc;

    delete $url_params->{form}->{form_name};
    delete $url_params->{form}->{id_entity};


    for (keys %{$url_params->{form}})
    {
        $nd->{$_} = $url_params->{form}->{$_};
    }

    $nd = save_netdesc($nd);
    return $nd
        ? [1, "<table><tr><td>subnet descriptions saving problem: $nd</td></tr></table>"]
        : [0, "<table><tr><td>subnet descriptions are updated</td></tr></table>"];
}

1;
