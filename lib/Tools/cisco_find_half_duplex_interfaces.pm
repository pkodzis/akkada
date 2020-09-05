package Tools::cisco_find_half_duplex_interfaces;

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
use CiscoHD;

use Data::Dumper;
use Log;

sub desc
{
    return <<EOF;
This tool locates half duplex interfaces across all monitored Cisco switches.<p>
EOF
}

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
    $cont->{form_name} = 'fakeform_cisco_find_hd';
    $cont->{no_border} = 1;

    push @{ $cont->{buttons} }, { caption => "find", url => "javascript:document.forms['fakeform_cisco_find_hd'].submit()" };

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

        $res = get_hd
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
        $result->{$id}->{result} = $res->[1];
        ++$found
            if ref($res->[1]->{raw}) eq 'ARRAY' && @{$res->[1]->{raw}} > 1;
    }

    return [0, "half duplex interfaces not found."]
        unless $found;

    my $table = table_begin("search result", 3);
    $table->setAttr('class="w"');
    $table->setAlign('LEFT');
    my $errors = '';

    $table->addRow
    (
         make_col_title("name"),
         make_col_title("ip"),
         make_col_title("result"),
    );

    my $i;
    my $scr;

    for (sort { uc $result->{$a}->{name} cmp uc $result->{$b}->{name} } keys %$result) 
    {
        if (! $result->{$_}->{exitcode})
        {
            $i = $_;
               
            if (defined $result->{$i}->{result}->{raw} && ref($result->{$i}->{result}->{raw}) && @{$result->{$i}->{result}->{raw}} > 1)
            {
                $table->addRow("<pre>" . $result->{$i}->{name} . "</pre>", 
                    "<pre>" . $result->{$i}->{ip} . "</pre>",  
                    "<pre>" . join("  ", @{$result->{$i}->{result}->{title}}) . "</pre>");
                $table->addRow("", "", "<pre>" . join("\n", @{$result->{$i}->{result}->{raw}}) . "</pre>");
                $scr->{$i} = $result->{$i};
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

    my $scripts = get_scripts($scr);
    return [0, "<table><tr><td>$table</td></tr><tr><td>$errors</td></tr><tr><td><pre>$scripts</pre></td></tr></table><p>" . get_signature() . "<p>&nbsp;"];
}

sub get_scripts
{
    my $data = shift;
    my $result;
    my $d;

    for my $id (sort { uc $data->{$a}->{name} cmp uc $data->{$b}->{name} } keys %$data)
    {
        $d = $data->{$id}->{result}->{parsed};

        $result .= "#\n# $data->{$id}->{name} ($data->{$id}->{ip}) IMPLEMENTATION SCRIPT:\n#\n";
        for (@$d)
        {
            $result .= "interface $_->{interface}\n  !description $_->{desc}\n  speed "
                . ($_->{speed} eq 'a-10' ? '10' : '100') . "\n  duplex full\n!\n";
        }        
        $result .= "end\n\n";

        $result .= "#\n# $data->{$id}->{name} ($data->{$id}->{ip}) VERIFICATION SCRIPT:\n#\n";
        for (@$d)
        {
            $result .= "show interface $_->{interface} \| in line protocol\n";
        }        
        $result .= "\n";

        $result .= "#\n# $data->{$id}->{name} ($data->{$id}->{ip}) BACK OUT SCRIPT:\n#\n";
        for (@$d)
        {
            $result .= "interface $_->{interface}\n  !description $_->{desc}"
                . ($_->{speed} =~ /a\-/ ? "\n  no speed" : '') . "\n  no duplex\n!\n";
        }        
        $result .= "end\n\n";
        $result .= "###############################################################################\n\n";
    }


    return $result;
}

1;
