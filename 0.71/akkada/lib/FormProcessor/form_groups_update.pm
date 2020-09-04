package FormProcessor::form_groups_update;

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

sub process
{
    my $url_params = shift;

    $url_params = url_dispatch( $url_params );

    eval
    {
        my $dbh = DB->new();

        for my $param (keys %{ $url_params->{form} })
        {
            next
                if $param eq 'form_name';
            next
                if $param eq 'id_entity';
            next
                if $param eq 'master';
            next
                if $param eq 'everyone';
            next
                if $param eq 'operators';
            next
                if $param eq 'delete_master';
            next
                if $param eq 'delete_everyone';
            next
                if $param eq 'delete_operators';

            if ($param =~ /^delete_/)
            {
                $param =~ s/^delete_//g;
                $dbh->exec( sprintf(qq|DELETE FROM rights 
                    WHERE id_group IN (SELECT id_group FROM groups WHERE name='%s')|, $param) );
                $dbh->exec( sprintf(qq|DELETE FROM users_2_groups
                    WHERE id_group IN (SELECT id_group FROM groups WHERE name='%s')|, $param) );
                $dbh->exec( sprintf(qq|DELETE FROM groups WHERE name='%s'|, $param) );
            }
            else
            {
                $dbh->exec( sprintf(qq|UPDATE groups SET name='%s' WHERE name='%s'|, $url_params->{form}->{$param}, $param) );
            }
        }
    };
    return [1, $@]
        if $@;

    return [0];
}

1;
