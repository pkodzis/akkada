package JobPlanner;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;         
use MyException qw(:try);
use Configuration;
use Proc::ProcessTable;
use DB;
use Common;
use Constants;
use Log;

# JobPlanner ma dzialac tak:
# 
#	-wczytuje liste procesow
#	-porownuje liste procesow z zarejestrowanymi w $self->probes
#		-jelsi jakiegos brakuje w liscie procesow to jest kasowany z $self->probes
#		 jednoczesnie robiony jest update zapisow w bazie danych
#
#	

use constant
{
    PROBES => 0,
    PIDS => 1,
    DBH => 2,
};

our $FlagsControlDir = CFG->{FlagsControlDir};
our $Period = CFG->{JobPlanner}->{Period};
our $LogEnabled = CFG->{LogEnabled};

sub new
{       
    my $class = shift;

    my $self = [];
    $self->[PROBES] = {};
    $self->[PIDS] = {};
    $self->[DBH] = DB->new();

    bless $self, $class;
    return $self;
}

sub probes_update
{
    my $self = shift;
    my $current = shift;

    for my $probe ( keys %{ $self->probes } )
    {
        for my $pid ( keys %{ $self->probes->{$probe} } )
        {
            next
                if $pid eq 'change';
            defined $current->{$probe}->{$pid}
                ? delete $current->{$probe}->{$pid}
                : $self->pid_remove( $probe, $pid );
        }
    }

    for my $probe ( keys %$current )
    {
        for my $pid ( keys %{ $current->{$probe} } )
        {
            $self->pid_add( $probe, $pid );
        }
    }
}

sub db_update
{
    my $self = shift;

    my @pids;
    my @id_entities;
    my $id_probe_type;
    my @ar;
    my $part;

    my $replan = flag_file_check($FlagsControlDir, 'replan.JobPlanner', 1);

    for my $probe ( keys %{ $self->probes } )
    {
            #print "change: ", $self->probes->{$probe}->{change}, "\n";

        if (! $replan)
        {
            next 
                unless $self->probes->{$probe}->{change}
        }

        $self->probes->{$probe}->{change} = 0;
        @pids = grep {! /^change$/ } keys %{ $self->probes->{$probe} };
        next
            unless @pids > 0;

        $id_probe_type = CFG->{ProbesMap}->{$probe};

        $self->dbh->exec(sprintf(qq|UPDATE entities SET probe_pid='' WHERE id_probe_type=%s|, $id_probe_type));

        @id_entities = map $_->[0], 
            @{ $self->dbh->exec( sprintf(qq|SELECT id_entity FROM entities,links 
                WHERE id_probe_type=%s 
                AND id_entity = id_child AND monitor<>0
                ORDER BY id_entity|,
            $id_probe_type) )->fetchall_arrayref };

        fisher_yates_shuffle(\@id_entities)
            if CFG->{JobPlanner}->{ShuffleEntities};
# @id_entities table randomize is not good solution
# hosts are attacked by too many prodcesses at the same time
# and starts to answer much longer
#use Data::Dumper; log_debug($probe . ": " . Dumper(\@id_entities),_LOG_ERROR);

        $part = int(($#id_entities+1) / ($#pids+1));
        $part++
            unless $part;

        while(@id_entities)
        {
            #print "^$part^";
            push @ar, [splice(@id_entities,0,$part)];
        }

        if (@ar > @pids)
        {
            push @{ $ar[$#ar-1] }, @{$ar[$#ar]};
            pop @ar;
        }

        my $pid;
        while (@pids)
        {
            last
                unless @ar;

            $pid = shift @pids;
            $part = shift @ar;

            #log_debug(sprintf( qq|UPDATE entities SET probe_pid=%s WHERE id_probe_type=%s and id_entity in (%s)|, $pid, $id_probe_type, join(',', @$part)), _LOG_ERROR);
            $self->dbh->exec( sprintf( qq|UPDATE entities SET probe_pid=%s 
                WHERE id_probe_type=%s and id_entity in (%s)|,
                $pid, $id_probe_type, join(',', @$part) ) );
            flag_files_create($FlagsControlDir, sprintf(qq|entities_init.%s|, $pid));
                #WHERE id_probe_type=%s and id_entity >= %s AND id_entity <= %s and monitor <> 0|,
                #$pid, $id_probe_type, $part->[0], $part->[$#$part] ) );
        }
    }
};

sub fisher_yates_shuffle 
{
    my $deck = shift;  # $deck is a reference to an array
    return
        unless @$deck;
    my $i = @$deck;
    my $j;
    while (--$i) 
    {
        $j = int rand ($i+1);
        @$deck[$i,$j] = @$deck[$j,$i];
    }
}



sub probes
{
    return $_[0]->[PROBES];
}

sub pid_remove
{
    my $self = shift;
    my $probe = shift;
    my $pid = shift;
    delete $self->probes->{$probe}->{$pid};
    delete $self->pids->{$pid};
    $self->probes->{$probe}->{change} = 1;
}

sub pid_add
{
    my $self = shift;
    my $probe = shift;
    my $pid = shift;
    $self->probes->{$probe}->{$pid} = 1;
    $self->probes->{$probe}->{change} = 1;
    $self->pids->{$pid} = 1;
}

sub pids
{
    return $_[0]->[PIDS];
}

sub dbh
{
    return $_[0]->[DBH];
}

sub get_probe_processes
{
    my $self = shift;

    my $cmndline;

    my $current = {};

    my $t = new Proc::ProcessTable;
    for my $process ( @{$t->table} )
    {
        $cmndline = $process->cmndline;
        next
            unless $cmndline =~ /np-/;
        next
            unless $cmndline =~ /\.pl$/;
        next
            if $cmndline =~ /np-run/;
        $cmndline = (split /np-/, $cmndline)[1];
        $cmndline = (split /\s/, $cmndline)[0];
        $cmndline = (split /\.pl/, $cmndline)[0];
        $current->{$cmndline}->{$process->pid} = 1;
    }

    return $current;
}


sub run
{
    my $self = shift;
    my $ppid = shift;
   
    my $current;
 
    while (1)
    {
        exit
            if ! kill(0, $ppid);

        $current = $self->get_probe_processes;
        $self->probes_update($current);
        $self->db_update;
        sleep ($Period ? $Period : 15);
    }

}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;
