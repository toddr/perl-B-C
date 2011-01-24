# Stash.pm -- show what stashes are loaded
# vishalb@hotmail.com
package B::Stash;

our $VERSION = '1.01';

=pod

=head1 NAME

B::Stash - show what stashes are loaded

=head1 DESCRIPTION

B::Stash has a poor side-effect only API and is only used by perlcc and L<B::C>.

It hooks into CHECK prints a comma-seperated list of loaded stashes (I<package names>)
prefixed with B<-u>.

With the B<xs> argument stashes with XS modules only are printed, prefixed with B<-x>.

With the B<-D> argument some debugging output is added.

Note that the resulting list of modules from B::Stash is usually larger than
the list of used modules determined by the compiler suite (C, CC, Bytecode).

=head1 SYNOPSIS

  perl -c -MB::Stash -e'use IO::Handle;'
  => -umain,-uIO

  perl -c -MB::Stash=xs -e'use IO::Handle;'
  => -xre,-xCwd,-xRegexp,-xIO

  perl -c -MO=Stash=xs,-D -e'use IO::Handle;'
  ...
  => -xre,-xCwd,-xRegexp,-xIO

  perl -c -MO=C,-dumpxs -e'use IO::Handle;'
  ...
  perlcc.lst: -xre,-xCwd,-xRegexp,-xIO

=cut

# BEGIN { %Seen = %INC }

sub import {
  my ($class, @options) = @_;
  my $opts = ",".join(",", @options).",";
  my $xs = $opts =~ /,xs,/;
  my $debug = $opts =~ /,-D,/;
  print "import: ",$class,$opts,"\n" if $debug;
  unless ($xs) {
    eval q[
     CHECK {
      ] . ($debug ? q[print "scan main\n"; my $debug=1;] : "") . q[
      my @arr = scan( $main::{"main::"},'',$debug );
      @arr = map { s/\:\:$//; $_ eq "<none>" ? () : $_; } @arr;
      print "-umain,-u", join( ",-u", @arr ), "\n";
    } ];
  } else {
    BEGIN { require B; }
    eval q[
     CHECK {
      ] . ($debug ? q[print "scanxs main\n"; my $debug=1;] : "") . q[
      B->import(qw(svref_2object CVf_CONST CVf_ANON));
      my @arr = scanxs( $main::{"main::"},'',$debug );
      @arr = map { s/\:\:$//; $_ eq "<none>" ? () : $_; } @arr;
      print "-x", join( ",-x", @arr ), "\n";
    } ];
  }
}

# new O interface, esp. for debugging
sub compile {
  my @options = @_;
  my $opts = ",".join(",", @options).",";
  my $xs = $opts =~ /,xs,/;
  my $debug = $opts =~ /,-D,/;
  print "import: ",$class,$opts,"\n" if $debug;
  unless ($xs) {
    print "scan main\n" if $debug;
    return sub {
      my @arr = scan( $main::{"main::"},'',$debug );
      @arr = map { s/\:\:$//; $_ eq "<none>" ? () : $_; } @arr;
      print "-umain,-u", join( ",-u", @arr ), "\n";
    }
  } else {
    BEGIN { require B; }
    print "scanxs main\n" if $debug;
    return sub {
      B->import(qw(svref_2object CVf_CONST CVf_ANON));
      my @arr = scanxs( $main::{"main::"},'',$debug );
      @arr = map { s/\:\:$//; $_ eq "<none>" ? () : $_; } @arr;
      print "-x", join( ",-x", @arr ), "\n";
    }
  }
}

sub scan {
  my $start  = shift;
  my $prefix = shift;
  my $debug = shift;
  $prefix = '' unless defined $prefix;
  my @return;
  foreach my $key ( grep /::$/, keys %{$start} ) {
    my $name = $prefix . $key;
    print $name,"\n" if $debug;
    unless ( $start eq ${$start}{$key} or omit($name) ) {
      push @return, $key unless $name eq "version::"; # version has an external ::vxs module
      foreach my $subscan ( scan( ${$start}{$key}, $name ) ) {
        my $subname = $key.$subscan;
        print $subname,"\n" if $debug;
        push @return, $subname unless $name eq "version::";
      }
    }
  }
  return @return;
}

sub omit {
  my $name = shift;
  my %omit   = (
    "DynaLoader::"   => 1,
    "XSLoader::"     => 1,
    "CORE::"         => 1,
    "CORE::GLOBAL::" => 1,
    "UNIVERSAL::"    => 1,
    "B::"    	     => 1,
    "O::"    	     => 1
  );
  my %static_core_pkg = map {$_ => 1} static_core_packages();
  return 1 if $omit{$name};
  return 1 if $static_core_pkg{substr($name,0,-2)};
  if ( $name eq "IO::" or $name eq "IO::Handle::" ) {
    $name =~ s/::/\//g;
    return 1 unless $INC{$name};
  }

  return 0;
}

# external XS modules only
sub scanxs {
  my $start  = shift;
  my $prefix = shift;
  my $debug = shift;
  $prefix = '' unless defined $prefix;
  my %IO = (IO::File:: => 1,
            IO::Handle:: => 1,
            IO::Socket:: => 1,
            IO::Seekable:: => 1,
            IO::Poll:: => 1);
  my @return;
  foreach my $key ( grep /::$/, keys %{$start} ) {
    my $name = $prefix . $key;
    print $name,"\n" if $debug;
    $name = "IO" if $IO{$name};
    unless ( $start eq ${$start}{$key} or omit($name) ) {
      push @return, $name if has_xs($name, $debug) and $name ne "version::";
      foreach my $subscan ( scanxs( ${$start}{$key}, $name, $debug ) ) {
        my $subname = $key.$subscan;
        print $subname,"\n" if $debug;
        push @return, $subname if !omit($subname) and has_xs($subname, $debug) and $name ne "version::";
      }
    }
  }
  return @return;
}

sub has_xs {
  my $name = shift;
  my $debug = shift;
  foreach my $key ( keys %{$name} ) {
    my $cvname = $name . $key;
    my $cv = svref_2object( \&{$cvname} );
    print "has_xs: &",$cvname," -> ",$cv," ",$cv->XSUB,"\n" if $debug and $cv;
    if ( $cv and $cv->XSUB ) {
      return 0 if in_static_core(substr($name,0,-2), $key);
      return 1 if $] < 5.007 or !($cv->CvFLAGS & CVf_CONST) or ($cv->CvFLAGS & CVf_ANON);
    }
  }
  return 0;
}

# Keep in sync with B::C
# XS in CORE which do not need to be bootstrapped extra.
# There are some specials like mro,re,UNIVERSAL.
sub in_static_core {
  my ($stashname, $cvname) = @_;
  if ($stashname eq 'UNIVERSAL') {
    return $cvname =~ /^(isa|can|DOES|VERSION)$/;
  }
  return 1 if $static_core_pkg{$stashname};
  if ($stashname eq 'mro') {
    return $cvname eq 'method_changed_in';
  }
  if ($stashname eq 're') {
    return $cvname =~ /^(is_regexp|regname|regnames_count|regexp_pattern)$/;;
  }
  if ($stashname eq 'PerlIO') {
    return $cvname eq 'get_layers';
  }
  if ($stashname eq 'PerlIO::Layer') {
    return $cvname =~ /^(find|NoWarnings)$/;
  }
  return 0;
}

# Keep in sync with B::C
# XS modules in CORE. Reserved namespaces.
# Note: mro,re,UNIVERSAL have both, static core and dynamic/static XS
# version has an external ::vxs
sub static_core_packages {
  my @pkg  = qw(Internals utf8 UNIVERSAL);
  push @pkg, qw(Tie::Hash::NamedCapture) if $] >= 5.010;
  push @pkg, qw(DynaLoader)		if $Config{usedl};
  # Win32CORE only in official cygwin pkg. And it needs to be bootstrapped,
  # handled by static_ext.
  push @pkg, qw(Cygwin)			if $^O eq 'cygwin';
  push @pkg, qw(NetWare)		if $^O eq 'NetWare';
  push @pkg, qw(OS2)			if $^O eq 'os2';
  push @pkg, qw(VMS VMS::Filespec vmsish) if $^O eq 'VMS';
  #push @pkg, qw(PerlIO) if $] >= 5.008006; # get_layers only
  return @pkg;
}

1;

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 2
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=2:
