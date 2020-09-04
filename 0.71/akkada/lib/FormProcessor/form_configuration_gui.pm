package FormProcessor::form_configuration_gui;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Entity;
use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;
use Data::Dumper;

$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 1;

my $C = CFG;

my $CfgFile = $ENV{AKKADA} . "/etc/akkada.conf";

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    $C->{Web}->{Stat}->{ShowDeltaTest} = $url_params->{form}->{show_delta_test} 
        && $url_params->{form}->{show_delta_test} eq 'on'
        ? 1
        : 0;

    $C->{Web}->{ListViewShowVendorsImages} = $url_params->{form}->{list_view_show_vendors_images} 
        && $url_params->{form}->{list_view_show_vendors_images} eq 'on'
        ? 1
        : 0;

    $C->{Web}->{ListViewShowFunctionsImages} = $url_params->{form}->{list_view_show_functions_images} 
        && $url_params->{form}->{list_view_show_functions_images} eq 'on'
        ? 1
        : 0;

    $C->{Web}->{Tree}->{ShowActiveNodeService} = $url_params->{form}->{show_active_node_service} 
        && $url_params->{form}->{show_active_node_service} eq 'on'
        ? 1
        : 0;

    $C->{Web}->{Tree}->{ShowServicesAlarms} = $url_params->{form}->{show_services_alarms};
    $C->{Web}->{History}->{DefaultLimit} = $url_params->{form}->{history_default_limit};
    $C->{Web}->{History}->{StatResolution} = $url_params->{form}->{history_stat_resolution};

    rename $CfgFile, sprintf("%s.%s", $CfgFile, time)
        or return [1, $@ . $!];
    open F, ">$CfgFile"
        or return [1, $@ . $!];
    print F Dumper($C)
        or return [1, $@ . $!];
    close F
        or return [1, $@ . $!];
    
    return [0];
}

1;
