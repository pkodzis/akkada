package FormProcessor::form_view_select;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );
#use Data::Dumper; die Dumper $url_params;

    my $session = session_get;

    my $db = DB->new();
    session_set_param($db, $session, '_ID_VIEW', $url_params->{form}->{id_view});

    if (defined $url_params->{form}->{add} && $url_params->{form}->{add} eq '1')
    {
        return [1, 'view not selected']
            unless $url_params->{form}->{id_view};
        eval
        {   
            my @tmp = map { $_->[0] } @{ $db->exec(
                sprintf(qq|SELECT view_order FROM entities_2_views where id_view=%s|, $url_params->{form}->{id_view})
                )->fetchall_arrayref };

#use Data::Dumper; die Dumper \@tmp;
            my $view_order = 0;
            if (@tmp)
            {
                @tmp = sort { $a <=> $b } @tmp;
                $view_order = ++$tmp[$#tmp];
            }


            $db->exec( sprintf(qq|INSERT INTO entities_2_views VALUES(%s, %s, %d)|, 
                $url_params->{form}->{id_view},
                $url_params->{form}->{id_entity},
                $view_order,
                ));

            flag_files_create(CFG->{StatusCalc}->{StatusCalcDir}, $url_params->{form}->{id_entity});
        };
    }

    return [1, $@]
        if $@;

    return [0];
}

1;
