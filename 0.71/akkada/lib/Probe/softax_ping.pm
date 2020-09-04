package Probe::softax_ping;

use vars qw($VERSION);

$VERSION = 0.2;

use base qw(Probe);
use strict;

use Time::HiRes qw(gettimeofday tv_interval);

use Net::SSLeay qw(get_https post_https make_headers make_form);
use LWP::Parallel::UserAgent;
use HTTP::Request::Common;
use XML::Simple; # qw(:strict);

use MyException qw(:try);
use Constants;
use Configuration;
use Log;
use Entity;
use URLRewriter;

use RRDGraph;

our $DataDir = CFG->{Probe}->{DataDir};
our $LogEnabled = CFG->{LogEnabled};
our $DefaultTimeout = CFG->{Probes}->{softax_ping}->{DefaultTimeout};
our $ThresholdMediumDefault = CFG->{Probes}->{softax_ping}->{ThresholdMediumDefault};
our $ThresholdHighDefault = CFG->{Probes}->{softax_ping}->{ThresholdHighDefault};

$|=1;

use constant 
{
    RESULT => 10,
    CODE => 11,
    BODY => 12,
};

sub id_probe_type
{
    return 15;
}

sub name
{
    return 'Softax application ping';
}

sub snmp
{
    return 0;
}

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    
    return $self;
}

sub code
{
    my $self = shift; 
    $self->[CODE] = shift
        if @_; 
    return $self->[CODE];
}   

sub body
{
    my $self = shift; 
    $self->[BODY] = shift
        if @_; 
    return $self->[BODY];
}   

sub clear_data
{
    my $self = shift;
    $self->[RESULT] = {};
    $self->[CODE] = 0;
    $self->[BODY] = undef;
};

sub entity_test
{
    my $self = shift;

    $self->SUPER::entity_test(@_);

    $self->clear_data;
    my $entity = shift;

    my ($t0, $t1, $params);

    $params->{test_name} = $entity->name;

    $params->{ip} = $entity->params('ip');
    throw EEntityMissingParameter('ip')
        unless $params->{ip};

    $params->{softax_ping_port} = $entity->params('softax_ping_port');
    throw EEntityMissingParameter('softax_ping_port')
        unless $params->{softax_ping_port};

    $params->{softax_ping_protocol} = $entity->params('softax_ping_protocol');
    throw EEntityMissingParameter('softax_ping_protocol')
        unless $params->{softax_ping_protocol};

    $params->{timeout} = $entity->params('timeout');
    $params->{timeout} = $DefaultTimeout
        unless defined $params->{timeout};

    $self->threshold_high($entity->params('threshold_high') || $ThresholdHighDefault);
    $self->threshold_medium($entity->params('threshold_medium') || $ThresholdMediumDefault);

    $t0 = [gettimeofday];

    $params->{softax_ping_protocol} eq 'http'
         ? $self->get_http($params)
         : $self->get_ssl($params);

    $t1 = [gettimeofday];
    $t0 = tv_interval($t0, $t1);

    my ($code, $body) = ($self->code, $self->body);

    if (! defined $code)
    {
        $self->errmsg('bad server response: unknown resposne code');
        $self->status(_ST_DOWN);
    }
    elsif ($code !~ /200/)
    {
        $self->errmsg('bad server response:' . $code);
        $self->status(_ST_DOWN);
    }
    else
    {
        try
        {   
            $body = eval { XMLin($body) } 
                if defined $body 
                && $body ne '';
        }
        except
        {   
            log_debug($@, _LOG_WARNING);
        };

        $body = ref($body) eq 'HASH' && defined $body->{test}
            ? $body->{test}
            : undef;

#use Data::Dumper; print Dumper ref($body), $body, $entity->id_entity; print "\n================\n";
    if (! defined $body)
    {
        $self->errmsg("test result missing");
        $self->status(_ST_MAJOR);
    }
    elsif ($body->{result} eq 'ERROR')
    {
        $self->errmsg($body->{'error-desc'})
            if defined $body->{'error-desc'};
        $self->status(_ST_DOWN);
    }
    elsif ($body->{result} eq 'SKIP')
    {
        $self->errmsg($body->{'error-desc'})
            if defined $body->{'error-desc'};
        $self->status(_ST_NOSTATUS);
    }

    my $status = $self->status;

    if ($status == _ST_OK && $body->{timing} > $self->threshold_high ) 
    {
        $self->errmsg("threshold high exceeded; test timing too long");
        $self->status(_ST_MINOR);
    }
    elsif ($status == _ST_OK && $body->{timing} > $self->threshold_medium ) 
    {
        $self->errmsg("threshold medium exceeded; test timing too long");
        $self->status(_ST_WARNING);
    }

    }

    my $result = $self->result;
    $result->{duration} = $t0;
    $result->{timing} = $body->{timing} 
        if ref($body) eq 'HASH' && defined $body->{timing};

    my $id_entity = $entity->id_entity;
    $entity->description_dynamic($body->{desc})
        if ref($body) eq 'HASH' && defined $body->{desc};
    $self->rrd_save($id_entity, $self->status);
    $self->save_data($id_entity, $t0, $body);
}

sub result
{
    return $_[0]->[RESULT];
}

sub rrd_result
{
    my $self = shift;
    my $result = $self->result;
    return
    {   
        'timing' => defined $result->{timing} ? $result->{timing} : 'U',
        'duration' => defined $result->{duration} ? $result->{duration} : 'U',
    };
}

sub rrd_config
{   
    return
    {   
        'timing' => 'GAUGE',
        'duration' => 'GAUGE',
    };
}


sub get_http
{
    my $self = shift;

    my $params = shift;
  
    my ($response_body,$respSize);

    my $ua = LWP::Parallel::UserAgent->new();

    my $request = new HTTP::Request
    (
        GET => 
        defined $params->{test_name} 
            ? sprintf(qq|http://%s:%s/ping/xml?test=%s|, $params->{ip}, $params->{softax_ping_port}, $params->{test_name}) 
            : sprintf(qq|http://%s:%s/ping/xml|, $params->{ip}, $params->{softax_ping_port}) 
    );

    $request->header('pragma' => 'no-cache', 'max-age' => '0'); 

    $ua->redirect (0);
    $ua->max_hosts(1);
    $ua->max_req  (1);
    $ua->register ($request); 

    my $entries = $ua->wait( $params->{timeout} );
    my $res = $entries->{(keys %$entries)[0]}->response;

    $self->code( $res->code );
    $self->body( $res->content );
}

sub get_ssl
{
    my $self = shift;
 
    my $params = shift;

    my ($page, $response, %reply_headers) = post_https
    (
        $params->{ip}, 
        $params->{softax_ping_port}, 
        defined $params->{test_name}
            ? "/ping/xml?test=$params->{test_name}"
            : "/ping/xml",
        make_headers('User-Agent' => 'akk@da', Referer => "https://$params->{ip}/")
    );
    $self->code( $response );
    $self->body( $page );
}  

sub discover_mode
{
    return _DM_MIXED;
}

sub discover_mandatory_parameters
{       
    my $self = shift;
    my $mp = $self->SUPER::discover_mandatory_parameters();
    
    push @$mp, 'softax_ping_port';
    push @$mp, 'softax_ping_protocol';
    
    return $mp;
}   

sub discover 
{
    my $self = shift;
    $self->SUPER::discover(@_);
    my $entity = shift;

    my $params = {};

    $params->{softax_ping_port} = $entity->params('softax_ping_port');
    throw EEntityMissingParameter('softax_ping_port')
        unless $params->{softax_ping_port};

    $params->{softax_ping_protocol} = $entity->params('softax_ping_protocol');
    throw EEntityMissingParameter('softax_ping_protocol')
        unless $params->{softax_ping_protocol};

    $params->{ip} = $entity->params('ip');
    throw EEntityMissingParameter('ip')
        unless $params->{ip};

    $params->{test_name} = CFG->{Probes}->{softax_ping}->{DiscoverTestName} || 'ias_html';

    $params->{softax_ping_protocol} eq 'http'
        ? $self->get_http($params)
        : $self->get_ssl($params);

    return
        unless $self->code =~ /200/;

    delete $params->{test_name};

    $params->{softax_ping_protocol} eq 'http'
        ? $self->get_http($params)
        : $self->get_ssl($params);

    return
        unless $self->code =~ /200/;

    my $body = $self->body;

    my $ref;

        try
        {   
            $ref = eval { XMLin($body) } 
                if $body ne '';
        }
        except
        {
            log_debug($@, _LOG_WARNING);
        };

    return
        unless ref($ref) eq 'HASH' && defined $ref->{test};

    $entity->params('softax_ping_version', $ref->{version})
        if defined $ref->{version};

    my $new = {};

    for (keys %{ $ref->{test} })
    {
        $new->{ $_ }->{softax_ping_protocol} = $params->{softax_ping_protocol};
        $new->{ $_ }->{softax_ping_port} = $params->{softax_ping_port};
    }

    return
        unless keys %$new;

    my $old = $self->_discover_get_existing_entities($entity);

    for my $name (keys %$old)
    {       
        next
            unless  defined $new->{$name};
                
        delete $new->{$name};
        delete $old->{$name};
    }
                
    for (keys %$new)
    {       
        $self->_discover_add_new_entity($entity, $_, $new->{$_})
            if $_ ne '';
        delete $new->{$_};
    }
}

sub _discover_add_new_entity
{
    my ($self, $parent, $name, $new) = @_;

    log_debug(sprintf(qq|adding new entity: id_parent: %s %s|, $parent->id_entity, $name), _LOG_DEBUG)
        if $LogEnabled;

    my $entity = $self->_entity_add({
       id_parent => $parent->id_entity,
       probe_name => CFG->{ProbesMapRev}->{$self->id_probe_type},
       name => $name,
       params => {},
       }, $self->dbh);

    if (ref($entity) eq 'Entity')
    {
        log_debug(sprintf(qq|new entity added: id_parent: %s id_entity: %s %s|, 
            $parent->id_entity, $entity->id_entity, $name), _LOG_INFO)
            if $LogEnabled;
    }
}

sub _discover_get_existing_entities
{

    my $self = shift;

    my @list = $self->SUPER::_discover_get_existing_entities(@_);

    my $result;
    my $name;

    for (@list)
    {   
        my $entity = Entity->new($self->dbh, $_);                                   
        if (defined $entity)
        {
            $name = $entity->name;
            $result->{$name}->{entity} = $entity;
        };
    };
    return $result;
}

sub save_data
{
    my $self = shift;
    my $id_entity = shift;
    my $duration = shift;
    my $body = shift;

    my $data_dir = $DataDir;

    open F, ">$data_dir/$id_entity";

    print F sprintf(qq|result\|%s\n|, $body->{result})
        if ref($body) eq 'HASH' && defined $body->{result};
    print F sprintf(qq|timing\|%s\n|, $body->{timing})
        if ref($body) eq 'HASH' && defined $body->{timing};
    print F sprintf(qq|duration\|%s\n|, $duration);

    close F;
}

sub desc_brief
{
    my ($self, $entity) = @_;

    my $result = $self->SUPER::desc_brief($entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    if (defined $data->{result})
    {   
        push @$result, sprintf(qq|result: %s|, $data->{result});
    }
    else
    {   
        push @$result, qq|result: n/a|;
    }
    if (defined $data->{duration})
    {   
        push @$result, sprintf(qq|duration: %.2f sec|, $data->{timing});
    }
    else
    {   
        push @$result, qq|duration: n/a|;
    }

    return $result;
}

sub desc_full_rows
{
    my ($self, $table, $entity) = @_;

    $self->SUPER::desc_full_rows($table, $entity);

    my $data = $entity->data;

    return
        unless scalar keys %$data > 1;

    $table->addRow('result', $data->{result})
        if defined $data->{result};
    $table->addRow('duration', sprintf(qq|%.2f sec|, $data->{timing}))
        if defined $data->{timing};
    $table->addRow('duration with test coating', sprintf(qq|%s sec|, $data->{duration}));

}

sub entity_get_name
{
    my $self = shift;
    my $entity = shift;

    my $result = sprintf(qq|%s%s|,
        $entity->name,
        $entity->status_weight == 0
            ? '*'
            : '');

    return $result;
}  

sub menu_stat
{ 
    return 1;
}

sub stat
{
    my $self = shift;
    my $table = shift;
    my $entity = shift;
    my $url_params = shift;
    my $default_only = defined @_ ? shift : 0;

    my $cgi = CGI->new();

    my $url;
    $url_params->{probe} = 'softax_ping';
    
    $url_params->{probe_prepare_ds} = 'prepare_ds';
                 
    $url_params->{probe_specific} = 'timing';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );

    return
        if $default_only;

    $url_params->{probe_specific} = 'duration';
    $table->addRow( $self->stat_cell_content($cgi, $url_params) );
}

sub prepare_ds_pre
{
    my $self = shift;
    my $rrd_graph = shift;
    my $url_params = $rrd_graph->url_params;

    $url_params->{probe_specific} eq 'timing'
        ? $rrd_graph->title('duration')
        : $rrd_graph->title('duration with test coating');
    $rrd_graph->unit('sec');
}

1;
