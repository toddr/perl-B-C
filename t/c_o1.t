#! /usr/bin/env perl
# better use testc.sh -O1 for debugging
BEGIN {
  if ($ENV{PERL_CORE}){
    chdir('t') if -d 't';
    @INC = ('.', '../lib');
  } else {
    unshift @INC, 't';
  }
  require 'test.pl'; # for run_perl()
}
use strict;
my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
my $ITHREADS  = ($Config{useithreads});

prepare_c_tests();

my @todo  = todo_tests_default("c_o1");
my @skip = (15) if $] == 5.010000 and $ITHREADS and !$DEBUGGING; # hanging

run_c_tests("C,-O1", \@todo, \@skip);
