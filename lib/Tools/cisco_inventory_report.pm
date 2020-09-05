package Tools::cisco_inventory_report;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use Common;
use Window::Buttons;
use Desktop::GUI;
use DB;
use Entity;
use HTML::Table;
use Configuration;

use Log;
use Number::Format qw(:subs);

$Number::Format::DECIMAL_FILL = 1;

require Plugins::utils_node;

our $ProbesMapRev = CFG->{ProbesMapRev};
our $ImagesDir = CFG->{ImagesDir};

sub image_function
{
    my $function = shift;
    $function = 'host'
        unless $function;
    my $alt = shift || '';

    my $img = -e "$ImagesDir/$function.gif"
        ? "/img/$function.gif"
        : "/img/unknown.gif";
    return CGI::img({ src=>$img, class => 'o', alt => $alt ? $alt : "function: $function"});
}

sub image_vendor
{
    my $vendor = shift || '';

    return ''
        unless $vendor;

    my $img = -e "$ImagesDir/$vendor.gif"
        ? "/img/$vendor.gif"
        : "/img/unknown.gif";
    return CGI::img({ src=>$img, class => 'o', alt => "vendor: $vendor"})
}

sub desc
{
    return <<EOF;
generate cisco inventory report for all hosts configured in <b>akk\@da</b>.<p>
it uses SNMP to collect data. for some of the request (e.g. flash information) cisco devices answers slowly.<br>
report's generation can take a few minutes, if your network is large.<p>
EOF
}

sub button_start
{
    my $url_params = shift;
    $url_params = url_dispatch( $url_params );

    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $buttons->add({ caption => 'start' , url => url_get({section => 'tool', start => 1}, $url_params), });
    $buttons->add({ caption => 'start in separate window' , target => $url_params->{tool_name},
        url => url_get({section => 'tool', start => 1}, $url_params), });
    return $buttons->get;
}

sub run
{
    my $url_params = shift;
    $url_params = url_dispatch( $url_params );

    my $db = DB->new();
    my $dbh = $db->dbh;

    $url_params->{options} = 2
        unless defined $url_params->{options} && $url_params->{options};

    my $items = $dbh->selectall_hashref("select entities.id_entity,entities.name,value as ip, status as entity_status,id_probe_type from entities,parameters,entities_2_parameters where parameters.name='ip' and entities_2_parameters.id_parameter = parameters.id_parameter and entities.id_entity=entities_2_parameters.id_entity and entities.id_probe_type=1", "id_entity");

    my $items_functions = $dbh->selectall_hashref("select entities.id_entity,value from entities,entities_2_parameters where id_parameter=16 and entities.id_entity = entities_2_parameters.id_entity", "id_entity");
    my $items_vendors = $dbh->selectall_hashref("select entities.id_entity,value from entities,entities_2_parameters where id_parameter=15 and entities.id_entity = entities_2_parameters.id_entity", "id_entity");

    my $inv = {};
    my $result;
    my $entities;

    for my $id_entity (keys %$items)
    {
        $entities->{$id_entity} = Entity->new( $db, $id_entity, 1);
        next
            unless defined $entities->{$id_entity}->data->{sysObjectID} 
                && $entities->{$id_entity}->data->{sysObjectID} =~ /^1\.3\.6\.1\.4\.1\.9/;

        $ENV{REQUEST_URI} = url_get({ id_entity => $id_entity, section => 'utils', id_probe_type => 1, form_id => 10, utilities_options => 'rawdata' }, $url_params);
        $result = Plugins::utils_node::process($ENV{REQUEST_URI});

        if (ref($result) ne 'ARRAY')
        {
            $result = {error => sprintf(qq|%s: %s|, "Plugins::utils_node.10", $@)};
        }
        else
        {
            if ($result->[0])
            {
                $result = {error => sprintf(qq|%s: %s|,"Plugins::utils_node.10::process", $result->[1] ? $result->[1] : 'unknown error') };
            }
            else
            {
                $result = ref($result->[1]) eq 'HASH' 
                    ? $result->[1] 
                    : $result->[1] 
                        ? { error => $result->[1] }
                        : { error => 'unknown result' };
            }
        }
        $inv->{$id_entity} = $result; 
        $inv->{$id_entity}->{name} = $entities->{$id_entity}->name;
    }

#use Data::Dumper; return [0, "<pre>" . Dumper($inv) . "</pre>"];

    return [0, table_render($entities, $inv) ];
}

sub table_render
{
    my $entities = shift;
    my $inv = shift;

    my $table = table_begin("cisco inventory report", 3);

    $table->addRow
    (
         make_col_title("chassie"),
         make_col_title("description"),
         make_col_title("modules"),
         make_col_title("flash"),
    );

    my @row;
    my $h;

    for my $id_entity (sort { uc $inv->{$a}->{name} cmp uc $inv->{$b}->{name}} keys %$inv)
    {


        @row = ();

        $h = $inv->{$id_entity}->{ChassieNew};

        push @row, sprintf(qq|name: <b>%s</b><br>ip: <b>%s</b><br>model: <b>%s</b><br>backplane: %s<br>slots: %s</br>version: %s<br>S/N: %s|,
            $entities->{$id_entity}->name || $id_entity,
            $entities->{$id_entity}->params('ip'),
            defined $h->{ccnModel} ? $h->{ccnModel} : $h->{ChassieTypeOld},
            $h->{ccnBkplType} || 'n/a',
            defined $h->{ccnNumSlots} ? $h->{ccnNumSlots} : $h->{ChassieSlotsOld} == -1 ? '-' : $h->{ChassieSlotsOld},
            $h->{ChassieVerOld} || 'n/a',
            (defined $h->{ccnSerialNumberString} ? $h->{ccnSerialNumberString} : $h->{ChassieSerialOld}) || 'n/a');

        push @row, $entities->{$id_entity}->data->{sysDescr};
        push @row, table_render_modules($inv->{$id_entity}->{ModulesNew});
        push @row, table_render_fp($inv->{$id_entity}->{fp});

        $table->addRow(@row);
        $table->setCellAttr($table->getTableRows, 2, 'class="e1"');
        $table->setCellAttr($table->getTableRows, $_, 'class="f"')
            for (1, 3, 4);
    }

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return scalar $table;
}

sub table_render_modules
{
    my $data = shift;
    
    return 'n/a'
        unless  keys %$data;

    my $table = table_begin();
    $table->setAlign('left');
    $table->setCellSpacing(0);

    my @row;
    my $h;
    
    for ( sort { $a <=> $b } keys %$data )
    {   
        @row = ();
        $h = $data->{$_};
   
        push @row, defined $h->{cmnModel} ? $h->{cmnModel} : defined $h->{cmnType} ? $h->{cmnType} : $h->{cmType};
        push @row, sprintf(qq|%s<br>slot: %s; ports: %s; slots: %s<br>hw: %s; fw: %s; sw: %s|,
            $h->{cmDescr},
            $_ == -1 ? '-' : $_,
            $h->{cmnNumPorts},
            $h->{cmSlots} || 'n/a',
            (defined $h->{cmnHwVersion} ? $h->{cmnHwVersion} : $h->{cmHwVersion} ) || 'n/a',
            $h->{cmnFwVersion} || 'n/a',
            (defined $h->{cmnSwVersion} ? $h->{cmnSwVersion} : $h->{cmSwVersion}) || 'n/a');
        push @row, sprintf(qq|S/N: %s|, (defined $h->{cmnSerialNumberString} ? $h->{cmnSerialNumberString} : $h->{cmSerial}) || 'n/a');

        #$table->addRow(map {"&nbsp;$_&nbsp;"} @row);
        $table->addRow(@row);
        if ($table->getTableRows > 1)
        {
            $table->setCellAttr($table->getTableRows-1, $_, 'class="n9"')
                for (1..3);
            $table->setCellAttr($table->getTableRows, $_, 'class="f"')
        }
    }

    return scalar $table;
}

sub table_render_fp
{
    my $data = shift;
    
    return 'n/a'
        unless  keys %$data;

    my $table = table_begin();
    $table->setAlign('left');
    $table->setCellSpacing(0);

    my @row;
    my $h;
    
    for my $sl ( sort { $a <=> $b } keys %$data )
    {   
    for ( sort { $a <=> $b } keys %{$data->{$sl}} )
    {
        @row = ();
        $h = $data->{$sl}->{$_};

        push @row, $h->{cfpName};
        push @row, sprintf(qq|size: %s|,
            ($h->{cfpSize} ? sprintf(qq|%sB (%s)|, $h->{cfpSize}, format_bytes($h->{cfpSize})) : 'empty'));
        push @row, sprintf(qq|free: %s|,
            ($h->{cfpFreeSpace} ? sprintf(qq|%sB (%s)|, $h->{cfpFreeSpace}, format_bytes($h->{cfpFreeSpace})) : 'empty'));
        $table->addRow(map {"&nbsp;$_&nbsp;"} @row);
        if ($table->getTableRows > 1)
        {
            $table->setCellAttr($table->getTableRows-1, $_, 'class="n9"')
                for (1..3);
        }
    }
        $h = [ keys %{$data->{$sl}} ];
        $h = @$h;
        $table->setCellRowSpan($table->getTableRows-$h+1, 1, $h);
    }

    return scalar $table;

}

sub make_col_title
{
    my ($name ) = @_;
    return sprintf(qq|<font class="g4">%s</font>|, $name);
}

1;
