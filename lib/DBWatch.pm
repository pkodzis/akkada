package DBWatch;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;         
use MyException qw(:try);
use Configuration;
use DB;
use Constants;
use Common;
use Log;

our $Period = CFG->{DBWatch}->{Period};
our $FlagsControlDir = CFG->{FlagsControlDir};
our $LogEnabled = CFG->{LogEnabled};
our $Start = 1;

use constant
{
    DBH => 0,
    ENTITIES_COUNT => 1,
};

sub new
{       
    my $class = shift;

    my $self = [];
    $self->[DBH] = DB->new();
    $self->[ENTITIES_COUNT] = 0;

    bless $self, $class;

    $SIG{USR1} = \&got_sig_usr1;
    $SIG{USR2} = \&got_sig_usr2;
    $SIG{TRAP} = \&trace_stack;

    return $self;
}

sub entities_count
{
    my $self = shift;
    if (@_)
    {
        log_debug(sprintf(qq|entities count change detected. old: %s; new: %s|, 
            $self->[ENTITIES_COUNT],
            $_[0]), _LOG_DEBUG)
            if $LogEnabled;

        $self->[ENTITIES_COUNT] = shift;
        flag_files_create($FlagsControlDir, 
            'entities_init.Discover',
            'entities_init.Available',
            'entities_init.ICMPMonitor',
            'available2.init_graph',
            );
        if ($Start)
        {
            flag_files_create($FlagsControlDir, 'replan.JobPlanner');
            $Start = 0;
        }
    }
    return $self->[ENTITIES_COUNT];
}

sub dbh
{
    return $_[0]->[DBH];
}

sub run
{
    my $self = shift;
    my $ppid = shift;

    my $entities_count;

    while (1)
    {

        exit
            if ! kill(0, $ppid);

        $entities_count = $self->dbh->exec('select count(*) from entities')->fetchrow_arrayref()->[0];

        $self->entities_count($entities_count)
            unless $entities_count eq $self->entities_count;

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
