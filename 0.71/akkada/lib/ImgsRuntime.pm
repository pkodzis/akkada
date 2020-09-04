package ImgsRuntime;

use strict;

use warnings FATAL => 'all';
use Apache2::RequestRec ( );
use Apache2::Const -compile => 'OK';

use lib "$ENV{AKKADA}/lib";
use Configuration;
use Common;

our $MaxCol = 24;

sub handler 
{
    $0 = 'akk@da images';
    my $r = shift;

    CGI::header( -expires => "now");

    my $path = $ENV{'PATH_INFO'};

    my $field = '';
    my $form = '';
    if ($path)
    {
        $path =~ s/^\///g;
        ($form, $field) = split /\//, $path, 2;
    }


    print qq|<HTML>  
<HEAD>  
<TITLE>$0</TITLE>
<LINK rel="StyleSheet" href="/css/akkada.css" type="text/css" />
<SCRIPT LANGUAGE = "JavaScript">
function select_img(img)
{
    var newimg = new Image();
    newimg.src = "/img/" + img + ".gif";
    self.opener.document.forms['$form'].elements['$field'].value = img;
    self.opener.document.getElementById('imgc'+'$field').src = newimg.src;
    window.close();
}
</SCRIPT>

</HEAD><BODY>|;

    my $file;
    my $name;

    my $col = 1;
    my $row = 2;

    my @files = (); 
    opendir(DIR, CFG->{ImagesDir});
    while (defined($file = readdir(DIR)))
    {
        push @files, $file;
    }
    closedir(DIR);

    my $table = table_begin('available images', $MaxCol);
   
    for $file ( sort { uc $a cmp uc $b } @files )
    {
        next
            unless $file =~ /\.gif$/ && $file !~ /^logo_*/;

        $name = (split /\./, $file)[0];

        if ($form && $field)
        {
            $table->setCell($row, $col, 
                qq|<a href="javascript:select_img('$name');"><img src="/img/$file" class="b10" alt="$name"/></a>|);
        }
        else
        {
            $table->setCell($row, $col, qq|<img src="/img/$file" class="b10" alt="$name"/>|);
        }

        $table->setCellAttr($row, $col, 'class="t2"');

        ++$col;
        if ($col > $MaxCol)
        {
            $col = 1;
            ++$row;
        }
    }

    print $table->getTable();

    print "</BODY></HTML>";

    return $Apache2::Const::OK;
}

1;

