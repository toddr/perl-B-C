#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=37
# ||= doesn't work with B::CC
use Test::More tests => 1;
use strict;
BEGIN {
  unshift @INC, 't';
  require "test.pl";
}

my $script = <<'EOF';
my $x;
$x ||= 1;
print "ok\n" if $x;
EOF

use B::CC;
ctestok(1, "CC", "ccode37i", $script,
        $B::CC::VERSION < 1.08 ? "B::CC issue 37" : undef);
