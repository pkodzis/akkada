package FormProcessor::form_alarms_filter;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;


my $items =
{   
        '' => '-- select --',
        parent => 'parent name',
        name => 'name',
        status => 'status',
        errmsg => 'error',
};

my $cond =
{
        '' => '-- select --',
        'equal' => 'equal',
        'not_equal' => 'not equal',
        'contain' => 'contain',
        'not_contain' => 'not contain',
};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $session = session_get;

    my $conditions = session_get_param($session, '_ALARMS_CONDITIONS') || {};
    my $cond_count = 0;

    for (sort keys %$conditions)
    {
        $cond_count = $_
            if $cond_count < $_;
    }

    eval {
        for my $param (keys %{ $url_params->{form} })
        {
            next
                unless $param =~ /^delete_/;
            $param =~ s/^delete_//g;
            delete $conditions->{$param}
                if defined $conditions->{$param};
        }
        if ($url_params->{form}->{value} ne '')
        {
            my @bad;
            push @bad, 'unknown field: ' . $url_params->{form}->{field}
                unless defined $items->{ $url_params->{form}->{field} };
            push @bad, 'field not selected'
                unless $url_params->{form}->{field};
            push @bad, 'unknown condition: ' . $url_params->{form}->{cond}
                unless defined $cond->{ $url_params->{form}->{cond} };
            push @bad, 'condition not selected'
                unless $url_params->{form}->{cond};

            if (! @bad )
            {
                ++$cond_count;
                $conditions->{ $cond_count } =
                {
                    field => $url_params->{form}->{field},
                    cond => $url_params->{form}->{cond},
                    value => $url_params->{form}->{value},
                };
            }
            else
            {
                die "[ERRORS: ", join(";", @bad), "]";
            }
        }
    };

    keys %$conditions
        ? session_set_param(DB->new(), $session, '_ALARMS_CONDITIONS', $conditions)
        : session_clear_param(DB->new(), $session, '_ALARMS_CONDITIONS');


    return [1, $@]
        if $@;

    return [0];
}

1;
