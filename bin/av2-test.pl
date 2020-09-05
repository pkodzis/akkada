#!/akkada/bin/perl

$|=1;
open F, "/tmp/av2";
while (<F>)
{
    s/\n//;
    s/\//#/;
    push @w, $_;
};

while (1)
{
    $i = int(rand(scalar @w));
if ($w[$i] =~ /10\.13\.21\./)
{
    $j = int(rand(2));
    if (! $ARGV[1])
    {
        $d = $j ? 'down' : 'up';
    }
    else
    {
        $d = $ARGV[1];
    }

    system `/bin/touch /tmp/av2-$d-$w[$i]`;
    print "/bin/touch /tmp/av2-$d-$w[$i]\n";
}

    sleep 1
        unless $ARGV[0];
}
