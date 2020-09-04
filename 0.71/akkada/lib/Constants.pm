package Constants;

use vars qw($VERSION $AUTOLOAD);

$VERSION = 0.1;

use strict;
use Exporter;
use MyException qw(:try);

use vars qw( @ISA @EXPORT);

@ISA = qw ( Exporter );

@EXPORT = qw
(
    _ST_OK _ST_WARNING _ST_MINOR _ST_MAJOR _ST_DOWN _ST_UNREACHABLE _ST_NOSNMP _ST_UNKNOWN _ST_NOSTATUS _ST_INFO _ST_INIT _ST_BAD_CONF _ST_RECOVERED
    _LOG_ERROR _LOG_WARNING _LOG_INFO _LOG_DEBUG _LOG_INTERNAL _LOG_DBINTERNAL
    _DM_AUTO _DM_MIXED _DM_MANUAL _DM_NODISCOVER
    _DT_BAD _DT_RAW _DT_TEXT _DT_STAT
    _R_VIE _R_VIO _R_COM _R_CMO _R_ACK _R_MDY _R_CRE _R_DEL
    _VM_TREE _VM_TREE_LIGHT _VM_VIEWS _VM_VIEWS_LIGHT _VM_TREEVIEWS _VM_FIND _VM_TREEFIND _VM_FIND_LIGHT _VM_TREEFIND_LIGHT
    %VIEWS_HARD %VIEWS_ALLTREES %VIEWS_LIGHT %VIEWS_TREE %VIEWS_FIND %VIEWS_VIEWS %VIEWS_TREEFIND %VIEWS_ALLFIND %VIEWS_ALLVIEWS %VIEWS_TREE_PURE %VIEWS_SWITCH
);

#RIGHTS
use constant
{
    _R_VIE => 0,
    _R_VIO => 1,
    _R_COM => 2,
    _R_CMO => 3,
    _R_ACK => 4,
    _R_MDY => 5,
    _R_CRE => 6,
    _R_DEL => 7,
};

#DATA TYPES for akkada output format
use constant
{
    _DT_BAD => 'bad',
    _DT_RAW => 'raw',
    _DT_TEXT => 'text',
    _DT_STAT => 'stat',
};

#VIEW MODES
use constant _VM_TREE => 0;
use constant _VM_VIEWS => 1; #!
use constant _VM_TREEVIEWS => 2;
use constant _VM_FIND => 3; #!
use constant _VM_TREEFIND => 4;
use constant _VM_TREE_LIGHT => 10;
use constant _VM_VIEWS_LIGHT => 11;
use constant _VM_FIND_LIGHT => 13;
use constant _VM_TREEFIND_LIGHT => 14;
our %VIEWS_SWITCH =
(
    0  => 10, # _VM_TREE           => _VM_TREE_LIGHT
    10 => 0,  # _VM_TREE_LIGHT     => _VM_TREE
    1  => 11, # _VM_VIEWS          => _VM_VIEWS_LIGHT
    2  => 11, # _VM_TREEVIEWS      => _VM_VIEWS_LIGHT
    11 => 2,  # _VM_VIEWS_LIGHT    => _VM_TREEVIEWS
    3  => 13, # _VM_FIND           => _VM_FIND_LIGHT
    13 => 3,  # _VM_FIND_LIGHT     => _VM_FIND
    4  => 14, # _VM_TREEFIND       => _VM_TREEFIND_LIGHT
    14 => 4,  # _VM_TREEFIND_LIGHT => _VM_TREEFIND
    
);
our %VIEWS_ALLTREES =
(
    0 => 1,  #_VM_TREE
    2 => 1,  #_VM_TREEVIEWS
    4 => 1,  #_VM_TREEFIND
);
our %VIEWS_HARD =
(
    0 => 1,  #_VM_TREE
    1 => 1,  #_VM_VIEWS
    2 => 1,  #_VM_TREEVIEWS
    3 => 1,  #_VM_FIND
    4 => 1,  #_VM_TREEFIND
);
our %VIEWS_LIGHT =
(
    10 => 1, #_VM_TREE_LIGHT
    11 => 1, #_VM_VIEWS_LIGHT
    13 => 1, #_VM_FIND_LIGHT
    14 => 1, #_VM_TREEFIND_LIGHT
);
our %VIEWS_TREE_PURE =
(
    0 => 1,  #_VM_TREE
    10 => 1, #_VM_TREE_LIGHT
);
our %VIEWS_TREE =
(
    0 => 1,  #_VM_TREE
    2 => 1,  #_VM_TREEVIEWS
    10 => 1, #_VM_TREE_LIGHT
);
our %VIEWS_VIEWS =
(
    1 => 1,  #_VM_VIEWS
    11 => 1, #_VM_VIEWS_LIGHT
);
our %VIEWS_ALLVIEWS =
(
    1 => 1,  #_VM_VIEWS
    2 => 1,  #_VM_TREEVIEWS
    11 => 1, #_VM_VIEWS_LIGHT
);
our %VIEWS_FIND =
(
    3 => 1,  #_VM_FIND
    13 => 1, #_VM_FIND_LIGHT
);
our %VIEWS_TREEFIND =
(
    4 => 1,  #_VM_TREEFIND
    14 => 1, #_VM_TREEFIND_LIGHT
);
our %VIEWS_ALLFIND =
(
    3 => 1,  #_VM_FIND
    13 => 1, #_VM_FIND_LIGHT
    4 => 1,  #_VM_TREEFIND
    14 => 1, #_VM_TREEFIND_LIGHT
);

#DISCOVER MODES
use constant _DM_NODISCOVER => 0;
use constant _DM_AUTO => 1;
use constant _DM_MIXED => 2;
use constant _DM_MANUAL => 3;

#SEVERITIES
use constant _LOG_ERROR      => 0;
use constant _LOG_WARNING    => 1;
use constant _LOG_INFO       => 2;
use constant _LOG_DEBUG      => 3;
use constant _LOG_INTERNAL   => 4;
use constant _LOG_DBINTERNAL   => 5;

#STATUSES
use constant _ST_OK          => 0;
use constant _ST_WARNING     => 1;
use constant _ST_MINOR       => 2;
use constant _ST_MAJOR       => 3;
use constant _ST_DOWN        => 4;
use constant _ST_NOSNMP      => 5;
use constant _ST_UNREACHABLE => 6;
use constant _ST_UNKNOWN     => 64;
use constant _ST_RECOVERED   => 123;
use constant _ST_INIT         => 124;
use constant _ST_INFO        => 125;
use constant _ST_BAD_CONF    => 126;
use constant _ST_NOSTATUS    => 127;


sub AUTOLOAD
{
    $AUTOLOAD =~ s/.*:://g;
    throw EUnknownMethod($AUTOLOAD)
        unless $AUTOLOAD eq 'DESTROY';
}

1;

