#!./perl -w
# blead cannot run -T

BEGIN {
    if ($ENV{PERL_CORE}){
	chdir('t') if -d 't';
	@INC = ('.', '../lib');
    }
    require Config;
    if ($ENV{PERL_CORE} and ($Config::Config{'extensions'} !~ /\bB\b/) ){
        print "1..0 # Skip -- Perl configured without B module\n";
        exit 0;
    }
}

use Test::More tests => 1;

use_ok('B::Bblock', qw(find_leaders));

# Someone who understands what this module does, please fill this out.
