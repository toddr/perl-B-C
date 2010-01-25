#
# t/test.pl - most of Test::More functionality without the fuss


# NOTE:
#
# Increment ($x++) has a certain amount of cleverness for things like
#
#   $x = 'zz';
#   $x++; # $x eq 'aaa';
#
# stands more chance of breaking than just a simple
#
#   $x = $x + 1
#
# In this file, we use the latter "Baby Perl" approach, and increment
# will be worked over by t/op/inc.t

$Level = 1;
my $test = 1;
my $planned;
my $noplan;

$TODO = 0;
$NO_ENDING = 0;

sub plan {
    my $n;
    if (@_ == 1) {
	$n = shift;
	if ($n eq 'no_plan') {
	  undef $n;
	  $noplan = 1;
	}
    } else {
	my %plan = @_;
	$n = $plan{tests};
    }
    print STDOUT "1..$n\n" unless $noplan;
    $planned = $n;
}

END {
    my $ran = $test - 1;
    if (!$NO_ENDING) {
	if (defined $planned && $planned != $ran) {
	    print STDERR
		"# Looks like you planned $planned tests but ran $ran.\n";
	} elsif ($noplan) {
	    print "1..$ran\n";
	}
    }
}

# Use this instead of "print STDERR" when outputing failure diagnostic
# messages
sub _diag {
    return unless @_;
    my @mess = map { /^#/ ? "$_\n" : "# $_\n" }
               map { split /\n/ } @_;
    my $fh = $TODO ? *STDOUT : *STDERR;
    print $fh @mess;

}

sub diag {
    _diag(@_);
}

sub skip_all {
    if (@_) {
	print STDOUT "1..0 # Skipped: @_\n";
    } else {
	print STDOUT "1..0\n";
    }
    exit(0);
}

sub _ok {
    my ($pass, $where, $name, @mess) = @_;
    # Do not try to microoptimize by factoring out the "not ".
    # VMS will avenge.
    my $out;
    if ($name) {
        # escape out '#' or it will interfere with '# skip' and such
        $name =~ s/#/\\#/g;
	$out = $pass ? "ok $test - $name" : "not ok $test - $name";
    } else {
	$out = $pass ? "ok $test" : "not ok $test";
    }

    $out .= " # TODO $TODO" if $TODO;
    print STDOUT "$out\n";

    unless ($pass) {
	_diag "# Failed $where\n";
    }

    # Ensure that the message is properly escaped.
    _diag @mess;

    $test = $test + 1; # don't use ++

    return $pass;
}

sub _where {
    my @caller = caller($Level);
    return "at $caller[1] line $caller[2]";
}

# DON'T use this for matches. Use like() instead.
sub ok ($@) {
    my ($pass, $name, @mess) = @_;
    _ok($pass, _where(), $name, @mess);
}

sub _q {
    my $x = shift;
    return 'undef' unless defined $x;
    my $q = $x;
    $q =~ s/\\/\\\\/g;
    $q =~ s/'/\\'/g;
    return "'$q'";
}

sub _qq {
    my $x = shift;
    return defined $x ? '"' . display ($x) . '"' : 'undef';
};

# keys are the codes \n etc map to, values are 2 char strings such as \n
my %backslash_escape;
foreach my $x (split //, 'nrtfa\\\'"') {
    $backslash_escape{ord eval "\"\\$x\""} = "\\$x";
}
# A way to display scalars containing control characters and Unicode.
# Trying to avoid setting $_, or relying on local $_ to work.
sub display {
    my @result;
    foreach my $x (@_) {
        if (defined $x and not ref $x) {
            my $y = '';
            foreach my $c (unpack("U*", $x)) {
                if ($c > 255) {
                    $y .= sprintf "\\x{%x}", $c;
                } elsif ($backslash_escape{$c}) {
                    $y .= $backslash_escape{$c};
                } else {
                    my $z = chr $c; # Maybe we can get away with a literal...
                    $z = sprintf "\\%03o", $c if $z =~ /[[:^print:]]/;
                    $y .= $z;
                }
            }
            $x = $y;
        }
        return $x unless wantarray;
        push @result, $x;
    }
    return @result;
}

sub is ($$@) {
    my ($got, $expected, $name, @mess) = @_;

    my $pass;
    if( !defined $got || !defined $expected ) {
        # undef only matches undef
        $pass = !defined $got && !defined $expected;
    }
    else {
        $pass = $got eq $expected;
    }

    unless ($pass) {
	unshift(@mess, "#      got "._q($got)."\n",
		       "# expected "._q($expected)."\n");
    }
    _ok($pass, _where(), $name, @mess);
}

sub isnt ($$@) {
    my ($got, $isnt, $name, @mess) = @_;

    my $pass;
    if( !defined $got || !defined $isnt ) {
        # undef only matches undef
        $pass = defined $got || defined $isnt;
    }
    else {
        $pass = $got ne $isnt;
    }

    unless( $pass ) {
        unshift(@mess, "# it should not be "._q($got)."\n",
                       "# but it is.\n");
    }
    _ok($pass, _where(), $name, @mess);
}

sub cmp_ok ($$$@) {
    my($got, $type, $expected, $name, @mess) = @_;

    my $pass;
    {
        local $^W = 0;
        local($@,$!);   # don't interfere with $@
                        # eval() sometimes resets $!
        $pass = eval "\$got $type \$expected";
    }
    unless ($pass) {
        # It seems Irix long doubles can have 2147483648 and 2147483648
        # that stringify to the same thing but are acutally numerically
        # different. Display the numbers if $type isn't a string operator,
        # and the numbers are stringwise the same.
        # (all string operators have alphabetic names, so tr/a-z// is true)
        # This will also show numbers for some uneeded cases, but will
        # definately be helpful for things such as == and <= that fail
        if ($got eq $expected and $type !~ tr/a-z//) {
            unshift @mess, "# $got - $expected = " . ($got - $expected) . "\n";
        }
        unshift(@mess, "#      got "._q($got)."\n",
                       "# expected $type "._q($expected)."\n");
    }
    _ok($pass, _where(), $name, @mess);
}

# Check that $got is within $range of $expected
# if $range is 0, then check it's exact
# else if $expected is 0, then $range is an absolute value
# otherwise $range is a fractional error.
# Here $range must be numeric, >= 0
# Non numeric ranges might be a useful future extension. (eg %)
sub within ($$$@) {
    my ($got, $expected, $range, $name, @mess) = @_;
    my $pass;
    if (!defined $got or !defined $expected or !defined $range) {
        # This is a fail, but doesn't need extra diagnostics
    } elsif ($got !~ tr/0-9// or $expected !~ tr/0-9// or $range !~ tr/0-9//) {
        # This is a fail
        unshift @mess, "# got, expected and range must be numeric\n";
    } elsif ($range < 0) {
        # This is also a fail
        unshift @mess, "# range must not be negative\n";
    } elsif ($range == 0) {
        # Within 0 is ==
        $pass = $got == $expected;
    } elsif ($expected == 0) {
        # If expected is 0, treat range as absolute
        $pass = ($got <= $range) && ($got >= - $range);
    } else {
        my $diff = $got - $expected;
        $pass = abs ($diff / $expected) < $range;
    }
    unless ($pass) {
        if ($got eq $expected) {
            unshift @mess, "# $got - $expected = " . ($got - $expected) . "\n";
        }
	unshift@mess, "#      got "._q($got)."\n",
		      "# expected "._q($expected)." (within "._q($range).")\n";
    }
    _ok($pass, _where(), $name, @mess);
}

# Note: this isn't quite as fancy as Test::More::like().

sub like   ($$@) { like_yn (0,@_) }; # 0 for -
sub unlike ($$@) { like_yn (1,@_) }; # 1 for un-

sub like_yn ($$$@) {
    my ($flip, $got, $expected, $name, @mess) = @_;
    my $pass;
    $pass = $got =~ /$expected/ if !$flip;
    $pass = $got !~ /$expected/ if $flip;
    unless ($pass) {
	unshift(@mess, "#      got '$got'\n",
		$flip
		? "# expected !~ /$expected/\n" : "# expected /$expected/\n");
    }
    local $Level = $Level + 1;
    _ok($pass, _where(), $name, @mess);
}

sub pass {
    _ok(1, '', @_);
}

sub fail {
    _ok(0, _where(), @_);
}

sub curr_test {
    $test = shift if @_;
    return $test;
}

sub next_test {
  my $retval = $test;
  $test = $test + 1; # don't use ++
  $retval;
}

# Note: can't pass multipart messages since we try to
# be compatible with Test::More::skip().
sub skip {
    my $why = shift;
    my $n    = @_ ? shift : 1;
    for (1..$n) {
        print STDOUT "ok $test # skip: $why\n";
        $test = $test + 1;
    }
    local $^W = 0;
    last SKIP;
}

sub todo_skip {
    my $why = shift;
    my $n   = @_ ? shift : 1;

    for (1..$n) {
        print STDOUT "not ok $test # TODO & SKIP: $why\n";
        $test = $test + 1;
    }
    local $^W = 0;
    last TODO;
}

sub eq_array {
    my ($ra, $rb) = @_;
    return 0 unless $#$ra == $#$rb;
    for my $i (0..$#$ra) {
	next     if !defined $ra->[$i] && !defined $rb->[$i];
	return 0 if !defined $ra->[$i];
	return 0 if !defined $rb->[$i];
	return 0 unless $ra->[$i] eq $rb->[$i];
    }
    return 1;
}

sub eq_hash {
    my ($orig, $suspect) = @_;
    my $fail;
    while (my ($key, $value) = each %$suspect) {
        # Force a hash recompute if this perl's internals can cache the hash key.
        $key = "" . $key;
        if (exists $orig->{$key}) {
            if ($orig->{$key} ne $value) {
                print STDOUT "# key ", _qq($key), " was ", _qq($orig->{$key}),
                  " now ", _qq($value), "\n";
                $fail = 1;
            }
        } else {
            print STDOUT "# key ", _qq($key), " is ", _qq($value),
              ", not in original.\n";
            $fail = 1;
        }
    }
    foreach (keys %$orig) {
        # Force a hash recompute if this perl's internals can cache the hash key.
        $_ = "" . $_;
        next if (exists $suspect->{$_});
        print STDOUT "# key ", _qq($_), " was ", _qq($orig->{$_}), " now missing.\n";
        $fail = 1;
    }
    !$fail;
}

sub require_ok ($) {
    my ($require) = @_;
    eval <<REQUIRE_OK;
require $require;
REQUIRE_OK
    _ok(!$@, _where(), "require $require");
}

sub use_ok ($) {
    my ($use) = @_;
    eval <<USE_OK;
use $use;
USE_OK
    _ok(!$@, _where(), "use $use");
}

# runperl - Runs a separate perl interpreter.
# Arguments :
#   switches => [ command-line switches ]
#   nolib    => 1 # don't use -I../lib (included by default)
#   prog     => one-liner (avoid quotes)
#   progs    => [ multi-liner (avoid quotes) ]
#   progfile => perl script
#   stdin    => string to feed the stdin
#   stderr   => redirect stderr to stdout
#   args     => [ command-line arguments to the perl program ]
#   verbose  => print the command line

my $is_mswin    = $^O eq 'MSWin32';
my $is_netware  = $^O eq 'NetWare';
my $is_macos    = $^O eq 'MacOS';
my $is_vms      = $^O eq 'VMS';
my $is_cygwin   = $^O eq 'cygwin';

sub _quote_args {
    my ($runperl, $args) = @_;

    foreach (@$args) {
	# In VMS protect with doublequotes because otherwise
	# DCL will lowercase -- unless already doublequoted.
       $_ = q(").$_.q(") if $is_vms && !/^\"/ && length($_) > 0;
	$$runperl .= ' ' . $_;
    }
}

sub _create_runperl { # Create the string to qx in runperl().
    my %args = @_;
    my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
    #- this allows, for example, to set PERL_RUNPERL_DEBUG=/usr/bin/valgrind
    if ($ENV{PERL_RUNPERL_DEBUG}) {
	$runperl = "$ENV{PERL_RUNPERL_DEBUG} $runperl";
    }
    unless ($args{nolib}) {
	if ($is_macos) {
	    $runperl .= ' -I::lib';
	    # Use UNIX style error messages instead of MPW style.
	    $runperl .= ' -MMac::err=unix' if $args{stderr};
	}
	else {
	    $runperl .= ' "-I../lib"'; # doublequotes because of VMS
	}
    }
    if ($args{switches}) {
	local $Level = 2;
	die "test.pl:runperl(): 'switches' must be an ARRAYREF " . _where()
	    unless ref $args{switches} eq "ARRAY";
	_quote_args(\$runperl, $args{switches});
    }
    if (defined $args{prog}) {
	die "test.pl:runperl(): both 'prog' and 'progs' cannot be used " . _where()
	    if defined $args{progs};
        $args{progs} = [$args{prog}]
    }
    if (defined $args{progs}) {
	die "test.pl:runperl(): 'progs' must be an ARRAYREF " . _where()
	    unless ref $args{progs} eq "ARRAY";
        foreach my $prog (@{$args{progs}}) {
            if ($is_mswin || $is_netware || $is_vms) {
                $runperl .= qq ( -e "$prog" );
            }
            else {
                $runperl .= qq ( -e '$prog' );
            }
        }
    } elsif (defined $args{progfile}) {
	$runperl .= qq( "$args{progfile}");
    } else {
	# You probaby didn't want to be sucking in from the upstream stdin
	die "test.pl:runperl(): none of prog, progs, progfile, args, "
	    . " switches or stdin specified"
	    unless defined $args{args} or defined $args{switches}
		or defined $args{stdin};
    }
    if (defined $args{stdin}) {
	# so we don't try to put literal newlines and crs onto the
	# command line.
	$args{stdin} =~ s/\n/\\n/g;
	$args{stdin} =~ s/\r/\\r/g;

	if ($is_mswin || $is_netware || $is_vms) {
	    $runperl = qq{$^X -e "print qq(} .
		$args{stdin} . q{)" | } . $runperl;
	}
	elsif ($is_macos) {
	    # MacOS can only do two processes under MPW at once;
	    # the test itself is one; we can't do two more, so
	    # write to temp file
	    my $stdin = qq{$^X -e 'print qq(} . $args{stdin} . qq{)' > teststdin; };
	    if ($args{verbose}) {
		my $stdindisplay = $stdin;
		$stdindisplay =~ s/\n/\n\#/g;
		print STDERR "# $stdindisplay\n";
	    }
	    `$stdin`;
	    $runperl .= q{ < teststdin };
	}
	else {
	    $runperl = qq{$^X -e 'print qq(} .
		$args{stdin} . q{)' | } . $runperl;
	}
    }
    if (defined $args{args}) {
	_quote_args(\$runperl, $args{args});
    }
    $runperl .= ' 2>&1'          if  $args{stderr} && !$is_mswin && !$is_macos;
    $runperl .= " \xB3 Dev:Null" if !$args{stderr} && $is_macos;
    if ($args{verbose}) {
	my $runperldisplay = $runperl;
	$runperldisplay =~ s/\n/\n\#/g;
	print STDERR "# $runperldisplay\n";
    }
    return $runperl;
}

sub runperl {
    die "test.pl:runperl() does not take a hashref"
	if ref $_[0] and ref $_[0] eq 'HASH';
    my $runperl = &_create_runperl;
    my $result;
    # ${^TAINT} is invalid in perl5.00505
    my $tainted;
    eval '$tainted = ${^TAINT};' if $] >= 5.006;
    my %args = @_;
    exists $args{switches} && grep m/^-T$/, @{$args{switches}} and $tainted = $tainted + 1;

    if ($tainted) {
	# We will assume that if you're running under -T, you really mean to
	# run a fresh perl, so we'll brute force launder everything for you
	my $sep;

	eval "require Config; Config->import";
	if ($@) {
	    warn "test.pl had problems loading Config: $@";
	    $sep = ':';
	} else {
	    $sep = $Config{path_sep};
	}

	my @keys = grep {exists $ENV{$_}} qw(CDPATH IFS ENV BASH_ENV);
	local @ENV{@keys} = ();
	# Untaint, plus take out . and empty string:
	local $ENV{'DCL$PATH'} = $1 if $is_vms && ($ENV{'DCL$PATH'} =~ /(.*)/s);
	$ENV{PATH} =~ /(.*)/s;
	local $ENV{PATH} =
	    join $sep, grep { $_ ne "" and $_ ne "." and -d $_ and
		($is_mswin or $is_vms or !(stat && (stat _)[2]&0022)) }
		    split quotemeta ($sep), $1;
	$ENV{PATH} .= "$sep/bin" if $is_cygwin;  # Must have /bin under Cygwin

	$runperl =~ /(.*)/s;
	$runperl = $1;

	$result = `$runperl`;
    } else {
	$result = `$runperl`;
    }
    $result =~ s/\n\n/\n/ if $is_vms; # XXX pipes sometimes double these
    return $result;
}

*run_perl = \&runperl; # Nice alias.

sub DIE {
    print STDERR "# @_\n";
    exit 1;
}

# A somewhat safer version of the sometimes wrong $^X.
my $Perl;
sub which_perl {
    unless (defined $Perl) {
	$Perl = $^X;

	# VMS should have 'perl' aliased properly
	return $Perl if $^O eq 'VMS';

	my $exe;
	eval "require Config; Config->import";
	if ($@) {
	    warn "test.pl had problems loading Config: $@";
	    $exe = '';
	} else {
	    $exe = $Config{exe_ext};
	}
       $exe = '' unless defined $exe;

	# This doesn't absolutize the path: beware of future chdirs().
	# We could do File::Spec->abs2rel() but that does getcwd()s,
	# which is a bit heavyweight to do here.

	if ($Perl =~ /^perl\Q$exe\E$/i) {
	    my $perl = "perl$exe";
	    eval "require File::Spec";
	    if ($@) {
		warn "test.pl had problems loading File::Spec: $@";
		$Perl = "./$perl";
	    } else {
		$Perl = File::Spec->catfile(File::Spec->curdir(), $perl);
	    }
	}

	# Build up the name of the executable file from the name of
	# the command.

	if ($Perl !~ /\Q$exe\E$/i) {
	    $Perl .= $exe;
	}

	warn "which_perl: cannot find $Perl from $^X" unless -f $Perl;

	# For subcommands to use.
	$ENV{PERLEXE} = $Perl;
    }
    return $Perl;
}

sub unlink_all {
    foreach my $file (@_) {
        1 while unlink $file;
        print STDERR "# Couldn't unlink '$file': $!\n" if -f $file;
    }
}

my $tmpfile = "misctmp000";
1 while -f ++$tmpfile;
END { unlink_all $tmpfile }

#
# _fresh_perl
#
# The $resolve must be a subref that tests the first argument
# for success, or returns the definition of success (e.g. the
# expected scalar) if given no arguments.
#

sub _fresh_perl {
    my($prog, $resolve, $runperl_args, $name) = @_;

    $runperl_args ||= {};
    $runperl_args->{progfile} = $tmpfile;
    $runperl_args->{stderr} = 1;

    open TEST, ">$tmpfile" or die "Cannot open $tmpfile: $!";

    # VMS adjustments
    if( $^O eq 'VMS' ) {
        $prog =~ s#/dev/null#NL:#;

        # VMS file locking
        $prog =~ s{if \(-e _ and -f _ and -r _\)}
                  {if (-e _ and -f _)}
    }

    print TEST $prog;
    close TEST or die "Cannot close $tmpfile: $!";

    my $results = runperl(%$runperl_args);
    my $status = $?;

    # Clean up the results into something a bit more predictable.
    $results =~ s/\n+$//;
    $results =~ s/at\s+misctmp\d+\s+line/at - line/g;
    $results =~ s/of\s+misctmp\d+\s+aborted/of - aborted/g;

    # bison says 'parse error' instead of 'syntax error',
    # various yaccs may or may not capitalize 'syntax'.
    $results =~ s/^(syntax|parse) error/syntax error/mig;

    if ($^O eq 'VMS') {
        # some tests will trigger VMS messages that won't be expected
        $results =~ s/\n?%[A-Z]+-[SIWEF]-[A-Z]+,.*//;

        # pipes double these sometimes
        $results =~ s/\n\n/\n/g;
    }

    my $pass = $resolve->($results);
    unless ($pass) {
        _diag "# PROG: \n$prog\n";
        _diag "# EXPECTED:\n", $resolve->(), "\n";
        _diag "# GOT:\n$results\n";
        _diag "# STATUS: $status\n";
    }

    # Use the first line of the program as a name if none was given
    unless( $name ) {
        ($first_line, $name) = $prog =~ /^((.{1,50}).*)/;
        $name .= '...' if length $first_line > length $name;
    }

    _ok($pass, _where(), "fresh_perl - $name");
}

#
# fresh_perl_is
#
# Combination of run_perl() and is().
#

sub fresh_perl_is {
    my($prog, $expected, $runperl_args, $name) = @_;
    local $Level = 2;
    _fresh_perl($prog,
		sub { @_ ? $_[0] eq $expected : $expected },
		$runperl_args, $name);
}

#
# fresh_perl_like
#
# Combination of run_perl() and like().
#

sub fresh_perl_like {
    my($prog, $expected, $runperl_args, $name) = @_;
    local $Level = 2;
    _fresh_perl($prog,
		sub { @_ ?
			  $_[0] =~ (ref $expected ? $expected : /$expected/) :
		          $expected },
		$runperl_args, $name);
}

sub can_ok ($@) {
    my($proto, @methods) = @_;
    my $class = ref $proto || $proto;

    unless( @methods ) {
        return _ok( 0, _where(), "$class->can(...)" );
    }

    my @nok = ();
    foreach my $method (@methods) {
        local($!, $@);  # don't interfere with caller's $@
                        # eval sometimes resets $!
        eval { $proto->can($method) } || push @nok, $method;
    }

    my $name;
    $name = @methods == 1 ? "$class->can('$methods[0]')"
                          : "$class->can(...)";

    _ok( !@nok, _where(), $name );
}

sub isa_ok ($$;$) {
    my($object, $class, $obj_name) = @_;

    my $diag;
    $obj_name = 'The object' unless defined $obj_name;
    my $name = "$obj_name isa $class";
    if( !defined $object ) {
        $diag = "$obj_name isn't defined";
    }
    elsif( !ref $object ) {
        $diag = "$obj_name isn't a reference";
    }
    else {
        # We can't use UNIVERSAL::isa because we want to honor isa() overrides
        local($@, $!);  # eval sometimes resets $!
        my $rslt = eval { $object->isa($class) };
        if( $@ ) {
            if( $@ =~ /^Can't call method "isa" on unblessed reference/ ) {
                if( !UNIVERSAL::isa($object, $class) ) {
                    my $ref = ref $object;
                    $diag = "$obj_name isn't a '$class' it's a '$ref'";
                }
            } else {
                die <<WHOA;
WHOA! I tried to call ->isa on your object and got some weird error.
This should never happen.  Please contact the author immediately.
Here's the error.
$@
WHOA
            }
        }
        elsif( !$rslt ) {
            my $ref = ref $object;
            $diag = "$obj_name isn't a '$class' it's a '$ref'";
        }
    }

    _ok( !$diag, _where(), $name );
}

sub tests {
    my $in = shift || "t/TESTS";
    $in = "TESTS" unless -f $in;
    undef $/;
    open TEST, "< $in" or die "Cannot open $in";
    my @tests = split /\n####+.*##\n/, <TEST>;
    close TEST;
    delete $tests[$#tests] unless $tests[$#tests];
    @tests;
}

sub run_cc_test {
    my ($cnt, $backend, $script, $expect, $keep_c, $keep_c_fail, $todo) = @_;
    my ($opt, $got);
    $expect =~ s/\n$//;
    my $fnbackend = lc($backend); #C,-O2
    ($fnbackend,$opt) = $fnbackend =~ /^(cc?)(,-o.)?/;
    $opt =~ s/,-/_/ if $opt;
    $opt = '' unless $opt;
    use Config;
    my $test = $fnbackend."code".$cnt.".pl";
    my $cfile = $fnbackend."code".$cnt.$opt.".c";
    my @obj = ($fnbackend."code".$cnt.$opt.".obj",
               $fnbackend."code".$cnt.$opt.".ilk",
               $fnbackend."code".$cnt.$opt.".pdb")
      if $Config{cc} =~ /^cl/i; # MSVC uses a lot of intermediate files
    my $exe = $fnbackend."code".$cnt.$opt.$Config{exe_ext};
    unlink ($test, $cfile, $exe, @obj);
    open T, ">$test"; print T $script; close T;
    my $Mblib = $] >= 5.009005 ? "-Mblib" : ""; # test also the CORE B in older perls
    unless ($Mblib) {           # check for -Mblib from the testsuite
        if (grep { m{blib(/|\\)arch$} } @INC) {
            $Mblib = "-Iblib/arch -Iblib/lib";  # forced -Mblib via cmdline without
            					# printing to stderr
            $backend = "-qq,$backend,-q" unless $ENV{TEST_VERBOSE};
        }
    } else {
        $backend = "-qq,$backend,-q" unless $ENV{TEST_VERBOSE};
    }
    $got = run_perl(switches => [ "$Mblib -MO=$backend,-o${cfile}" ],
                    verbose  => $ENV{TEST_VERBOSE}, # for debugging
                    nolib    => $ENV{PERL_CORE} ? 0 : 1, # include ../lib only in CORE
                    stderr   => 1, # to capture the "ccode.pl syntax ok"
                    progfile => $test);
    if (! $? and -s $cfile) {
        use ExtUtils::Embed ();
        my $command = ExtUtils::Embed::ccopts." -o $exe $cfile ";
        $command .= " ".ExtUtils::Embed::ldopts("-std");
        $command .= " -lperl" if $command !~ /(-lperl|CORE\/libperl5)/ and $^O ne 'MSWin32';
        my $NULL = $^O eq 'MSWin32' ? '' : '2>/dev/null';
        my $cmdline = "$Config{cc} $command $NULL";
        system($cmdline);
        unless (-e $exe) {
            print "not ok $cnt $todo failed $cmdline\n";
            print STDERR "# ",system("$Config{cc} $command");
            unlink ($test, $cfile, $exe, @obj) if !$keep_c;
            return 0;
        }
        $exe = "./".$exe unless $^O eq 'MSWin32';
        $got = `$exe`;
        if (defined($got) and ! $?) {
            if ($cnt == 25 and $expect eq '0 1 2 3 4321' and $] < 5.008) {
                $expect = '0 1 2 3 4 5 4321';
            }
            if ($got =~ /^$expect$/) {
                print "ok $cnt", $todo eq '#' ? "\n" : " $todo\n";
                unlink ($test, $cfile, $exe, @obj) if !$keep_c and ! -s $cfile;
                return 1;
            } else {
                $keep_c = $keep_c_fail unless $keep_c;
                print "not ok $cnt $todo wanted: \"$expect\", got: \"$got\"\n";
                unlink ($test, $cfile, $exe, @obj) if !$keep_c and ! -s $cfile;
                return 0;
            }
        } else {
            $got = '';
        }
    }
    print "not ok $cnt $todo wanted: \"$expect\", \$\? = $?, got: \"$got\"\n";
    $keep_c = $keep_c_fail unless $keep_c;
    unlink ($test, $cfile, $exe, @obj) if !$keep_c;
    return 0;
}

sub prepare_c_tests {
    BEGIN {
        use Config;
        if ($^O eq 'VMS') {
            print "1..0 # skip - B::C doesn't work on VMS\n";
            exit 0;
        }
        if (($Config{'extensions'} !~ /\bB\b/) ) {
            print "1..0 # Skip -- Perl configured without B module\n";
            exit 0;
        }
        # with 5.10 and 5.8.9 PERL_COPY_ON_WRITE was renamed to PERL_OLD_COPY_ON_WRITE
        if ($Config{ccflags} =~ /-DPERL_OLD_COPY_ON_WRITE/) {
            print "1..0 # skip - no OLD COW for now\n";
            exit 0;
        }
    }
}

sub run_c_tests {
    my $backend = $_[0];
    my @todo = @{$_[1]};
    my @skip = @{$_[2]};

    use Config;
    my $AUTHOR      = -d ".svn";
    my $keep_c      = 0;	# set it to keep the pl, c and exe files
    my $keep_c_fail = $AUTHOR;	# set it to keep the pl, c and exe files on failures

    my %todo = map { $_ => 1 } @todo;
    my %skip = map { $_ => 1 } @skip;
    my @tests = tests();

    # add some CC specific tests after 100
    # perl -lne "/^\s*sub pp_(\w+)/ && print \$1" lib/B/CC.pm > ccpp
    # for p in `cat ccpp`; do echo -n "$p "; grep -m1 " $p[(\[ ]" *.concise; done
    # 
    # grep -A1 "coverage: ny" lib/B/CC.pm|grep sub
    # pp_stub pp_cond_expr pp_dbstate pp_reset pp_stringify pp_ncmp pp_preinc
    # pp_formline pp_enterwrite pp_leavewrite pp_entergiven pp_leavegiven
    # pp_dofile pp_grepstart pp_mapstart pp_grepwhile pp_mapwhile
    if ($backend =~ /^CC/) {
        local $/;
        my $cctests = <<'CCTESTS';
my ($r_i,$i_i,$d_d)=(0,2,3.0); $r_i=$i_i*$i_i; $r_i*=$d_d; print $r_i;
>>>>
12
######### 101 - CC types and arith ###############
if ($x eq "2"){}else{print "ok"}
>>>>
ok
######### 102 - CC cond_expr,stub,scope ############
require B; my $x=1e1; my $s="$x"; print ref B::svref_2object(\$s)
>>>>
B::PV
######### 103 - CC stringify srefgen ############
CCTESTS
        my $i = 100;
        for (split /\n####+.*##\n/, $cctests) {
            next unless $_;
            $tests[$i] = $_;
            $i++;
        }
    }

    print "1..".(scalar @tests)."\n";

    my $cnt = 1;
    for (@tests) {
        my $todo = $todo{$cnt} ? "#TODO" : "#";
        # skip empty CC holes to have the same test indices in STATUS and t/testcc.sh
        unless ($_) {
            print sprintf("ok %d # skip hole for CC\n", $cnt);
            $cnt++;
            next;
        }
        # only once. skip subsequent tests 29 on MSVC. 7:30min!
        if ($cnt == 29 and $Config{cc} =~ /^cl/i and $backend ne 'C') {
            $todo{$cnt} = $skip{$cnt} = 1;
        }
        if ($todo{$cnt} and $skip{$cnt} and !$AUTHOR) {
            print sprintf("ok %d # skip\n", $cnt);
        } else {
            my ($script, $expect) = split />>>+\n/;
            run_cc_test($cnt, $backend, $script, $expect, $keep_c, $keep_c_fail, $todo);
        }
        $cnt++;
    }
}
1;

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 78
# End:
# vim: expandtab shiftwidth=4:
