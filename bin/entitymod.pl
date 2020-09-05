#!/usr/bin/perl -w

use strict;
use Getopt::Long;

use lib "$ENV{AKKADA}/lib";
use Tree;
use DB;
use FormProcessor::form_options_mandatory;
use FormProcessor::form_options_update;


my $url_params = app_options();

exit
    unless keys %$url_params;

my $form_result;
my $work;

if (keys %{$url_params->{oman}->{form}} > 1)
{
++$work;
print "processing mandatory options...\n";

$FormProcessor::form_options_mandatory::CMDMode = 1;

$form_result = eval 
{
    FormProcessor::form_options_mandatory::process($url_params->{oman});
};

if (ref($form_result) ne 'ARRAY')
{
    print $@, "\n";
}
elsif ($form_result->[0] == 1)
{
    print $form_result->[1],"\n";
}
else
{
    print "update OK\n";
    print $form_result->[1], "\n"
        if $form_result->[1];
}

}

if (keys %{$url_params->{opar}->{form}} > 1)
{

++$work;
print "processing optional parameters...\n";

$FormProcessor::form_options_update::CMDMode = 1;

$form_result = eval 
{
    FormProcessor::form_options_update::process($url_params->{opar});
};

if (ref($form_result) ne 'ARRAY')
{
    print $@, "\n";
}
elsif ($form_result->[0] == 1)
{
    print $form_result->[1],"\n";
}
else
{
    print "update OK\n";
    print $form_result->[1], "\n"
        if $form_result->[1];
}


}

if (! $work)
{
    print "nothing done.\n";
}

sub app_options 
{
    my $help = 0;
    my $id_entity = '';
    my $name = '';
    my $check_period = '';
    my $check_period_children = 0;
    my $monitor = '';
    my $monitor_children = 0;
    my $status_weight = '';
    my $calculated_status_weight = '';
    my $id_parent = '';
    my %update = ();
    my @delete = ();
    my %add = ();

    my $result = {};

    if (!GetOptions(
                     'help|?'   => \$help,
                     'id_entity=i'  => \$id_entity,
                     'name=s'  => \$name,
                     'check_period=i'  => \$check_period,
                     'check_period_children'  => \$check_period_children,
                     'monitor=i'  => \$monitor,
                     'monitor_children'  => \$monitor_children,
                     'status_weight=i'  => \$status_weight,
                     'calculated_status_weight=i'  => \$calculated_status_weight,
                     'id_parent=i'  => \$id_parent,
                     'set=s'  => \%update,
                     'delete=s'  => \@delete,
                    ) || $help || ! $id_entity)
    {
        app_usage(2);
    }

    $result->{oman}->{form}->{id_entity} = $id_entity;
    $result->{opar}->{form}->{id_entity} = $id_entity;
    
    $result->{oman}->{form}->{name} = $name if $name ne '';
    $result->{oman}->{form}->{check_period} = $check_period if $check_period ne '';
    $result->{oman}->{form}->{check_period_children} = $check_period_children if $check_period_children;
    $result->{oman}->{form}->{monitor} = $monitor if $monitor ne '';
    $result->{oman}->{form}->{monitor_children} = $monitor_children if $monitor_children;
    $result->{oman}->{form}->{status_weight} = $status_weight if $status_weight ne '';
    $result->{oman}->{form}->{calculated_status_weight} = $calculated_status_weight if $calculated_status_weight ne '';
    $result->{oman}->{form}->{id_parent} = $id_parent if $id_parent ne '';

    for (keys %update)
    {
        $result->{opar}->{form}->{$_} = $update{$_};
    }
    for (@delete)
    {
        $result->{opar}->{form}->{'delete_' . $_} = 1;
    }

    return $result;
}

sub app_usage 
{
    my $exit = shift;

    print STDERR <<EOF;

AKK\@DA Entity modification tool.

Usage: $0 [-help] [-option=...] 

    -help		        this message

mandatory:
    -id_entity                  id of the entity to update

options:
    -name                       name of the entity
    -check_period               check period in seconds
    -check_period_children      check period change will affect all node's services
    -monitor                    0/1, disable/enable monitoring of the entity
    -monitor_children           monitor change will affect all node's services
    -status_weight              status weight
    -calculated_status_weight   calculated status weight
    -id_parent                  id of the parent entity

for all other optional parameters use syntax:

add or update:
    --set function=router --set vendor=microsoft --set nic_ip=123.123.123.123

delete:
    --delete function  --delete vendor


EOF
    exit $exit 
        if defined $exit && $exit != 0;
}


