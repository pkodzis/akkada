package Find;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;         
use Forms;
use Configuration;
use NodesList;

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

    my $options = $self->session->param('_FIND');

    $self->find_entities($options)
        if defined $options && ref($options) eq 'HASH' && keys %$options;

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
    my $options = shift;
    my $dbh = $self->dbh;

    my $statement = qq|SELECT id_entity FROM entities |;
    my @cond = ();

    if ($options->{ip})
    {
         push @cond, qq|(id_entity in (SELECT entities.id_entity FROM entities,parameters,entities_2_parameters WHERE parameters.name='ip' AND parameters.id_parameter=entities_2_parameters.id_parameter AND entities_2_parameters.id_entity=entities.id_entity AND value like '%$options->{ip}%') OR id_entity in (SELECT entities.id_entity FROM entities,parameters,entities_2_parameters WHERE parameters.name='nic_ip' AND parameters.id_parameter=entities_2_parameters.id_parameter AND entities_2_parameters.id_entity=entities.id_entity AND value like '%$options->{ip}%'))|;
    }

    if ($options->{id_parent})
    {
        my @ids = keys %{ $self->tree->get_node_down_family($options->{id_parent}) };
        push @cond, sprintf(qq|(id_entity in (%s))|, join(',', @ids))
            if @ids;
    }

    push @cond, qq|id_entity in (SELECT id_entity FROM entities WHERE name like '%$options->{name}%'| 
        . ($options->{case} ? ' COLLATE latin1_bin' : '') . ')'
        if $options->{name};

    if ($options->{id_probe_type} && $options->{id_probe_type} !~ /:/)
    {
        push @cond, qq|id_entity in (SELECT id_entity FROM entities WHERE id_probe_type = $options->{id_probe_type})|;
    }
    elsif ($options->{id_probe_type})
    {
         my $id_probe_type = (split /:/, $options->{id_probe_type})[1];
         push @cond, qq|id_entity in (SELECT entities.id_entity FROM entities,parameters,entities_2_parameters WHERE parameters.name='snmp_generic_definition_name' AND parameters.id_parameter=entities_2_parameters.id_parameter AND entities_2_parameters.id_entity=entities.id_entity AND value = '$id_probe_type')|;
    }

    $statement .= 'WHERE ' . join(' AND ', @cond)
       if @cond;

    return
        if $statement eq qq|SELECT id_entity FROM entities |;

    my $res = $self->dbh->exec($statement)->fetchall_arrayref;

    $self->[VIEW_ENTITIES] = [ map { $_->[0] } @$res ]
        if defined $res && ref($res) eq 'ARRAY' && @$res;
}

sub form_entity_find
{
    my $self = shift;
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

    my $nodeslist = NodesList->new({
        title => 'find in',
        form => $cont,
        field_name => 'id_parent',
        default_id => defined $options->{id_parent} ? $options->{id_parent} : '',
        dbh => $self->dbh,
        cgi => $self->cgi,
        tree => $self->tree,
    });

    return form_create($cont);
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

1;
