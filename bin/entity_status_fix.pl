#!/usr/bin/perl -w

use strict;
use Getopt::Long;

use lib "$ENV{AKKADA}/lib";
use DB;
use Tree;
use Configuration;
use FormProcessor::form_options_mandatory;
$FormProcessor::form_options_mandatory::CMDMode = 1;


my $work = app_options();

return 
    unless $work;

my $dbh = DB->new();


my $req = $dbh->exec("SELECT id_entity,name,status 
    FROM entities WHERE monitor=0 and status<>127")->fetchall_hashref("id_entity");

my $entity;

for my $id_entity (keys %$req)
{
    $entity = Entity->new($dbh, $id_entity);
    $entity->monitor(1);
    $entity->db_update_entity;
    $entity->monitor(0);
    $entity->db_update_entity;
    print sprintf(qq|entity %d: %s: FIXED\n|, $id_entity, $req->{$id_entity}->{name});
}

sub app_options 
{
    my $help = 0;
    my $do = 0;

    my $result = {};

    if (!GetOptions(
                     'help|?'   => \$help,
                     'y'  => \$do,
                    ) || $help || ! $do)
    {
        app_usage(2);
    }

    return $do;
}

sub app_usage 
{
    my $exit = shift;

    print STDERR <<EOF;

AKK\@DA entity status fix tool should be used only for upgrade
to version 0.73 from previous releases. This must be done at the end of
the upgrade procedure when new libraries are available.

Usage: $0 [-help] [-y] 

    -help		        this message
    -y				start fixing procedure

EOF
    exit $exit 
        if defined $exit && $exit != 0;
}


