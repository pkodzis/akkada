package WSE;

use base qw(WSBase);
use strict;

use Common;
use Configuration;
use Constants;
use Log;
use Serializer;

our $LogEnabled = CFG->{LogEnabled};
our $TMPL = CFG->{Web}->{Templates};

sub get
{
    my $self = shift;

    return $self->not_logged
        unless $self->is_logged;

    my $url_params = $self->url_params;

    return $self->bad_request
        unless defined $url_params->{wskey} && $url_params->{wskey};

    my $wskey = "ext_" . $url_params->{wskey};

    return $self->bad_request
        unless $self->can($wskey);

    return $self->$wskey;
}

sub ext_test
{
    my $self = shift;
    $self->header;

    return qq|<a href="javascript:openPage('center','pGeneral','/wse/test','general','general', true);">DUPA</a>
this a test function output <a href="javascript:messageObj.close();">CLOSE</a>
<script type="text/javascript">
function createNewWindow() 
{ 
var newWindowModel = new DHTMLSuite.windowModel({windowsTheme:false,id:'newWindow',title:'New dynamically created window',xPos:200,yPos:200,minWidth:100,minHeight:100 } ); 
newWindowModel.addTab({ id:'myTab',htmlElementId:'myTab',tabTitle:'tab1',
contentUrl:'/wse/img_picker?form_name=a&field_name=2' } ); 
var newWindowWidget = new DHTMLSuite.windowWidget(newWindowModel); 
//newWindowWidget.setLayoutThemeWindows()
newWindowWidget.init(); 
var myWindowCollection = new DHTMLSuite.windowCollection();
myWindowCollection.addWindow(newWindowWidget);
myWindowCollection.setNumberOfColumnsWhenTiled(1);
myWindowCollection.setDivWindowsArea('center');
} 
</script>
<a href="#" onclick="createNewWindow();return false">Create window</A> 
|;
}

sub ext_about
{
    my $self = shift;

    my $tmpl = HTML::Template->new(filename => "$TMPL/about.tmpl");

    $tmpl->param(version => $self->version);
    $tmpl->param(copyright => $self->copyright);

    $self->header;

    return $tmpl->output;
}

sub ext_img_picker
{
    my $self = shift;
    my $url_params = $self->url_params;

    my $form_name = defined $url_params->{form}->{form_name} && $url_params->{form}->{form_name} ? $url_params->{form}->{form_name} : undef;
    my $field_name = defined $url_params->{form}->{field_name} && $url_params->{form}->{field_name} ? $url_params->{form}->{field_name} : undef;

    return "bad request"
        unless defined $form_name
        && defined $field_name;

    my $content = '';
    my $file;
    my $name;

    my @files = ();
    opendir(DIR, CFG->{ImagesDir});
    while (defined($file = readdir(DIR)))
    {
        push @files, $file;
    }
    closedir(DIR);

    for $file ( sort { uc $a cmp uc $b } @files )
    {
        next
            unless $file =~ /\.gif$/ && $file !~ /^logo_*/;
        $name = (split /\./, $file)[0];
        $content .= qq|<a href="javascript:select_img('$name');"><img src="/img/$file" class="b10" alt="$name" width=16 height=16/></a>|;
    }

    my $tmpl = HTML::Template->new(filename => "$TMPL/img_picker.tmpl");

    $tmpl->param(form_name => $form_name);
    $tmpl->param(field_name => $field_name);
    $tmpl->param(content => $content);

    return $tmpl->output;
}


1;
