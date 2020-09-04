#!/akkada/bin/perl -w

# tool for creating akkada snmp_generic templates from SNMP MIB files table entries
#

if (@ARGV < 3)
{
   print "usage:\n
$0 <MIB FILE> <TABLE_ENTRY_NAME> <BASE_OID_FOR_SNMP_TABLE_OF_SNMP_TABLE_ENTRY>\n\n";
   print "example usage:\n
$0 /usr/local/share/snmp/mibs/SW-MIB.txt SwFCPortEntry  1.3.6.1.4.1.1588.2.1.1.1.6.2.1\n\n";
   exit;
}

$th = <<EOF;
#      text_test => {
#          bad => [ { value => '', alarm_level => , message => '', }, ],
#          expected => [ { value => '', alarm_level => , message => '', }, ],
#      },
#      threshold_high => { value => '', alarm_level => , message => "", },
#      threshold_medium => { value => '', alarm_level => , message => "", },
#      threshold_too_low => { value => '', alarm_level => , message => "", },
EOF

open F, $ARGV[0] or die $@;
@w = <F>;
close F;

sub ext_syntax_integer
{
    my $s1 = shift;
    my @s = split /\r|\r\n|\n/, $s1;
    my $fl = 0;
    my @r;
    for my $l (@s)
    {
        if (! $fl && $l =~ /SYNTAX/ && $l =~ /integer/i && $l =~ /{/)
        {
            $fl = 1;
            next;
        }
        elsif ($fl && $l =~ /}/)
        {
            last;
        }
        elsif ($fl)
        {
            push @r, $l;
        }
    }
    @s = ();
    for my $l (@r)
    {
        $l =~ s/^#//;
        $l =~ s/\s+//g;
        $l = (split /\)/, $l)[0];
        if (defined $l)
        {
            $fl = [split /\(/, $l];
            push @s, $fl;
        }
    }
    $fl = "      text_translator => {\n";
    for (@s)
    {
        $fl .= qq|        $_->[1] => '$_->[0]',\n|;
    }
    $fl .= "     },\n";
}

$flag = 0;
for (@w)
{
    if (! $flag && $_ =~ /OBJECT-TYPE/)
    {
        $_ =~ s/^\s+|\n//g;
        $i = (split /\s/, $_)[0];
        next
            unless $i;
        next
            if $i =~ /^--/;
        $flag = 1;
        $syn = '';
    }
    elsif ($flag && $_ =~ /::=/)
    {
        $flag = 0;
        next
            unless $_ =~ /$ARGV[1]/i;
        $_ =~ s/^\s+|\n//g;
        $_ =~ s/\s+/ /g;
        $_ = (split /{/, $_)[1];
        $_ = (split /}/, $_)[0];
        $_ =~ s/^\s+|\s+$//g;
        $_ = (split / /, $_)[1];
        $res{$_} = [$i, $syn];
        $syn = '';
    }
    elsif ($flag)
    {
        $syn .= "#$_";
    }
}

print "#\n";
print "# REMOVE ALL HASHED LINES MANUALY\n";
print "#\n{\n";
print "  TRACKS => {\n";
for (sort { $a <=> $b } keys %res)
{
    print qq|    '$ARGV[2].$_' => {\n|;
    print qq|      track_name => '$res{$_}->[0]',\n|;
    if ($res{$_}->[1] =~ /counter/i)
    {
        print qq|      rrd_track_type => 'COUNTER',\n|;
    }
    elsif ($res{$_}->[1] =~ /gauge/i)
    {
        print qq|      rrd_track_type => 'GAUGE',\n|;
    }
    if ($res{$_}->[1] =~ /syntax.*integer.*{/i)
    {
        print ext_syntax_integer($res{$_}->[1]);
    }
    print $th;
    print qq|##########################################################\n|;
    print qq|$res{$_}->[1]\n|;
    print qq|##########################################################\n|;
    print qq|    },\n|;
}
print "  },\n}";
