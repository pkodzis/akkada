package Top;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;          
use MyException qw(:try);
use Configuration;
use Log;
use Constants;
use Common;
use DB;
use Data::Dumper;

our $FlagsControlDir;
our $LogEnabled;
our $Period;
our $TopDir;
our $ListSize;
our $Expire;
our $DisplayColumns;
our $ProbesMapRev;
our $OldLastCheckAlarm;

use constant
{
    DBH => 1,
    LIST => 2,
};

sub cfg_init
{
    Configuration->reload_cfg;

    $FlagsControlDir = CFG->{FlagsControlDir};
    $LogEnabled = CFG->{LogEnabled};
    $Period = CFG->{Top}->{Period};
    $TopDir = CFG->{Top}->{TopDir};
    $ListSize = CFG->{Top}->{ListSize};
    $Expire = CFG->{Top}->{Expire};
    $DisplayColumns = CFG->{Top}->{DisplayColumns};
    $ProbesMapRev = CFG->{ProbesMapRev};
    $OldLastCheckAlarm = CFG->{Web}->{OldLastCheckAlarm};

    log_debug("configuration initialized", _LOG_WARNING)
        if $LogEnabled;
};


sub new
{
    my $this = shift;
    my $class = ref($this) || $this;

    cfg_init();

    my $self = [];

    $self->[DBH] = DB->new();
    $self->[LIST] = {};

    bless $self, $class;

    $SIG{USR1} = \&got_sig_usr1;
    $SIG{USR2} = \&got_sig_usr2;
    $SIG{HUP} = \&cfg_init;
    $SIG{TRAP} = \&trace_stack;

    return $self;
}

sub dbh
{
    return $_[0]->[DBH];
}

sub list
{
    return $_[0]->[LIST];
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

        $self->top10;

        sleep ($Period ? $Period : 60);
    }
}

sub top10
{
    my $self = shift;

    opendir(DIR, $TopDir)
        or log_debug("directory probems: $!", _LOG_ERROR);
    my @job = grep { /^\d+$/ } readdir(DIR);
    closedir DIR;

    my $list = $self->list;

    log_debug("before data loading: " . Dumper($list), _LOG_INTERNAL)
        if $LogEnabled;

    my ($probe, $id_entity, $value, $time);

    my $last_check;
    $time = time;

    for $id_entity (@job)
    {
        open F, "$TopDir/$id_entity"
            or log_debug("file access problem: $!", _LOG_ERROR);
        ($probe, $value) = split /:/, <F>;
        close F;
        $last_check = (stat("$TopDir/$id_entity"))[9];
        unlink "$TopDir/$id_entity";
        if ($value eq 'U')
        {
            delete $list->{$probe}->{$id_entity}
                if defined $list->{$probe}->{$id_entity};
        }
        else
        {
            $list->{$probe}->{$id_entity} = [$value, $last_check];
        }
    }

    log_debug("after data loading: " . Dumper($list), _LOG_INTERNAL)
        if $LogEnabled;

    for $probe (keys %$list)
    {
        for (keys %{$list->{$probe}})
        {
            delete $list->{$probe}->{$_}
                if $time - $list->{$probe}->{$_}->[1] > $Expire;
        }
    }

    $self->calculate;

    log_debug("after data processing: " . Dumper($list), _LOG_INTERNAL)
        if $LogEnabled;

    $self->save;
}

sub calculate
{
    my $self = shift;
    my $list = $self->list;
    my @tmp;

    for my $i (keys %$list)
    {
        my %h = ();
        @tmp = sort { $list->{$i}->{$b}->[0] <=> $list->{$i}->{$a}->[0] } keys %{$list->{$i}};
        @tmp = splice @tmp, 0, $ListSize;

        for (@tmp)
        {
            $h{$_} = $list->{$i}->{$_};
        }

        $list->{$i} = \%h;
    }
}

sub save
{
    my $self = shift;
    my $list = $self->list;

    my $file = "$TopDir/data";

    if (-e $file)
    {
        open F, "+<$file"
            or log_debug("file access problem: $!", _LOG_ERROR);
    }
        else
    {
        open F, ">$file"
            or log_debug("file access problem: $!", _LOG_ERROR);
    }
    seek(F, 0, 0);

    for my $i (keys %$list)
    {
        for (sort { $list->{$i}->{$b}->[0] <=> $list->{$i}->{$a}->[0] } keys %{$list->{$i}})
        {
            print F "$i:$_:$list->{$i}->{$_}->[0]:$list->{$i}->{$_}->[1]\n";
        }
    }
    truncate(F, tell(F));
    close F;

}

sub load
{
    my $self = shift;
    my $result = {};
    my ($idpt, $id,$v,$lc);

    open F, "$TopDir/data"
        or log_debug("file access problem: $!", _LOG_ERROR);
    while (<F>)
    {
        chomp;
        ($idpt, $id, $v, $lc) = split /:/, $_;
        $result->{$idpt} = []
            unless defined $result->{$idpt};
        push @{$result->{$idpt}}, [$id, $v, $lc];
    }
    close F;

    return $result;
}

sub get
{
    my $self = shift;
    my $url_params = shift;
    my $entity_cgi = shift;

    my $data = $self->load;

    return "no data. check nm-top.pl process"
        unless keys %$data;

    my $table = HTML::Table->new();
    $table->setAlign("LEFT");
    $table->setAttr('class="w"');

    my $d;
    my $t;
    my $color;
    my $r;
    my ($status, $last_check, $check_period, $e);

    my $dbh = $self->dbh;

    my $timestamp = time;
    my @row = ();

    for my $probe (keys %$data)
    {
        $d = $data->{$probe};
        $t = HTML::Table->new();
        $t->setAlign("LEFT");
        $t->setAttr('class="w"');
        #$t = table_begin(sprintf(qq|%s utilization - top %s|, uc $probe, $ListSize), 6, $t);
        $self->table_top_title($t);

        $url_params->{probe} = $probe;
        $url_params->{probe_specific} = '';

        $color = 1;
        my $i = 1;

        for (@$d)
        {
            try
            {
                $e = Entity->new( $dbh, $_->[0]);

                ($status) = $self->entity_row_top($entity_cgi, $t, $e, $i, $_->[1], $timestamp - $_->[2]);

                $r = $t->getTableRows;

                $self->entity_row_top_style($t, $r, $status, $e);

                $t->setRowClass($r, qq|tr_$color|);
                $color = $color ? 0 : 1;
                ++$i;
            }
            catch  EEntityDoesNotExists with
            {
            }
            except
            {
            };
        }
        #$table->addRow($t);
        push @row, make_popup_form($t, "section_${probe}_top10", sprintf(qq|%s utilization - top %s|, uc $probe, $ListSize));
        if (@row == $DisplayColumns)
        {
            $table->addRow(@row);
            $table->setCellAttr($table->getTableRows, $_, qq|class="f"|)
                for (1..@row);
            @row = ();
        }
    }
    if (@row)
    {
        $table->addRow(@row);
        $table->setCellAttr($table->getTableRows, $_, qq|class="f"|)
            for (1..@row);
    }

    return $table;
}

sub entity_row_top
{
    my $self = shift;
    my $entity_cgi = shift;
    my $table = shift;
    my $entity = shift;
    my $order = shift;
    my $util = shift;
    my $age= shift;

    return
        unless $entity;

    $entity->load_data;

    my $cgi = $entity_cgi->cgi;
    my $tree = $entity_cgi->tree;

    my $entity_parent;

    try
    {
        $entity_parent = Entity->new( $self->dbh, $entity->id_parent );
    }
    catch  EEntityDoesNotExists with
    {
    }
    except
    {
    };

    my $id_entity = $entity->id_entity;
    my $node = $tree->get_node($id_entity);
    my $status = $node->get_calculated_status;
    my $id_probe_type = $entity->id_probe_type;
    my $probe = $ProbesMapRev->{$id_probe_type};

    my @result;

    push @result, sprintf(qq|%s.|, $order);

    my $id_parent = $entity->id_parent;
    my $parent = $tree->get_node( $id_parent );

    push @result, $entity_cgi->image_vendor( $parent->image_vendor );
    push @result, $entity_cgi->a_popup(
    {
        id => $id_parent,
        probe => $ProbesMapRev->{$entity_parent->id_probe_type},
        name => $entity_cgi->entity_get_name($entity_parent, $ProbesMapRev->{$entity_parent->id_probe_type}),
        section => 'general',
    });

    push @result, $entity_cgi->image_function($parent);

    push @result, $entity_cgi->a_popup(
    {
        id => $id_entity,
        probe => $probe,
        name => $entity_cgi->entity_get_name($entity, $probe),
        section => 'general',
    });

    push @result, status_name($status);

    push @result, $entity_cgi->image_function($node);

    push @result, sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($util), $util);
    #push @result, "utilization:&nbsp;". sprintf(qq|<font class="%s">%.2f%%</font>|, percent_bar_style_select($util), $util);

    push @result, duration_row($age);

    $table->addRow(@result);

    return ($status);
}

sub entity_row_top_style
{
    my $self = shift;
    my $table = shift;
    my $row = shift;
    my $status = shift;
    my $entity = shift;

    $table->setCellAttr($row, 2, 'class="t2"');
    $table->setCellAttr($row, 3, 'class="f"');
    $table->setCellAttr($row, 4, 'class="t2"');
    $table->setCellAttr($row, 5, 'class="f"');
    $table->setCellAttr($row, 6, qq|class="ts| . $status . qq|"|);
    $table->setCellAttr($row, 7, 'class="t2"');
    $table->setCellAttr($row, 8, 'class="f"');
    $table->setCellAttr($row, 9, 'class="f"');
}

sub table_top_title
{
    my $self = shift;
    my $table = shift;

    $table->addRow(
        '',
        '',
        'parent',
        '',
        'name',
        'status',
        '',
        'utilization',
        'age of data',
    );

    my $row = $table->getTableRows;

    $table->setCellAttr($row, 3, 'class="g4"');
    $table->setCellAttr($row, 5, 'class="g4"');
    $table->setCellAttr($row, 6, 'class="g4"');
    $table->setCellAttr($row, 8, 'class="g4"');
    $table->setCellAttr($row, 9, 'class="g4"');
}

1;
