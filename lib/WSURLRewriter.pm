package WSURLRewriter;

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

    $result->{wskey} = undef;
    $result->{section} = 'general';
    $result->{id_entity} = 0;

    my $tmp;

=pod
    if (@_)
    {
        $tmp = shift;
        $tmp =~ s/^\/ws//g;
        $tmp =~ /^\/(.*),(.*)/;
        $result->{wskey} = $1;
        $tmp = $2;
        $tmp =~ s/\?.*$//g;
    }
    else
    {
        $tmp = $ENV{'PATH_INFO'};
        $tmp =~ /^\/(.*),(.*)/;
        $result->{wskey} = $1;
        $tmp = $2;
        $tmp =~ s/\?.*$//g;
    }

    my @s = split /,/, $tmp;
=cut

    if (@_)
    {
        $tmp = shift;
        $tmp =~ s/^\/ws//g;
        $tmp =~ s/\?.*$//g;
    }
    else
    {
        $tmp = $ENV{'PATH_INFO'};
    }

    $tmp =~ s/^\///;
    my @s = split /,/, $tmp;



#warn $ENV{'PATH_INFO'};
#warn $tmp;
#use Data::Dumper; warn Dumper($result);

    $result->{context} = $tmp;

    if (@s)
    {
        $result->{wskey} = shift @s;
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

1;
