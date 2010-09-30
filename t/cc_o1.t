#! /usr/bin/env perl
# better use testcc.sh -O1 for debugging
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

my @todo  = todo_tests_default("cc_o1");
# skip core dump causing known limitations, like custom sort or runtime labels
my @skip = (21,24,31);

run_c_tests("CC,-O1", \@todo, \@skip);
