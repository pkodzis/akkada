package Tools::cisco_locate_MAC_address;

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
use DB;
use CiscoCAMTable;

use Data::Dumper;
use Log;

sub desc
{
    return <<EOF;
This tool locates MAC address across all monitored Cisco switches.<p>
Please enter MAC address using format xxxx.xxxx.xxxx<p>
EOF
}

=pod
SELECT entities.id_entity,name FROM entities,entities_2_parameters WHERE id_probe_type=1 AND entities.id_entity=entities_2_parameters.id_entity AND entities_2_parameters.id_parameter=15 AND value='cisco';
=cut

sub button_start
{
    my $url_params = shift;
    $url_params = url_dispatch( $url_params );

    my $cgi = CGI->new();

    my $db = DB->new();

    my $sws = $db->dbh->selectall_hashref(qq|SELECT entities.id_entity,entities.name FROM entities,entities_2_parameters,parameters
        WHERE id_probe_type=1 
        AND entities.id_entity=entities_2_parameters.id_entity 
        AND entities_2_parameters.id_parameter=parameters.id_parameter
        AND parameters.name='vendor'
        AND value='cisco'|,
        "id_entity");

    return "function unavailable. currently AKK\@DA does not monitor any cisco device."
        if ! defined $sws || ! keys %$sws;

    my $ips = $db->dbh->selectall_hashref(qq|SELECT entities.id_entity,value FROM entities,entities_2_parameters,parameters
        WHERE id_probe_type=1
        AND entities.id_entity=entities_2_parameters.id_entity
        AND entities_2_parameters.id_parameter=parameters.id_parameter
        AND parameters.name='ip'|,
        "id_entity");


    my $cont;
    $cont->{form_name} = 'fakeform_cisco_locate_MAC_address';
    $cont->{no_border} = 1;

    push @{ $cont->{buttons} }, { caption => "find", url => "javascript:document.forms['fakeform_cisco_locate_MAC_address'].submit()" };

    push @{ $cont->{rows} },
    [
        "<b>locate MAC address:</b>",
        $cgi->textfield({ name => 'mac', value => '', class => "textfield",}),
    ];
    push @{ $cont->{rows} }, [ ];
    push @{ $cont->{rows} }, [ ];
    push @{ $cont->{rows} },
    [
        make_col_title("name"),
        make_col_title("login (optional)"),
        make_col_title("password"),
        make_col_title("type"),
        make_col_title("ignore"),
    ];
    push @{ $cont->{rows} },
    [
        "<b>DEFAULTS:</b>",
        $cgi->textfield({ name => 'login_default', value => '', class => "textfield",}),
        $cgi->textfield({ name => 'passwd_default', value => '', class => "textfield",}),
        $cgi->popup_menu(-name => "type_default", -values=> ['telnet','ssh1','ssh2'], -default=>'telnet'),
    ];

    push @{ $cont->{rows} }, [ ];
    push @{ $cont->{rows} }, [ ];

    for (sort { uc $sws->{$a}->{name} cmp uc $sws->{$b}->{name} } keys %$sws)
    {
        push @{ $cont->{rows} },
        [
            $sws->{$_}->{name},
            $cgi->textfield({ name => "username_$_", value => '', class => "textfield",}),
            $cgi->textfield({ name => "passwd_$_", value => '', class => "textfield",}),
            $cgi->popup_menu(-name => "type_$_", -values=> ['','telnet','ssh1','ssh2'], -default=>''),
            $cgi->checkbox({name => "ignore_$_", label => "", })
                . $cgi->hidden({ name => "name_$_", value => $sws->{$_}->{name}})
                . $cgi->hidden({ name => "ip_$_", value => $ips->{$_}->{value}}),
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

    my $post = {};
    my $mac = lc $url_params->{form}->{mac};

    return [1, "enter MAC address you would like to locate"]
        unless $mac;
    return [1, "enter MAC address in proper format xxxx.xxxx.xxxx; allowed characters: 0-9,a-f,A-F"]
        unless $mac =~ /[0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}/;

    delete $url_params->{form}->{mac};
    delete $url_params->{form}->{form_name};
    delete $url_params->{form}->{id_entity};

    my @tmp;

    for (keys %{$url_params->{form}})
    {
        @tmp = split /_/, $_;
        $post->{$tmp[1]}->{$tmp[0]} = $url_params->{form}->{$_};
    }

    my $res;
    my $result = {};
    my $found = 0;

    for my $id (sort { uc $post->{$a}->{name} cmp uc $post->{$b}->{name} } keys %$post)
    {
        next
            if $id eq 'default';
        next
            if defined $post->{$id}->{ignore};

        $res = get_cam_table
        ( 
            $post->{$id}->{ip},
            defined $post->{$id}->{username} && $post->{$id}->{username}
                ? $post->{$id}->{username}
                : $post->{default}->{username},
            defined $post->{$id}->{passwd} && $post->{$id}->{passwd}
                ? $post->{$id}->{passwd}
                : $post->{default}->{passwd},
            defined $post->{$id}->{type} && $post->{$id}->{type}
                ? $post->{$id}->{type}
                : $post->{default}->{type},
        );
       
        $result->{$id} = { name => $post->{$id}->{name}, ip => $post->{$id}->{ip} }; 
        $result->{$id}->{exitcode} = $res->[0];
        $found = 1
            if defined  $res->[1]->{$mac};
        $result->{$id}->{result} = $res->[1]->{$mac};
    }

    return [0, "search result for MAC address <b>$mac</b>:<p>not found."]
        unless $found;

    my $table = table_begin("search result", 5);
    $table->setAlign('LEFT');
    my $errors = '';

    $table->addRow
    (
         make_col_title("name"),
         make_col_title("ip"),
         make_col_title("interfaces"),
         make_col_title("vlan"),
         make_col_title("description"),
    );

    my $i;

    for (sort { uc $result->{$a}->{name} cmp uc $result->{$b}->{name} } keys %$result) 
    {
        if (! $result->{$_}->{exitcode})
        {
            $i = $_;
               
            if (defined $result->{$i}->{result} && ref($result->{$i}->{result}) && @{$result->{$i}->{result}})
            {
                for (@{$result->{$i}->{result}})
                {
                    $_->[1] =~ /^\d*$/
                        ? $table->addRow("<b>" . $result->{$i}->{name} . "</b>", "<b>" . $result->{$i}->{ip} . "</b>", "<b>" . $_->[0] . "</b>", "<b>" . $_->[1] . "</b>", "<b>" . $_->[2] . "</b>")
                        : $table->addRow($result->{$i}->{name}, $result->{$i}->{ip}, $_->[0], $_->[1], $_->[2]);
                    #join("<br>", map {"$i->[0]; $i->[1]; $i->[2]"} @{$result->{$i}->{result}}))
                }
            }
        }
        else
        {
            if (! $errors)
            {
                $errors = table_begin("errors", 3);
                $errors->setAlign('LEFT');
                $errors->addRow
                (
                    make_col_title("name"),
                    make_col_title("ip"),
                    make_col_title("error"),
                );
            }
            $errors->addRow($result->{$_}->{name}, $result->{$_}->{ip}, $result->{$_}->{exitcode});
        }
    }

    my $color = 0;

    for $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    if ($errors)
    {
        for $i ( 3 .. $errors->getTableRows)
        {
            $errors->setRowClass($i, sprintf(qq|tr_%d|, $color));
            $color = ! $color;
        }
    }

    return [0, "<table><tr><td>search result for MAC address <b>$mac</b>:<p></td></tr><tr><td>$table</td></tr><tr><td>$errors</td></tr></table>"];
}

1;
