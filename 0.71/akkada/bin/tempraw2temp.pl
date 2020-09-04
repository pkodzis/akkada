#!/akkada/bin/perl -w

# tool for creating akkada snmp_generic templates from raw templates created by mib2tempraw.pl
#

if (@ARGV < 1)
{
   print "usage:\n
$0 <RAW TEMPLATE FILE>\n\n";
   exit;
}

open F, $ARGV[0] or die $@;
@rtf = <F>;
close F;

$rt = do "$ARGV[0]";
$rt = $rt->{TRACKS};

$res = "  DESC => {\n";
$gr = "  GRAPHS => [\n";
$i = 0;

for (sort { (split /\./, $a)[ (split /\./, $a)-1 ] <=> (split /\./, $b)[ (split /\./, $b)-1 ]  } keys %$rt)
{
    ++$i;
    $res .= sprintf(qq|    %s => { 
      title => '%s', order => %s, brief => 0, 
|, $rt->{$_}->{track_name}, $rt->{$_}->{track_name}, $i*10);

    if (defined $rt->{$_}->{text_test})
    {
        $res .= qq|      format_bad => '<span class="g9">%s</span>',\n|;
        $res .= qq|      format => '<span class="g8">%s</span>',\n|;
    }
    else
    {
        $res .= "      format => '%s',\n";
    }

    $res .= "      show_absolute_value => 2,\n      value_format => '%%NUMBER.0%%',\n"
        if defined $rt->{$_}->{rrd_track_type} && $rt->{$_}->{rrd_track_type} eq 'COUNTER';
    $res .= "    },\n";

    if (defined $rt->{$_}->{rrd_track_type})
    {
        $gr .= <<EOF;
    {
       title => '$rt->{$_}->{track_name}',
       units => '?',
       tracks => [
           {
               name => '$rt->{$_}->{track_name}',
               title => '$rt->{$_}->{track_name}',
               color => '330099',
               style => 'LINE1',
           },
       ],
    },
EOF
    }
}

$res .= "  },\n";
$gr .= "  ],\n";

print <<EOF;
{
  DISCOVER_AFFECTED_SYSOBJECTID => [ ? ],
  DISCOVER => [ ?, ],
  DISCOVER_NAME_OVERRIDE => '%%DISCOVER_NAME%%',
  ENTITY_ICON => 'icon',
EOF

print @rtf;

print $gr;
print $res;

print "}\n";
