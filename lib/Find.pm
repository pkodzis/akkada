package Find;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;         
use Forms;
use Configuration;
use NodesList;
use Constants;
use Common;

our $DataDir = CFG->{Probe}->{DataDir};
our $GrepBin = CFG->{GrepBin};

use constant 
{
    CGI => 0,
    SESSION => 1,
    VIEW_ENTITIES => 2,
    DBH => 3,
    TREE => 4,
};

sub new
{       
    my $class = shift;

    my $self;

    $self->[CGI] = shift;
    $self->[SESSION] = shift;
    $self->[DBH] = shift;
    $self->[TREE] = shift;

    bless $self, $class;
=pod
    my $options = $self->session->param('_FIND');

    $self->find_entities($options)
        if defined $options && ref($options) eq 'HASH' && keys %$options;
=cut

    return $self;
}

sub view_entities
{
    return $_[0]->[VIEW_ENTITIES];
}

sub dbh
{
    return $_[0]->[DBH];
}

sub cgi 
{
    return $_[0]->[CGI];
}

sub tree
{
    return $_[0]->[TREE];
}

sub session
{
    return $_[0]->[SESSION];
}

sub find_entities
{
    my $self = shift;

    my $options = @_ ? shift : $self->session->param('_FIND');

    return 
        unless defined $options && ref($options) eq 'HASH' && keys %$options;

    my $dbh = $self->dbh;

    my $statement = qq|SELECT id_entity FROM entities |;
    my @cond = ();
    my @cond_calc = ();
    my $statuses_calc = undef;

    if ($options->{ip})
    {
         push @cond, qq|(id_entity in (SELECT entities.id_entity FROM entities,parameters,entities_2_parameters WHERE parameters.name='ip' AND parameters.id_parameter=entities_2_parameters.id_parameter AND entities_2_parameters.id_entity=entities.id_entity AND value like '%$options->{ip}%') OR id_entity in (SELECT entities.id_entity FROM entities,parameters,entities_2_parameters WHERE parameters.name='nic_ip' AND parameters.id_parameter=entities_2_parameters.id_parameter AND entities_2_parameters.id_entity=entities.id_entity AND value like '%$options->{ip}%'))|;
         push @cond_calc, qq|(entities.id_entity in (SELECT entities.id_entity FROM entities,parameters,entities_2_parameters WHERE parameters.name='ip' AND parameters.id_parameter=entities_2_parameters.id_parameter AND entities_2_parameters.id_entity=entities.id_entity AND value like '%$options->{ip}%') OR id_entity in (SELECT entities.id_entity FROM entities,parameters,entities_2_parameters WHERE parameters.name='nic_ip' AND parameters.id_parameter=entities_2_parameters.id_parameter AND entities_2_parameters.id_entity=entities.id_entity AND value like '%$options->{ip}%'))|;
    }

    if ($options->{id_parent})
    {
        my @ids = keys %{ $self->tree->get_node_down_family($options->{id_parent}) };
        push @cond, sprintf(qq|(id_entity in (%s))|, join(',', @ids))
            if @ids;
        push @cond_calc, sprintf(qq|(entities.id_entity in (%s))|, join(',', @ids))
            if @ids;
    }

    if ($options->{name})
    {
        push @cond, qq|id_entity in (SELECT id_entity FROM entities WHERE name like '%$options->{name}%'| 
            . ($options->{case} ? ' COLLATE latin1_bin' : '') . ')';
        push @cond_calc, qq|entities.id_entity in (SELECT id_entity FROM entities WHERE name like '%$options->{name}%'| 
            . ($options->{case} ? ' COLLATE latin1_bin' : '') . ')';
    };

    if ($options->{function})
    {
        push @cond, qq|id_entity in ( SELECT entities.id_entity FROM entities,parameters,entities_2_parameters 
            WHERE entities_2_parameters.id_entity=entities.id_entity 
            AND entities_2_parameters.id_parameter=parameters.id_parameter 
            AND parameters.name='function' 
            AND entities_2_parameters.value like '%$options->{function}%' )|;
    }

    if ($options->{cdata})
    {
        my @tmp = ();

        open(F, sprintf(qq|cd %s; %s -l -E "%s" *\||, $DataDir, $GrepBin, $options->{cdata}));
        while (<F>)
        {
            s/\n//g;
            s/$DataDir\///g;
            push @tmp, $_;
        }
        closedir(F);

        if (@tmp)
        {
            push @cond, sprintf(qq|id_entity in (%s)|, join(",", @tmp));
        }
    }

    if (defined $options->{id_probe_type} && $options->{id_probe_type} ne '' && $options->{id_probe_type} !~ /:/)
    {
        push @cond, qq|id_entity in (SELECT id_entity FROM entities WHERE id_probe_type = $options->{id_probe_type})|;
        push @cond_calc, qq|entities.id_entity in (SELECT id_entity FROM entities WHERE id_probe_type = $options->{id_probe_type})|;
    }
    elsif (defined $options->{id_probe_type} && $options->{id_probe_type} ne '')
    {
         my $id_probe_type = (split /:/, $options->{id_probe_type})[1];
         push @cond, qq|id_entity in (SELECT entities.id_entity FROM entities,parameters,entities_2_parameters WHERE parameters.name='snmp_generic_definition_name' AND parameters.id_parameter=entities_2_parameters.id_parameter AND entities_2_parameters.id_entity=entities.id_entity AND value = '$id_probe_type')|;
         push @cond_calc, qq|entities.id_entity in (SELECT entities.id_entity FROM entities,parameters,entities_2_parameters WHERE parameters.name='snmp_generic_definition_name' AND parameters.id_parameter=entities_2_parameters.id_parameter AND entities_2_parameters.id_entity=entities.id_entity AND value = '$id_probe_type')|;
    }

    if (defined $options->{status} && $options->{status} ne '' && $options->{status} ne '-1')
    {
        push @cond, "((status=" . $options->{status} 
            . " AND flap=0) OR (flap<>0 AND flap_status=" 
            . $options->{status} . "))";
        push @cond, "status_weight<>0";
        push @cond, "monitor=1"
            if $options->{status} != _ST_NOSTATUS;
        push @cond, "id_probe_type>1"
            if $options->{status} != _ST_UNREACHABLE && $options->{status} != _ST_NOSNMP;

        push @cond_calc, "statuses.status=" . $options->{status} . " AND entities.status<>5 AND entities.status<>6";
        push @cond_calc, "statuses.status_weight<>0";
        push @cond_calc, "monitor=1"
            if $options->{status} != _ST_NOSTATUS;
        push @cond_calc, "id_probe_type<2";

=pod
        $statuses_calc = $self->dbh->exec("SELECT entities.id_entity FROM entities,statuses WHERE statuses.status=" 
            . $options->{status} 
            . " AND statuses.status_weight<>0 AND id_probe_type<2 
            AND entities.id_entity=statuses.id_entity")->fetchall_arrayref;

        $statuses_calc = [ map { $_->[0] } @$statuses_calc ]
            if defined $statuses_calc && ref($statuses_calc) eq 'ARRAY' && @$statuses_calc;
=cut
    }
    elsif (defined $options->{status} && $options->{status} ne '')
    {
        push @cond, "((status<>0 AND flap=0) OR (flap<>0 AND flap_status<>0))";
        push @cond, "status_weight<>0";
        push @cond, "monitor=1";
        push @cond, "id_probe_type>1";
        push @cond_calc, "statuses.status<>0 AND entities.status<>5 AND entities.status<>6";
        push @cond_calc, "statuses.status_weight<>0";
        push @cond_calc, "monitor=1";
        push @cond_calc, "id_probe_type<2";
    }


    $statement .= 'WHERE ' . join(' AND ', @cond)
       if @cond;

    return
        if $statement eq qq|SELECT id_entity FROM entities |;

#warn $statement;
    my $res = $self->dbh->exec($statement)->fetchall_arrayref;

    $self->[VIEW_ENTITIES] = [ map { $_->[0] } @$res ]
        if defined $res && ref($res) eq 'ARRAY' && @$res;

    if ($options->{status})
    {
        $statement = qq|SELECT entities.id_entity FROM statuses,entities WHERE entities.id_entity=statuses.id_entity|;
        $statement .= " AND " . join(' AND ', @cond_calc)
            if @cond_calc;

#warn $statement;
        $statuses_calc = $self->dbh->exec($statement)->fetchall_arrayref;

        $statuses_calc = [ map { $_->[0] } @$statuses_calc ]
            if defined $statuses_calc && ref($statuses_calc) eq 'ARRAY' && @$statuses_calc;

        if (defined $statuses_calc)
        {
            push @{$self->[VIEW_ENTITIES]}, @$statuses_calc;
        }
    }
}

sub form_entity_find
{
    my $self = shift;
    my $views = @_ ? shift : undef;
    my $cgi = $self->cgi;

    my $cont;
    $cont->{form_name} = 'form_entity_find';
    $cont->{no_border} = 1;
    push @{ $cont->{buttons} }, { caption => "find", url => "javascript:document.forms['form_entity_find'].submit()" };

    my $options = $self->session->param('_FIND');

    push @{ $cont->{rows} },
    [
        'entity name',
        $cgi->textfield({ name => 'name', value => defined $options && defined $options->{name} ? $options->{name} : ''
            , class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'entity ip',
        $cgi->textfield({ name => 'ip', value => defined $options && defined $options->{ip} ? $options->{ip} : ''
            , class => "textfield",}),
    ];
    push @{ $cont->{rows} },
    [
        'case sensitive',
        $cgi->checkbox({name => "case", label => "", checked => defined $options && defined $options->{case} ? $options->{case} : ''}),
    ];
    push @{ $cont->{rows} },
    [
        'probe type',
        $self->get_probe_types($options),
    ];

    push @{ $cont->{rows} },
    [
        'status',
        $self->get_statuses($options),
    ];

    push @{ $cont->{rows} },
    [
        'entity function',
        $cgi->textfield({ name => 'function', value => defined $options && defined $options->{function} ? $options->{function} : ''
            , class => "textfield",}),
    ];

    push @{ $cont->{rows} },
    [
        'data',
        $cgi->textfield({ name => 'cdata', value => defined $options && defined $options->{cdata} ? $options->{cdata} : ''
            , class => "textfield",}),
    ];

    my $nodeslist = NodesList->new({
        title => 'find in',
        form => $cont,
        field_name => 'id_parent',
        default_id => defined $options->{id_parent} ? $options->{id_parent} : '',
        dbh => $self->dbh,
        cgi => $self->cgi,
        tree => $self->tree,
    });

    my $form_view_add = '';
    if (defined $views)
    {
        $options = join("&", map { "$_=$options->{$_}" } grep { defined $options->{$_} && $options->{$_} } keys %$options);
        $form_view_add = make_popup_form($views->form_view_add($options), 'section_form_view_add', 'save result as view') . '<br>'
            if $options;
    }

    return form_create($cont) . $form_view_add;
}

sub get_probe_types
{
    my $self = shift;
    my $options = shift;
    my $cgi = $self->cgi;
    my %pm = %{CFG->{ProbesMapRev}};
    my $snmp_generic;

    eval "require Probe::snmp_generic; \$snmp_generic = Probe::snmp_generic->new();" or die $@;

    my $id_snmp_generic = CFG->{ProbesMap}->{snmp_generic};

    $pm{''} = "--- select (optional) ---";
    $pm{$id_snmp_generic} = "snmp_generic (all)";
    for (keys %{$snmp_generic->def})
    {
        $pm{"$id_snmp_generic:$_"} = "snmp_generic ($_)";
    }

    return $cgi->popup_menu(-name=>'id_probe_type', -values=>[ sort { uc $pm{$a} cmp uc $pm{$b} } keys %pm], -labels=> \%pm, -default => defined $options && defined $options->{id_probe_type} ? $options->{id_probe_type} : '', -class => 'textfield'),
}


sub get_statuses
{
    my $self = shift;
    my $options = shift;
    my $cgi = $self->cgi;

    my %pm = %_ST_LIST;

    for (keys %pm)
    {
        $pm{$_} = status_name($_);
    }
    $pm{-1} = 'not OK';
    $pm{''} = "--- select (optional) ---";

    return $cgi->popup_menu(-name=>'status', -values=>[ sort { uc $pm{$a} cmp uc $pm{$b} } keys %pm], -labels=> \%pm, -default => defined $options && defined $options->{status} ? $options->{status} : '', -class => 'textfield'),
}


1;
