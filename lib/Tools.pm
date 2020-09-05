package Tools;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;         
use Configuration;
use Constants;
use Common;
use URLRewriter;
use Forms;

use constant 
{
    DB => 0,
    SESSION => 1,
    CGI => 2,
    URL_PARAMS => 3,
    LIST => 5,
    TREE => 7,
};


sub new
{       
    my $class = shift;

    my $self;

    $self->[DB] = shift;
    $self->[SESSION] = shift;
    $self->[CGI] = shift;
    $self->[URL_PARAMS] = shift;
    $self->[TREE] = shift;

    my $file;
    opendir(DIR, sprintf(qq|%s/Tools|, CFG->{LibDir}));
    while (defined($file = readdir(DIR)))
    {
        next
            unless $file =~ /\.pm$/;
        $file =~ s/\.pm$//g;
        $self->[LIST]->{$file} = "$file.pm";
    }
    closedir(DIR);

    bless $self, $class;

    return $self;
}

sub tree
{
    return $_[0]->[TREE];
}

sub list
{
    return $_[0]->[LIST];
}

sub session
{
    return $_[0]->[SESSION];
}

sub url_params
{
    return $_[0]->[URL_PARAMS];
}

sub db
{
    return $_[0]->[DB];
}

sub cgi
{
    return $_[0]->[CGI];
}

sub get_left
{
    my $self = shift;

    my $list = $self->list();
    return
        unless defined $list && keys %$list;

    my $table= HTML::Table->new(-width=> '100%');
    $table->setAlign("CENTER");
    $table->setAttr('class="w"');

    my $but = Window::Buttons->new();
    $but->button_refresh(0);
    $but->button_back(0);
    $but->vertical(1);

    my $name;
    for my $key (sort keys %$list)
    {
        $name = $key;
        $name =~s/_/ /g;
        $but->add({ caption => $name, 
            url => sprintf(qq|javascript:top.frames[0].location='%s'|, 
            #url => sprintf(qq|javascript:top.frames['ifr_tool'].location.href('%s')|, 
            url_get({section => 'tool', tool_name => $key}, $self->url_params))})
    }

    $table->addRow($but);
    return scalar $table;
}


1;
