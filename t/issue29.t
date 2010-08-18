#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=29
use Test::More tests => 2;
use strict;

my $name = "ccode29i";
my $script = <<'EOF';
use open qw(:std :utf8);
$_ = <>;
print unpack('U*', $_), " ";
print $_ if /\w/;
EOF

# :std only since perl-5.8.0 b178108dc
$script =~ s/:std // if $] < 5.008;
open F, ">", "$name.pl";
print F $script;
close F;

$ENV{LC_ALL} = 'C.UTF-8';
my $expected = "24610 ö";
my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
system "$runperl -Mblib blib/script/perlcc -o $name $name.pl";
unless (-e $name or -e "$name.exe") {
  print "ok 1 #skip perlcc failed. Try -Bdynamic or -Bstatic or fix your ldopts.\n";
  print "ok 2 #skip\n";
  exit;
}
my $runexe = $^O eq 'MSWin32' ? "$name.exe" : "./$name";
my $result = `echo "ö" | $runexe`;
$result =~ s/\n$//;
TODO: {
  local $TODO = "B::C issue 29";
  ok($result eq $expected, "'$result' ne '$expected'");
}

system "$runperl -Mblib blib/script/perlcc -B -o $name.plc $name.pl";
unless (-e $name or -e "$name.exe") {
  print "ok 2 #skip perlcc failed. Try -Bdynamic or -Bstatic or fix your ldopts.\n";
  exit;
}
$runexe = "$runperl -Mblib -MByteloader $name.plc";
$result = `echo "ö" | $runexe`;
$result =~ s/\n$//;
ok($result eq $expected, "#Bytecode issue 29: '$result' eq '$expected'");

END {
  #unlink($name, "$name.plc", "$name.pl", "$name.exe");
}
