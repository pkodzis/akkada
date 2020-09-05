package FormProcessor::form_history_filter;

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
        status_old => 'status old',
        status_new => 'status new',
        errmsg => 'error',
        'id_probe_type' => 'probe',
};

my $cond =
{
        '' => '-- select --',
        'equal' => 'equal',
        'not_equal' => 'not equal',
        'greater' => 'greater',
        'lower' => 'lower',
        'contain' => 'contain',
        'not_contain' => 'not contain',
};

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $session = session_get;

    my $conditions = session_get_param($session, '_HISTORY_CONDITIONS') || {};
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
        if ($url_params->{form}->{value} ne '' || $url_params->{form}->{'value_field'} ne '')
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
                    value_field => $url_params->{form}->{value_field},
                };
            }
            else
            {
                die "[ERRORS: ", join(";", @bad), "]";
            }
        }
    };


    keys %$conditions
        ? session_set_param(DB->new(), $session, '_HISTORY_CONDITIONS', $conditions)
        : session_clear_param(DB->new(), $session, '_HISTORY_CONDITIONS');

    return [1, $@]
        if $@;

    return [0];
}

1;
