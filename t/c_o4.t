#! /usr/bin/env perl
# better use testc.sh -O4 for debugging
BEGIN {
  unless (-d ".svn") {
    print "1..0 #SKIP Only if -d .svn\n";
    exit;
  }
  if ($ENV{PERL_CORE}){
    chdir('t') if -d 't';
    @INC = ('.', '../lib');
  } else {
    unshift @INC, 't';
  }
  require 'test.pl'; # for run_perl()
}
use strict;
#my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
my $ITHREADS  = ($Config{useithreads});

prepare_c_tests();

my @todo = (10,12,19,25,39);	#5.8.9
@todo    = (10,12,19,25,27,39) if !$ITHREADS;
@todo = (10,12,15,19,25,27)    if $] < 5.007;
@todo = (10,12,19,25,29,39,41) if $] >= 5.010;
push @todo, (32)   if $] >= 5.011003;

my @skip = (15,27); # sigsegv, out of memory

run_c_tests("C,-O4", \@todo, \@skip);
