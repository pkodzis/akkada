package Probe::group;

use vars qw($VERSION);

$VERSION = 0.1;

use base qw(Probe);
use strict;
use Constants;

sub id_probe_type
{
    return 0;
}

sub discover_mode
{
    return _DM_NODISCOVER;
}

sub name
{
    return 'group';
}


sub snmp
{
    return 0;
}

sub popup_items
{
    my $self = shift;

    $self->SUPER::popup_items(@_);

    my $buttons = $_[0]->{buttons};
    my $class = $_[0]->{class};
    my $view_mode = $_[0]->{view_mode};
    $buttons->add({ caption => "<hr>", url => "",});
    $buttons->add({ caption => "add group", url => "javascript:open_location('0','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class', '1');",});
    $buttons->add({ caption => "add node", url => "javascript:open_location('0','"
        . $self->popup_item_url_app($view_mode)
        . "','','$class', '2');",});
}

1;
