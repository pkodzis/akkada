package ActionsExecutor;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;          
use MyException qw(:try);
use Entity;
use Configuration;
use Log;
use Constants;
use Common;
use DB;
use Data::Dumper;
use Time::Period;

our $FlagsControlDir;
our $Period;
our $Modules;
our $LogEnabled;
our $ActionsDir;

use constant
{
    MODULES => 0,
    CONTACTS => 1,
    DBH => 2,
};


sub cfg_init
{
    Configuration->reload_cfg;

    $FlagsControlDir = CFG->{FlagsControlDir};
    $Period = CFG->{ActionsExecutor}->{Period};
    $Modules = CFG->{ActionsExecutor}->{Modules};
    $LogEnabled = CFG->{LogEnabled};
    $ActionsDir = CFG->{ActionsBroker}->{ActionsDir};

    log_debug("configuration initialized", _LOG_WARNING)
        if $LogEnabled;
};

sub new
{
    cfg_init();

    my $this = shift;
    my $class = ref($this) || $this;

    my $self = [];

    $self->[DBH] = DB->new();

    bless $self, $class;

    $self->modules_load();
    $self->contacts_load();

    $SIG{USR1} = \&got_sig_usr1;
    $SIG{USR2} = \&got_sig_usr2;
    $SIG{TRAP} = \&trace_stack;
    $SIG{HUP} = \&cfg_init;

    return $self;
}

sub dbh
{
    return $_[0]->[DBH];
}

sub contacts
{
    return $_[0]->[CONTACTS];
}

sub contacts_load
{
    my $self = shift;

    $self->[CONTACTS] = {};
    my $req = $self->dbh->exec(qq|
         SELECT contacts_2_cgroups.id_cgroup,contacts.id_contact,email,phone,other FROM contacts,contacts_2_cgroups 
         WHERE contacts.id_contact=contacts_2_cgroups.id_contact AND active=1;
         |);

    while( my $h = $req->fetchrow_hashref )
    {
        $self->[CONTACTS]->{$h->{id_cgroup}}->{$h->{id_contact}} = $h;
    }
}

sub modules
{
    return $_[0]->[MODULES];
}

sub modules_load
{   
    my $self = shift;

    $self->[MODULES] = {};
    for my $module (keys %$Modules)
    {
        eval "require ActionsExecutor::$module; \$self->[MODULES]->{\$module} = ActionsExecutor::${module}->new();";
        log_exception($@, _LOG_ERROR)
            if $@;
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

        if (flag_file_check($FlagsControlDir, 'ActionsExecutor.contacts_load', 1))
        {
            $self->contacts_load;
        }
        if (flag_file_check($FlagsControlDir, 'ActionsExecutor.modules_load', 1))
        {
            $self->modules_load;
        }

        if (flag_file_check($FlagsControlDir, 'ActionsExecutor.contacts_dump', 1))
        {
            log_debug(Dumper($self->contacts),_LOG_ERROR);
        }
        if (flag_file_check($FlagsControlDir, 'ActionsExecutor.modules_dump', 1))
        {
            log_debug(Dumper($self->modules),_LOG_ERROR);
        }


        opendir(DIR, $ActionsDir);
        while (defined($file = readdir(DIR)))
        {
            next
                unless $file =~ /^job\./;

            $self->process_job($file);
        }
        closedir(DIR);

        sleep ($Period ? $Period : 15);
    }
}

sub process_job
{
    my $self = shift;
    my $file = shift;
    my $fullfile = sprintf(qq|%s/%s|, $ActionsDir, $file);

    log_debug(sprintf(qq|start processing job %s|,$file),_LOG_DEBUG)
        if $LogEnabled;

    my $data = {};

    open F, $fullfile
        or log_exception( EFileSystem->new($!), _LOG_ERROR);
    %$data = map { s/\n// && split /\|\|/, $_ && $_ } <F>;
    close F;

    unlink $fullfile
        or log_exception( EFileSystem->new($!), _LOG_ERROR);

    my ($tmp, $module, $id_entity, $timestamp) = split /\./, $file;

    my $modules = $self->modules;

    if (! defined $modules->{$module})
    {
        log_debug(sprintf(qq|job %s ignored, because command %s is unknown or disabled.|, $file, $module), _LOG_ERROR)
            if $LogEnabled;
    }
   
    $modules->{$module}->process($data, $self->contacts->{ $data->{id_cgroup} }); 
}

sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;
