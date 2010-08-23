#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=38
# ||= doesn't work with B::CC
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

# we should return the value (2) not just 0/1 (false/true)
my $script = <<'EOF';
my $x = 2;
$x = $x || 3;
print "ok\n" if $x == 2;
EOF

use B::CC;
ctestok(1, "CC", "ccode38i", $script,
        $B::CC::VERSION < 1.08 ? "B::CC issue 38" : undef);
