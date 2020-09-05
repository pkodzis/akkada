package URLRewriter;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION);

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( url_dispatch url_get );
%EXPORT_TAGS = ( default => [qw( url_dispatch url_get )] );

use strict;          
use CGI;

use Configuration;
use Constants;

our $WCFG = CFG->{Web};

sub url_dispatch
{
    my $result;

    $result->{section} = 'general';
    $result->{id_entity} = 0;

    my $tmp;

    if (@_)
    {
        $tmp = shift;
        $tmp =~ s/^\/gui//g;
        $tmp =~ s/\?.*$//g;
    }
    else
    {
        $tmp = $ENV{'PATH_INFO'};
    }

    $tmp =~ s/^\///;
    my @s = split /,/, $tmp;

    $result->{context} = $tmp;

    if (@s)
    {
        $result->{id_entity} = shift @s;
        $result->{id_entity} = 0
            unless $result->{id_entity} =~ /\d+/;

        $s[0] = 0
            unless $s[0] =~ /\d+/;

        if (defined $WCFG->{Sections}->{$s[0]})
        {
            $result->{section} = $WCFG->{Sections}->{$s[0]};
        }
        else
        {
            return $result;
        }
        shift @s;

        for ( @{ $WCFG->{SectionDefinitions}->{$result->{section}}->[1] } )
        {
            $result->{$_} = shift @s;
            last
                unless @s;
        }
    }

    my $cgi = CGI->new();
    @s = $cgi->param;

    my @p;
    if (@s)
    {
        for (@s)
        {
            @p = $cgi->param($_);
            $result->{form}->{$_} = @p == 1 ? $cgi->param($_) : \@p;
        }
    }

    return $result;
}

sub url_gen
{
    my $script_name = shift;
    return $script_name . '/' . join(',', @_);
}

sub url_get
{
    my (%p, %r, $script_name);

    if (@_)
    {
        %p = %{$_[0]};
        shift;
        %r = %{$_[0]}
            if @_;
        shift;
        $script_name = shift || $ENV{'SCRIPT_NAME'};
    }

    if (keys %r)
    {
        for (keys %p)
        {
            $r{$_} = $p{$_};
        }
        %p = %r;
    }

    my @params;

    push @params, defined $p{id_entity} 
        ? $p{id_entity} 
        : '';

    push @params, defined $WCFG->{SectionDefinitions}->{ $p{section} }
        ? $WCFG->{SectionDefinitions}->{ $p{section} }->[0]
        : 0;

    for (@{ $WCFG->{SectionDefinitions}->{ $p{section} }->[1] })
    {
        push @params, $p{$_};
    }

    return url_gen($script_name, @params);
}

1;
