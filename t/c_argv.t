#! /usr/bin/env perl
use strict;
use Test::More tests => 3;
my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $Mblib = $] < 5.007 ? "-Iblib/arch -Iblib/lib" : "-Mblib";
$Mblib = '-Iblib\arch -Iblib\lib' if $] < 5.007 and $^O eq 'MSWin32';
my $pl = "ccode00.pl";
my $plc = $pl . "c";
my $d = <DATA>;

open F, ">", $pl;
print F $d;
close F;
is(`$runperl $Mblib blib/script/perlcc -r $pl ok 1`, "ok 1\n",
   "perlcc -r file args");

open F, ">", $pl;
my $d2 = $d;
$d2 =~ s/nok 1/nok 2/;
print F $d2;
close F;
is(`$runperl $Mblib blib/script/perlcc -O -r $pl ok 2`, "ok 2\n",
   "perlcc -O -r file args");

open F, ">", $pl;
my $d3 = $d;
$d3 =~ s/nok 1/nok 3/;
print F $d3;
close F;
is(`$runperl $Mblib blib/script/perlcc -B -r $pl ok 3`, "ok 3\n",
   "perlcc -B -r file args");

END {
  unlink("a", "a.out", $pl, $plc);
}

__DATA__
print @ARGV?join(" ",@ARGV):"nok 1 # empty \@ARGV","\n";
