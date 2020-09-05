#!/usr/bin/perl -w

# script to test connectivity from AKKADA's server to GTalk's server.
# edit vales below

use lib "/akkada/lib";
use GTalk;
use strict;


#EDIT THESE VALUES
my $username = "username";
my $password = "password";
my $to = "to\@gmail.com";
my $b = "akkada test";

#DON'T CHANGE ANYTHING BELOW
print GTalk::GTalk(
    username => $username, 
    password => $password,
    to => $to,
    body => $b,
    debuglevel => 1, 
    debugfile => '/tmp/gtalklog.txt');


