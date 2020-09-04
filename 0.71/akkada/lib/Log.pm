package Log;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION $AUTOLOAD );

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( log_exception log_debug );
%EXPORT_TAGS = ( default => [qw(log_exception log_debug)] );

use strict;
use MyException qw(:try);
use Configuration;
use Constants;

our $TraceLevel = CFG->{TraceLevel};

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

