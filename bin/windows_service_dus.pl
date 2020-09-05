#!/usr/bin/perl -w

use strict;
use Getopt::Long;

use lib "$ENV{AKKADA}/lib";
use DB;
use Tree;
use Configuration;
use FormProcessor::form_options_mandatory;
$FormProcessor::form_options_mandatory::CMDMode = 1;

my $ID = undef;
my $work = app_options();

return 
    unless $work;

our $ProbesMap = CFG->{ProbesMap};

my $discovery_exclude = CFG->{Probes}->{windows_service}->{DiscoveryExclude};
my $dbh = DB->new();

my $req = $dbh->exec(sprintf(qq|SELECT id_entity,name,monitor FROM entities WHERE id_probe_type=%d|, $ProbesMap->{windows_service} ))->fetchall_hashref("id_entity");

if (defined $ID and $ID)
{
    my $tree = Tree->new({url_params => {}, id_user => 0, view => {}, db => $dbh, root_only => 1});
    my @ch = keys %{$tree->get_node_down_family($ID, "")};

    if (! @ch)
    {
        print sprintf(qq|entity %d has no children\n|, $ID);
        exit;
    }

    my %CH = ();
    @CH{@ch} = @ch;
    for (keys %$req)
    {
        delete $req->{$_}
            unless defined $CH{$_};
    }

    if (! keys %$req)
    {
        print sprintf(qq|entity %d has no children of windows_service type\n|, $ID);
        exit;
    }
}

for my $id_entity (keys %$req)
{
    if (defined $discovery_exclude->{ $req->{$id_entity}->{name} } &&  $discovery_exclude->{ $req->{$id_entity}->{name} })
    {
        if ($req->{$id_entity}->{monitor})
        {
            disable_entity($id_entity);
        }
        elsif($work ==2)
        {
            print sprintf(qq|entity %d: %s: ALREADY DISABLED\n|, $id_entity, $req->{$id_entity}->{name});
        }
    }
    elsif($work == 2)
    {
        print sprintf(qq|entity %d: %s: OK\n|, $id_entity, $req->{$id_entity}->{name});
    }
}

sub disable_entity
{
    my $id_entity = shift;

    my $form_result = eval
    {
        FormProcessor::form_options_mandatory::process( { 'form' => { 'id_entity' => $id_entity, 'monitor' => 0} } );
    };

    if (ref($form_result) ne 'ARRAY')
    {
        print sprintf(qq|entity %d: %s: ERROR: %s\n|, $id_entity, $req->{$id_entity}->{name}, $@);
    }
    elsif ($form_result->[0] == 1)
    {
        print sprintf(qq|entity %d: %s: ERROR: %s\n|, $id_entity, $req->{$id_entity}->{name}, $form_result->[1]);
    }
    else
    {
        print sprintf(qq|entity %d: %s: DISABLED\n|, $id_entity, $req->{$id_entity}->{name});
    }
}

sub app_options 
{
    my $help = 0;
    my $do = 0;
    my $verbose = 0;

    if (!GetOptions(
                     'help|?'   => \$help,
                     'y'  => \$do,
                     'v'  => \$verbose,
                     "id=i"  => \$ID,
                    ) || $help || ! $do)
    {
        app_usage(2);
    }

    return $do+$verbose;
}

sub app_usage 
{
    my $exit = shift;

    print STDERR <<EOF;

AKK\@DA windows_service disable unwanted services 
configure at $ENV{AKKADA}/etc/conf.d/Probes/windows_service.conf

Usage: $0 [-help] [-y] [-v] [-id <entity id>]

    -help		        this message
    -y				starts cleaning procedure
				without that option this tool
				does nothing
    -v				verbose
    -id <entity id>		optional; if defined, operation will be done
				only for all children entities of provided
				entity in the meaning of the locations tree

EOF
    exit $exit 
        if defined $exit && $exit != 0;
}


