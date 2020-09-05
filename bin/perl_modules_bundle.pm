package Bundle::perl_modules_bundle;

$VERSION = '0.01';

1;

__END__

=head1 NAME

Bundle::perl_modules_bundle - Snapshot of monules needed by akkada

=head1 SYNOPSIS

perl -MCPAN -e 'install Bundle::Snapshot_2007_10_23_00'

=head1 CONTENTS

MIME::Base64 undef

Class::ErrorHandler undef

Data::Buffer undef

Math::BigInt undef

Digest::SHA1 undef

String::CRC32 undef

Math::Pari undef

Crypt::IDEA undef

Digest::BubbleBabble undef

Crypt::DH undef

Math::GMP undef

Crypt::DES_EDE3 undef

Crypt::CBC undef

Crypt::Blowfish undef

Tie::EncryptedHash undef

Class::Loader undef

Crypt::Random undef

Convert::ASCII::Armour undef

Digest::MD2 undef

Sort::Versions undef

Crypt::Primes undef

Crypt::RSA undef

Convert::PEM undef

Crypt::DSA undef

Array::Compare undef

Tree::DAG_Node undef

Sub::Uplevel undef

Test::Exception undef

Test::Warn undef

Sub::Uplevel undef

Tree::DAG_Node undef

Sub::Uplevel undef

Test::Exception undef

Array::Compare undef

Tree::DAG_Node undef

Test::Warn undef

Bit::Vector undef

Cache::File undef

CGI undef

CGI::Compress::Gzip undef

CGI::Session::ExpireSessions undef

CGI::Session undef

Crypt::DES undef

Date::Manip undef

DBD::mysql undef

DBI undef

Digest::HMAC undef

Digest::MD5 undef

Error undef

File::Spec undef

HTML::Table undef

HTTP::Request undef

HTTP::Request::Common undef

IO::Handle undef

IO::Socket undef

IO::Socket::INET undef

IO::Socket::SSL undef

LWP::Parallel::UserAgent undef

Mail::Sender undef

Math::RPN undef

NetAddr::IP undef

Net::DNS undef

Net::DNS::Resolver undef

Net::IP undef

Net::SNMP undef

Net::SSH::Perl undef

Net::SSLeay undef

Number::Format undef

Number::Format undef

Pod::Escapes undef

Pod::Simple undef

Proc::ProcessTable undef

Test::Builder::Tester undef

Test::More undef

Test::Pod undef

Time::HiRes undef

Time::Local undef

Time::Period undef

XML::Simple undef

Authen::SASL undef

Net::SSH::Perl undef

XML::Stream undef

Net::XMPP undef

=head1 CONFIGURATION

Summary of my perl5 (revision 5 version 8 subversion 8) configuration:
  Platform:
    osname=linux, osvers=2.6.9-34.elsmp, archname=i386-linux-thread-multi
    uname='linux hs20-bc2-2.build.redhat.com 2.6.9-34.elsmp #1 smp fri feb 24 16:56:28 est 2006 i686 i686 i386 gnulinux '
    config_args='-des -Doptimize=-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -m32 -march=i386 -mtune=generic -fasynchronous-unwind-tables -Dversion=5.8.8 -Dmyhostname=localhost -Dperladmin=root@localhost -Dcc=gcc -Dcf_by=Red Hat, Inc. -Dinstallprefix=/usr -Dprefix=/usr -Darchname=i386-linux -Dvendorprefix=/usr -Dsiteprefix=/usr -Duseshrplib -Dusethreads -Duseithreads -Duselargefiles -Dd_dosuid -Dd_semctl_semun -Di_db -Ui_ndbm -Di_gdbm -Di_shadow -Di_syslog -Dman3ext=3pm -Duseperlio -Dinstallusrbinperl=n -Ubincompat5005 -Uversiononly -Dpager=/usr/bin/less -isr -Dd_gethostent_r_proto -Ud_endhostent_r_proto -Ud_sethostent_r_proto -Ud_endprotoent_r_proto -Ud_setprotoent_r_proto -Ud_endservent_r_proto -Ud_setservent_r_proto -Dinc_version_list=5.8.7 5.8.6 5.8.5 -Dscriptdir=/usr/bin'
    hint=recommended, useposix=true, d_sigaction=define
    usethreads=define use5005threads=undef useithreads=define usemultiplicity=define
    useperlio=define d_sfio=undef uselargefiles=define usesocks=undef
    use64bitint=undef use64bitall=undef uselongdouble=undef
    usemymalloc=n, bincompat5005=undef
  Compiler:
    cc='gcc', ccflags ='-D_REENTRANT -D_GNU_SOURCE -fno-strict-aliasing -pipe -Wdeclaration-after-statement -I/usr/local/include -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64 -I/usr/include/gdbm',
    optimize='-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -m32 -march=i386 -mtune=generic -fasynchronous-unwind-tables',
    cppflags='-D_REENTRANT -D_GNU_SOURCE -fno-strict-aliasing -pipe -Wdeclaration-after-statement -I/usr/local/include -I/usr/include/gdbm'
    ccversion='', gccversion='4.1.1 20060928 (Red Hat 4.1.1-28)', gccosandvers=''
    intsize=4, longsize=4, ptrsize=4, doublesize=8, byteorder=1234
    d_longlong=define, longlongsize=8, d_longdbl=define, longdblsize=12
    ivtype='long', ivsize=4, nvtype='double', nvsize=8, Off_t='off_t', lseeksize=8
    alignbytes=4, prototype=define
  Linker and Libraries:
    ld='gcc', ldflags =' -L/usr/local/lib'
    libpth=/usr/local/lib /lib /usr/lib
    libs=-lresolv -lnsl -lgdbm -ldb -ldl -lm -lcrypt -lutil -lpthread -lc
    perllibs=-lresolv -lnsl -ldl -lm -lcrypt -lutil -lpthread -lc
    libc=/lib/libc-2.5.so, so=so, useshrplib=true, libperl=libperl.so
    gnulibc_version='2.5'
  Dynamic Linking:
    dlsrc=dl_dlopen.xs, dlext=so, d_dlsymun=undef, ccdlflags='-Wl,-E -Wl,-rpath,/usr/lib/perl5/5.8.8/i386-linux-thread-multi/CORE'
    cccdlflags='-fPIC', lddlflags='-shared -O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -m32 -march=i386 -mtune=generic -fasynchronous-unwind-tables -L/usr/local/lib'



=head1 AUTHOR

Piotr Kodzis
