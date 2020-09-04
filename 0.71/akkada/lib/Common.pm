package Common;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION );

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( child_get_ids parent_get_id_and_status node_set_status node_get_status flag_files_create flag_file_check timeticks_2_duration merge_statuses load_data_file status_name percent_bar_style_select parameter_get_id duration sql_fix_string child_get_ids_all hex_en hex_de crypt_pass status_number duration_row tip parameter_get_list session_get_param session_set_param session_clear_param snmp_session runtime findmax smokecol flag_files_create_ow history_get_job msgs session_get conspiracy get_entities_mass_data table_begin decode_mac log_audit snmp_DateAndTime_2_str users_init right_bit_test get_param_instance get_param_instances_count img_chooser build_img_chooser get_entity_fqdn blade_fake);
%EXPORT_TAGS = ( default => [qw( child_get_ids parent_get_id_and_status node_set_status node_get_status flag_files_create flag_file_check timeticks_2_duration merge statuses load_data_file status_name percent_bar_style_select parameter_get_id duration sql_fix_string child_get_ids_all hex_en hex_de crypt_pass status_number duration_row tip parameter_get_list session_get_param session_set_param session_clear_param snmp_session runtime findmax smokecol flag_files_create_ow history_get_job msgs session_get conspiracy get_entities_mass_data table_begin decode_mac log_audit snmp_DateAndTime_2_str users_init right_bit_test get_param_instance get_param_instances_count img_chooser build_img_chooser get_entity_fqdn blade_fake)] );

use strict;
use MyException qw(:try);
use DB;
use Constants;
use Configuration;
use Log;
use Digest::MD5;
use CGI::Session;
use CGI;
use Data::Dumper;
use Serializer;
use Net::SNMP;
use RRDs;
use HTML::Table;
use User;

our $Web = CFG->{Web};
our $LogEnabled = CFG->{LogEnabled};

sub build_img_chooser
{
    my $cgi = shift;
    my $fname = shift;
    my $name = shift;
    my $value = shift;
    my $cont = shift;

    my $text = $cgi->textfield({ name => $name, value => $value, class => "textfield",});
    my $imgc = img_chooser($fname, $name, $value);
    my $t = HTML::Table->new(-spacing=>0, -padding=>0);
    $t->setAttr('class="w"');
    $t->addRow($text, '&nbsp;', $imgc, '&nbsp;');
    my $rows = $cont->{rows};
    $rows = $#$rows + 4;
    push @{ $cont->{class} }, [ $rows, 2, 't2' ];
    return $t->getTable;
}

sub img_chooser
{
    my $form = shift;
    my $field = shift;
    my $img = shift || 'imgfolder.gif';

    $img .= ".gif"
        if $img !~ /\./;
    return qq|<a href="javascript:nw('/imgs/$form/$field',400,600);"><img id="imgc$field" src="/img/$img" class="b10" alt="click her
e to choose image"></a>|;
}

sub right_bit_test
{
    my ($r, $bit) = @_;
    my $v = Bit::Vector->new(8);
    $v->from_Bin($r);
    return $v->bit_test($bit);
}

sub users_init
{
  my $db = shift;

  my $users = $db->dbh->selectall_hashref(qq|SELECT id_user,username,locked FROM users|, "id_user");

  my $req = $db->exec(qq|SELECT id_user,id_group FROM users_2_groups|);
  while( my $h = $req->fetchrow_hashref )
  {
      push @{$users->{ $h->{id_user} }->{ groups }}, $h->{id_group};
  }

  for (keys %$users)
  {
      $users->{$_} = User->new($users->{$_});
  }
  return $users;
}

sub snmp_DateAndTime_2_str
{
    my $result = unpack( "H*", shift);

    return 'bad format'
        unless $result;

    $result =  pack( "H*", scalar $result);

    return 'bad format'
        unless $result;

    my @d = unpack "H4C*", $result;

    return 'bad format'
        if ! @d || @d < 6;

    $result = sprintf(qq|%s-%02d-%02d %02d:%02d:%02d|, hex $d[0], $d[1], $d[2], $d[3], $d[4], $d[5]);
    $result .= sprintf(qq| %s%s:%s|, $d[7] == 43 ? '+' : '-', $d[8], $d[9])
        if (@d > 7);
    return $result;
}

sub user_name_get
{
    my ($db, $id_user) = @_;
    return $db->dbh->selectrow_arrayref(sprintf(qq|SELECT username FROM users where id_user=%s|, $id_user))->[0];
}

sub log_audit
{
    my $entity = shift;
    my $msg = shift;
    my $session = session_get();
    $entity->history_record(sprintf(qq|%s by %s (%s)|, 
        $msg,
        user_name_get($entity->dbh, $session->param('_LOGGED')),
        $session->param('_SESSION_REMOTE_ADDR')));
}

sub decode_mac
{ 
  my $a = unpack 'H*', shift;
  return join '.', unpack("A4" x (length($a)/4), $a);
}

sub table_begin
{
    my ($title, $cols, $table, $subtitle) = @_;

    if (! defined $table)
    {   
        $table= HTML::Table->new();
        $table->setAlign("CENTER");
        $table->setAttr('class="e"');
    }

    if ($title)
    {   
        $title = qq|<span class="z">&nbsp;$title:&nbsp;</b></span>|;
        $title .= qq|<b>&nbsp;$subtitle</b>|
            if $subtitle;
        $table->addRow($title);
        $table->setCellColSpan(1, 1, $cols);
    }

    return $table;
}

sub get_entities_mass_data
{
    my $dbh = shift;
    my $ids = shift;

    my $all = {};
    @$all{ @$ids } = @$ids;
#use Data::Dumper; log_debug("XXXX: " . Dumper($ids) . Dumper($all),_LOG_ERROR);
    my $result = $dbh->exec( sprintf(qq|SELECT *,UNIX_TIMESTAMP(status_last_change) 
        AS status_last_change FROM entities WHERE id_entity=%s|, join(" OR id_entity=", @$ids))
        )->fetchall_hashref("id_entity");

    my $req = $dbh->exec( sprintf(qq|SELECT * FROM links WHERE id_child=%s|, join(" OR id_child=", @$ids))
        )->fetchall_hashref("id_child");

    for (keys %$req)
    {
        next
            unless defined $result->{$_};
        $result->{$_}->{id_parent} = $req->{$_}->{id_parent};
        ++$all->{ $req->{$_}->{id_parent} };
    }

    $req = $dbh->exec( sprintf(qq| SELECT id_entity, name, value FROM parameters,entities_2_parameters
        WHERE entities_2_parameters.id_parameter=parameters.id_parameter AND (id_entity=%s)|, join(" OR id_entity=", keys %$all))
        )->fetchall_arrayref;

    my $params = {};
    $params->{ $_->[0] }->{ $_->[1] } = $_->[2]
        for @$req;


    for my $i (keys %$result)
    {
        my %p;
        $result->{$i}->{params_own} = $params->{ $i };

        if (defined $result->{$i} 
            && defined $result->{$i}->{id_parent}
            && defined $params->{ $result->{$i}->{id_parent} } 
            && defined $result->{$i}->{id_probe_type}
            && $result->{$i}->{id_probe_type} > 1)
        {
            %p = %{ $params->{ $result->{$i}->{id_parent} } };
        } 
#use Data::Dumper; log_debug("DDD1: " . Dumper(\%p),_LOG_ERROR);
        @p{ keys %{ $params->{$i} } } = values %{ $params->{$i} };
#use Data::Dumper; log_debug("DDD2: " . Dumper(\%p),_LOG_ERROR);
        $result->{$i}->{params} = \%p;
#use Data::Dumper; log_debug("DDD3: " . Dumper($result->{$i}),_LOG_ERROR);
    }
#use Data::Dumper; log_debug("DDD3: " . Dumper($result),_LOG_ERROR);
    return $result;
}

sub session_get
{
    my $cgi = new CGI;
    my $sid = $cgi->cookie("AKKADA_SESSION_ID");

    my $session = CGI::Session->new(undef, $sid, { Directory=> CFG->{Web}->{Session}->{FilesDir} } );
    return $session;
}

sub smokecol
{
    my $count = ( shift )- 2 ;
    my $half = int($count/2);

    my @items;
    my $color;

    for (my $i=$count; $i> $half; $i--)
    {
        $color = int(190/$half * ($i-$half))+50;
        push @items, "AREA:cp".($i+2)."#".(sprintf("%02x",$color) x 3);
    };

    for (my $i=$half; $i >= 0; $i--)
    {
        $color = int(190/$half * ($half - $i))+64;
        push @items, "AREA:cp".($i+2)."#".(sprintf("%02x",$color) x 3);
    };
    return \@items;
}

sub findmax 
{
    my $rrdFile = shift;
    my $pingCount = shift;
    my $start = shift;
    my $end = shift;

    my $pings = "ping".int($pingCount/1.1);

    my %maxmedian;
    my @maxmedian;

    my @args = ("dummy", '--start', $start);
    push @args, ('--end', $end);
    push @args, ("DEF:maxping=$rrdFile:median:AVERAGE",
        'PRINT:maxping:MAX:%le' );

    my ($graphret,$xs,$ys) = RRDs::graph(@args);

    my $error = RRDs::error();
    die $error
        if $error;

    my $val = $graphret->[0];
    $val = 1 
        if $val =~ /nan/i;

    $maxmedian{$start} = $val;
    push @maxmedian, $val;

    my $med = (sort @maxmedian)[int(($#maxmedian) / 2 )];
    my $max = 0.001; # 0.000001
    my $unison_tolerance = 2; ### ???? what the fuck is that? ;>

    foreach my $x ( keys %maxmedian )
    {
        if ( not defined $unison_tolerance 
             or ($maxmedian{$x} <= $unison_tolerance * $med and $maxmedian{$x} >= $med / $unison_tolerance) )
        {
            $max = $maxmedian{$x} 
                unless $maxmedian{$x} < $max;
            $maxmedian{$x} = undef;
        };
    }

    my $max_rtt = 100000;

    foreach my $x ( keys %maxmedian )
    {
        if (defined $maxmedian{$x}) 
        {
            $maxmedian{$x} *= 1.5;
        }
        else
        {
           $maxmedian{$x} = $max * 1.5;
        }
        # make it a nice clean number
        $maxmedian{$x} =~ s/^([0.]*)([1-9]).*/$1$2/;
        $maxmedian{$x} += ( ${1}."1" + 0.0 ) ;
        $maxmedian{$x} = $max_rtt
            if $max_rtt && $maxmedian{$x} > $max_rtt;       
    };
    return \%maxmedian;    
}


sub runtime
{
    if ( (getpwuid($<))[0] ne CFG->{OSLogin})
    {
        print sprintf(qq|switch to user %s before starting the system\n|, CFG->{OSLogin});
        exit;
    }

    my $pidfile = shift;

    if ($pidfile)
    {   
        $pidfile = sprintf(qq|%s/%s.pid|, CFG->{PidDir}, $0);
        if (-f $pidfile )
        {   
            open PIDFILE, "<$pidfile";
            <PIDFILE> =~ /(\d+)/;
            my $pid = $1;
            log_debug("error: another copy of $0 ($pid) seems to be running. check $pidfile\n", _LOG_ERROR)
                if kill 0, $pid;
            close PIDFILE;
        }
    }

    log_debug("starting $0 ...", _LOG_WARNING)
        if $LogEnabled;

    defined (my $pid = fork)
        or die "can't fork: $!";

    exit
        if $pid;

    if ($pidfile)
    {
        open(PIDFILE,">$pidfile") 
            or log_debug("problem creating $pidfile: $!\n", _LOG_ERROR);
        print PIDFILE "$$\n";
        close PIDFILE;
    }
}

sub get_param_instance
{
    my ($param, $instance) = @_;
    return ''
        unless defined $param;
    my @result = split /::/, $param;
    return defined $result[$instance]
        ? $result[$instance]
        : '';
}

sub get_param_instances_count
{
    my $param = shift;
    my @result = split /::/, $param;
    return @result > 0 
        ? $#result
        : 0;
}

sub snmp_session
{
    my $ip = shift;
    my $entity = shift;
    my $nonblocking = @_ ? shift : 0;

    my $snmp_v = 
    {
        '1' => 1,
        '2' => 1,
        '3' => 1,
        'snmpv1' => 1,
        'snmpv2c' => 1,
        'snmpv3' => 1,
    };

    my $snmp_instance = $entity->params('snmp_instance') || 0;

    log_debug(sprintf(qq|creating snmp session for instance %s|, $snmp_instance), _LOG_DEBUG)
        if $LogEnabled;

    my $version = get_param_instance($entity->params('snmp_version'), $snmp_instance);

    $version = 'snmpv2c'
        unless $version;

    if (! defined $snmp_v->{$version})
    {
        log_debug(sprintf(qq|unknown snmp version: %s. option ignored. using version 2c.|, $version), _LOG_WARNING);
        $version = 'snmpv2c';
    }

    my $snmp_port = get_param_instance($entity->params('snmp_port'), $snmp_instance);
    $snmp_port = 161
        unless $snmp_port;

    my $timeout = get_param_instance($entity->params('snmp_timeout'), $snmp_instance);
    $timeout = 3
        unless $timeout;

    my $retry = get_param_instance($entity->params('snmp_retry'), $snmp_instance);
    $retry = 3
        unless $retry;

    return $version eq '3' || $version eq 'snmpv3'
        ? snmp_session_v3($ip, $snmp_port, $entity, $version, $timeout, $retry, $nonblocking, $snmp_instance)
        : snmp_session_v12c($ip, $snmp_port, $entity, $version, $timeout, $retry, $nonblocking, $snmp_instance);
}

sub snmp_session_v12c
{
    my $ip = shift;
    my $snmp_port = shift;
    my $entity = shift;
    my $version = shift;
    my $timeout = shift;
    my $retry = shift;
    my $nonblocking = shift;
    my $snmp_instance = shift;


    my $community_ro = get_param_instance($entity->params('snmp_community_ro'), $snmp_instance);

    #throw EEntityMissingParameter(sprintf( qq|snmp_community_ro in entity %s|, $entity->id_entity))
    return (undef, "missing community_ro")
        unless $community_ro;

    return Net::SNMP->session(
        -hostname => $ip,
        -community => $community_ro,
        -port => $snmp_port,
        -version => $version,
        -translate => ['-all'],
        -timeout => $timeout,
        -retries => $retry,
        -nonblocking => $nonblocking,
        );

}

sub snmp_session_v3
{
    my $ip = shift;
    my $snmp_port = shift;
    my $entity = shift;
    my $version = shift;
    my $timeout = shift;
    my $retry = shift;
    my $nonblocking = shift;
    my $snmp_instance = shift;

    my $authprotocols = 
    {
        'md5' => 1,
        'sha' => 1,
    };

    my $user = get_param_instance($entity->params('snmp_user'), $snmp_instance);
    throw EEntityMissingParameter(sprintf( qq|snmp_user mandatory if version 3 used. in entity %s|, $entity->id_entity))
        unless $user;

    my $authpassword = get_param_instance($entity->params('snmp_authpassword'), $snmp_instance);
    throw EEntityMissingParameter(sprintf( qq|snmp_authpassword mandatory if version 3 used. in entity %s|, $entity->id_entity))
        unless $authpassword;

    my $authprotocol = get_param_instance($entity->params('snmp_authprotocol'), $snmp_instance);
    $authprotocol = 'md5'
        unless $authprotocol;

    if (! defined $authprotocols->{$authprotocol})
    {   
        log_debug(sprintf(qq|unknown snmp authprotocol: %s. supported protocols: md5 sha. trying md5.|, $authprotocol), _LOG_WARNING);
        $authprotocol = 'md5';
    }

    my $privprotocol = get_param_instance($entity->params('snmp_privprotocol'), $snmp_instance);

    return Net::SNMP->session(
        -hostname => $ip,
        -port => $snmp_port,
        -version => $version,
        -username     => $user,
        -authpassword => $authpassword,
        -authprotocol => $authprotocol,
        -translate => ['-all'],
        -nonblocking => $nonblocking,
        -timeout => $timeout,
        -retries => $retry)
        unless $privprotocol;

    my $privprotocols = 
    {
        'des' => 1,
        '3desede' => 1,
        'aescfb128' => 1,
        'aescfb192' => 1,
        'aescfb256' => 1,
    };

    if (! defined $privprotocols->{$privprotocol})
    {   
        log_debug(sprintf(qq|unknown snmp privprotocol: %s. supported privprotocol: . trying des.|, $privprotocol), _LOG_WARNING);
        $privprotocol = 'des';
    }

    my $privpassword =  get_param_instance($entity->params('snmp_privpassword'), $snmp_instance);
    $privpassword = $authpassword
        unless $privpassword;

    return Net::SNMP->session(
        -hostname => $ip,  
        -port => $snmp_port,
        -version => $version, 
        -username     => $user,     
        -authpassword => $authpassword,
        -authprotocol => $authprotocol,
        -privprotocol => $privprotocol,
        -privpassword => $privpassword,
        -nonblocking => $nonblocking,
        -translate => ['-all'],
        -timeout => $timeout, 
        -retries => $retry);
}

sub session_get_param
{
    my $session = shift;
    my $param = shift;
    my $context = $session->param('_CONTEXT');
    return
        unless ref($context);
    return
        unless defined $context->{$param};
    return $context->{$param};
}

sub session_set_param
{
    my $dbh = shift;
    my $session = shift;
    my $param = shift; 
    my $value = shift; 
    my $context = $session->param('_CONTEXT');
    $context = {}
        unless ref($context);
 
    if (defined $context->{$param} && $context->{$param} eq $value)
    {
    }
    else
    {
        $context->{$param} = $value;
        $session->param('_CONTEXT', $context);
#use Data::Dumper; warn Dumper([caller(0)]);
#use Data::Dumper; warn Dumper([caller(1)]);
#use Data::Dumper; warn Dumper([caller(2)]);
#use Data::Dumper; warn Dumper([caller(3)]);
#use Data::Dumper; warn Dumper([caller(4)]);
#warn  "DB: " . Dumper($context);
        my $id_logged_user = $session->param("_LOGGED");
        $dbh->exec( sprintf(qq|UPDATE users SET context='%s' WHERE id_user=%s|, freeze($context), $id_logged_user) )
            if $id_logged_user;
    }
}

sub session_clear_param
{    
    my $dbh = shift;
    my $session = shift;
    my $param = shift;
    my $context = $session->param('_CONTEXT');
    $context = {}
        unless ref($context);
    if (defined $context->{$param})
    {
        delete $context->{$param};
        $session->param('_CONTEXT', $context);
#warn  "DB: " . Dumper($context);

        my $id_logged_user = $session->param("_LOGGED");
        $dbh->exec( sprintf(qq|UPDATE users SET context='%s' WHERE id_user=%s|, freeze($context), $id_logged_user) )
            if $id_logged_user;
    }
}

sub msgs
{
    return defined $Web->{Msgs}->{$_[0]}
        ? $Web->{Msgs}->{$_[0]}
        : 'message unknown!';
}

sub tip
{
    return 
        unless $Web->{TipsShow};
    return defined $Web->{Tips}->{$_[0]}
        ? sprintf(qq|<span><table class="w"><tr><td class="p1">%s</td></tr></table></span>|, $Web->{Tips}->{$_[0]})
        : '';
}

sub crypt_pass 
{
    my $md5 = new Digest::MD5();
    $md5->add(shift);
    return $md5->hexdigest();
}

sub hex_en {
  return join('',unpack 'H*',(shift));
}

sub hex_de {
  return (pack'H*',(shift));
}

sub sql_fix_string
{
    if ($_[0])
    {
        $_[0] =~ s/\'//g;
        $_[0] =~ s/\</\&lt/g;
        $_[0] =~ s/\</\&gt/g;
    }
    return $_[0];
}

sub duration
{
    return duration_row(time - shift);
}

sub duration_row
{
  my $s = shift;
  my ($i, $result);

  $i = int( $s/217728000);
  $result .= "${i}y " if $i;
  $s = $s - $i*217728000;

  $i = int( $s/86400);
  $result .= "${i}d " if $i;
  $s = $s - $i*86400;

  $i = int( $s/3600);
  if ($i)
  {
     $i = "0$i" if $i < 10;
     $result .= "${i}h ";
  }
  $s = $s - $i*3600;

  $i = int( $s/60);
  if ($i)
  {
     $i = "0$i" if $i < 10;
     $result .= "${i}m ";
  }
  $s = $s - $i*60;

  if ($s)
  {
     $s = "0$s" if $s < 10;
     $result .= "${s}s ";
  }

  return $result;
}

sub percent_bar_style_select
{
    my $v = shift;
    my $low = @_ ? 1 : 0;

    if (! $low)
    {
        return 'j_10' unless $v;
        return 'j_10' if $v < 10;
        return 'j_20' if $v < 20;
        return 'j_30' if $v < 30;
        return 'j_40' if $v < 40;
        return 'j_50' if $v < 50;
        return 'j_60' if $v < 60;
        return 'j_70' if $v < 70;
        return 'j_80' if $v < 80;
        return 'j_90' if $v < 90;
        return 'j_100';
   }
   else
   {
        return 'j_11' unless $v;
        return 'j_11' if $v < 10;
        return 'j_21' if $v < 20;
        return 'j_31' if $v < 30;
        return 'j_41' if $v < 40;
        return 'j_51' if $v < 50;
        return 'j_61' if $v < 60;
        return 'j_71' if $v < 70;
        return 'j_81' if $v < 80;
        return 'j_91' if $v < 90;
        return 'j_101';
   }
}

sub status_name
{
  my $status = shift;
  return 'OK' if $status == 0;
  return 'Warning' if $status == 1;
  return 'Minor' if $status == 2;
  return 'Major' if $status == 3;
  return 'Down' if $status == 4;
  return 'No SNMP' if $status == 5;
  return 'Unreachable' if $status == 6;
  return 'Unknown' if $status == 64;
  return 'Recovered' if $status == 123;
  return 'Init' if $status == 124;
  return 'Info' if $status == 125;
  return 'Bad configuration' if $status == 126;
  return 'No status' if $status == 127;
  return undef;
}

sub status_number
{
  my $status = shift;
  return 0 if uc($status) eq 'OK';
  return 1 if uc($status) eq 'WARNING';
  return 2 if uc($status) eq 'MINOR';
  return 3 if uc($status) eq 'MAJOR';
  return 4 if uc($status) eq 'DOWN';
  return 5 if uc($status) eq 'NO SNMP';
  return 6 if uc($status) eq 'UNREACHABLE';
  return 64 if uc($status) eq 'UNKNOWN';
  return 123 if uc($status) eq 'RECOVERED';
  return 124 if uc($status) eq 'NEW';
  return 125 if uc($status) eq 'INFO';
  return 126 if uc($status) eq 'BAD CONFIGURATION';
  return 127 if uc($status) eq 'NO STATUS';
  return -1;
}

sub parameter_get_id
{
    throw EMissingArgument("database handle")
        unless @_ && ref($_[0]) eq 'DB';

    my $dbh = shift;
    
    throw EMissingArgument("parameter name")
        unless @_ && $_[0];

    my $name = shift;

    my $id_parameter = $dbh->exec(
        sprintf(qq| SELECT id_parameter FROM parameters
            WHERE name='%s'|, $name)
        )->fetchrow_arrayref;
    return defined $id_parameter
        ? $id_parameter->[0]
        : 0;    
}

sub parameter_get_list
{
    throw EMissingArgument("database handle")
        unless @_ && ref($_[0]) eq 'DB';

    my $dbh = shift;

    my @result = map $_->[0], @{ $dbh->exec(qq|SELECT name FROM parameters|)->fetchall_arrayref };
    return @result
        ? \@result
        : [];
}

sub load_data_file
{
    my $id_entity = shift 
        || throw EMissingArgument('id_entity');
    my $file = sprintf("%s/%s", CFG->{Probe}->{DataDir}, $id_entity);

    my ($result, @tmp);

    open F, $file;

    while (<F>)
    {
        chomp;
        @tmp = split /\|/, $_, 2;
        $result->{$tmp[0]} = $tmp[1];
    }

    close F;

    $result->{last_check} = (stat($file))[9];

    return $result;
}

sub merge_statuses
{
    my ($s1, $s2) = @_;

    if ($s1 <= _ST_UNREACHABLE && $s2 <= _ST_UNREACHABLE)
    {
        return $s1 > $s2 
            ? $s1
            : $s2;
    }
    elsif ($s1 <= _ST_UNREACHABLE && $s1 > _ST_OK)
    {
        return $s1;
    }
    elsif ($s2 <= _ST_UNREACHABLE && $s2 > _ST_OK)
    {
        return $s2;
    }
    elsif ($s2 == _ST_UNKNOWN)
    {
        return _ST_UNKNOWN;
    }
    elsif ($s1 == _ST_UNKNOWN)
    {
        return $s2;
    }
    else
    {
        return $s1 > $s2 
            ? $s1
            : $s2;
    }
}

sub flag_files_create_ow
{
    my $dir = shift;
    my @files = @_;
    my $i = 0;

    for my $file (@files)
    {   
        $file = sprintf(qq|%s/%s|, $dir, $file);

        unlink $file
            if -e $file;

        open F, ">$file" || die $!;
        print F "";
        close F;
        $i++;
        log_debug(sprintf(qq|flag file overriden: %s|, $file), _LOG_INTERNAL)
            if $LogEnabled;
    }

    return $i;
}

sub flag_files_create
{
    my $dir = shift;
    my @files = @_;
    my $i = 0;
#use Data::Dumper; log_debug(Dumper(\@files) . $dir, _LOG_ERROR);
    my $filefullname;
    for my $file (@files)
    {
        $filefullname = sprintf(qq|%s/%s|, $dir, $file);

        if ($file eq 'master_hold')
        {
            while ( -e $filefullname)
            {
                log_debug("waiting for master tree lock at " . (caller(1))[3], _LOG_DEBUG)
                    if $LogEnabled;
                sleep 1;
            };
        }
        
        if (! -e $filefullname)
        {
            open F, ">$filefullname" || die $!;
            print F "";
            close F;
            $i++;
            log_debug(sprintf(qq|flag file created: %s|, $filefullname), _LOG_INTERNAL)
                if $LogEnabled;
        }
    }
    return $i;
}

sub flag_file_check
{
    my ($dir, $file, $delete) = @_;

    my $tm;

    $file = sprintf(qq|%s/%s|, $dir, $file);

    if ( -e $file )
    {
        $tm = (stat($file))[9];
        if ($delete)
        {
            unlink $file || die $!;
        }
        return $tm;
    }
    else
    {
        return 0;
    }
}

sub history_get_job
{
    my $dbh = shift;
    my $id_entity = shift;
    my $view_mode = shift;
    my $view_entities = shift;

    my $job =[];

#!= _VM_TREEVIEWS &&$view_mode != _VM_VIEWS && $view_mode != _VM_VIEWS_LIGHT && $view_mode != _VM_FIND && $view_mode != _VM_TREEFIND
    my $root = $id_entity && ! defined $VIEWS_ALLVIEWS{$view_mode} && ! defined $VIEWS_ALLFIND{$view_mode}
        ? $id_entity
        : 0;

    if (! defined $VIEWS_ALLVIEWS{$view_mode} && ! defined $VIEWS_ALLFIND{$view_mode})
    {   
        $job = child_get_ids_all($dbh, $root)
            if $root;
    }
    else
    {   
        my $tmp;
        for (@$view_entities)
        {   
            for ( @{child_get_ids_all($dbh, $_)})
            {   
                ++$tmp->{$_};
            }
        }
        $job = [ keys %$tmp ];
    }
    return $job;
}

sub child_get_ids
{
    throw EMissingArgument("database handle")
        unless @_ && ref($_[0]) eq 'DB';

    my $dbh = shift;

    throw EMissingArgument('id_entity')
        unless @_;
    throw EBadArgumentType(sprintf(qq|id_entity: '%s'|, $_[0]))
                unless $_[0] =~ /^[1-9].*$/;

    my @result = map $_->[0], @{ $dbh->exec(sprintf(qq|SELECT id_child FROM links WHERE id_parent=%s|, shift))->fetchall_arrayref };
    return \@result;
}

sub child_get_ids_all
{
    my $db = shift;
    my $id = shift;

    my $links = $db->dbh->selectall_hashref("SELECT * FROM links", "id_child");
    my $parents = {};
    for (keys %$links)
    {
        $parents->{$links->{$_}->{id_parent}}->{$_} = 1;    
    }
    my $res = [];

    if ($id)
    {
        child_get_ids_all_($parents, $res, $id);
    }
    else
    {
        for (keys %$links)
        {
            push @$res, $_;
        }
    }

    return $res;
}

sub child_get_ids_all_
{
    my ($parents, $res, $id) = @_;
    push @$res, $id;
    if (defined $parents->{$id})
    {
        for (keys %{ $parents->{$id} })
        {
            child_get_ids_all_($parents, $res, $_);
                #if ref($parents->{$id}->{$_});
        }
    }
}

sub parent_get_id_and_status
{
    throw EMissingArgument("database handle")
        unless @_ && ref($_[0]) eq 'DB';

    my $dbh = shift;

    throw EMissingArgument('id_entity')
        unless @_;
    throw EBadArgumentType(sprintf(qq|id_entity: '%s'|, $_[0]))
                unless $_[0] =~ /^[1-9].*$/;

    my $req = $dbh->exec(sprintf(qq|SELECT id_entity,status FROM links,entities 
        WHERE id_entity=id_parent AND id_child=%s|, shift))->fetchrow_hashref;

    return defined $req
        ? ($req->{id_entity}, $req->{status})
        : (0, undef);
}

sub node_get_status
{
    throw EMissingArgument("database handle")
        unless @_ && ref($_[0]) eq 'DB';

    my $dbh = shift;

    throw EMissingArgument('id_entity')
        unless @_;
    throw EBadArgumentType(sprintf(qq|id_entity: '%s'|, $_[0]))
                unless $_[0] =~ /^[1-9].*$/;

    my $id = shift;

    my $req = $dbh->exec(sprintf(qq|SELECT * FROM statuses WHERE id_entity=%s|, $id))->fetchrow_hashref;

    return defined $req
        ? $req
        : {status=>125, status_weight=>1};
}

sub node_set_status
{
    throw EMissingArgument("database handle")
        unless @_ && ref($_[0]) eq 'DB';

    my $dbh = shift;

    throw EMissingArgument('id_entity')
        unless @_;
    throw EBadArgumentType(sprintf(qq|id_entity: '%s'|, $_[0]))
                unless $_[0] =~ /^[1-9].*$/;

    my $id = shift;

    throw EMissingArgument('status')
        unless @_;
    throw EBadArgumentType(sprintf(qq|status: '%s'|, $_[0]))
                unless $_[0] =~ /^[0-9].*$/;

    my $status = shift;

    my $req = $dbh->exec(sprintf(qq|SELECT * FROM statuses WHERE id_entity=%s|, $id))->fetchrow_hashref;
    if (defined $req)
    {
        $dbh->exec(sprintf(qq|UPDATE statuses set status=%s,last_change=NOW() WHERE id_entity=%s|, $status, $id));
    }
    else
    {
        $dbh->exec(sprintf(qq|INSERT INTO statuses VALUES(%s,%s,NOW(), 1)|, $id, $status));
    }

    log_debug(sprintf(qq|node_set_status: entity %s: set status %d|, $id, $status), _LOG_DEBUG);

}

sub timeticks_2_duration
{
  die ("missing argument seconds") unless @_;
  my $s = shift;
  my $result = "timeticks: ($s) " ;
  my $i;

  return $result
      if $s eq '';

  $i = int( $s/21772800000);
  $result .= "${i} years, " if $i;
  $s = $s - $i*21772800000;

  $i = int( $s/8640000);
  $result .= "${i} days, " if $i;
  $s = $s - $i*8640000;

  $i = int( $s/360000);
  $i = "0$i" if $i < 10;
  $result .= $i ? "${i}:" : "0";
  $s = $s - $i*360000;

  $i = int( $s/6000);
  $i = "0$i" if $i < 10;
  $result .= $i ? "${i}:" : "0";
  $s = $s - $i*6000;

  $i = int( $s/60);
  $i = "0$i" if $i < 10;
  $result .= $i ? "${i}." : "0";
  $s = $s - $i*60;

  $s = "0$s" if $s < 10;
  $result .= $s ? $s : "0";

  return $result;
}

sub conspiracy
{
    my $result = shift;

    my $file = CFG->{Web}->{ConspiracyFile};

    return $result
        unless -e $file;

    open F, $file
        or return $result;

    my @s;

    while (<F>)
    {   
        next
            if /^#/;
        s/\n//g;
        @s = split(/\|/, $_, 2);
        $result =~ s/$s[0]/$s[1]/gi;
    }

    close F;

    return $result;
}

sub get_entity_fqdn
{           
    my $id_entity = shift;
    my $tree = shift;
    
    my @fqdn;
    my $items = $tree->items;

    if (! $id_entity)
    {
        push @fqdn, 'root';
    }
    else
    {
        my $name;
        my $path = $tree->get_node_path($id_entity);

        my $id;

        while (@$path)
        {
            $id = pop @$path;
            $name = defined $items->{$id}
                ? $items->{$id}->name
                    ? $items->{$id}->name
                    : "unknown, id $id"
                : 'undef error!';
            push @fqdn, $name;
        }
    }
    if (@fqdn)
    {
        $fqdn[$#fqdn] = sprintf("<b>%s</b>", $fqdn[$#fqdn]);
    }
    return join('::', @fqdn);
}

sub blade_fake
{
    return join("", map { chr($_) } 128,0,4,80);
    #my $result = '';
    #for (128,0,4,80,1,10,13,77,227) { $result .= chr($_) }
    #return $result;
}

1;
