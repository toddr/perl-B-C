#! /usr/bin/env perl
# B::CC limitations with last/next/continue. See README.
# See also issue36.t
use Test::More tests => 4;
use strict;
BEGIN {
    unshift @INC, 't';
    require "test.pl";
}
my $base = "ccode_last";

# XXX Bogus. This is not the real 'last' failure as described in the README
my $script1 = <<'EOF';
# last outside loop
label: {
  print "ok\n";
  last label;
  print " not ok\n";
}
EOF

use B::CC;
# 5.12 still fails test 1
ctestok(1, "CC", $base, $script1
       ($B::CC::VERSION < 1.08 or $] =~ /5\.01[12]/ ? "last outside loop fixed with B-CC-1.08" : undef));

my $script2 = <<'EOF';
# Label not found at compile-time for last
lab1: {
  print "ok\n";
  my $label = "lab1";
  last $label;
  print " not ok\n";
}
EOF
ctestok(2, "CC", $base, $script2,
           "B::CC Label not found at compile-time for last");

# XXX TODO Bogus or already fixed by Heinz Knutzen for issue 36
my $script3 = <<'EOF';
# last for non-loop block
{
  print "ok";
  last;
  print " not ok\n";
}
EOF
ctestok(3, "CC", $base, $script3
          $B::CC::VERSION < 1.08 ? "last for non-loop block fixed with B-CC-1.08" : undef);

my $script4 = <<'EOF';
# issue 55 segfault for non local loop exit
LOOP:
{
    my $sub = sub { last LOOP; };
    $sub->();
}
print "ok";
EOF
# TODO
ctestok(4, "CC", $base, $script4,
           $B::CC::VERSION < 1.11 ? "B::CC issue 55 non-local exit with last => segv" : undef);
