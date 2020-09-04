package FormProcessor::form_view_manage;

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
use Views;
use CGI;

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    my $idv = $url_params->{form}->{update};
    if ($idv)
    {
        my $name = $url_params->{form}->{name};
        return [1, 'view name cannot be empty']
            unless $name;

        my $function = $url_params->{form}->{function};

        eval
        {
            my $db = DB->new();

            $db->exec( sprintf(qq|UPDATE views SET name='%s',function='%s' WHERE id_view=%s|, $name, $function, $idv) );
        };

        return [1, $@]
            if $@;
        return [0];
    }
   
    my $id = $url_params->{form}->{id_entity};
    return [1, 'unknown entity']
        unless $id;
    return [1, 'unknown entity']
        if $id =~ /\D/;
    $idv = $url_params->{form}->{id_view};
    return [1, 'unknown view']
        unless $idv;
    return [1, 'unknown view']
        if $idv =~ /\D/;

    my $action = $url_params->{form}->{action};
    return [1, 'unknown action']
        unless defined $action ;
    return [1, 'unknown action']
        unless $action eq 'up'
        || $action eq 'down'
        || $action eq 'del';
        
    if ($action eq 'del')
    {
        eval
        {   
            my $db = DB->new();

            $db->exec( sprintf(qq|DELETE FROM entities_2_views WHERE id_entity=%s AND id_view=%s|, $id, $idv) );

            my $req = $db->exec( sprintf(qq|SELECT id_entity FROM entities_2_views WHERE id_view=%s|,$idv))->fetchall_arrayref();

            flag_files_create(CFG->{StatusCalc}->{StatusCalcDir}, $req->[0]->[0])
                if @$req;

        }
    }
    else
    {
        my $session = session_get;

        eval
        {   
            my $db = DB->new();
            my $views = Views->new($db, $session, CGI->new(), $url_params);
            my @e = @{ $views->view_entities };

            my $idx = -1;
            for (@e)
            {
                ++$idx;
                last
                    if $_ == $id;
            }
            die 'internal index error'
                if $idx == -1;
            return 0
                if $action eq 'down' && $idx == $#e;
            return 0
                if $action eq 'up' && $idx == 0;

                my $cur = $views->entities->{$id};
                my $prev = $views->entities->{ $e[ $idx + ($action eq 'down' ? 1 : -1) ] };
                $db->exec( sprintf(qq|UPDATE entities_2_views set view_order=9999 WHERE id_entity=%s AND id_view=%s|,
                    $prev->{eid}, $idv) );
                $db->exec( sprintf(qq|UPDATE entities_2_views set view_order=%s WHERE id_entity=%s AND id_view=%s|,
                    $prev->{view_order}, $cur->{eid}, $idv) );
                $db->exec( sprintf(qq|UPDATE entities_2_views set view_order=%s WHERE id_entity=%s AND id_view=%s|,
                    $cur->{view_order}, $prev->{eid}, $idv) );
        };
    }

    return [1, $@]
        if $@;

    return [0];
}

1;
