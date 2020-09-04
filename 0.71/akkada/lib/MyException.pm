package MyException;

use vars qw( $VERSION $AUTOLOAD);

$VERSION = 0.1;

use base Error;
use overload ('""' => 'stringify');
use XML::Simple;
use Time::HiRes qw( gettimeofday );
use POSIX qw(strftime);
use Configuration;

$|=1;

our $StackTrace = CFG->{MyException}->{StackTrace};
our $TimeFormat = CFG->{MyException}->{TimeFormat};
our $LogFileXML = CFG->{MyException}->{LogFileXML};
our $LogFileText = CFG->{MyException}->{LogFileText};
our $TextOneLineMode = CFG->{MyException}->{TextOneLineMode};

sub get_time
{
    my $self = shift;

    my @t = gettimeofday;
    $t[1] = sprintf("%06s", $t[1]);

    if ($TimeFormat eq 'human')
    {
        $t[0] = localtime($t[0]);
        $t[0] = strftime "%Y %b %e %H:%M:%S", localtime;
    }
    return join(".", @t);
}

sub new
{
    my $self = shift;

    my $text =""; 
    $text .= shift
        if @_;

    my @args = ();

    local $Error::Depth = $Error::Depth + 1;
    local $Error::Debug = 1;

    @args = ( -file => $1, -line => $2)
        if($text =~ s/ at (\S+) line (\d+)(\.\n)?$//s);

    $self->SUPER::new(-text => $text, @args);

}

sub stringify 
{
    my $self = shift;

    my $stacktrace = $self->stacktrace;
    $stacktrace =~ s/\s+$//g;
    $stacktrace = [split /\n\t/, $stacktrace];
#    shift @$stacktrace;
#    shift @$stacktrace;

    my $type = @_ && $_[0]
        ? shift
        : 'xml';

    return
        if $type eq 'no';

    throw Error::Simple("bad argument type. possible options: xml, text")
        unless $type eq 'text' || $type eq 'xml';

    if ($type eq 'xml') 
    {
        my $error = 
        {
            code => ref($self),
            timestamp => $self->get_time,
            body => 
            {
                #file => [$self->file],
                line => [$self->line],
                pid => [$$],
                text => [$self->SUPER::stringify],
            },
        };
        if ($StackTrace)
        {
            my $i = 0;
            while ($i < $#$stacktrace+1)
            {
                $error->{stacktrace}->{$i} = [ $stacktrace->[$i] ];
                $i++;
            }
        }

        if ($LogFileXML)
        {
            eval 
            {
                open F, ">>" . $LogFileXML
                    or die $@, $LogFileXML;
                print F XMLout($error, RootName => 'exception');
                close F;
            }
            or die $@, $!;
        }
        else
        {
            print XMLout($error, RootName => 'exception');
        }
    }
    else
    {
        my $outp;

        if ($TextOneLineMode)
        {
            $outp = sprintf("%s: %s %s %s %s\n", $self->get_time, $0, $$, ref($self), $self->SUPER::stringify);
        }
        else
        {
            my $len = 128;

            my $t = sprintf("[********** %s START (pid: %s) %s ",
                ref($self), $$, $self->get_time);

            $t .= "*" x ($len - length($t));

            $outp = sprintf("%s]\n[* text: %s\n", 
            #$outp = sprintf("%s]\n[* file: %s; line: %s\n[* text: %s\n", 
                $t, $self->SUPER::stringify);
                #$t, $self->file, $self->line, $self->SUPER::stringify);

            if ($StackTrace)
            {
                $outp .= "[* stacktrace:\n";
                my $i = 0;
                while ($i < $#$stacktrace+1)
                {
                    $outp .= sprintf("[*     %s: %s\n", $i, $stacktrace->[$i]);
                    $i++;
                }
            }

            $t = sprintf("[********** %s STOP  (pid: %s) ", ref($self), $$);
            $t .= "*" x ($len - length($t));
            $outp .= "$t]\n";
        }

        if ($LogFileText)
        {
            eval 
            {
                open F, ">>" . $LogFileText
                    or die $@;
                print F $outp;
                close F; 
            } 
            or die $@, $!;
        }
        else
        {
            print $outp;
        }
    }
}

1;

#COMMON ERRORS
package ECommon; use base MyException; 1;

#LOG
package DBINTERNAL; use base ECommon; 1;
package INTERNAL; use base ECommon; 1;
package DEBUG; use base ECommon; 1;
package INFO; use base ECommon; 1;
package WARNING; use base ECommon; 1;
package ERROR; use base ECommon; 1;

#OS System ERRORS
package ECannotFork; use base ECommon; 1;
package EFileSystem; use base ECommon; 1;

#ARGUMENT ERRORS
package EMissingArgument; use base ECommon; 1;
package EBadArgumentType; use base ECommon; 1;
package ENoArgumentNeeded; use base ECommon; 1;
package ENumberArgumentBadRange; use base ECommon; 1;

#OBJECT ERRORS
package EOOPerl; use base MyException; 1;
package EUnknownMethod; use base EOOPerl; 1;
package EReadOnlyMethod; use base EOOPerl; 1;
package EAlreadySet; use base EOOPerl; 1;
package EPrivateMethod; use base EOOPerl; 1;

#DATABASE ERRORS
package EDBConnect; use base ECommon; 1;
package EDBExec; use base ECommon; 1;
package EDBFetch; use base ECommon; 1;
package EDBDelete; use base ECommon; 1;
package EDBInsert; use base ECommon; 1;
package EDBUpdate; use base ECommon; 1;
package EDBSelect; use base ECommon; 1;

#AKKADA SYSTEM ERRORS
package EBadStatus; use base ECommon; 1;

#Entity.pm
package EEntityDoesNotExists; use base ECommon; 1;
package EEntityParentDoesNotExists; use base ECommon; 1;
package EEntityParameterMissing; use base ECommon; 1;
package EEntityUnknownStatCommand; use base ECommon; 1;
package EEntityMissingParameter; use base ECommon; 1;

package ERRDs; use base ECommon; 1;

package EXMLError; use base ECommon; 1;

