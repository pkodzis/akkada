package Configuration;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION $AUTOLOAD);

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( CFG reload_cfg );
%EXPORT_TAGS = ( default => [qw(CFG reload_cfg)] );

use strict;
use Constants;
use MyException qw(:try);

our $cfg;

sub reload_cfg
{
    try 
    {
        $cfg = do "$ENV{AKKADA}/etc/akkada.conf";
    }
    except
    {
        throw EFileSystem($!);
    };
}

sub CFG 
{
    return $cfg; 
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

__PACKAGE__->reload_cfg;

1;

