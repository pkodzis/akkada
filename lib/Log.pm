package Log;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION $AUTOLOAD );

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( log_exception log_debug got_sig_usr1 got_sig_usr2 trace_stack);
%EXPORT_TAGS = ( default => [qw(log_exception log_debug init_globals got_sig_usr1 got_sig_usr2 trace_stack)] );

use strict;
use MyException qw(:try);
use Configuration;
use Constants;

our $TraceLevel = CFG->{TraceLevel};

sub init_globals
{
    $TraceLevel = CFG->{TraceLevel};
}

sub trace_stack
{
    if ($MyException::StackTrace)
    {
        $MyException::StackTrace = 0;
        $MyException::TextOneLineMode = 1;
        log_debug("StackTrace disabled", _LOG_ERROR);
    }
    else
    {
        $MyException::StackTrace = 1;
        $MyException::TextOneLineMode = 0;
        log_debug("StackTrace enabled", _LOG_ERROR);
    }
}

sub got_sig_usr1
{
    CFG->{TraceLevel}++;
    Log::init_globals();
    log_debug(sprintf(qq|trace level increased. current trace level %d|, CFG->{TraceLevel}), _LOG_ERROR);
}

sub got_sig_usr2
{
    CFG->{TraceLevel}--
        if CFG->{TraceLevel};
    Log::init_globals();
    log_debug(sprintf(qq|trace level decreased. current trace level %d|, CFG->{TraceLevel}), _LOG_ERROR);
}

sub log_exception
{
    my $exception = shift;
    my $trace = shift;

    if ($trace > $TraceLevel)
    {
        $exception->stringify('no');
    }
    else
    {
        $exception->stringify('text');
    }
}

sub log_debug
{
    my $exception = shift;
    my $trace = shift;

    if ( $trace <= $TraceLevel)
    {
        if ( $trace == _LOG_ERROR )
        {
            $exception = ERROR->new($exception);
        }
        elsif ( $trace == _LOG_WARNING )
        {
            $exception = WARNING->new($exception);
        }
        elsif ( $trace == _LOG_INFO )
        {
            $exception = INFO->new($exception);
        }
        elsif ( $trace == _LOG_DEBUG)
        {
            $exception = DEBUG->new($exception);
        }
        elsif ( $trace == _LOG_INTERNAL)
        {
            $exception = INTERNAL->new($exception);
        }
        else
        {
            $exception = DBINTERNAL->new($exception);
        }
        $exception->stringify('text');
    }
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;

