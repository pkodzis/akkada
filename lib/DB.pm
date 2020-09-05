package DB;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;         
use MyException qw(:try);
use Configuration;
use DBI;

use Log;
use Constants;

use constant DBH => 0;
use constant DISABLE_UPDATES => 1;

our $CHARSET = CFG->{Database}->{CharSet} || 'utf8';

sub new
{       
    my $class = shift;
    my $self;

    try
    {
        $self->[DBH] = DBI->connect
            (
                CFG->{Database}->{DSN},
                CFG->{Database}->{Username},
                CFG->{Database}->{Password},
                { 'RaiseError' => 1 },
            );
        $self->[DBH]->do('set names ' . $CHARSET);
        $self->[DBH]->do('set charset ' . $CHARSET);
    }
    except
    {
        throw EDBConnect("database initialization problem: $@");
    };
    bless $self, $class;
    log_debug("DBCONN", _LOG_INTERNAL);
    return $self;
}

sub disable_updates
{
    my $self = shift;
    if (@_)
    {
        $self->[DISABLE_UPDATES] = shift;
    }
    return $self->[DISABLE_UPDATES];
}

sub exec
{
    my $self = shift;

    throw EMissingArgument("nothink to do.... give me somethink!")
        unless @_;

    throw EBadArgumentType("job must be a not empty string")
        unless ref($_[0]) eq '' and $_[0] ne '';

    my $req;
    my $job = shift;

    $job =~ s/\000//g;
    $job =~ s/\\/\\\\/g;

    if ($job =~/^update /i && $self->disable_updates)
    {
        log_debug(sprintf(qq|update ignored: %s|, $job), _LOG_INTERNAL);
        return undef;
    }

    try
    {
        log_debug(sprintf(qq|job: %s|, $job), _LOG_DBINTERNAL);
        $req = $self->dbh->prepare($job);
        $req->execute();
    }
    except
    {
        if ($self->dbh->err == 1062)
        {
            throw EDBDupl('duplicate key');
        }
        else
        {
            throw EDBExec(sprintf("job: %s; error: %s", $job, $@));
        }
    };

    return $req;
}

sub dbh
{
    my $self = shift;

    throw EReadOnlyMethod
        if @_;

    if (! $self->[DBH]->ping)
    {
        try
        {
            $self->[DBH] = DBI->connect
            (
                CFG->{Database}->{DSN},
                CFG->{Database}->{Username},
                CFG->{Database}->{Password},
                { 'RaiseError' => 1 },
            );
            $self->[DBH]->do('set names ' . $CHARSET);
            $self->[DBH]->do('set charset ' . $CHARSET);
        }
        except
        {
            throw EDBConnect("database initialization problem: $@");
        };
    }
    return $self->[DBH];
}


sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}


sub DESTROY
{
    if (defined $_[0]->[DBH])
    {
        $_[0]->[DBH]->disconnect;
        log_debug("DBDISC",_LOG_INTERNAL);
    }
}


1;
