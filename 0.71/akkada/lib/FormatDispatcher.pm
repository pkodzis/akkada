package FormatDispatcher;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION );

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( format_dispatch );
%EXPORT_TAGS = ( default => [qw( format_dispatch )] );

use strict;
use Constants;
use Log;

sub format_dispatch
{
    my $s = shift;
    return $s =~ /\|\|TEXT\|\|/
        ? _text($s)
        : _stat($s);
}

sub _text
{
    my $s = shift;
    my $error = '';

    my @fields = split /\|\|/, $s;
#use Data::Dumper; log_debug(Dumper(\@fields),_LOG_ERROR);
    shift @fields;
    shift @fields;

    my $allowed =
    {
        'output' => 1,
        'expected' => 1,
        'bad' => 1,
        'brief' => 1,
    };

    my $text = {};

    my @f;
#log_debug(Dumper(\@fields),_LOG_ERROR);
    @fields = @fields
        ? split /\:\:/, $fields[0]
        : ();

#use Data::Dumper; log_debug(Dumper(\@fields),_LOG_ERROR);
    for (@fields)
    {
        @f = split /=/, $_, 2;
        if (@f < 2 || (defined $f[0] && ! defined $allowed->{ $f[0] } ) )
        {
             $error = sprintf(qq|bad output format: %s|, join('=', @f));
             return ($text, $error);
        }
        if ($f[0] eq 'output')
        {
             $text->{output} = defined $f[1] ? $f[1] : '';
        }
        elsif ($f[0] eq 'brief')
        {
             $text->{brief} = defined $f[1] ? $f[1] : '';
        }
        elsif ($f[0] eq 'bad' || $f[0] eq 'expected')
        {
             push @{ $text->{$f[0]} }, $f[1]
                 if defined $f[1];
        }
    }
#use Data::Dumper; log_debug(Dumper($text),_LOG_ERROR);

    $error = "bad output format: missing output field"
        unless defined $text->{output};

    return ($text, $error);
}

sub _stat
{
    my $s = shift;
    my $result = {};
    my $error = '';

    my @defs = split /\|\|/, $s;
    shift @defs;
    shift @defs;

    my $allowed =
    {
        'output' => 1,
        'cfs' => 1,
        'title' => 1,
        'min' => 0,
        'max' => 0,
    };

    my $cfs_allowed =
    {
        'GAUGE' => 1,
        'COUNTER' => 1,
    };

    my @f;
    my @fields;
    my $i=0;

    for my $def (@defs)
    {
        @fields = split /\:\:/, $def;
        ++$i;

        for (@fields)
        {
            @f = split /=/, $_, 2;
            if (@f < 2 || (defined $f[0] && ! defined $allowed->{ $f[0] } ) )
            {
                $error = sprintf(qq|bad output format: %s|, join('=', @f));
                return($result, $error);
            }
            $result->{$i}->{$f[0]} = defined $f[1] ? $f[1] : '';
        }

        for (keys %$allowed)
        {
            next
                unless $allowed->{$_};

            next
                if defined $result->{$i}->{$_};

            $error = sprintf(qq|bad output format: missing %s field|, $_);
            return($result, $error);
        }

        if ($result->{$i}->{output} !~ /^-{0,1}\d*\.{0,1}\d+$/)
        {
            $error = "bad output format: output must be a number";
            return($result, $error);
        }
    }

    return ($result, $error);
}

1;
