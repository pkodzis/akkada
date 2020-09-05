package RRDGraph;

use strict;
use RRDs;
use POSIX;
use Time::HiRes qw( gettimeofday );
use File::Find; # for O_RW....
use IO::Handle; # for sysopen
use Fcntl ':flock'; # for flock


use URLRewriter;
use DB;
use Configuration;
use Entity;
use Common;

use constant
{
     ARGS => 0,
     URL_PARAMS => 1,
     ENTITY => 2,
     DBH => 3,

     _BEGIN => 4,
     _END => 5,
     UNIT => 6,
     SCALE => 8,
     WIDTH => 9,
     HEIGHT => 10,
     TITLE => 11,

     PROBE => 12,
     AVG => 13,
     MIN => 14,
     MAX => 15,
     AVG_FORM => 16,
     MIN_FORM => 17,
     MAX_FORM => 18,
     AVG_MIN_MAX_ORDER => 19,

     PROBE_PREPARE_DS => 20,
     PROBE_SPECIFIC => 21,

     HISTORY_ALARM_TIME => 22,
     HISTORY_ALARM_ERR => 23,

     ONLY_GRAPH => 24,
     ZOOM => 25,
     NO_LEGEND => 26,
     NO_X_GRID => 27,
     NO_Y_GRID => 28,
     NO_TITLE => 29,
     FORCE_SCALE => 30,
     MINIMUM => 31,

     PNAME => 40,
};

our $FileTmp = CFG->{Web}->{RRDGraph}->{DirTmp};
our $TitleMaxLen = CFG->{Web}->{RRDGraph}->{TitleMaxLen};

$FileTmp .= '/'
    unless $FileTmp =~ /\/$/;

sub new 
{
    my $class = shift;
    my $self = [];
    bless $self, $class;

    my $url_params = url_dispatch();

    my $def = CFG->{Web}->{RRDGraph}->{Defaults};

    $self->[DBH] = shift;

    $self->[ENTITY] = Entity->new($self->dbh, $url_params->{id_entity}, 1);
    $self->[PNAME] = Entity->new($self->dbh, $self->entity->id_parent, 1)->name;


    $self->[URL_PARAMS] = $url_params;
    $self->[ARGS] = [];
    $self->[AVG_MIN_MAX_ORDER] = 'LHA';

    $self->probe_prepare_ds( $url_params->{probe_prepare_ds} || 'prepare_ds');
    $self->probe_specific( $url_params->{probe_specific} || '');
    $self->begin( $url_params->{begin} || $def->{Begin});
    $self->begin( '-3h' )
        unless $self->begin;

    $self->end( $url_params->{end} || $def->{End});
    $self->end( 'now' )
        unless $self->end;

    $self->only_graph( $url_params->{only_graph} || 'off');
    $self->zoom( $url_params->{zoom} || 0);
    $self->no_legend( $url_params->{no_legend} || 'off');
    $self->no_x_grid( $url_params->{no_x_grid} || 'off');
    $self->no_y_grid( $url_params->{no_y_grid} || 'off');
    $self->no_title( $url_params->{no_title} || 'off');
    $self->force_scale( $url_params->{force_scale} || 'off');
    $self->minimum( $url_params->{minimum} || 0);
    $self->scale( $url_params->{scale} || '');
    $self->width( $url_params->{width} || $def->{Width});
    $self->height( $url_params->{height} || $def->{Height});

    $self->title('');
    $self->unit('');

    $self->avg_form( $url_params->{avg_form} || $def->{AvgForm} );
    $self->min_form( $url_params->{min_form} || $def->{MinForm} );
    $self->max_form( $url_params->{max_form} || $def->{MaxForm} );

    $self->avg( $url_params->{avg} ne '' ? $url_params->{avg} : $def->{Avg} );
    $self->min( $url_params->{min} ne '' ? $url_params->{min} : $def->{Min} );
    $self->max( $url_params->{max} ne '' ? $url_params->{max} : $def->{Max} );

    $self->history_alarm_time( $url_params->{history_alarm_time} ne '' ? $url_params->{history_alarm_time} : '' );
    $self->history_alarm_err( $url_params->{history_alarm_err} ne '' ? $url_params->{history_alarm_err} : '' );

    $self->avg_min_max_order( $url_params->{avg_min_max_order} || $def->{AvgMinMaxOrder} );

    $self->load_probe( $url_params->{probe} );
    $self->prepare_graph_preds;

    my $probe_prepare_ds = $self->probe_prepare_ds;
    my $probe_prepare_ds_pre = $probe_prepare_ds . "_pre";

    $self->probe->$probe_prepare_ds_pre($self);

    my ($up, $down, $ds);
    my @cf = split //, $self->avg_min_max_order;

    for ( @cf )
    {
        if ($_ eq 'A' && $self->avg != 0)
        {
            ($up, $down, $ds) = $self->probe->$probe_prepare_ds($self, 'AVERAGE');
        }
        elsif ($_ eq 'L' && $self->min != 0)
        {
            ($up, $down, $ds) = $self->probe->$probe_prepare_ds($self, 'MIN');
        }
        elsif ($_ eq 'H' && $self->max != 0)
        {
            ($up, $down, $ds) = $self->probe->$probe_prepare_ds($self, 'MAX');
        }
    }

#warn join("!", @{$self->args});

    $self->prepare_graph_postds($up, $down, $ds);

    if ($url_params->{save_session})
    {
        my $session = session_get;
        my $options = session_get_param($session, '_GRAPH_OPTIONS') || {};
        $options->{begin} = $self->begin;
        $options->{end} = $self->end;
        $options->{only_graph} = $self->only_graph;
        $options->{no_y_grid} = $self->no_y_grid;
        $options->{no_x_grid} = $self->no_x_grid;
        $options->{no_legend} = $self->no_legend;
        $options->{zoom} = $self->zoom;
        $options->{height} = $self->height;
        $options->{width} = $self->width;
        $options->{scale} = $self->scale;
        $options->{minimum} = $self->minimum;
        $options->{force_scale} = $self->force_scale;
        $options->{no_title} = $self->no_title;
        session_set_param($self->dbh, $session, '_GRAPH_OPTIONS', $options);
    }

    return $self;
}

sub load_probe
{   
    my $self = shift;
    my $probe_name = shift;

    my $probe;
    
    eval "require Probe::$probe_name; \$probe = Probe::${probe_name}->new();" or die $@;

    $self->[PROBE] = $probe;
}

sub prepare_graph_preds
{
    my $self = shift;
    my $p = shift;

    my $args = $self->args;

    my $begin = $self->begin;
    my $end = $self->end;

    push @$args, ''; # sub get -> podmienia te wartosc na prawdziwa nazwe pliku

    push @$args, '-r'
        if $self->force_scale eq 'on';

    push @$args, '-g'
        if $self->no_legend eq 'on';

    push @$args, '-m', $self->zoom
        if $self->zoom;
    push @$args, '-j'
        if $self->only_graph eq 'on';

    push @$args, '-a', 'PNG';
    push @$args, '--start', $begin;
    push @$args, '--end', $end
        if $end;

    push @$args, '--slope-mode';
    push @$args, '--interlaced';


    push @$args, '--color', "SHADEA#FFFFFF";
    push @$args, '--color', "SHADEB#FFFFFF";
    push @$args, '--color', "BACK#FFFFFF";

    push @$args, 'HRULE:0#6E6E6B';

    my $maximum = $self->scale || 'U';
    if ($self->avg < 0 || $self->min < 0 || $self->max < 0)
    {
        $self->height(2*$self->height);
        push @$args, '-l', -$maximum, '-u', $maximum;
    }
    else
    {
        push @$args, '-l', $self->minimum, '-u', $maximum;
    }

    my $history_t = $self->history_alarm_time;
    if ($history_t)
    {
        my $history_m = $self->history_alarm_err;
        $history_m = 'ERROR: ' . $history_m
             if $history_m;
        $history_m .= ' (' . strftime("%H:%M %m/%d/%Y", localtime($history_t)) . ')\n';
        $history_m =~ s/\:/\\\:/g;
        push @$args, sprintf(qq|VRULE:%s#FF0000:%s|, $history_t, $history_m);
    }


}

sub prepare_graph_postds
{
    my $self = shift;
    my $up = shift;
    my $down = shift;
    my $ds = shift;

    my $args = $self->args;

    if ($up)
    {   
        push @$args, "CDEF:down_up=$ds,UN,INF,0,IF";
        push @$args, "AREA:down_up#FFFFCC";
    }
    if ($down)
    {
        push @$args, "CDEF:down_down=$ds,UN,INF,0,IF,-1,*";
        push @$args, "AREA:down_down#FFFFCC";
    }

    my $begin = $self->begin;
    my $end = $self->end;

    push @$args, '--width', $self->width;
    push @$args, '--height', $self->height;

    if ($self->no_x_grid eq 'on')
    {
        push @$args, '--x-grid', 'none';
    }
    elsif ($begin eq '-10800' && $end eq 'now') 
    {
        push @$args, '--x-grid', 'MINUTE:5:HOUR:1:MINUTE:20:0:%H:%M'; #3hours
    }
    elsif ($begin eq '-1d' && $end eq 'now') 
    {
        push @$args, '--x-grid', 'HOUR:1:HOUR:24:HOUR:2:0:%H:%M'; #daily
    }
    elsif ($begin eq '-7d' && $end eq 'now')
    {
        push @$args, '--x-grid', 'HOUR:6:DAY:1:DAY:1:86400:%b %d'; #week
    }
    elsif ($begin eq '-31d' && $end eq 'now')
    {
        push @$args, '--x-grid', 'DAY:1:WEEK:1:WEEK:1:86400:%b %d'; #month
    }
    elsif ($begin eq '-365d' && $end eq 'now') 
    {
        push @$args, '--x-grid', 'MONTH:1:MONTH:1:MONTH:1:2419200:%b'; #year
    }

    if ($self->no_y_grid eq 'on')
    {
        push @$args, '--y-grid', 'none';
    }

    push @$args, '--title', $self->title
        unless $self->no_title eq 'on';
    push @$args, '--vertical-label', $self->unit;

    my $time = strftime '%m/%d/%Y %H\:%M\:%S', localtime;

    push @$args, 'COMMENT:\n';
    push @$args, 'COMMENT:\n';
    push @$args, 'COMMENT:created by akk@da ' . $time . '\r';

}

sub prepare_ds
{
    my $self = shift;
}

sub history_alarm_time
{
    my $self = shift;
    $self->[HISTORY_ALARM_TIME] = shift
        if @_;
    return $self->[HISTORY_ALARM_TIME];
}

sub history_alarm_err
{
    my $self = shift;
    $self->[HISTORY_ALARM_ERR] = shift
        if @_;
    return $self->[HISTORY_ALARM_ERR];
}

sub pname
{
    return $_[0]->[PNAME];
}

sub args
{
    return $_[0]->[ARGS];
}

sub dbh
{
    return $_[0]->[DBH];
}

sub url_params
{
    return $_[0]->[URL_PARAMS];
}

sub entity
{
    return $_[0]->[ENTITY];
}

sub begin
{
    my $self = shift;
    $self->[_BEGIN] = shift
        if @_;
    return $self->[_BEGIN];
}

sub end
{
    my $self = shift;
    $self->[_END] = shift
        if @_;
    return $self->[_END];
}

sub unit
{
    my $self = shift;
    $self->[UNIT] = shift
        if @_;
    return $self->[UNIT];
}    

sub no_legend
{
    my $self = shift;
    $self->[NO_LEGEND] = shift
        if @_;
    return $self->[NO_LEGEND];
}

sub force_scale
{
    my $self = shift;
    $self->[FORCE_SCALE] = shift
        if @_;
    return $self->[FORCE_SCALE];
}

sub minimum
{
    my $self = shift;
    $self->[MINIMUM] = shift
        if @_;
    return $self->[MINIMUM];
}

sub no_x_grid
{
    my $self = shift;
    $self->[NO_X_GRID] = shift
        if @_;
    return $self->[NO_X_GRID];
}

sub no_y_grid
{
    my $self = shift;
    $self->[NO_Y_GRID] = shift
        if @_;
    return $self->[NO_Y_GRID];
}

sub zoom
{
    my $self = shift;
    $self->[ZOOM] = shift
        if @_;
    return $self->[ZOOM];
}

sub no_title
{
    my $self = shift;
    $self->[NO_TITLE] = shift
        if @_;
    return $self->[NO_TITLE];
}

sub only_graph
{           
    my $self = shift;
    $self->[ONLY_GRAPH] = shift
        if @_;
    return $self->[ONLY_GRAPH];
} 

sub scale
{
    my $self = shift;
    $self->[SCALE] = shift
        if @_;
    return $self->[SCALE];
}     

sub width
{
    my $self = shift;
    $self->[WIDTH] = shift
        if @_;
    return $self->[WIDTH];
}     

sub height
{
    my $self = shift;
    $self->[HEIGHT] = shift
        if @_;
    return $self->[HEIGHT];
}     

sub title
{
    my $self = shift;
    if (@_)
    {
        $self->[TITLE] = shift;
    }
    my $name = $self->entity->name;

    $name = sprintf(qq|%s...|, substr($name, 0, $TitleMaxLen))
        if (length($name) > $TitleMaxLen);
    $name = sprintf(qq|%s - %s [%s-%s]|, $name, $self->[TITLE], $self->begin, $self->end);

    if ($self->pname)
    {
        $name = sprintf(qq|%s: %s|, $self->pname, $name);
    }

    $name = conspiracy($name)
        if CFG->{Web}->{ConspiracyFile};

    return $name;
}     

sub avg
{
    my $self = shift;
    $self->[AVG] = shift
        if @_;
    return $self->[AVG];
}     

sub avg_form
{
    my $self = shift;
    $self->[AVG_FORM] = shift
        if @_;
    return $self->[AVG_FORM];
}     

sub min
{
    my $self = shift;
    $self->[MIN] = shift
        if @_;
    return $self->[MIN];
}     

sub min_form
{
    my $self = shift;
    $self->[MIN_FORM] = shift
        if @_;
    return $self->[MIN_FORM];
}     

sub max
{
    my $self = shift;
    $self->[MAX] = shift
        if @_;
    return $self->[MAX];
}     

sub max_form
{
    my $self = shift;
    $self->[MAX_FORM] = shift
        if @_;
    return $self->[MAX_FORM];
}     

sub probe_specific
{
    my $self = shift;
    $self->[PROBE_SPECIFIC] = shift
        if @_;
    return $self->[PROBE_SPECIFIC];
}     

sub probe_prepare_ds
{
    my $self = shift;
    $self->[PROBE_PREPARE_DS] = shift
        if @_;
    return $self->[PROBE_PREPARE_DS];
}     

sub avg_min_max_order
{
    my $self = shift;
    if (@_)
    {
        $self->[AVG_MIN_MAX_ORDER] = shift
            if $_[0] eq 'AHL'
            || $_[0] eq 'ALH'
            || $_[0] eq 'LHA'
            || $_[0] eq 'LAH'
            || $_[0] eq 'HLA'
            || $_[0] eq 'HAL';
    }
    return $self->[AVG_MIN_MAX_ORDER];
}     

sub get_track_mode_and_form
{
    my $self = shift;
    my $cf = shift;
    return ($self->avg, $self->avg_form , 'a', 'average')
        if $cf eq 'AVERAGE';
    return ($self->min, $self->min_form, 'l', 'minimum')
        if $cf eq 'MIN';
    return ($self->max, $self->max_form, 'h', 'maximum')
        if $cf eq 'MAX';
}


sub probe
{
    return $_[0]->[PROBE];
}

sub get
{
    my $self = shift;

    my $ft = $FileTmp . gettimeofday . $$;

=pod
    die "sysopen \"$ft\": $!"
        unless sysopen(F, $ft, O_RDWR|O_CREAT, 0777);
    binmode(F);
    flock(F, LOCK_EX)
        or warn "flock: $!";
    truncate(F, 0)
        or warn "truncate: $!";
    F->autoflush(1);
=cut

    my $args = $self->args;
    $args->[0] = $ft;
#use Data::Dumper; warn Dumper $args;

    RRDs::graph(@$args);

    my $error = RRDs::error();
    warn $error
        if $error;
    open(H, "<$ft")
        or die "open: $! $ft";
=pod
    my $old_fh = select(H);
    $/ = undef;
=cut

    print STDOUT <H>;
    close(H);

=pod
    flock(F, LOCK_UN)
        or warn "flock: $!";
    close(F);
    select($old_fh) if defined $old_fh;
=cut
    unlink($ft)
        or warn "unlink \"$ft\": $!";

}


1;
