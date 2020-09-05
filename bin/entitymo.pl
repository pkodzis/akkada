#!/usr/bin/perl -w

use strict;
use Getopt::Long;

use lib "$ENV{AKKADA}/lib";
use Tree;
use DB;
use FormProcessor::form_options_mandatory;


my $url_params = app_options();

exit
    unless keys %$url_params;

$FormProcessor::form_options_mandatory::CMDMode = 1;

my $form_result = eval 
{
    FormProcessor::form_options_mandatory::process($url_params);
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
                    ) || $help || ! $id_entity)
    {
        app_usage(2);
    }

    $result->{form}->{id_entity} = $id_entity;
    $result->{form}->{name} = $name if $name ne '';
    $result->{form}->{check_period} = $check_period if $check_period ne '';
    $result->{form}->{check_period_children} = $check_period_children if $check_period_children;
    $result->{form}->{monitor} = $monitor if $monitor ne '';
    $result->{form}->{monitor_children} = $monitor_children if $monitor_children;
    $result->{form}->{status_weight} = $status_weight if $status_weight ne '';
    $result->{form}->{calculated_status_weight} = $calculated_status_weight if $calculated_status_weight ne '';
    $result->{form}->{id_parent} = $id_parent if $id_parent ne '';

    return $result;
}

sub app_usage 
{
    my $exit = shift;

    print STDERR <<EOF;

AKK\@DA Entity mandatory options modify tool.

Usage: $0 [-help] [-option=...] 

    -help		        this message

mandatory:
    -id_entity                  id of the entity to update

optional:
    -name                       name of the entity
    -check_period               check period in seconds
    -check_period_children      check period change will affect all node's services
    -monitor                    0/1, disable/enable monitoring of the entity
    -monitor_children           monitor change will affect all node's services
    -status_weight              status weight
    -calculated_status_weight   calculated status weight
    -id_parent                  id of the parent entity

EOF
    exit $exit 
        if defined $exit && $exit != 0;
}


