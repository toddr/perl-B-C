#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=54
# pad_swipe error with package pmcs
use strict;
my $name = "ccode54p";
use Test::More tests => 1;

my $pkg = <<"EOF";
package $name;
sub test {
  \$abc='ok';
  print "\$abc\\n";
}
1;
EOF

open F, ">", "$name.pm";
print F $pkg;
close F;

my $expected = "ok";
my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
system "$runperl -Mblib -MO=Bytecode,-H,-o$name.pmc $name.pm";
unless (-e "$name.pmc") {
  print "not ok 1 #B::Bytecode failed.\n";
  exit;
}
my $runexe = "$runperl -Mblib -I. -M$name -e\"$name\::test\"";
my $result = `$runexe`;
$result =~ s/\n$//;

#TODO: {
  #local $TODO = "Bytecode issue 54 curpad";
ok($result eq $expected, "'$result' eq '$expected'");
#}

END {
  unlink($name, "$name.pmc", "$name.pm")
    if $result eq $expected;
}

