# Modified for AKKADA's purposes by Piotr Kodzis

##############################################################################
#
#  This library is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Library General Public
#  License as published by the Free Software Foundation; either
#  version 2 of the License, or (at your option) any later version.
#
#  This library is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  Library General Public License for more details.
#
#  You should have received a copy of the GNU Library General Public
#  License along with this library; if not, write to the
#  Free Software Foundation, Inc., 59 Temple Place - Suite 330,
#  Boston, MA  02111-1307, USA.
#
#  Copyright (C) 1998-2004 Jabber Software Foundation http://jabber.org/
#
#  Modified by Thus0 <Thus0@free.fr>
#  2005/10 : Google Talk Instant Messaging support
#
##############################################################################

package GTalk;

=head1 NAME

GTalk - Send instant message to Google Talk

=head1 SYNOPSIS

  GTalk provides a Perl user with access to Google Talk instant messaging.

  For more information about Google Talk visit:

    http://www.google.com/talk/developer.html

=head1 DESCRIPTION

  GTalk is a module to easy send instant messages to Google Talk
  instant messaging using XMPP Protocol, with SASL PLAIN authentication.
  It needs Net::XMPP and Authen::SASL modules.

=head1 EXAMPLES
  
  use Gtalk;
  GTalk::GTalk(username=>"thus0", password=>"test123",
               to=>"petrus\@gmail.com", body=>"Hello World!");

  GTalk::GTalk(debuglevel=>2, debugfile=>'Gtalk-log.txt',
               username=>"thus0", password=>"test123",
               to=>"petrus\@gmail.com", body=>"Hello World!");
  

=head1 METHODS

  GTalk(username=>string,    - creates the GTalk object. 'debugfile'
        password=>string,    should be set to the path for the debug
        to=>string,          log to be written. If set to "stdout" then
        subject=>string,     the debug will go there. 'debuglevel'
        body=>string,        controls the amount of debug.
        debuglevel=>0|1|2,   'username' is your google username (without	
        debugfile=>string,   the suffix '@google.com') whereas 'to' is the
        timeout=>integer);   recipient google email (i.e xxxx@google.com)

=head1 AUTHOR

Google Talk support by Thus0 <thus0@free.fr> in October of 2005

=head1 COPYRIGHT

Copyright (c) 2005 Thus0. All rights reserved.
This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

use Authen::SASL;
use Carp;
use Getopt::Long;
use Net::XMPP qw( Client );
use strict;

sub parse_error
{
    my $er = shift;
    my $data = shift;
    if (ref($data) eq 'HASH')
    {
        $er = sprintf(qq|%s: %s: %s|, $er, $data->{type}, $data->{text});
    }
    elsif (ref($data) eq 'ARRAY')
    {
        $er = @$data
            ? sprintf(qq|%s: %s: %s|, $er, $data->[0], $data->[1])
            : $er;
    }
    else
    {
        $er = sprintf(qq|%s: %s|, $er, $data);
    }
    return $er;
}

###############################################################################
#
# GTalk - Send an instant message to Google Talk instant messanging.
#
###############################################################################
sub GTalk
{
    my %args;

    while($#_ >= 0) { $args{ lc pop(@_) } = pop(@_); }

    carp("GTalk requires a username argument") unless exists($args{username});
    carp("GTalk requires a password argument") unless exists($args{password});
    carp("GTalk requires a to argument") unless exists($args{to});
    carp("GTalk requires a body argument") unless exists($args{body});

    $args{debuglevel} = 0 unless exists($args{debuglevel});
    $args{debugfile}  = 'stdout' unless exists($args{debugfile});
    $args{timeout}    = 10 unless exists($args{timeout});
    $args{subject}    = 'GTalk' unless exists($args{subject});
    $args{resource}   = 'GTalk.pl';

    my $client = new Net::XMPP::Client(debuglevel=>$args{debuglevel},
                                       debugfile=>$args{debugfile});
    
    if (! $client->Connect(hostname=>"talk.google.com", port=>5222,
                           timeout=>$args{timeout}, connectiontype=>"tcpip",
                           tls=>1, componentname=>"gmail.com"))
    {
        return parse_error("connection error", $client->GetErrorCode());
    }

    # Modification of XMPP::Protocol::AuthSASL
    my @res = GAuthSASL($client, username=>$args{username}, password=>$args{password},
                        resource=>$args{resource});
    return parse_error("Authorization failed", \@res)
        if ! @res || $res[0] ne "ok";

    # Send google talk message
    $client->MessageSend(to=>$args{to}, subject=>$args{subject},
                         body=>$args{body}, resource=>$args{resource});

    return parse_error("Sending failed", \@res)
        if ! @res || $res[0] ne "ok";

    # Close connection
    $client->Disconnect();

    return '';
}

###############################################################################
#
# AuthSASL - Try and auth to Google Talk using SASL, the XMPP preferred way
#            of authenticating.
#
###############################################################################
sub GAuthSASL
{
    my $self = shift;
    my %args;

    while($#_ >= 0) { $args{ lc pop(@_) } = pop(@_); }

    $self->{DEBUG}->Log1("AuthSASL: shiney new auth");

    carp("AuthSASL requires a username arguement")
        unless exists($args{username});
    carp("AuthSASL requires a password arguement")
        unless exists($args{password});

    $args{resource} = "" unless exists($args{resource});

    #-------------------------------------------------------------------------
    # Create the SASLClient on our end
    #-------------------------------------------------------------------------
    my $sid = $self->{SESSION}->{id};
    # Modification of XML::Stream::SASLClient
    &GSASLClient($self->{STREAM}, $sid,
                                  $args{username},
                                  $args{password}
                                 );

    $args{timeout} = "120" unless exists($args{timeout});

    #-------------------------------------------------------------------------
    # While we haven't timed out, keep waiting for the SASLClient to finish
    #-------------------------------------------------------------------------
    my $endTime = time + $args{timeout};
    while(!$self->{STREAM}->SASLClientDone($sid) && ($endTime >= time))
    {
        $self->{DEBUG}->Log1("AuthSASL: haven't authed yet... let's wait.");
        return unless (defined($self->Process(1)));
        &{$self->{CB}->{update}}() if exists($self->{CB}->{update});
    }
    
    #-------------------------------------------------------------------------
    # The loop finished... but was it done?
    #-------------------------------------------------------------------------
    if (!$self->{STREAM}->SASLClientDone($sid))
    {
        $self->{DEBUG}->Log1("AuthSASL: timed out...");
        return( "system","SASL timed out authenticating");
    }

    #-------------------------------------------------------------------------
    # Ok, it was done... but did we auth?
    #-------------------------------------------------------------------------
    if (!$self->{STREAM}->SASLClientAuthed($sid))
    {
        $self->{DEBUG}->Log1("AuthSASL: Authentication failed.");
        return ( "error", $self->{STREAM}->SASLClientError($sid));
    }
    
    #-------------------------------------------------------------------------
    # Phew... Restart the <stream:stream> per XMPP
    #-------------------------------------------------------------------------
    $self->{DEBUG}->Log1("AuthSASL: We authed!");
    $self->{SESSION} = $self->{STREAM}->OpenStream($sid);
    $sid = $self->{SESSION}->{id};
    
    $self->{DEBUG}->Log1("AuthSASL: We got a new session. sid($sid)");

    #-------------------------------------------------------------------------
    # Look in the new set of <stream:feature/>s and see if xmpp-bind was
    # offered.
    #-------------------------------------------------------------------------
    my $bind = $self->{STREAM}->GetStreamFeature($sid,"xmpp-bind");
    if ($bind)
    {
        $self->{DEBUG}->Log1("AuthSASL: Binding to resource");
        $self->BindResource($args{resource});
    }

    #-------------------------------------------------------------------------
    # Look in the new set of <stream:feature/>s and see if xmpp-session was
    # offered.
    #-------------------------------------------------------------------------
    my $session = $self->{STREAM}->GetStreamFeature($sid,"xmpp-session");
    if ($session)
    {
        $self->{DEBUG}->Log1("AuthSASL: Starting session");
        $self->StartSession();
    }

    return ("ok","");
}

###############################################################################
#
# GSASLClient - This is a helper function to perform all of the required steps
#               for doing SASL with the Google Talk server.
#
###############################################################################
sub GSASLClient
{
    my $self = shift;
    my $sid = shift;
    my $username = shift;
    my $password = shift;
  
    my $mechanisms = $self->GetStreamFeature($sid,"xmpp-sasl");

    return unless defined($mechanisms);

    my $sasl = new Authen::SASL(mechanism=>join(" ",@{$mechanisms}),
                                callback=>{
                                           user     => $username,
                                           pass     => $password
                                          }
                               );

    $self->{SIDS}->{$sid}->{sasl}->{client} = $sasl->client_new();
    $self->{SIDS}->{$sid}->{sasl}->{username} = $username;
    $self->{SIDS}->{$sid}->{sasl}->{password} = $password;
    $self->{SIDS}->{$sid}->{sasl}->{authed} = 0;
    $self->{SIDS}->{$sid}->{sasl}->{done} = 0;

    $self->SASLAuth($sid);
}

1;
