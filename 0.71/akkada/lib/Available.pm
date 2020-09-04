package Available;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;          

use IPC::Open3;
use File::Spec;
use Symbol qw(gensym);

use MyException qw(:try);
use Configuration;
use Log;
use Constants;
use Common;
use StatusTree;

our $LogEnabled = CFG->{LogEnabled};
our $FPing = CFG->{Available}->{fping};
our $Period = CFG->{Available}->{Period};
our $PingCount = CFG->{Available}->{PingCount};
our $FlagsControlDir = CFG->{FlagsControlDir};
our $StatusCalcDir = CFG->{StatusCalc}->{StatusCalcDir};

use constant
{
    ST => 0,  #StatusTree;
};

sub new
{
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = [];
    $self->[ST] = StatusTree->new();
    bless $self, $class;
    #$self->st->load;
    return $self;
}

sub run
{
    my $self = shift;
    my $ppid = shift;

    while (1) 
    { 

        exit
            if ! kill(0, $ppid);

        $self->st->load
            if flag_file_check($FlagsControlDir, 'entities_init.Available', 1);

        $self->st->load
            unless keys %{$self->st->ips};

        $self->available_check;

        sleep $Period || 1;
    }
}


sub available_check
{
    my $self = shift;

    my ($ip, @tmp, $pid, $inh, $outh, $errh, $status, $node, $parent, $result);

    my $ips = $self->st->ips;

    return
        unless keys %$ips;

    my @ip_list;

    for (keys %$ips)
    {
        $node = $ips->{$_};
        $parent = $node->parent;
        push @ip_list, $_
            unless $parent->status == _ST_UNREACHABLE;
    }

    $result = {};

    $pid = open3($inh,$outh,$errh, @$FPing, $PingCount, @ip_list);

    for (<$outh>)
    {
        if (/^open3:/)
        {
            log_debug($_, _LOG_ERROR)
                 if $LogEnabled;
            next;
        }

        chomp;
        @tmp = split /\s+/;

        $ip = shift @tmp;

        shift @tmp;
        @tmp = grep { ! /^-$/ } @tmp;

        if (@tmp ) # == $PingCount) - tak min 1 ping = ok;
        {
            $result->{ $ip } = 1;
        }
        else
        {
            $result->{ $ip } = 0;
        }
    }

    waitpid($pid, 0);
    close $inh
        if defined $inh;
    close $outh
        if defined $outh;
    close $errh
        if defined $errh;

    my $status_old;
    for $ip (keys %$result)
    {
        $node = $ips->{$ip};

        next
            unless $node; # czasami fping zwraca ICMP redirect itp.

        $status = $node->status;
        $status_old = $status;
#print $ip, ": ", $status, ": ", $result->{ $ip }, "\n";
        if ($result->{ $ip })
        {
#print "1";
            if (! $node->status_inh )
            {
#print "2";
                $status = _ST_UNKNOWN
                    if $status == _ST_UNREACHABLE;
            }
        }
        else
        {
#print "3";
            $status = _ST_UNREACHABLE;
        }
#print "= $status = \n";
#print sprintf(qq|aval: %d %d %d\n|, $ip, $node->status, $status);
        $node->status($status);

        $self->st->leafs_set_unknown()
            if $status_old != $status && $status == _ST_UNREACHABLE;
    }

}

sub st
{
    return $_[0]->[ST];
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;
