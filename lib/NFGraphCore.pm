package NFGraphCore;

use strict;
use Graph::Easy;
use Time::HiRes qw( gettimeofday );
use Data::Dumper;

use URLRewriter;
use DB;
use Configuration;
use Common;
use Constants;

use constant
{
     URL_PARAMS => 1,
     DBH => 3,
};

our $FileTmp = CFG->{Web}->{RRDGraph}->{DirTmp};
our $CorrelationsDir = CFG->{Probe}->{CorrelationsDir};
our $DOT = CFG->{Available2}->{DOT};
our $DOTranksep = CFG->{Available2}->{DOTranksep};



$FileTmp .= '/'
    unless $FileTmp =~ /\/$/;

sub new 
{
    my $class = shift;
    my $self = [];
    bless $self, $class;

    my $url_params = url_dispatch();

    $self->[DBH] = shift;
    $self->[URL_PARAMS] = $url_params;

    return $self;
}

sub dbh
{
    return $_[0]->[DBH];
}

sub url_params
{
    return $_[0]->[URL_PARAMS];
}

sub get
{
    my $self = shift;

    my $id = $self->url_params->{id_entity};

    my $c = do "$CorrelationsDir/$id";
    my ($vxs, $egs, $degs) = ($c->{correlation}->{vxs}, $c->{correlation}->{egs}, $c->{correlation}->{degs});
    my ($rc, $rcc) = ($c->{correlation}->{root_causes}, $c->{correlation}->{root_causes_candidates});
    $rc = $rcc
        unless keys %$rc;

    $degs = $$degs;

    my %tmph;
    my @tmp = map { (split /:/, $_)[1] } grep { /^id:/ } @$vxs;
    @tmph{@tmp} = @tmp;
    @tmp = map { (split /:/, $_)[1] } map { $degs->{$_}->{host} } keys %$degs;
    @tmph{@tmp} = @tmp;
    @tmp = keys %tmph;


    my $ids = {};
    #my $req = $self->dbh->exec(sprintf(qq|SELECT id_entity,name FROM entities WHERE id_entity IN (%s)|, join(",", @tmp)))->fetchall_arrayref();
    my $req = $self->dbh->exec(sprintf(qq|SELECT entities.id_entity,entities.name,value FROM entities,entities_2_parameters,parameters
        WHERE entities.id_entity=entities_2_parameters.id_entity
        AND entities_2_parameters.id_parameter=parameters.id_parameter
        AND parameters.name='ip'
        AND entities.id_entity IN (%s)|, join(",", @tmp)))->fetchall_arrayref();

    for (@$req)
    {
        $ids->{$_->[0]} = { name => $_->[1], ip => $_->[2], fwd => 0 };
    }

    $req = $self->dbh->exec(sprintf(qq|SELECT entities.id_entity,value FROM entities,entities_2_parameters,parameters
        WHERE entities.id_entity=entities_2_parameters.id_entity
        AND entities_2_parameters.id_parameter=parameters.id_parameter
        AND parameters.name='ip_forwarding'
        AND entities.id_entity IN (%s)|, join(",", @tmp)))->fetchall_arrayref();
    for (@$req)
    {
        next
            unless defined $ids->{$_->[0]};
        $ids->{$_->[0]}->{fwd} = $_->[1];
    };

    my $i;
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


    my $nvxs = [];
    my $name;
    my $nd = load_netdesc;

    for my $vx (@$vxs)
    {
        if ($vx !~ /^id:(.*)/)
        {
            $req = $vx;
            $vx =~ s/^net://;
            push @$nvxs, {name => $vx, fwd => 0, net => 1, desc => defined $nd->{$vx} ? $nd->{$vx} : ''};
                for (@$egs)
                {
                    if ($_->[0] eq $req)
                    {
                        $_->[0] = $vx;
                    }
                    elsif ($_->[1] eq $req)
                    {
                        $_->[1] = $vx;
                    }
                }
        }
        else
        {
            $req = $1;
            $name = $names->{$req}->{name};
            $name = $vx
                unless $name;

            if (! defined $ids->{$req})
            {
                push @$nvxs, {name => $name, fwd => 2, net => 0, ip => ''};
                #push @$nvxs, {name => $vx, fwd => 2, net => 0, ip => ''};
            }
            else
            {
                $ids->{$req}->{name} = $name;
                push @$nvxs, {name => $ids->{$req}->{name}, fwd => $ids->{$req}->{fwd} , net => 0, ip => $ids->{$req}->{ip}};
                $rc->{$ids->{$req}->{name}} = 1
                    if defined $rc->{$vx};
                for (@$egs)
                {
                    if ($_->[0] eq $vx)
                    {
                        $_->[0] = $ids->{$req}->{name};
                    }
                    elsif ($_->[1] eq $vx)
                    {
                        $_->[1] = $ids->{$req}->{name};
                    }
                }
            }
        }
    }

    for my $e (keys %$degs)
    {
        $degs->{$e}->{net} =~ s/^net://;
        $degs->{$e}->{host} =~ /^id:(.*)/;
        $req = $1;
        if (! defined $ids->{$req})
        {
            $degs->{$e}->{host} = {name => $degs->{$e}->{host}, fwd => 2, net => 0, ip => ''};
        }
        else
        {
            $rc->{$ids->{$req}->{name}} = 1
                    if defined $rc->{$degs->{$e}->{host}};
	    $degs->{$e}->{host} = {name => $ids->{$req}->{name}, fwd => $ids->{$req}->{fwd} , net => 0, ip => $ids->{$req}->{ip}};
        }
    }

    $vxs = $nvxs;

#warn Dumper($vxs);
#warn Dumper($egs);
#warn Dumper($degs);

    my $ge = Graph::Easy->new();
    $ge->strict(undef);
    $ge->set_attribute("ranksep", "$DOTranksep equally");
    $ge->set_attribute("bgcolor", "transparent");

    my ($s, $shape, $color, $fill, $style);

    for my $vx (@$vxs)
    {
        $s = $ge->add_node($vx->{name});
        ($shape, $color, $fill, $style) = $self->get_vertix_style($vx->{name}, $vx->{fwd}, $vx->{net});
        $vx->{net}
            ? $s->set_attributes({ shape => $shape, fill => $fill, color => $color, style => $style, 
              label => "$vx->{name}\\n$vx->{desc}",
              fontsize => '8px',
              fontname => 'Helvetica' })
            : $s->set_attributes({ shape => $shape, fill => defined $rc->{$vx->{name}} ? "red" : $fill, color => defined $rc->{$vx->{name}} ? "white" : $color, style => $style,
              label => "$vx->{name}\\n$vx->{ip}", 
              #width => '0.18',
              #height=> '0.18',
              #fixedsize => 'true',
              fontsize => '8px',
              fontname => 'Helvetica' });
    }

    for my $e (keys %$degs)
    {
        if (! $ge->node($degs->{$e}->{net}))
        {
        $s = $ge->add_node($degs->{$e}->{net});
        ($shape, $color, $fill, $style) = $self->get_vertix_style($degs->{$e}->{net}, 0, 1);
        $s->set_attributes({ shape => $shape, fill => "white", color => $color, style => $style,
            fontsize => '8px',
            fontname => 'Helvetica' });
        }
        if (! $ge->node($degs->{$e}->{host}->{name}))
        {
        $s = $ge->add_node($degs->{$e}->{host}->{name});
        ($shape, $color, $fill, $style) = $self->get_vertix_style($degs->{$e}->{host}->{name}, $degs->{$e}->{host}->{fwd}, $degs->{$e}->{host}->{net});
        $s->set_attributes({ shape => $shape, fill => "red", color => "white", style => $style,
            label => "$degs->{$e}->{host}->{name}\\n$degs->{$e}->{host}->{ip}", 
            #width => '0.18',
            #height=> '0.18',
            #fixedsize => 'true',
            fontsize => '8px',
            fontname => 'Helvetica' });
        }
    }

    for my $eg (@$egs)
    {
        if ($s = $ge->add_edge_once($eg->[0], $eg->[1]))
        {
            ($shape, $color, $style) = $self->get_edge_style();;
            $s->set_attributes({ arrowhead => $shape, color => $color, style => $style});
        }
    }

    for my $e (keys %$degs)
    {
        if ($s = $ge->add_edge_once($degs->{$e}->{host}->{name}, $degs->{$e}->{net}))
        {
            ($shape, $color, $style) = $self->get_edge_style();;
            $s->set_attributes({ arrowhead => $shape, color => "#FF0000", style => 'dashed'});
        }
    }

    my $graphviz = $ge->as_graphviz();
    my $ft = $FileTmp . gettimeofday . $$;

    open DOT, "|$DOT -Tpng -o $ft" or die ("Cannot open pipe to $DOT: $!");

    print DOT $graphviz;
    close DOT;

    open(H, "<$ft")
        or die "open: $! $ft";
    print STDOUT <H>;
    close(H);

    unlink($ft)
        or warn "unlink \"$ft\": $!";

}

sub get_edge_style
{
    my $sefl = shift;
    my ($style, $shape, $color);

    $style = '';
    $shape = 'none';
    $color = 'black';

    return ($shape, $color, $style);
}

sub get_vertix_style
{
    my ($self, $v, $fwd, $net) = @_;

    my ($status, $fill , $shape, $color);

    my $style = 'filled';#,rounded

    if ($net)
    {
        $color = 'black';
        #$fill = '#00BFFF';
        #$fill = '#ADFF2F';
        $fill = '#CDCDCD';
        $shape = 'ellipse';
        #$shape = '/akkada/htdocs/img/tcp_generic.gif';
    }
    elsif ($fwd == _FWD_YES)
    {
        $color = 'black';
        #$fill = '#ADFF2F';
        $fill = '#CDCDCD';
        $shape = 'octagon';
        #$shape = '/akkada/htdocs/img/router.gif';
    }
    else
    {
        $color = 'black';
        $fill = '#CDCDCD';
        #$fill = '#ADFF2F';
        $shape = 'box';
        #$shape = '/akkada/htdocs/img/node.gif';
    }

    return ($shape, $color, $fill, $style);
}


1;
