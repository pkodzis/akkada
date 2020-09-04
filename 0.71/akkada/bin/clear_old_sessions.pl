#!/akkada/bin/perl -w

use lib "$ENV{AKKADA}/lib";

use strict;
use Configuration;
use CGI::Session::ExpireSessions;

CGI::Session::ExpireSessions -> new(temp_dir => CFG->{Web}->{Session}->{FilesDir}, verbose => $ARGV[0]) -> expire_file_sessions();
