package Plugins::utils_node::cisco_inventory;

use vars qw($VERSION);

$VERSION = 0.1;

use strict;          

use Configuration;
use Constants;
use DB;
use URLRewriter;
use MyException qw(:try);
use Common;
use Net::SNMP qw(:snmp);
use Entity;
use Number::Format qw(:subs);

$Number::Format::DECIMAL_FILL = 1;

my $TAB = {};
my $URL_PARAMS;

sub available
{
    return $_[0] =~ /^1\.3\.6\.1\.4\.1\.9/ ? 'cisco inventory' : 0;
}

my $_cfDevice =
{
    2 => 'cfdSize',
    7 => 'cfdName',
    8 => 'cfdDescr',
    10 => 'cfdCard',
    13 => 'cfdRemovable',
};

my $_cfdRemovable =
{
    1 => 'true',
    2 => 'false',
};

my $_cfPartition =
{
    4 => 'cfpSize',
    5 => 'cfpFreeSpace',
    6 => 'cfpFileCount',
    8 => 'cfpStatus',
    10 => 'cfpName',
};

my $_cfpStatus =
{
    1 => 'readOnly',
    2 => 'runFromFlash',
    3 => 'readWrite',
};

my $_cfFiles =
{
    2 => 'cffSize',
    3 => 'cffChecksum',
    4 => 'cffStatus',
    5 => 'cffName',
    6 => 'cffType',
    7 => 'cffDate',
};

my $_cffStatus =
{
    1 => 'deleted',
    2 => 'invalidChecksum',
    3 => 'valid',
};

my $_cffType =
{
    1 => 'unknown',
    2 => 'config',
    3 => 'image',
    4 => 'directory',
    5 => 'crashinfo',
};

my $_cModulesOld =
{
    2 => 'cmType',
    3 => 'cmDescr',
    4 => 'cmSerial',
    5 => 'cmHwVersion',
    6 => 'cmSwVersion',
    7 => 'cmSlotNumber',
    8 => 'cmContainedByIndex',
    9 => 'cmOperStatus',
    10 => 'cmSlots',
};

my $_cmOperStatus =
{
    1 => 'not-specified',
    2 => 'up',
    3 => 'down',
    4 => 'standby',
};

my $_cmType = 
{
    1 => "unknown",
    2 => "csc1",
    3 => "csc2",
    4 => "csc3",
    5 => "csc4",
    6 => "rp",
    7 => "cpu-igs",
    8 => "cpu-2500",
    9 => "cpu-3000",
    10 => "cpu-3100",
    11 => "cpu-accessPro",
    12 => "cpu-4000",
    13 => "cpu-4000m",
    14 => "cpu-4500",
    15 => "rsp1",
    16 => "rsp2",
    17 => "cpu-4500m",
    18 => "cpu-1003",
    19 => "cpu-4700",
    20 => "csc-m",
    21 => "csc-mt",
    22 => "csc-mc",
    23 => "csc-mcplus",
    24 => "csc-envm",
    25 => "chassisInterface",
    26 => "cpu-4700S",
    27 => "cpu-7200-npe100",
    28 => "rsp7000",
    29 => "chassisInterface7000",
    30 => "rsp4",
    31 => "cpu-3600",
    32 => "cpu-as5200",
    33 => "c7200-io1fe",
    34 => "cpu-4700m",
    35 => "cpu-1600",
    36 => "c7200-io",
    37 => "cpu-1503",
    38 => "cpu-1502",
    39 => "cpu-as5300",
    40 => "csc-16",
    41 => "csc-p",
    50 => "csc-a",
    51 => "csc-e1",
    52 => "csc-e2",
    53 => "csc-y",
    54 => "csc-s",
    55 => "csc-t",
    80 => "csc-r",
    81 => "csc-r16",
    82 => "csc-r16m",
    83 => "csc-1r",
    84 => "csc-2r",
    56 => "sci4s",
    57 => "sci2s2t",
    58 => "sci4t",
    59 => "mci1t",
    60 => "mci2t",
    61 => "mci1s",
    62 => "mci1s1t",
    63 => "mci2s",
    64 => "mci1e",
    65 => "mci1e1t",
    66 => "mci1e2t",
    67 => "mci1e1s",
    68 => "mci1e1s1t",
    69 => "mci1e2s",
    70 => "mci2e",
    71 => "mci2e1t",
    72 => "mci2e2t",
    73 => "mci2e1s",
    74 => "mci2e1s1t",
    75 => "mci2e2s",
    100 => "csc-cctl1",
    101 => "csc-cctl2",
    110 => "csc-mec2",
    111 => "csc-mec4",
    112 => "csc-mec6",
    113 => "csc-fci",
    114 => "csc-fcit",
    115 => "csc-hsci",
    116 => "csc-ctr",
    121 => "cpu-7200-npe150",
    122 => "cpu-7200-npe200",
    123 => "cpu-wsx5302",
    124 => "gsr-rp",
    126 => "cpu-3810",
    127 => "cpu-2600",
    128 => "cpu-rpm",
    129 => "cpu-ubr904",
    130 => "cpu-6200-mpc",
    131 => "cpu-1700",
    132 => "cpu-7200-npe300",
    133 => "cpu-1400",
    134 => "cpu-800",
    135 => "cpu-psm-1gbps",
    137 => "cpu-7200-npe175",
    138 => "cpu-7200-npe225",
    140 => "cpu-1417",
    141 => "cpu-psm1-1oc12",
    142 => "cpu-optical-regenerator",
    143 => "cpu-ubr924",
    144 => "cpu-7120",
    145 => "cpu-7140",
    146 => "cpu-psm1-2t3e3",
    147 => "cpu-psm1-4oc3",
    150 => "sp",
    151 => "eip",
    152 => "fip",
    153 => "hip",
    154 => "sip",
    155 => "trip",
    156 => "fsip",
    157 => "aip",
    158 => "mip",
    159 => "ssp",
    160 => "cip",
    161 => "srs-fip",
    162 => "srs-trip",
    163 => "feip",
    164 => "vip",
    165 => "vip2",
    166 => "ssip",
    167 => "smip",
    168 => "posip",
    169 => "feip-tx",
    170 => "feip-fx",
    178 => "cbrt1",
    179 => "cbr120e1",
    180 => "cbr75e",
    181 => "vip2-50",
    182 => "feip2",
    183 => "acip",
    184 => "mc11",
    185 => "mc12a",
    186 => "io1fe-tx-isl",
    187 => "geip",
    188 => "vip4",
    189 => "mc14a",
    190 => "mc16a",
    191 => "mc11a",
    192 => "cip2",
    200 => "npm-4000-fddi-sas",
    201 => "npm-4000-fddi-das",
    202 => "npm-4000-1e",
    203 => "npm-4000-1r",
    204 => "npm-4000-2s",
    205 => "npm-4000-2e1",
    206 => "npm-4000-2e",
    207 => "npm-4000-2r1",
    208 => "npm-4000-2r",
    209 => "npm-4000-4t",
    210 => "npm-4000-4b",
    211 => "npm-4000-8b",
    212 => "npm-4000-ct1",
    213 => "npm-4000-ce1",
    214 => "npm-4000-1a",
    215 => "npm-4000-6e-pci",
    217 => "npm-4000-1fe",
    218 => "npm-4000-1hssi",
    219 => "npm-4000-2e-pci",
    230 => "pa-1fe",
    231 => "pa-8e",
    232 => "pa-4e",
    233 => "pa-5e",
    234 => "pa-4t",
    235 => "pa-4r",
    236 => "pa-fddi",
    237 => "sa-encryption",
    238 => "pa-ah1t",
    239 => "pa-ah2t",
    241 => "pa-a8t-v35",
    242 => "pa-1fe-tx-isl",
    243 => "pa-1fe-fx-isl",
    244 => "pa-1fe-tx-nisl",
    245 => "sa-compression",
    246 => "pa-atm-lite-1",
    247 => "pa-ct3",
    248 => "pa-oc3sm-mux-cbrt1",
    249 => "pa-oc3sm-mux-cbr120e1",
    254 => "pa-ds3-mux-cbrt1",
    255 => "pa-e3-mux-cbr120e1",
    257 => "pa-8b-st",
    258 => "pa-4b-u",
    259 => "pa-fddi-fd",
    260 => "pm-cpm-1e2w",
    261 => "pm-cpm-2e2w",
    262 => "pm-cpm-1e1r2w",
    263 => "pm-ct1-csu",
    264 => "pm-2ct1-csu",
    265 => "pm-ct1-dsx1",
    266 => "pm-2ct1-dsx1",
    267 => "pm-ce1-balanced",
    268 => "pm-2ce1-balanced",
    269 => "pm-ce1-unbalanced",
    270 => "pm-2ce1-unbalanced",
    271 => "pm-4b-u",
    272 => "pm-4b-st",
    273 => "pm-8b-u",
    274 => "pm-8b-st",
    275 => "pm-4as",
    276 => "pm-8as",
    277 => "pm-4e",
    278 => "pm-1e",
    280 => "pm-m4t",
    281 => "pm-16a",
    282 => "pm-32a",
    283 => "pm-c3600-1fe-tx",
    284 => "pm-c3600-compression",
    285 => "pm-dmodem",
    286 => "pm-8admodem",
    287 => "pm-16admodem",
    288 => "pm-c3600-1fe-fx",
    289 => "pm-1fe-2t1-csu",
    290 => "as5200-carrier",
    291 => "as5200-2ct1",
    292 => "as5200-2ce1",
    293 => "as5200-dtd-carrier",
    310 => "pm-as5xxx-12m",
    311 => "pm-as5xxx-12m-56k",
    312 => "pm-as5xxx-12m-v110",
    330 => "wm-c2500-5in1",
    331 => "wm-c2500-t1-csudsu",
    332 => "wm-c2500-sw56-2wire-csudsu",
    333 => "wm-c2500-sw56-4wire-csudsu",
    334 => "wm-c2500-bri",
    335 => "wm-c2500-bri-nt1",
    360 => "wic-serial-1t",
    361 => "wic-serial-2t",
    363 => "wic-csu-dsu-4",
    364 => "wic-s-t-3420",
    365 => "wic-s-t-2186",
    366 => "wic-u-3420",
    367 => "wic-u-2091",
    368 => "wic-u-2091-2081",
    369 => "wic-s-t-2186-leased",
    370 => "wic-t1-csudsu",
    371 => "wic-serial-2as",
    372 => "aim-compression",
    373 => "c3660-2fe-tx",
    374 => "pm-oc3mm",
    375 => "pm-oc3mm-vpd",
    376 => "pm-oc3smi-vpd",
    377 => "pm-oc3sml-vpd",
    378 => "pm-oc3sml",
    379 => "pm-oc3smi",
    389 => "c36xx-1fe-tx",
    400 => "pa-jt2",
    401 => "pa-posdw",
    402 => "pa-4me1-bal",
    403 => "pa-2ce1-balanced",
    404 => "pa-2ct1",
    405 => "pa-1vg",
    406 => "pa-atmdx-ds3",
    407 => "pa-atmdx-e3",
    408 => "pa-atmdx-sml-oc3",
    409 => "pa-atmdx-smi-oc3",
    410 => "pa-atmdx-mm-oc3",
    414 => "pa-a8t-x21",
    415 => "pa-a8t-rs232",
    416 => "pa-4me1-unbal",
    417 => "pa-4r-fdx",
    418 => "pa-1e3",
    419 => "pa-2e3",
    420 => "pa-1t3",
    421 => "pa-2t3",
    422 => "pa-2ce1-unbalanced",
    423 => "pa-14e-switch",
    424 => "pa-1fe-fx-nisl",
    425 => "pa-esc-channel",
    426 => "pa-par-channel",
    427 => "pa-ge",
    428 => "pa-4ct1-csu",
    429 => "pa-8ct1-csu",
    430 => "c3800-vdm",
    431 => "c3800-vdm-dc-2t1e1",
    432 => "c3800-vdm-dc-1t1e1-enet",
    433 => "pa-2feisl-tx",
    434 => "pa-2feisl-fx",
    435 => "mc3810-dcm",
    436 => "mc3810-mfm-e1balanced-bri",
    437 => "mc3810-mfm-e1unbalanced-bri",
    438 => "mc3810-mfm-e1-unbalanced",
    439 => "mc3810-mfm-dsx1-bri",
    440 => "mc3810-mfm-dsx1-csu",
    441 => "mc3810-vcm",
    442 => "mc3810-avm",
    443 => "mc3810-avm-fxs",
    444 => "mc3810-avm-fxo",
    445 => "mc3810-avm-em",
    446 => "mc3810-vcm3",
    447 => "mc3810-bvm",
    448 => "mc3810-avm-fxo-uk",
    449 => "mc3810-avm-fxo-ger",
    450 => "mc3810-hcm2",
    451 => "mc3810-hcm6",
    452 => "mc3810-avm-fxo-pr3",
    453 => "mc3810-avm-fxo-pr2",
    461 => "pm-dtd-6m",
    462 => "pm-dtd-12m",
    480 => "as5300-4ct1",
    481 => "as5300-4ce1",
    482 => "as5300-carrier",
    484 => "as5300-dtd-carrier",
    485 => "as5300-8ct1-4t",
    486 => "as5300-8ce1-4t",
    487 => "as5300-4ct1-4t",
    488 => "as5300-4ce1-4t",
    489 => "as5300-amazon2-carrier",
    500 => "vic-em",
    501 => "vic-fxo",
    502 => "vic-fxs",
    503 => "vpm-2v",
    504 => "vpm-4v",
    505 => "dsp-vfc30",
    507 => "dspm-c542",
    508 => "vic-2fxo-eu",
    509 => "vic-2fxo-m3",
    510 => "vic-2fxo-m4",
    511 => "vic-2fxo-m5",
    512 => "vic-2fxo-m6",
    513 => "vic-2fxo-m7",
    514 => "vic-2fxo-m8",
    515 => "vic-2st-2086",
    516 => "hdv",
    517 => "dspm-6c549",
    530 => "pos-qoc3-mm",
    531 => "pos-qoc3-sm",
    532 => "pos-oc12-mm",
    533 => "pos-oc12-sm",
    534 => "atm-oc12-mm",
    535 => "atm-oc12-sm",
    536 => "pos-oc48-mm-l",
    537 => "pos-oc48-sm-lr-fc",
    538 => "gsr-sfc",
    539 => "gsr-csc",
    540 => "gsr-csc4",
    541 => "gsr-csc8",
    542 => "gsr-sfc8",
    543 => "atm-qoc3-sm",
    544 => "atm-qoc3-mm",
    545 => "gsr-oc12chds3-mm",
    546 => "gsr-oc12chds3-sm",
    547 => "gsr-1ge",
    548 => "gsr-oc12chsts3-mm",
    549 => "gsr-oc12chsts3-sm",
    552 => "pos-oc48-sm-sr-fc",
    553 => "pos-qoc3-sm-l",
    560 => "pa-8ct1",
    561 => "pa-8ce1",
    562 => "pa-ce3",
    563 => "pa-4r-dtr",
    564 => "pa-possw-sm",
    565 => "pa-possw-mm",
    566 => "pa-possw-lr",
    567 => "pa-1t3-plus",
    568 => "pa-2t3-plus",
    569 => "pa-ima-t1",
    570 => "pa-ima-e1",
    571 => "pa-2ct1-csu",
    572 => "pa-2ce1",
    600 => "pm-1fe-1t1",
    601 => "pm-1fe-2t1",
    602 => "pm-1fe-1e1",
    603 => "pm-1fe-2e1",
    604 => "pm-1fe-1t1-csu",
    605 => "pm-atm25",
    606 => "pm-hssi",
    630 => "as5800-dsc",
    631 => "as5800-12t1",
    632 => "as5800-12e1",
    633 => "as5800-mica-hmm",
    634 => "as5800-t3",
    635 => "as5800-1fe-dsi",
    636 => "as5800-mica-dmm",
    637 => "as5800-vcc",
    638 => "as5800-dspm-6c549",
    639 => "as5800-dsp",
    650 => "slc-cap8",
    651 => "ntc-oc3si",
    652 => "ntc-oc3mm",
    653 => "ntc-stm1si",
    654 => "ntc-stm1mm",
    655 => "slc-dmt8",
    656 => "slc-dmt16",
    657 => "ntc-ds3",
    750 => "atmdx-rpm",
    802 => "pa-atm-oc12-mm",
    803 => "pa-atm-oc12-smi",
    804 => "pa-mct3",
    805 => "pa-mc2t3",
    806 => "pa-pos-oc12-mm",
    807 => "pa-pos-oc12-sm",
    808 => "srp-pa-oc12-mm",
    809 => "srp-pa-oc12-sm-ir",
    810 => "srp-pa-oc12-lr",
    850 => "ausm-8t1",
    851 => "ausm-8e1",
    852 => "cesm-8t1",
    853 => "cesm-8e1",
    854 => "frsm-8t1",
    855 => "frsm-8e1",
    856 => "frsm-4x21",
    857 => "frsm-2hssi",
    858 => "cesm-1t3",
    859 => "cesm-1e3",
    860 => "vism-8t1",
    861 => "vism-8e1",
    862 => "mgx-rpm",
    863 => "mgx-srm-3t3",
    900 => "wsx-2914",
    901 => "wsx-2922",
    902 => "wsx-2914-v",
    903 => "wsx-2922-v",
    904 => "wsx-2924-v",
    905 => "wsx-2951",
    906 => "wsx-2961",
    907 => "wsx-2971",
    908 => "wsx-2972",
    909 => "wsx-2931",
    950 => "lm-bnc-2t3",
    951 => "lm-bnc-2e3",
    952 => "lm-db15-4x21",
    953 => "lm-scsi2-2hssi",
    954 => "lm-rj48-8t1",
    955 => "lm-rj48-8t1-r",
    956 => "lm-rj48-8e1",
    957 => "lm-rj48-8e1-r",
    958 => "lm-smb-8e1",
    959 => "lm-smb-8e1-r",
    960 => "lm-psm-ui",
    961 => "lm-mmf-4oc3",
    962 => "lm-smfir-4oc3",
    963 => "lm-smflr-4oc3",
    964 => "lm-smfir-1oc12",
    965 => "lm-smflr-1oc12",
    966 => "lm-s3-ui",
    967 => "lm-1fe-tx",
    968 => "lm-1fe-fx",
    969 => "lm-1mmf-fddi",
    970 => "lm-1smf-fddi",
    971 => "lm-rj45-4e",
    1050 => "gsr-8fe-tx",
    1051 => "gsr-8fe-fx",
    1054 => "pos-qoc12-sm-lr",
    1055 => "pos-qoc12-mm-sr",
    1056 => "pos-oc48-sm-lr-sc",
    1057 => "pos-oc48-sm-sr-sc",
    1058 => "srp-oc12-sm-ir",
    1059 => "srp-oc12-sm-lr",
    1060 => "srp-oc12-mm",
    1061 => "pos-en-oc48-sr-sc",
    1062 => "pos-en-oc48-sr-fc",
    1063 => "pos-en-oc48-lr-sc",
    1064 => "pos-en-oc48-lr-fc",
    1065 => "pos-en-qoc12-sr",
    1066 => "pos-en-qoc12-ir",
    1067 => "copper-6ds3",
    1068 => "copper-12ds3",
    1100 => "aim-lc-4e1-compression",
    1150 => "io-2fe-tx-isl",
};

my $_ccTypeOld =
{
    0 => 'value',
};

my $_cctType =
{
    1 => 'unknown',
    2 => 'multibus',
    3 => 'agsplus',
    4 => 'igs',
    5 => 'c2000',
    6 => 'c3000',
    7 => 'c4000',
    8 => 'c7000',
    9 => 'cs500',
    10 => 'c7010',
    11 => 'c2500',
    12 => 'c4500',
    13 => 'c2102',
    14 => 'c2202',
    15 => 'c2501',
    16 => 'c2502',
    17 => 'c2503',
    18 => 'c2504',
    19 => 'c2505',
    20 => 'c2506',
    21 => 'c2507',
    22 => 'c2508',
    23 => 'c2509',
    24 => 'c2510',
    25 => 'c2511',
    26 => 'c2512',
    27 => 'c2513',
    28 => 'c2514',
    29 => 'c2515',
    140 => 'c7120-ae3',
    141 => 'c7120-smi3',
    142 => 'c7140-dualt3',
    143 => 'c7140-duale3',
    144 => 'c7140-dualat3',
    145 => 'c7140-dualae3',
    146 => 'c7140-dualmm3',
    150 => 'c12016',
    152 => 'c7140-octt1',
    153 => 'c7140-dualfe',
    154 => 'cat3548xl',
    155 => 'cat6006',
    156 => 'cat6009',
    157 => 'cat6506',
    158 => 'cat6509',
    160 => 'mc3810-v3',
    162 => 'c7507z',
    163 => 'c7513z',
    164 => 'c7507mx',
    165 => 'c7513mx',
    166 => 'ubr912-c',
    167 => 'ubr912-s',
    168 => 'ubr914',
    173 => 'cat4232-l3',
    174 => 'cOpticalRegeneratorDCPower',
    180 => 'cva122',
    181 => 'cva124',
    182 => 'as5850',
    185 => 'mgx8240',
    191 => 'ubr925',
    192 => 'ubr10012',
    194 => 'c12016-8r',
    195 => 'c2650',
    196 => 'c2651',
    210 => 'c675e',
    211 => 'c676',
    212 => 'c677',
    213 => 'c678',
    214 => 'c3661-ac',
    215 => 'c3661-dc',
    216 => 'c3662-ac',
    217 => 'c3662-dc',
    218 => 'c3662-ac-co',
    219 => 'c3662-dc-co',
    220 => 'ubr7111',
    222 => 'ubr7114',
    224 => 'c12010',
    225 => 'c8110',
    227 => 'ubr905',
    231 => 'c7150-dualfe',
    232 => 'c7150-octt1',
    233 => 'c7150-dualt3',
    236 => 'cvps1110',
    237 => 'ccontentengine',
    238 => 'ciad2420',
    239 => 'c677i',
    240 => 'c674',
    241 => 'cdpa7630',
    245 => 'cat2924-lre-xl',
    246 => 'cat2912-lre-xl',
    247 => 'cva122e',
    248 => 'cva124e',
    249 => 'curm',
    250 => 'curm2fe',
    251 => 'curm2fe2v',
    252 => 'c7401VXR',
    255 => 'cap340',
    256 => 'cap350',
    257 => 'cdpa7610',
    261 => 'c12416',
    262 => 'ws-c2948g-l3-dc',
    263 => 'ws-c4908g-l3-dc',
    264 => 'c12406',
    265 => 'pix-firewall506',
    266 => 'pix-firewall515',
    267 => 'pix-firewall520',
    268 => 'pix-firewall525',
    269 => 'pix-firewall535',
    270 => 'c12410',
    271 => 'c811',
    272 => 'c813',
    273 => 'c10720',
    274 => 'cMWR1900',
    275 => 'c4224',
    276 => 'cWSC6513',
    277 => 'c7603',
    278 => 'c7606',
    279 => 'c7401ASR',
    307 => 'cCe507av',
    308 => 'cCe560av',
    309 => 'cIe2105',
    313 => 'c7304',
    322 => 'cWSC6503',
    326 => 'ccontentengine2636',
    327 => 'ccontentengine-dw2636',
    332 => 'c6400-uac',
    334 => 'c2610XM',
    335 => 'c2611XM',
    336 => 'c2620XM',
    337 => 'c2621XM',
    338 => 'c2650XM',
    339 => 'c2651XM',
    400 => 'cat6k-sup720',
    404 => 'airbr-1300',
    410 => 'c878',
    411 => 'c871',
    413 => 'c2811',
    414 => 'c2821',
    415 => 'c2851',
    420 => 'cat3750g-16td',
    422 => 'cigesm',
    423 => 'c1841',
};

my $_ccVerOld = { 0 => 'value', };
my $_ccSerialOld = { 0 => 'value', };
my $_ccSlotsOld = { 0 => 'value', };

my $_ccNew = 
{
    1 => 'ccnSysType',
    2 => 'ccnBkplType',
    3 => 'ccnPs1Type',
    6 => 'ccnPs2Type',
    14 => 'ccnNumSlots',
    16 => 'ccnModel',
    19 => 'ccnSerialNumberString',
    20 => 'ccnPs2Type',
};

my $_ccnSysType =
{
    1 => 'other',
    3 => 'wsc1000',
    4 => 'wsc1001',
    5 => 'wsc1100',
    6 => 'wsc5000',
    7 => 'wsc2900',
    8 => 'wsc5500',
    9 => 'wsc5002',
    10 => 'wsc5505',
    11 => 'wsc1200',
    12 => 'wsc1400',
    13 => 'wsc2926',
    14 => 'wsc5509',
    15 => 'wsc6006',
    16 => 'wsc6009',
    17 => 'wsc4003',
    18 => 'wsc5500e',
    19 => 'wsc4912g',
    20 => 'wsc2948g',
    22 => 'wsc6509',
    23 => 'wsc6506',
    24 => 'wsc4006',
    25 => 'wsc6509NEB',
    26 => 'wsc2980g',
    27 => 'wsc6513',
    28 => 'wsc2980ga',
    30 => 'cisco7603',
    31 => 'cisco7606',
    32 => 'cisco7609',
    33 => 'wsc6503',
    34 => 'wsc6509NEBA',
    35 => 'wsc4507',
    36 => 'wsc4503',
    37 => 'wsc4506',
    38 => 'wsc65509',
    40 => 'cisco7613',
};

my $_ccnBkplType =
{
   1 => 'other',
   2 => 'fddi',
   3 => 'fddiEthernet',
   4 => 'giga',
   5 => 'giga3',
   6 => 'giga3E',
   7 => 'giga12',
   8 => 'giga16',
   9 => 'giga40',
};

my $_ccnPsType = 
{
    1 => 'other',
    2 => 'none',
    3 => 'w50',
    4 => 'w200',
    5 => 'w600',
    6 => 'w80',
    7 => 'w130',
    8 => 'wsc5008',
    9 => 'wsc5008a',
    10 => 'w175',
    11 => 'wsc5068',
    12 => 'wsc5508',
    13 => 'wsc5568',
    14 => 'wsc5508a',
    15 => 'w155',
    16 => 'w175pfc',
    17 => 'w175dc',
    18 => 'wsc5008b',
    19 => 'wsc5008c',
    20 => 'wsc5068b',
    21 => 'wscac1000',
    22 => 'wscac1300',
    23 => 'wscdc1000',
    24 => 'wscdc1360',
    25 => 'wsc4008',
    26 => 'wsc5518',
    27 => 'wsc5598',
    28 => 'w120',
    29 => 'externalPS',
    30 => 'wscac2500w',
    31 => 'wscdc2500w',
    32 => 'wsc4008dc',
    33 => 'wscac4000w',
    34 => 'wscdc4000w',
    35 => 'pwr950ac',
    36 => 'pwr950dc',
    37 => 'pwr1900ac',
    38 => 'pwr1900dc',
    39 => 'pwr1900ac6',
    42 => 'wsx4008ac650w',
    43 => 'wsx4008dc650w',
    44 => 'wscac3000w',
    46 => 'pwrc451000ac',
    47 => 'pwrc452800acv',
    48 => 'pwrc451300acv',
    49 => 'pwrc451400dcp',
    50 => 'wscdc3000w',
    51 => 'pwr1400ac',
};

my $_cModulesNew =
{
    2 => 'cmnType',
    3 => 'cmnSerialNumber',
    10 => 'cmnStatus',
    13 => 'cmnName',
    14 => 'cmnNumPorts',
    16 => 'cmnSubType', #karta matka
    17 => 'cmnModel',
    18 => 'cmnHwVersion',
    19 => 'cmnFwVersion',
    20 => 'cmnSwVersion',
    21 => 'cmnStandbyStatus',
    24 => 'cmnSubType2',
    25 => 'cmnSlotNum',
    26 => 'cmnSerialNumberString',
};

my $_cmnType =
{
    1 => 'other',
    2 => 'empty',
    3 => 'wsc1000',
    4 => 'wsc1001',
    5 => 'wsc1100',
    37 => 'wsx5020',
    38 => 'wsx5006',
    39 => 'wsx5005',
    40 => 'wsx5509',
    41 => 'wsx5506',
    42 => 'wsx5505',
    43 => 'wsx5156',
    44 => 'wsx5157',
    45 => 'wsx5158',
    46 => 'wsx5030',
    47 => 'wsx5114',
    48 => 'wsx5223',
    49 => 'wsx5224',
    50 => 'wsx5012',
    52 => 'wsx5302',
    53 => 'wsx5213a',
    54 => 'wsx5380',
    55 => 'wsx5201',
    56 => 'wsx5203',
    57 => 'wsx5530',
    61 => 'wsx5161',
    62 => 'wsx5162',
    65 => 'wsx5165',
    66 => 'wsx5166',
    67 => 'wsx5031',
    68 => 'wsx5410',
    69 => 'wsx5403',
    73 => 'wsx5201r',
    74 => 'wsx5225r',
    75 => 'wsx5014',
    76 => 'wsx5015',
    77 => 'wsx5236',
    78 => 'wsx5540',
    79 => 'wsx5234',
    210 => 'wsx6101oc12smf',
    211 => 'wsx6416gemt',
    212 => 'wsx6182pa',
    213 => 'osm2oc12AtmMM',
    214 => 'osm2oc12AtmSI',
    216 => 'osm4oc12PosMM',
    217 => 'osm4oc12PosSI',
    218 => 'osm4oc12PosSL',
    219 => 'wsx6ksup1a2ge',
    220 => 'wsx6302amsm',
    221 => 'wsx6416gbic',
    222 => 'wsx6224ammmt',
    223 => 'wsx6380nam',
    224 => 'wsx6248arj45',
    225 => 'wsx6248atel',
    226 => 'wsx6408agbic',
    229 => 'wsx6608t1',
    230 => 'wsx6608e1',
    231 => 'wsx6624fxs',
    233 => 'wsx6316getx',
    234 => 'wsf6kmsfc2',
    235 => 'wsx6324mmmt',
    236 => 'wsx6348rj45',
    237 => 'wsx6ksup22ge',
    238 => 'wsx6324sm',
    239 => 'wsx6516gbic',
    240 => 'osm4geWanGbic',
    241 => 'osm1oc48PosSS',
    242 => 'osm1oc48PosSI',
    243 => 'osm1oc48PosSL',
    244 => 'wsx6381ids',
    245 => 'wsc6500sfm',
    246 => 'osm16oc3PosMM',
    247 => 'osm16oc3PosSI',
    248 => 'osm16oc3PosSL',
    249 => 'osm2oc12PosMM',
    250 => 'osm2oc12PosSI',
    251 => 'osm2oc12PosSL',
    252 => 'wsx650210ge',
    253 => 'osm8oc3PosMM',
    254 => 'osm8oc3PosSI',
    255 => 'osm8oc3PosSL',
    258 => 'wsx6548rj45',
    259 => 'wsx6524mmmt',
    286 => 'osm4oc3PosSI',
    290 => 'wsSvcIdsm2',
    291 => 'wsSvcNam2',
    292 => 'wsSvcFwm1',
    293 => 'wsSvcCe1',
    294 => 'wsSvcSsl1',
    300 => 'wsx4012',
    301 => 'wsx4148rj',
    302 => 'wsx4232gbrj',
    303 => 'wsx4306gb',
    304 => 'wsx4418gb',
    305 => 'wsx44162gbtx',
    306 => 'wsx4912gb',
    307 => 'wsx2948gbrj',
    309 => 'wsx2948',
    310 => 'wsx4912',
    311 => 'wsx4424sxmt',
    312 => 'wsx4232rjxx',
    313 => 'wsx4148rj21',
    317 => 'wsx4124fxmt',
    318 => 'wsx4013',
    319 => 'wsx4232l3',
    320 => 'wsx4604gwy',
    321 => 'wsx44122Gbtx',
    322 => 'wsx2980',
    323 => 'wsx2980rj',
    324 => 'wsx2980gbrj',
    325 => 'wsx4019',
    326 => 'wsx4148rj45v',
    604 => 'osm1choc12T3SI',
    608 => 'osm2oc12PosMMPlus',
    609 => 'osm2oc12PosSIPlus',
    610 => 'osm16oc3PosSIPlus',
    611 => 'osm1oc48PosSSPlus',
    612 => 'osm1oc48PosSIPlus',
    613 => 'osm1oc48PosSLPlus',
    614 => 'osm4oc3PosSIPlus',
    616 => 'osm8oc3PosSIPlus',
    617 => 'osm4o',
};

my $_cmnStatus =
{
    1 => 'other',
    2 => 'ok',
    3 => 'minorFault',
    4 => 'majorFault',
};

my $_cmnSubType =
{
    1 => 'other',
    2 => 'empty',
    3 => 'wsf5510',
    4 => 'wsf5511',
    6 => 'wsx5304',
    7 => 'wsf5520',
    8 => 'wsf5521',
    9 => 'wsf5531',
    100 => 'wsf6020',
    101 => 'wsf6020a',
    102 => 'wsf6kpfc',
    103 => 'wsf6kpfc2',
    104 => 'wsf6kvpwr',
    105 => 'wsf6kdfc',
    106 => 'wsf6kpfc2a',
    107 => 'wsf6kdfca',
    200 => 'vsp300dfc',
    201 => 'wsf6kpfc3a',
    202 => 'wsf6kdfc3a',
};

my $_cmnStandbyStatus =
{
    1 => 'other',
    2 => 'active',
    3 => 'standby',
    4 => 'error',
};



our $OIDS =
{
    '1.3.6.1.4.1.9.9.10.1.1.2.1' => { name => 'FlashDevices', disp => $_cfDevice, dispf => { 'cfdRemovable' => $_cfdRemovable }, enabled => 'flash' },
    '1.3.6.1.4.1.9.9.10.1.1.4.1.1' => { name => 'FlashPartitions', disp => $_cfPartition , dispf => { 'cfpStatus' => $_cfpStatus }, enabled => 'flash' },
    '1.3.6.1.4.1.9.9.10.1.1.4.2.1.1' => { name => 'FlashFiles', disp => $_cfFiles, dispf => { 'cffStatus' => $_cffStatus , 'cffType' => $_cffType }, enabled => 'flash' }, 
    '1.3.6.1.4.1.9.3.6.1' => { name => 'ChassieTypeOld', disp => $_ccTypeOld, dispf => { 'value' => $_cctType}, enabled => 'chassie' },
    '1.3.6.1.4.1.9.3.6.2' => { name => 'ChassieVerOld', disp => $_ccVerOld, dispf => { }, enabled => 'chassie' },
    '1.3.6.1.4.1.9.3.6.3' => { name => 'ChassieSerialOld', disp => $_ccSerialOld, dispf => { }, enabled => 'chassie' },
    '1.3.6.1.4.1.9.3.6.12' => { name => 'ChassieSlotsOld', disp => $_ccSlotsOld, dispf => { }, enabled => 'chassie' },
    '1.3.6.1.4.1.9.3.6.11.1' => { name => 'ModulesOld', disp => $_cModulesOld, dispf => { 'cmType' => $_cmType, cmOperStatus => $_cmOperStatus}, enabled => 'modules' },
    '1.3.6.1.4.1.9.5.1.2' => { name => 'ChassieNew', disp => $_ccNew, dispf => { ccnSysType => $_ccnSysType, ccnBkplType => $_ccnBkplType, ccnPs1Type => $_ccnPsType, ccnPs2Type => $_ccnPsType, ccnPs3Type => $_ccnPsType, }, enabled => 'chassie' },
    '1.3.6.1.4.1.9.5.1.3.1.1' => { name => 'ModulesNew', disp => $_cModulesNew, dispf => { cmnType => $_cmnType, cmnStatus => $_cmnStatus, cmnSubType => $_cmnSubType, cmnStandbyStatus => $_cmnStandbyStatus, cmnSubType2 => $_cmnSubType }, enabled => 'modules' },
};

sub get
{
    $TAB = {};
    $URL_PARAMS = shift;

    my $what = {}; 

    if (defined $URL_PARAMS->{utilities_options})
    {
        @$what{ split(/\+/, $URL_PARAMS->{utilities_options}) } = split(/\+/, $URL_PARAMS->{utilities_options});
        $URL_PARAMS->{utilities_options} = $what;
    }
    
    my $rawdata = 0;
    if (defined $URL_PARAMS->{utilities_options} && defined $URL_PARAMS->{utilities_options}->{rawdata})
    {
        $rawdata = 1;
        delete $URL_PARAMS->{utilities_options}->{rawdata};
        delete $URL_PARAMS->{utilities_options}
            if ! keys %{$URL_PARAMS->{utilities_options}};
    }
    
    my $result = table_get();
    return $result
        if $result;

    mix_data();

    return $TAB
        if $rawdata;

    return table_render();
}


sub make_col_title
{
    my ($name) = @_;
    return sprintf(qq|<span class="g4">%s</span>|, $name);

}

sub mix_data
{
    my $h;

    # links ModulesOld and ModulesNew sections; mixed info stays in ModulesNew where keys are stlo numbers
    for my $i (keys %{$TAB->{ModulesOld}})
    {
        if ($TAB->{ModulesOld}->{$i}->{cmContainedByIndex})
        {
            $TAB->{SubModules}->
            { 
                $TAB->{ModulesOld}->
                { 
                    $TAB->{ModulesOld}->{$i}->{cmContainedByIndex} 
                }->{cmSlotNumber}
            }->{$i} = $TAB->{ModulesOld}->{$i};
        }
        else
        {
            $h = $TAB->{ModulesOld}->{$i}->{cmSlotNumber};
            for (keys %{$TAB->{ModulesOld}->{$i}})
            {
                $TAB->{ModulesNew}->{$h}->{$_} = $TAB->{ModulesOld}->{$i}->{$_};
            }
        }
    }

    # build ChassieNew section
    for ('ChassieSerialOld', 'ChassieVerOld', 'ChassieSlotsOld', 'ChassieTypeOld')
    {
        $TAB->{ChassieNew}->{$_} = $TAB->{$_}->{''}->{value}
            if defined $TAB->{$_};
    }
    if (defined $TAB->{ChassieNew}->{0})
    {
        for (keys %{ $TAB->{ChassieNew}->{0} })
        {
            $TAB->{ChassieNew}->{$_} = $TAB->{ChassieNew}->{0}->{$_};
        }
        delete $TAB->{ChassieNew}->{0};
    }

    # build FlashDevices section
    for (keys %{$TAB->{FlashDevices}})
    {
        $h = $TAB->{FlashDevices}->{$_}->{cfdCard};
        $h =~ s/^1\.3\.6\.1\.4\.1\.9\.3\.6\.11\.1\.1\.//g;
        $TAB->{fd}->{$h}->{$_} = $TAB->{FlashDevices}->{$_};
        $TAB->{FlashDevices}->{$_}->{cmSlotNumber} = $TAB->{ModulesOld}->{$h}->{cmSlotNumber};
    }

    # build FlashPartitions section
    for (keys %{$TAB->{FlashPartitions}})
    {
        $h = [split /\./, $_];
        $TAB->{fp}->{$h->[0]}->{$h->[1]} = $TAB->{FlashPartitions}->{$_};
    }

    # build FlashFiles section
    for (keys %{$TAB->{FlashFiles}})
    {
        $h = [split /\./, $_];
        $TAB->{ff}->{ $TAB->{fp}->{$h->[0]}->{$h->[1]}->{cfpName}  }->{$h->[2]} = $TAB->{FlashFiles}->{$_};
    }
}

sub table_render
{
    my $result = table_begin();
    $result->setAlign('left');
    $result->addRow(table_render_chassie())
        if ! defined $URL_PARAMS->{utilities_options} || defined $URL_PARAMS->{utilities_options}->{chassie};
    $result->addRow(table_render_modules())
        if ! defined $URL_PARAMS->{utilities_options} || defined $URL_PARAMS->{utilities_options}->{modules};
    $result->addRow(table_render_submodules())
        if ! defined $URL_PARAMS->{utilities_options} || defined $URL_PARAMS->{utilities_options}->{modules};
    $result->addRow(table_render_flash_devices())
        if ! defined $URL_PARAMS->{utilities_options} || defined $URL_PARAMS->{utilities_options}->{flash};
    $result->addRow(table_render_flash_partitions())
        if ! defined $URL_PARAMS->{utilities_options} || defined $URL_PARAMS->{utilities_options}->{flash};
    $result->addRow(table_render_flash_files())
        if ! defined $URL_PARAMS->{utilities_options} || defined $URL_PARAMS->{utilities_options}->{flash};

    return scalar $result;
}


sub table_render_chassie
{
    my @row;

    my $h = $TAB->{ChassieNew};
    my $table = table_begin("chassie", 7);
    $table->setAlign('left');

    if (! keys %$h)
    {
        $table->addRow("MIB not supported by device");
        return scalar $table;
    }

    $table->addRow
    (
        make_col_title("model"),
        make_col_title("backplane"),
        make_col_title("slots"),
        make_col_title("version"),
        make_col_title("serial"),
        make_col_title("power 1"),
        make_col_title("power 2"),
    );

    @row = ();

    push @row, defined $h->{ccnModel} ? $h->{ccnModel} : $h->{ChassieTypeOld};
    push @row, $h->{ccnBkplType} || 'n/a';
    push @row, defined $h->{ccnNumSlots} ? $h->{ccnNumSlots} : $h->{ChassieSlotsOld} == -1 ? '-' : $h->{ChassieSlotsOld};
    push @row, $h->{ChassieVerOld};
    push @row, (defined $h->{ccnSerialNumberString} ? $h->{ccnSerialNumberString} : $h->{ChassieSerialOld}) || 'n/a';
    push @row, $h->{ccnPs1Type} || 'n/a';
    push @row, $h->{ccnPs2Type} || 'n/a';

    $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
    $table->setCellAttr($table->getTableRows, $_, 'class="f"')
        for (1..7);

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return scalar $table;
}


sub table_render_submodules
{
    my @row;
    my $h;

    my $data = $TAB->{SubModules};
    my $datan = $TAB->{ModulesNew};

    my $table = table_begin("submodules", 9);
    $table->setAlign('left');

    if (! keys %$data)
    {
        $table->addRow("no submodules or MIB not supported by device");
        return scalar $table;
    }

    $table->addRow
    (
        make_col_title("contained by"),
        make_col_title("slot"),
        make_col_title("description"),
        make_col_title("model"),
        make_col_title("slots"),
        make_col_title("hw"),
        make_col_title("sw"),
        make_col_title("serial"),
        make_col_title("status"),
    );

    for my $sl ( sort { $a <=> $b } keys %$data )
    {

    for ( sort { $a <=> $b } keys %{$data->{$sl}} )
    {
        @row = ();
        $h = $data->{$sl}->{$_};

        push @row, sprintf(qq|slot %s: %s|, $sl, $datan->{$sl}->{cmDescr});
        push @row, $h->{cmSlotNumber};
        push @row, $h->{cmDescr};
        push @row, $h->{cmType};
        push @row, $h->{cmSlots} || '-';
        push @row, $h->{cmHwVersion}  || 'n/a';
        push @row, $h->{cmSwVersion} || 'n/a';
        push @row, $h->{cmSerial} || 'n/a';
        push @row, $h->{cmOperStatus};

        $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
        $table->setCellAttr($table->getTableRows, $_, 'class="f"')
            for (1..9);
    }
        $h = [ keys %{$data->{$sl}} ];
        $h = @$h;
        $table->setCellRowSpan($table->getTableRows-$h+1, 1, $h);
    }

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return scalar $table;
}

sub table_render_modules
{
    my @row;
    my $h;

    my $data = $TAB->{ModulesNew};

    my $table = table_begin("modules", 10);
    $table->setAlign('left');

    if (! keys %$data)
    {
        $table->addRow("MIB not supported by device");
        return scalar $table;
    }

    $table->addRow
    ( 
        make_col_title("slot"),
        make_col_title("ports"),
        make_col_title("description"),
        make_col_title("model"),
        make_col_title("slots"),
        make_col_title("hw"),
        make_col_title("fw"),
        make_col_title("sw"),
        make_col_title("serial"),
        make_col_title("status"),
    );


    for ( sort { $a <=> $b } keys %$data )
    {
        @row = ();
        $h = $data->{$_};

        push @row, $_ == -1 ? '-' : $_;
        push @row, $h->{cmnNumPorts};
        push @row, $h->{cmDescr};
        push @row, defined $h->{cmnModel} ? $h->{cmnModel} : defined $h->{cmnType} ? $h->{cmnType} : $h->{cmType};
        push @row, $h->{cmSlots} || 'n/a';
        push @row, (defined $h->{cmnHwVersion} ? $h->{cmnHwVersion} : $h->{cmHwVersion} ) || 'n/a';
        push @row, $h->{cmnFwVersion} || 'n/a';
        push @row, (defined $h->{cmnSwVersion} ? $h->{cmnSwVersion} : $h->{cmSwVersion}) || 'n/a';
        push @row, (defined $h->{cmnSerialNumberString} ? $h->{cmnSerialNumberString} : $h->{cmSerial}) || 'n/a';
        push @row, defined $h->{cmnStatus} ? ($h->{cmnStatus} . " (standby status: " . $h->{cmnStandbyStatus} . ")") : $h->{cmOperStatus};

        $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
        $table->setCellAttr($table->getTableRows, $_, 'class="f"')
            for (1..10);
    } 

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {   
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return scalar $table;
}

sub table_render_flash_devices
{
    my @row;
    my $h;

    my $data = $TAB->{fd};
    my $datan = $TAB->{ModulesOld};

    my $table = table_begin("flash devices", 5);
    $table->setAlign('left');

    if (! keys %$data)
    {
        $table->addRow("no flash devices or MIB not supported by device");
        return scalar $table;
    }

    $table->addRow
    (
        make_col_title("contained by"),
        make_col_title("name"),
        make_col_title("description"),
        make_col_title("size"),
        make_col_title("removable"),
    );

    for my $sl ( sort { $a <=> $b } keys %$data )
    {

    for ( sort { $a <=> $b } keys %{$data->{$sl}} )
    {
        @row = ();
        $h = $data->{$sl}->{$_};

        push @row, sprintf(qq|slot %s: %s|, $datan->{$sl}->{cmSlotNumber}, $datan->{$sl}->{cmDescr});
        push @row, $h->{cfdName};
        push @row, $h->{cfdDescr};
        push @row, $h->{cfdSize} ? sprintf(qq|%sB (%s)|, $h->{cfdSize}, format_bytes($h->{cfdSize})) : 'empty';
        push @row, $h->{cfdRemovable};

        $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
        $table->setCellAttr($table->getTableRows, $_, 'class="f"')
            for (1..5);
    }
        $h = [ keys %{$data->{$sl}} ];
        $h = @$h;
        $table->setCellRowSpan($table->getTableRows-$h+1, 1, $h);
    }

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return scalar $table;
}

sub table_render_flash_partitions
{
    my @row;
    my $h;

    my $data = $TAB->{fp};
    my $table = table_begin("flash partitions", 5);
    $table->setAlign('left');

    if (! keys %$data)
    {
        $table->addRow("no flash partitions or MIB not supported by device");
        return scalar $table;
    }

    $table->addRow
    (
        make_col_title("name"),
        make_col_title("files<br>count"),
        make_col_title("size"),
        make_col_title("free space"),
        make_col_title("status"),
    );

    for my $sl ( sort { $a <=> $b } keys %$data )
    {

    for ( sort { $a <=> $b } keys %{$data->{$sl}} )
    {
        @row = ();
        $h = $data->{$sl}->{$_};

        push @row, $h->{cfpName};
        push @row, $h->{cfpFileCount};
        push @row, $h->{cfpSize} ? sprintf(qq|%sB (%s)|, $h->{cfpSize}, format_bytes($h->{cfpSize})) : 'empty';
        push @row, $h->{cfpFreeSpace} ? sprintf(qq|%sB (%s)|, $h->{cfpFreeSpace}, format_bytes($h->{cfpFreeSpace})) : 'empty';
        push @row, $h->{cfpStatus};

        $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
        $table->setCellAttr($table->getTableRows, $_, 'class="f"')
            for (1..5);
    }
        $h = [ keys %{$data->{$sl}} ];
        $h = @$h;
        $table->setCellRowSpan($table->getTableRows-$h+1, 1, $h);
    }

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return scalar $table;
}

sub table_render_flash_files
{
    my @row;
    my $h;

    my $data = $TAB->{ff};
    my $table = table_begin("flash files", 6);
    $table->setAlign('left');

    if (! keys %$data)
    {
        $table->addRow("no flash files or MIB not supported by device");
        return scalar $table;
    }

    $table->addRow
    (
        make_col_title("partition"),
        make_col_title("name"),
        make_col_title("size"),
        make_col_title("checksum"),
        make_col_title("type"),
        make_col_title("status"),
    );

    for my $sl ( sort { $a cmp $b } keys %$data )
    {

    for ( sort { $data->{$sl}->{$a}->{cffName} <=>  $data->{$sl}->{$b}->{cffName} } keys %{$data->{$sl}} )
    {
        @row = ();
        $h = $data->{$sl}->{$_};

        push @row, $sl;
        push @row, $h->{cffName};
        push @row, sprintf(qq|%sB (%s)|, $h->{cffSize}, format_bytes($h->{cffSize}));
        push @row, $h->{cffChecksum};
        push @row, $h->{cffType};
        push @row, $h->{cffStatus};

        $table->addRow( map { "&nbsp;$_&nbsp;" } @row);
        $table->setCellAttr($table->getTableRows, $_, 'class="f"')
            for (1..6);
    }
        $h = [ keys %{$data->{$sl}} ];
        $h = @$h;
        $table->setCellRowSpan($table->getTableRows-$h+1, 1, $h);
    }

    my $color = 0;
    for my $i ( 3 .. $table->getTableRows)
    {
        $table->setRowClass($i, sprintf(qq|tr_%d|, $color));
        $color = ! $color;
    }

    return scalar $table;
}

sub table_get
{
    my $entity = Entity->new(DB->new(), $URL_PARAMS->{id_entity});

    return "unknown entity"
        unless $entity;

    log_audit($entity, sprintf(qq|plugin %s executed|, (split /::/, __PACKAGE__,2)[1]));

    my $ip = $entity->params('ip');
    return sprintf( qq|missing ip address in entity %s|, $entity->id_entity)
        unless $ip;

    my ($session, $error) = snmp_session($ip, $entity, 1);
    if (! $session || $error)
    {
        return "snmp error: $error";
    }

    my $result;

    for (keys %$OIDS)
    {
        if (defined $URL_PARAMS->{utilities_options})
        {
            next
                unless defined $URL_PARAMS->{utilities_options}->{ $OIDS->{$_}->{enabled} };
        }
       
    $result = $session->get_bulk_request(
        -callback       => [\&main_cb, {}, $_],
        -maxrepetitions => 10,
        -varbindlist    => [$_]
        );
    if (!defined($result)) 
    {
       return sprintf("ERROR 1: %s.\n", $session->error);
    }
    $session->snmp_dispatcher();
    }

    $session->close;

    return 0;
}

sub main_cb
{
    my ($session, $table, $main_oid) = @_;

    if (!defined($session->var_bind_list)) 
    {
        return sprintf("ERROR 2: %s\n", $session->error);
    }
    else 
    {
        my $next;

        for my $oid (oid_lex_sort(keys(%{$session->var_bind_list}))) 
        {
            if (! oid_base_match($main_oid, $oid)) 
            {
                $next = undef;
                last;
            }
            $next = $oid;
            $table->{$oid} = $session->var_bind_list->{$oid};
        }
#use Data::Dumper; warn Dumper($table);

        if (defined($next)) 
        {
            my $result = $session->get_bulk_request(
                -callback       => [\&main_cb, $table, $main_oid],
                -maxrepetitions => 10,
                -varbindlist    => [$next]
                );

            if (!defined($result)) 
            {
                return sprintf("ERROR3: %s\n", $session->error);
            }
        }
        else 
        {
            my $s;
            foreach my $oid (oid_lex_sort(keys(%{$table}))) 
            {
                $s = $oid;
                $s =~ s/^$main_oid\.//;
                $s = [ split /\./, $s, 2 ];
#$TAB->{$oid} = $table->{$oid};
                $TAB->{ $OIDS->{$main_oid}->{name} }->{ $s->[1] }->{ $OIDS->{$main_oid}->{disp}->{ $s->[0] } } = 
                    defined $OIDS->{$main_oid}->{dispf}->{ $OIDS->{$main_oid}->{disp}->{ $s->[0] } }
                        ? defined $OIDS->{$main_oid}->{dispf}->{ $OIDS->{$main_oid}->{disp}->{ $s->[0] } }->{ $table->{$oid} }
                            ? $OIDS->{$main_oid}->{dispf}->{ $OIDS->{$main_oid}->{disp}->{ $s->[0] } }->{ $table->{$oid} }
                            : $table->{$oid}
                        : $table->{$oid};
            }
        }
    }
#use Data::Dumper; warn Dumper($TAB);
}

1;
