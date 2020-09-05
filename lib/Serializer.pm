package Serializer;

use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION );

$VERSION = 0.1;

require Exporter;

@ISA = qw ( Exporter );
@EXPORT = qw( freeze thaw);
%EXPORT_TAGS = ( default => [qw(freeze thaw)] );

use Data::Dumper;

sub freeze 
{
  local $Data::Dumper::Indent = 0;
  local $Data::Dumper::Purity = 1;
  local $Data::Dumper::Deepcopy = 1;
  return hex_en( Data::Dumper::Dumper( shift ) );
}

sub thaw 
{
  my $val = hex_de(shift);
  return eval($val =~ /^\{/ ? '+'.$val : $val);
}

sub hex_en 
{
  return join('',unpack 'H*',(shift));
}

sub hex_de 
{
  return (pack'H*',(shift));
}

1;
