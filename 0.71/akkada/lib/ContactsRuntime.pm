package ContactsRuntime;

use strict;

use warnings FATAL => 'all';
use Apache2::RequestRec ( );
use Apache2::Const -compile => 'OK';

use lib "$ENV{AKKADA}/lib";
use DB;
use Common;
use Window::Buttons;
use CGI;
use LWP::Parallel::UserAgent;
use HTTP::Request;
use XML::Simple;
use Configuration;
use CGIContacts;

#our $ExternalInformation = CFG->{Web}->{Contacts}->{ExternalInformation};

#our $DB = DB->new();

sub handler 
{
    $0 = 'akk@da contacts';
    my $r = shift;

    CGI::header( -expires => "now");

    print qq|
<HTML>  
<HEAD>  
<TITLE>$0</TITLE>
<META HTTP-EQUIV="Pragma" CONTENT="no-cache">
<META HTTP-EQUIV="Expires" CONTENT="-1">
<LINK rel="StyleSheet" href="/css/akkada.css" type="text/css" />
</HEAD><BODY>|;


    my $path = $ENV{'PATH_INFO'};

    if (! $path)
    {
        print "no contacts available.";
        return $Apache2::Const::OK;
    }

    $path =~ s/\///g;
    $path = [ split /\,/, $path ];

=pod
    my $id_entity = shift @$path;
    my $title;
    my $req = $DB->exec("SELECT id_probe_type,name,id_parent 
        FROM entities,links 
        WHERE id_entity=$id_entity 
        AND entities.id_entity=links.id_child");
    $req = $req->fetchrow_hashref;

    if (! defined $req->{name})
    {
        $req = $DB->exec("SELECT id_probe_type,name FROM entities WHERE id_entity=$id_entity");
        $req = $req->fetchrow_hashref;
    }

    $title = $req->{name};
    if ($req->{id_probe_type} > 1)
    {
        $req = $DB->exec("SELECT * FROM entities WHERE id_entity=$req->{id_parent}");
        $req = $req->fetchrow_hashref;
        $title = "$req->{name}::" . $title;
    }

    my $t = table_begin('contacts for', 2, undef, $title);

    $req = $DB->exec(sprintf(qq|SELECT contacts.name,contacts.email,contacts.phone,contacts.company,contacts.alias
        FROM contacts, cgroups, contacts_2_cgroups, entities_2_cgroups
        WHERE entities_2_cgroups.id_entity IN (%s)
            AND entities_2_cgroups.id_cgroup = contacts_2_cgroups.id_cgroup 
            AND contacts_2_cgroups.id_contact = contacts.id_contact 
            AND contacts_2_cgroups.id_cgroup = cgroups.id_cgroup 
        GROUP BY contacts.id_contact
        ORDER BY contacts.name|, $id_entity ));

    my @s;
    my $color = 0;
    my $prv = {};
    my $ext;
    while( my $h = $req->fetchrow_hashref )
    {   
        @s = ();
        if ($h->{alias} && $ExternalInformation->{Enabled}) {
            $ext = get_external_info($h->{alias});
        }
        else
        {
            $ext = '';
        }
        push @s, $h->{name} if $h->{name};
        push @s, $h->{company} if $h->{company};
        push @s, $h->{phone} if $h->{phone};
        push @s, $h->{email} if $h->{email};
        $prv->{ join(', ', @s) } = 1;
        $t->addRow($ext->[0], sprintf(qq|*&nbsp;%s|, join(', ', @s)));
        $t->setCellAttr($t->getTableRows, 1, sprintf('class="%s"', $ext->[1]));
        $t->setCellAttr($t->getTableRows, 2, 'class="f"');
        $t->setRowAttr($t->getTableRows, sprintf(qq|class="tr_%d"|, $color));
        $color = ! $color;
    }

    $req = $DB->exec(sprintf(qq|SELECT contacts.name,contacts.email,contacts.phone,contacts.company,contacts.alias
        FROM contacts, cgroups, contacts_2_cgroups, entities_2_cgroups
        WHERE entities_2_cgroups.id_entity IN (%s)
            AND entities_2_cgroups.id_cgroup = contacts_2_cgroups.id_cgroup 
            AND contacts_2_cgroups.id_contact = contacts.id_contact 
            AND contacts_2_cgroups.id_cgroup = cgroups.id_cgroup 
        GROUP BY contacts.id_contact
        ORDER BY contacts.name|, join(', ', @$path) ));

    $color = 0;
    while( my $h = $req->fetchrow_hashref )
    {   
        @s = ();
        if ($h->{alias} && $ExternalInformation->{Enabled}) {
            $ext = get_external_info($h->{alias});
        }
        else
        {
            $ext = '';
        }
        push @s, $h->{name} if $h->{name};
        push @s, $h->{company} if $h->{company};
        push @s, $h->{phone} if $h->{phone};
        push @s, $h->{email} if $h->{email};
        next
            if defined $prv->{ join(', ', @s) };
        $t->addRow($ext->[0], sprintf(qq|%s|, join(', ', @s)));
        $t->setCellAttr($t->getTableRows, 1, sprintf('class="%s"', $ext->[1]));
        $t->setCellAttr($t->getTableRows, 2, 'class="f"');
        $t->setRowAttr($t->getTableRows, sprintf(qq|class="tr_%d"|, $color));
        $color = ! $color;
    }

    $t->addRow('all binded contact groups are empty.')
        if $t->getTableRows == 1;

    my $buttons = Window::Buttons->new();
    $buttons->button_refresh(0);
    $buttons->button_back(0);
    $buttons->add({ caption => 'close' , url => 'javascript:window.close()' });
    $t->addRow( $buttons->get );
    $t->setCellColSpan($t->getTableRows, 1, 2);

    print $t;
=cut
    print CGIContacts::get_contacts($path);
    print "</BODY></HTML>";

    return $Apache2::Const::OK;
}

=pod
sub get_external_info
{
    my $alias = shift;
    my $result = '';

    my $ua = LWP::Parallel::UserAgent->new();
    my $request = new HTTP::Request(GET => sprintf($ExternalInformation->{URL}, $alias));
    $request->header('pragma' => 'no-cache', 'max-age' => '0');
    $ua->redirect (0);
    $ua->max_hosts(1);
    $ua->max_req  (1);
    $ua->register ($request);

    my $entries = $ua->wait(1);
    my $res = $entries->{(keys %$entries)[0]}->response;
    my $content = $res->content();

    if ($content)
    {
         my $ref = XMLin($content);
         require $ExternalInformation->{Module} . '.pm';
         $result = $ExternalInformation->{Module}->process($ref);
    }
    return $result;
}
=cut

1;

