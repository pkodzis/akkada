package OnCall;

#
# example private application connection module
# see etc/conf.d/Web/Contacts.conf file
# to see the configuration of external information functions
#

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

sub process
{
    my $ref = $_[1];
    my $result = '';
    my $class = 'm';

    return [$result, $class]
        unless defined $ref->{oncall};

    if ($ref->{oncall}->{available} eq "true")
    {
        $result = '<img class="b10" src="/img/on.gif" alt="on call">';
    }
    elsif ($ref->{oncall}->{available} eq "false")
    {
        $result = '<img class="b10" src="/img/off.gif" alt="not available">';
    }

    return [$result, $class];
}

1;
