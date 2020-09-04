package StatusCalc;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;          
use MyException qw(:try);
use Entity;
use Configuration;
use Log;
use Constants;
use DB;
use Common;

use constant
{
    DBH => 0,
};

our $ThresholdHigh = CFG->{StatusCalc}->{ThresholdHigh};
our $ThresholdMed = CFG->{StatusCalc}->{ThresholdMed};
our $StatusCalcDir = CFG->{StatusCalc}->{StatusCalcDir};
our $Period = CFG->{StatusCalc}->{Period};
our $LogEnabled = CFG->{LogEnabled};
our $FlagsUnreachableDir = CFG->{FlagsUnreachableDir};
our $TreeCacheDir = CFG->{Web}->{TreeCacheDir};


sub new
{
    my $class = shift;

    my $self = [];

    $self->[DBH] = DB->new();

    bless $self, $class;

    return $self;
}

sub views_recalc_status
{
    my $self = shift;

    throw EMissingArgument('id_entity')
        unless @_;
    throw EBadArgumentType(sprintf(qq|id_entity: '%s'|, $_[0]))
                unless $_[0] =~ /^[1-9].*$/;

    my $id = shift;

    my $statuses = $self->dbh->exec("SELECT * FROM statuses", "id_entity")->fetchall_hashref("id_entity");

    my $req = $self->dbh->exec(
        sprintf(qq|SELECT views.id_view,entities.id_entity,entities.status,status_weight,views.status
            FROM entities_2_views,entities,views WHERE
            views.id_view IN (SELECT id_view FROM entities_2_views WHERE entities_2_views.id_entity=%s)
            AND entities.id_entity = entities_2_views.id_entity
            AND monitor<>0
            AND entities_2_views.id_view = views.id_view
            |,$id))->fetchall_arrayref();

    my $views;
    my $st_new;

    for (@$req)
    {
        if (defined $statuses->{ $_->[1] })
        {
            $views->{ $_->[0] }->{count} += $statuses->{ $_->[1] }->{status_weight};
            $views->{ $_->[0] }->{st}->{ $statuses->{ $_->[1] }->{status} } += $statuses->{ $_->[1] }->{status_weight};
        }
        $views->{ $_->[0] }->{count} += $_->[3];
        $views->{ $_->[0] }->{st}->{$_->[2]} += $_->[3];
        $views->{ $_->[0] }->{status} = $_->[4];
    }

    for my $id_view (keys %$views)
    {
        if ($views->{$id_view}->{count})
        {
            for (keys %{ $views->{$id_view}->{st} })
            {
                $views->{$id_view}->{st}->{$_} = ( $views->{$id_view}->{st}->{$_} / $views->{$id_view}->{count}) * 100;
            }
        }
        $st_new = status_calc_row($views->{$id_view});
        log_debug(sprintf(qq|UPDATE views set status=%s WHERE id_view=%s\n|, $st_new, $id_view), _LOG_INFO);
        $self->dbh->exec(sprintf(qq|UPDATE views set status=%s,last_change=NOW() WHERE id_view=%s|, $st_new, $id_view))
            if $st_new != $views->{$id_view}->{status};
    }
}

sub status_calc_row
{
    my $s = shift;
    my $status = _ST_OK;

    my $count = $s->{count};
    $s = $s->{st};

    if ($count)
    {
        foreach (keys %$s)
        {
            $s->{$_} = ($s->{$_}/$count) * 100;
        }
    }

    if (($s->{6} || $s->{5} || $s->{4}) && $status == _ST_OK)
    {
        $status = _ST_DOWN
            if ($s->{6}+$s->{5}+$s->{4}+$s->{3}+$s->{2}+$s->{1} > $ThresholdHigh) ;
    }

    if (($s->{6} || $s->{5} || $s->{4} || $s->{3}) && $status == _ST_OK)
    {
        if ($s->{6}+$s->{5}+$s->{4} > $ThresholdMed)
        {
            $status = _ST_MAJOR;
        }
        elsif ($s->{6}+$s->{5}+$s->{4}+$s->{3}+$s->{2}+$s->{1} > $ThresholdHigh)
        {
            $status = _ST_MAJOR;
        }
    }

    if ($s->{6} || $s->{5} || ($s->{4} || $s->{3} || $s->{2}) && $status == _ST_OK)
    {
        if ($s->{6} + $s->{5} + $s->{4} > $ThresholdMed)
        {
            $status = _ST_MINOR;
        }
        elsif ($s->{2} > $ThresholdMed)
        {
            $status = _ST_MINOR;
        }
        elsif ($s->{6}+$s->{5}+$s->{4}+$s->{3}+$s->{2}+$s->{1} > $ThresholdHigh)
        {
            $status = _ST_MINOR;
        }
    }

    $status = _ST_MINOR
        if (($s->{5} || $s->{6}) && $status == _ST_OK);

    $status = _ST_WARNING
        if (($s->{5} || $s->{4} || $s->{3} || $s->{2} || $s->{1}) && $status == _ST_OK);

    $status = _ST_UNKNOWN
        if ($s->{64} && $status == _ST_OK);

    $status = _ST_INIT
        if ($s->{124} && $status == _ST_OK);
    return $status;
}

sub entity_recalc_status
{
    my $self = shift;

    throw EMissingArgument('id_entity')
        unless @_;
    throw EBadArgumentType(sprintf(qq|id_entity: '%s'|, $_[0]))
                unless $_[0] =~ /^[1-9].*$/;

    my $id = shift;

    my $calc_status = node_get_status($self->dbh, $id);
   
    return
        if $calc_status->{status} == _ST_UNREACHABLE;

    my $st = {};
    my $count = 0;
    my $status = _ST_OK;
    my $change = 0;
    my $status_weight;

    my %s = (
        0 => 0,
        1 => 0,
        2 => 0,
        3 => 0,
        4 => 0,
        5 => 0,
        6 => 0,
        64 => 0,
        124 => 0,
        125 => 0,
        126 => 0,
        127 => 0,
        );


    #
    # collect child services statuses
    #

    my $req = $self->dbh->exec(
        sprintf(qq|SELECT id_entity,status,status_weight,flap,flap_status FROM entities 
        WHERE monitor <> 0 AND id_entity IN (SELECT id_child FROM links WHERE id_parent=%s)|, 
        $id))->fetchall_hashref('id_entity');

    @$st{keys %$req} = values %$req;

    my $stf;

    foreach my $id_entity ( keys %$st ) 
    {
        next 
            if $st->{$id_entity}->{status} == _ST_NOSTATUS;

        $stf = $st->{$id_entity}->{flap}
            ? $st->{$id_entity}->{flap_status}
            : $st->{$id_entity}->{status};
        next
            unless defined $s{ $stf };
        $s{ $stf } += $st->{$id_entity}->{status_weight};
        $count += $st->{$id_entity}->{status_weight};
    }

    #
    # collect child nodes statuses
    #

    if (keys %$st)
    {            
        $req = $self->dbh->exec(
            sprintf(qq|SELECT id_entity,status,status_weight FROM statuses 
            WHERE id_entity in (%s)|, join(",", keys %$st)))->fetchall_hashref('id_entity');

        @$st{ map { "n-$_" } keys %$req} = values %$req;

        for my $id_entity ( keys %$st ) 
        {
            next 
                if $st->{$id_entity}->{status} == _ST_NOSTATUS;

            $stf = $st->{$id_entity}->{status};

            next
                unless defined $s{ $stf };
            $s{ $stf } += $st->{$id_entity}->{status_weight};
            $count += $st->{$id_entity}->{status_weight};
        }
    } 

    $status = status_calc_row({ count => $count, st => \%s});

    log_debug(sprintf(qq|recalculating entity %s status: %s|, 
        $id, 
        $calc_status->{status} != $status 
            ? sprintf(qq|%s -> %s changed|, $calc_status->{status}, $status)
            : $status), _LOG_INFO)
        if $LogEnabled;

    if (($calc_status->{status} != $status)
       || (! $calc_status->{status_weight} && $calc_status->{status} != _ST_OK))
    {
        $status = _ST_OK
            unless $calc_status->{status_weight};
        node_set_status($self->dbh, $id, $status);
        flag_files_create($TreeCacheDir, sprintf(qq|reload.%s|, $id) );
        $id = (parent_get_id_and_status($self->dbh, $id))[0];
        $self->entity_recalc_status($id)
            if $id;    
    }
}

sub run
{
    my $self = shift;
    my $ppid = shift;

    my $file;
    
    while (1)
    {
        exit
            if ! kill(0, $ppid);

        opendir(DIR, $StatusCalcDir);
        while (defined($file = readdir(DIR))) 
        {
            next
                if $file =~ /^\./;

            unlink "$StatusCalcDir/$file";

            if ($file !~ /^[0-9].*$/ || $file eq '0')
            {
                next;
            }

            if ( flag_file_check($FlagsUnreachableDir, $file, 0) )
            {
                $self->views_recalc_status($file);    
                log_debug(sprintf(qq|entity %s status recalculation flag ignored; unreachable flag exists|,
                    $file), _LOG_DEBUG);
                next;
            }

            $self->entity_recalc_status($file);    
            $self->views_recalc_status($file);    
        }
        closedir(DIR);
        sleep ($Period ? $Period : 15);
    }

}

sub dbh
{
    return $_[0]->[DBH];
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;
