#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=24
use strict;
use Test::More tests => 3;

my $name = "ccode24i";
my $script = <<'EOF';
my %H; dbmopen(%H,'ccode24i.db',0600); print q(ok);
EOF

open F, ">", "$name.pl";
print F $script;
close F;

my $result;
my $Mblib = $] < 5.007 ? "" : "-Mblib"; # 5.6 Bytecode not yet released
my $O = $] >= 5.013005 ? "-Wb=-fno-fold,-fno-warnings" : ""; # reduce bloat
my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $expected = `$runperl $name.pl`;

$result = `$runperl $Mblib blib/script/perlcc -r -B $name.pl`;
is($result, $expected, "Bytecode dbm fixed with r882, 1.30");
unlink("$name.db*");

$Mblib = $] < 5.007 ? "-Iblib/arch -Iblib/lib" : "-Mblib";
$result = `$runperl $Mblib blib/script/perlcc -r $O $name.pl`;
#TODO: {
#  local $TODO = "B::C issue 24 dbm";
is($result, $expected, "C dbm fixed with r879, 1.30");
#}
unlink("$name.db*", "a", "a.out");

$result = `$runperl $Mblib blib/script/perlcc -r -O $O $name.pl`;
TODO: {
  local $TODO = "B::CC issue 24 dbm";
  is($result, $expected, "CC dbm fixed with r881, but XSLoader missing");
}

END {
  unlink("$name*", "a", "a.out");
}
