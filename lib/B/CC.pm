#      CC.pm
#
#      Copyright (c) 1996, 1997, 1998 Malcolm Beattie
#      Copyright (c) 2009, 2010, 2011 Reini Urban
#      Copyright (c) 2010 Heinz Knutzen
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#
package B::CC;

our $VERSION = '1.09';

use Config;
use strict;
#use 5.008;
use B qw(main_start main_root class comppadlist peekop svref_2object
  timing_info init_av sv_undef amagic_generation
  OPf_WANT_VOID OPf_WANT_SCALAR OPf_WANT_LIST OPf_WANT
  OPf_MOD OPf_STACKED OPf_SPECIAL
  OPpASSIGN_BACKWARDS OPpLVAL_INTRO OPpDEREF_AV OPpDEREF_HV
  OPpDEREF OPpFLIP_LINENUM G_VOID G_SCALAR G_ARRAY
);
#CXt_NULL CXt_SUB CXt_EVAL CXt_SUBST CXt_BLOCK
use B::C qw(save_unused_subs objsym init_sections mark_unused
  output_all output_boilerplate output_main fixup_ppaddr save_sig
  svop_or_padop_pv);
use B::Bblock qw(find_leaders);
use B::Stackobj qw(:types :flags);
use B::C::Flags;

@B::OP::ISA = qw(B::NULLOP B);           # support -Do
@B::LISTOP::ISA = qw(B::BINOP B);       # support -Do

# These should probably be elsewhere
# Flags for $op->flags

my $module;         # module name (when compiled with -m)
my %done;          # hash keyed by $$op of leaders of basic blocks
                    # which have already been done.
my $leaders;        # ref to hash of basic block leaders. Keys are $$op
                    # addresses, values are the $op objects themselves.
my @bblock_todo;  # list of leaders of basic blocks that need visiting
                    # sometime.
my @cc_todo;       # list of tuples defining what PP code needs to be
                    # saved (e.g. CV, main or PMOP repl code). Each tuple
                    # is [$name, $root, $start, @padlist]. PMOP repl code
                    # tuples inherit padlist.
my @stack;         # shadows perl's stack when contents are known.
                    # Values are objects derived from class B::Stackobj
my @pad;           # Lexicals in current pad as Stackobj-derived objects
my @padlist;       # Copy of current padlist so PMOP repl code can find it
my @cxstack;       # Shadows the (compile-time) cxstack for next,last,redo
		    # This covers only a small part of the perl cxstack
my $labels;         # hashref to array of op labels
my %constobj;      # OP_CONST constants as Stackobj-derived objects
                    # keyed by $$sv.
my $need_freetmps = 0;	# We may postpone FREETMPS to the end of each basic
			# block or even to the end of each loop of blocks,
			# depending on optimisation options.
my $know_op       = 0;	# Set when C variable op already holds the right op
			# (from an immediately preceding DOOP(ppname)).
my $errors        = 0;	# Number of errors encountered
my %no_stack;		# PP names which don't need save pp restore stack
my %skip_stack;	# PP names which don't need write_back_stack (empty)
my %skip_lexicals;	# PP names which don't need write_back_lexicals
my %skip_invalidate;	# PP names which don't need invalidate_lexicals
my %ignore_op;		# ops which do nothing except returning op_next
my %need_curcop;	# ops which need PL_curcop
my $package_pv;      # sv->pv of previous op for method_named

my %lexstate;           #state of padsvs at the start of a bblock
my $verbose;
my ( $entertry_defined, $vivify_ref_defined );
my ( $module_name, %debug, $strict );

# Optimisation options. On the command line, use hyphens instead of
# underscores for compatibility with gcc-style options. We use
# underscores here because they are OK in (strict) barewords.
my ( $freetmps_each_bblock, $freetmps_each_loop, $inline_ops, $omit_taint, $slow_signals );
$inline_ops = 1 unless $^O eq 'MSWin32'; # Win32 cannot link to unexported pp_op()
my %optimise = (
  freetmps_each_bblock => \$freetmps_each_bblock, #-O1
  freetmps_each_loop   => \$freetmps_each_loop,	  #-O2
  inline_ops 	       => \$inline_ops,	  	  #always
  omit_taint           => \$omit_taint,
  slow_signals         => \$slow_signals,
);
my %async_signals = map { $_ => 1 } # 5.14 ops which do PERL_ASYNC_CHECK
  qw(wait waitpid nextstate and cond_expr unstack or defined subst);
# perl patchlevel to generate code for (defaults to current patchlevel)
my $patchlevel = int( 0.5 + 1000 * ( $] - 5 ) );    # unused?
my $ITHREADS   = $Config{useithreads};
my $PERL510    = ( $] >= 5.009005 );
my $PERL511    = ( $] >= 5.011 );

my $SVt_PVLV = $PERL510 ? 10 : 9;
my $SVt_PVAV = $PERL510 ? 11 : 10;
# use sub qw(CXt_LOOP_PLAIN CXt_LOOP);
if ($PERL511) {
  sub CXt_LOOP_PLAIN {5} # CXt_LOOP_FOR CXt_LOOP_LAZYSV CXt_LOOP_LAZYIV
} else {
  sub CXt_LOOP {3}
}
sub CxTYPE_no_LOOP  {
  $PERL511 
    ? ( $_[0]->{type} < 4 or $_[0]->{type} > 7 )
    : $_[0]->{type} != 3
}

# Could rewrite push_runtime() and output_runtime() to use a
# temporary file if memory is at a premium.
my $ppname;    	     # name of current fake PP function
my $runtime_list_ref;
my $declare_ref;     # Hash ref keyed by C variable type of declarations.

my @pp_list;        # list of [$ppname, $runtime_list_ref, $declare_ref]
		     # tuples to be written out.

my ( $init, $decl );

sub init_hash {
  map { $_ => 1 } @_;
}

#
# Initialise the hashes for the default PP functions where we can avoid
# either stack save/restore,write_back_stack, write_back_lexicals or invalidate_lexicals.
# XXX We should really take some of this info from Opcodes (was: CORE opcode.pl)
#
# no args and no return value = Opcodes::argnum 0
%no_stack         = init_hash qw(pp_unstack pp_break pp_continue);
				# pp_enter pp_leave, use/change global stack.
#skip write_back_stack (no args)
%skip_stack       = init_hash qw(pp_enter);
%skip_lexicals   = init_hash qw(pp_enter pp_enterloop);
%skip_invalidate = init_hash qw(pp_enter pp_enterloop);
%need_curcop     = init_hash qw(pp_rv2gv  pp_bless pp_repeat pp_sort pp_caller
  pp_reset pp_rv2cv pp_entereval pp_require pp_dofile
  pp_entertry pp_enterloop pp_enteriter pp_entersub pp_entergiven
  pp_enter pp_method);
%ignore_op = init_hash qw(pp_scalar pp_regcmaybe pp_lineseq pp_scope pp_null);

{ # block necessary for caller to work
  my $caller = caller;
  if ( $caller eq 'O' ) {
    require XSLoader;
    XSLoader::load('B::C'); # for r-magic only
  }
}

sub debug {
  if ( $debug{runtime} ) {
    # TODO: fix COP to callers line number
    warn(@_) if $verbose;
  }
  else {
    my @tmp = @_;
    runtime( map { chomp; "/* $_ */" } @tmp );
  }
}

sub declare {
  my ( $type, $var ) = @_;
  push( @{ $declare_ref->{$type} }, $var );
}

sub push_runtime {
  push( @$runtime_list_ref, @_ );
  warn join( "\n", @_ ) . "\n" if $debug{runtime};
}

sub save_runtime {
  push( @pp_list, [ $ppname, $runtime_list_ref, $declare_ref ] );
}

sub output_runtime {
  my $ppdata;
  print qq(\n#include "cc_runtime.h"\n);
  # CC coverage: 12, 32

  # Perls >=5.8.9 have a broken PP_ENTERTRY. See PERL_FLEXIBLE_EXCEPTIONS in cop.h
  # Fixed in CORE with 5.11.4
  print'
#undef PP_ENTERTRY
#define PP_ENTERTRY(label)  	\
	STMT_START {                    \
	    dJMPENV;			\
	    int ret;			\
	    JMPENV_PUSH(ret);		\
	    switch (ret) {		\
		case 1: JMPENV_POP; JMPENV_JUMP(1);\
		case 2: JMPENV_POP; JMPENV_JUMP(2);\
		case 3: JMPENV_POP; SPAGAIN; goto label;\
	    }                                      \
	} STMT_END' 
    if $entertry_defined and $] < 5.011004;
  # XXX need to find out when PERL_FLEXIBLE_EXCEPTIONS were actually active.
  # 5.6.2 not, 5.8.9 not. coverage 32

  # test 12. Used by entereval + dofile
  if ($PERL510 or $ITHREADS) {
    # Threads error Bug#55302: too few arguments to function
    # CALLRUNOPS()=>CALLRUNOPS(aTHX)
    # fixed with 5.11.4
    print '
#undef  PP_EVAL
#define PP_EVAL(ppaddr, nxt) do {		\
	dJMPENV;				\
	int ret;				\
        PUTBACK;				\
	JMPENV_PUSH(ret);			\
	switch (ret) {				\
	case 0:					\
	    PL_op = ppaddr(aTHX);		\\';
    if ($PERL510) {
      # pp_leaveeval sets: retop = cx->blk_eval.retop
      print '
	    cxstack[cxstack_ix].blk_eval.retop = Nullop; \\';
    } else {
      # up to 5.8 pp_entereval did set the retstack to next.
      # nullify that so that we can now exec the rest of this bblock.
      # (nextstate .. leaveeval)
      print '
	    PL_retstack[PL_retstack_ix - 1] = Nullop;  \\';
    }
    print '
	    if (PL_op != nxt) CALLRUNOPS(aTHX);	\
	    JMPENV_POP;				\
	    break;				\
	case 1: JMPENV_POP; JMPENV_JUMP(1);	\
	case 2: JMPENV_POP; JMPENV_JUMP(2);	\
	case 3:					\
            JMPENV_POP; 			\
	    if (PL_restartop && PL_restartop != nxt) \
		JMPENV_JUMP(3);			\
        }                                       \
	PL_op = nxt;                            \
	SPAGAIN;                                \
    } while (0)
';
  }

  # Perl_vivify_ref not exported on MSWin32
  # coverage: 18
  if ($PERL510 and $^O eq 'MSWin32') {
    # CC coverage: 18, 29
    print << '__EOV' if $vivify_ref_defined;

/* Code to take a scalar and ready it to hold a reference */
#  ifndef SVt_RV
#    define SVt_RV   SVt_IV
#  endif
#  define prepare_SV_for_RV(sv)						\
    STMT_START {							\
		    if (SvTYPE(sv) < SVt_RV)				\
			sv_upgrade(sv, SVt_RV);				\
		    else if (SvPVX_const(sv)) {				\
			SvPV_free(sv);					\
			SvLEN_set(sv, 0);				\
                        SvCUR_set(sv, 0);				\
		    }							\
		 } STMT_END

void
Perl_vivify_ref(pTHX_ SV *sv, U32 to_what)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) {
	if (SvREADONLY(sv))
	    Perl_croak(aTHX_ "%s", PL_no_modify);
	prepare_SV_for_RV(sv);
	switch (to_what) {
	case OPpDEREF_SV:
	    SvRV_set(sv, newSV(0));
	    break;
	case OPpDEREF_AV:
	    SvRV_set(sv, newAV());
	    break;
	case OPpDEREF_HV:
	    SvRV_set(sv, newHV());
	    break;
	}
	SvROK_on(sv);
	SvSETMAGIC(sv);
    }
}

__EOV
  }

  foreach $ppdata (@pp_list) {
    my ( $name, $runtime, $declare ) = @$ppdata;
    print "\nstatic\nCCPP($name)\n{\n";
    my ( $type, $varlist, $line );
    while ( ( $type, $varlist ) = each %$declare ) {
      print "\t$type ", join( ", ", @$varlist ), ";\n";
    }
    foreach $line (@$runtime) {
      print $line, "\n";
    }
    print "}\n";
  }
}

sub runtime {
  my $line;
  foreach $line (@_) {
    push_runtime("\t$line");
  }
}

sub init_pp {
  $ppname           = shift;
  $runtime_list_ref = [];
  $declare_ref      = {};
  runtime("dSP;");
  declare( "I32", "oldsave" );
  map { declare( "SV", "*$_" ) } qw(sv src dst left right);
  declare( "MAGIC", "*mg" );
  $decl->add( "#undef cxinc", "#define cxinc() Perl_cxinc(aTHX)")
    if $] < 5.011001 and $inline_ops;
  declare( "PERL_CONTEXT", "*cx" );
  declare( "I32", "gimme");
  $decl->add("static OP * $ppname (pTHX);");
  debug "init_pp: $ppname\n" if $debug{queue};
}

# Initialise runtime_callback function for Stackobj class
BEGIN { B::Stackobj::set_callback( \&runtime ) }

# new ccpp optree (XXX fixme test 18)
# Initialise saveoptree_callback for B::C class
sub cc_queue {
  my ( $name, $root, $start, @pl ) = @_;
  debug "cc_queue: name $name, root $root, start $start, padlist (@pl)\n"
    if $debug{queue};
  if ( $name eq "*ignore*" ) {
    $name = 0;
  }
  else {
    push( @cc_todo, [ $name, $root, $start, ( @pl ? @pl : @padlist ) ] );
  }
  my $fakeop = B::FAKEOP->new( "next" => 0, sibling => 0, ppaddr => $name );
  $start = $fakeop->save;
  debug "cc_queue: name $name returns $start\n" if $debug{queue};
  return $start;
}
BEGIN { B::C::set_callback( \&cc_queue ) }

sub valid_int     { $_[0]->{flags} & VALID_INT }
sub valid_double  { $_[0]->{flags} & VALID_DOUBLE }
sub valid_numeric { $_[0]->{flags} & ( VALID_INT | VALID_DOUBLE ) }
sub valid_sv      { $_[0]->{flags} & VALID_SV }

sub top_int     { @stack ? $stack[-1]->as_int     : "TOPi" }
sub top_double  { @stack ? $stack[-1]->as_double  : "TOPn" }
sub top_numeric { @stack ? $stack[-1]->as_numeric : "TOPn" }
sub top_sv      { @stack ? $stack[-1]->as_sv      : "TOPs" }
sub top_bool    { @stack ? $stack[-1]->as_bool    : "SvTRUE(TOPs)" }

sub pop_int     { @stack ? ( pop @stack )->as_int     : "POPi" }
sub pop_double  { @stack ? ( pop @stack )->as_double  : "POPn" }
sub pop_numeric { @stack ? ( pop @stack )->as_numeric : "POPn" }
sub pop_sv      { @stack ? ( pop @stack )->as_sv      : "POPs" }

sub pop_bool {
  if (@stack) {
    return ( ( pop @stack )->as_bool );
  }
  else {
    # Careful: POPs has an auto-decrement and SvTRUE evaluates
    # its argument more than once.
    runtime("sv = POPs;");
    return "SvTRUE(sv)";
  }
}

sub write_back_lexicals {
  my $avoid = shift || 0;
  debug "write_back_lexicals($avoid) called from @{[(caller(1))[3]]}\n"
    if $debug{shadow};
  my $lex;
  foreach $lex (@pad) {
    next unless ref($lex);
    $lex->write_back unless $lex->{flags} & $avoid;
  }
}

# The compiler tracks state of lexical variables in @pad to generate optimised
# code. But multiple execution paths lead to the entry point of a basic block.
# The state of the first execution path is saved and all other execution
# paths are restored to the state of the first one.
# Missing flags are regenerated by loading values.
# Added flags must are removed; otherwise the compiler would be too optimistic,
# hence generating code which doesn't match state of the other execution paths.
sub save_or_restore_lexical_state {
  my $bblock = shift;
  unless ( exists $lexstate{$bblock} ) {
    foreach my $lex (@pad) {
      next unless ref($lex);
      ${ $lexstate{$bblock} }{ $lex->{iv} } = $lex->{flags};
    }
  }
  else {
    foreach my $lex (@pad) {
      next unless ref($lex);
      my $old_flags = ${ $lexstate{$bblock} }{ $lex->{iv} };
      next if ( $old_flags eq $lex->{flags} );
      my $changed = $old_flags ^ $lex->{flags};
      if ( $changed & VALID_SV ) {
        ( $old_flags & VALID_SV ) ? $lex->write_back : $lex->invalidate;
      }
      if ( $changed & VALID_DOUBLE )
      {
        ( $old_flags & VALID_DOUBLE ) ? $lex->load_double : $lex->invalidate_double;
      }
      if ( $changed & VALID_INT ) {
        ( $old_flags & VALID_INT ) ? $lex->load_int : $lex->invalidate_int;
      }
    }
  }
}

sub write_back_stack {
  return unless @stack;
  runtime( sprintf( "EXTEND(sp, %d);", scalar(@stack) ) );
  # return unless @stack;
  foreach my $obj (@stack) {
    runtime( sprintf( "PUSHs((SV*)%s);", $obj->as_sv ) );
  }
  @stack = ();
}

sub invalidate_lexicals {
  my $avoid = shift || 0;
  debug "invalidate_lexicals($avoid) called from @{[(caller(1))[3]]}\n"
    if $debug{shadow};
  my $lex;
  foreach $lex (@pad) {
    next unless ref($lex);
    $lex->invalidate unless $lex->{flags} & $avoid;
  }
}

sub reload_lexicals {
  my $lex;
  foreach $lex (@pad) {
    next unless ref($lex);
    my $type = $lex->{type};
    if ( $type == T_INT ) {
      $lex->as_int;
    }
    elsif ( $type == T_DOUBLE ) {
      $lex->as_double;
    }
    else {
      $lex->as_sv;
    }
  }
}

{

  package B::Pseudoreg;

  #
  # This class allocates pseudo-registers (OK, so they're C variables).
  #
  my %alloc;    # Keyed by variable name. A value of 1 means the
                # variable has been declared. A value of 2 means
                # it's in use.

  sub new_scope { %alloc = () }

  sub new ($$$) {
    my ( $class, $type, $prefix ) = @_;
    my ( $ptr, $i, $varname, $status, $obj );
    $prefix =~ s/^(\**)//;
    $ptr = $1;
    $i   = 0;
    do {
      $varname = "$prefix$i";
      $status  = $alloc{$varname};
    } while $status == 2;
    if ( $status != 1 ) {

      # Not declared yet
      B::CC::declare( $type, "$ptr$varname" );
      $alloc{$varname} = 2;    # declared and in use
    }
    $obj = bless \$varname, $class;
    return $obj;
  }

  sub DESTROY {
    my $obj = shift;
    $alloc{$$obj} = 1;         # no longer in use but still declared
  }
}
{

  package B::Shadow;

  #
  # This class gives a standard API for a perl object to shadow a
  # C variable and only generate reloads/write-backs when necessary.
  #
  # Use $obj->load($foo) instead of runtime("shadowed_c_var = foo").
  # Use $obj->write_back whenever shadowed_c_var needs to be up to date.
  # Use $obj->invalidate whenever an unknown function may have
  # set shadow itself.

  sub new {
    my ( $class, $write_back ) = @_;

    # Object fields are perl shadow variable, validity flag
    # (for *C* variable) and callback sub for write_back
    # (passed perl shadow variable as argument).
    bless [ undef, 1, $write_back ], $class;
  }

  sub load {
    my ( $obj, $newval ) = @_;
    $obj->[1] = 0;         # C variable no longer valid
    $obj->[0] = $newval;
  }

  sub write_back {
    my $obj = shift;
    if ( !( $obj->[1] ) ) {
      $obj->[1] = 1;       # C variable will now be valid
      &{ $obj->[2] }( $obj->[0] );
    }
  }
  sub invalidate { $_[0]->[1] = 0 }    # force C variable to be invalid
}

my $curcop = B::Shadow->new(
  sub {
    my $opsym = shift->save;
    runtime("PL_curcop = (COP*)$opsym;");
  }
);

#
# Context stack shadowing. Mimics stuff in pp_ctl.c, cop.h and so on.
#
sub dopoptoloop {
  my $cxix = $#cxstack;
  while ( $cxix >= 0 && CxTYPE_no_LOOP( $cxstack[$cxix] ) ) {
    $cxix--;
  }
  debug "dopoptoloop: returning $cxix" if $debug{cxstack};
  return $cxix;
}

sub dopoptolabel {
  my $label = shift;
  my $cxix  = $#cxstack;
  while (
    $cxix >= 0
    && ( CxTYPE_no_LOOP( $cxstack[$cxix] )
      || $cxstack[$cxix]->{label} ne $label )
    )
  {
    $cxix--;
  }
  debug "dopoptolabel: returning $cxix\n" if $debug{cxstack};
  if ($cxix < 0 and $debug{cxstack}) {
    for my $cx (0 .. $#cxstack) {
      print $cx,$cxstack[$cx],"\n";
    }
  }
  return $cxix;
}

sub push_label {
  my $op = shift;
  my $type = shift;
  push @{$labels->{$type}}, ( $op );
}

sub pop_label {
  my $type = shift;
  my $op = pop @{$labels->{$type}};
  # avoid duplicate labels
  write_label ($op);
}

sub error {
  my $format = shift;
  my $file   = $curcop->[0]->file;
  my $line   = $curcop->[0]->line;
  $errors++;
  if (@_) {
    warn sprintf( "%s:%d: $format\n", $file, $line, @_ );
  }
  else {
    warn sprintf( "%s:%d: %s\n", $file, $line, $format );
  }
}

#
# Load pad takes (the elements of) a PADLIST as arguments and loads up @pad
# with Stackobj-derived objects which represent those lexicals.  If/when perl
# itself can generate type information (my int $foo; my $foo:Cint) then we'll
# take advantage of that here. Until then, we'll use various hacks to tell the
# compiler when we want a lexical to be a particular type or to be a register.
#
sub load_pad {
  my ( $namelistav, $valuelistav ) = @_;
  @padlist = @_;
  my @namelist  = $namelistav->ARRAY;
  my @valuelist = $valuelistav->ARRAY;
  my $ix;
  @pad = ();
  debug "load_pad: $#namelist names, $#valuelist values\n" if $debug{pad};

  # Temporary lexicals don't get named so it's possible for @valuelist
  # to be strictly longer than @namelist. We count $ix up to the end of
  # @valuelist but index into @namelist for the name. Any temporaries which
  # run off the end of @namelist will make $namesv undefined and we treat
  # that the same as having an explicit SPECIAL sv_undef object in @namelist.
  # [XXX If/when @_ becomes a lexical, we must start at 0 here.]
  for ( $ix = 1 ; $ix < @valuelist ; $ix++ ) {
    my $namesv = $namelist[$ix];
    my $type   = T_UNKNOWN;
    my $flags  = 0;
    my $name   = "tmp";
    my $class  = class($namesv);
    if ( !defined($namesv) || $class eq "SPECIAL" ) {
      # temporaries have &PL_sv_undef instead of a PVNV for a name
      $flags = VALID_SV | TEMPORARY | REGISTER;
    }
    else {
      my ($nametry) = $namesv->PV =~ /^\$(.+)$/ if $namesv->PV;
      $name = $nametry if $nametry;
      # XXX magic names: my $i_ir, my $d_d. No cmdline switch? We should accept attrs also
      # XXX We should also try Devel::TypeCheck here
      if ( $name =~ /^(.*)_([di])(r?)$/ ) {
        $name = $1;
        if ( $2 eq "i" ) {
          $type  = T_INT;
          $flags = VALID_SV | VALID_INT;
        }
        elsif ( $2 eq "d" ) {
          $type  = T_DOUBLE;
          $flags = VALID_SV | VALID_DOUBLE;
        }
        $flags |= REGISTER if $3;
      }
    }
    $name = "${ix}_$name";
    $pad[$ix] =
      B::Stackobj::Padsv->new( $type, $flags, $ix, "i$name", "d$name" );

    debug sprintf( "PL_curpad[$ix] = %s\n", $pad[$ix]->peek ) if $debug{pad};
  }
}

sub declare_pad {
  my $ix;
  for ( $ix = 1 ; $ix <= $#pad ; $ix++ ) {
    my $type = $pad[$ix]->{type};
    declare( "IV",
      $type == T_INT ? sprintf( "%s=0", $pad[$ix]->{iv} ) : $pad[$ix]->{iv} )
      if $pad[$ix]->save_int;
    declare( "double",
      $type == T_DOUBLE
      ? sprintf( "%s = 0", $pad[$ix]->{nv} )
      : $pad[$ix]->{nv} )
      if $pad[$ix]->save_double;

  }
}

#
# Debugging stuff
#
sub peek_stack {
  sprintf "stack = %s\n", join( " ", map( $_->minipeek, @stack ) );
}

#
# OP stuff
#

sub label {
  my $op = shift;
  # Preserve original label name for "real" labels
  if ($op->can("label") and $op->label) {
    # cc should error errors on duplicate named labels
    return sprintf( "label_%s_%x", $op->label, $$op );
  } else {
    return sprintf( "lab_%x", $$op );
  }
}

sub write_label {
  my $op = shift;
  #debug sprintf("lab_%x:?\n", $$op);
  unless ($labels->{label}->{$$op}) {
    my $l = label($op);
    push_runtime( sprintf( "  %s:", label($op) ) );
    # avoid printing duplicate jump labels
    $labels->{label}->{$$op} = $l;
  }
}

sub loadop {
  my $op    = shift;
  my $opsym = $op->save;
  runtime("PL_op = $opsym;") unless $know_op;
  return $opsym;
}

sub doop {
  my $op     = shift;
  my $ppaddr = $op->ppaddr;
  my $sym    = loadop($op);
  my $ppname = "pp_" . $op->name;
  if ($inline_ops) {
    # inlining direct calls is safe, just CALLRUNOPS for macros not
    $ppaddr = "Perl_".$ppname;
    $no_stack{$ppname}
      ? runtime("PL_op = $ppaddr();")
      : runtime("PUTBACK; PL_op = $ppaddr(); SPAGAIN;");
  } else {
    $no_stack{$ppname}
      ? runtime("PL_op = $ppaddr(aTHX);")
      : runtime("DOOP($ppaddr);");
  }
  $know_op = 1;
  return $sym;
}

sub gimme {
  my $op    = shift;
  my $want = $op->flags & OPf_WANT;
  return ( $want == OPf_WANT_VOID ? G_VOID :
           $want == OPf_WANT_SCALAR ? G_SCALAR :
           $want == OPf_WANT_LIST ? G_ARRAY :
           undef );
}

#
# Code generation for PP code
#

# coverage: 18,19,25,...
sub pp_null {
  my $op = shift;
  return $op->next;
}

# coverage: 102
sub pp_stub {
  my $op    = shift;
  my $gimme = gimme($op);
  if ( not defined $gimme ) {
    write_back_stack();
    runtime("if (block_gimme() == G_SCALAR)",
            "\tXPUSHs(&PL_sv_undef);");
  } elsif ( $gimme == G_SCALAR ) {
    my $obj = B::Stackobj::Const->new(sv_undef);
    push( @stack, $obj );
  }
  return $op->next;
}

# coverage: 2,21,28,30
sub pp_unstack {
  my $op = shift;
  @stack = ();
  runtime("PP_UNSTACK;");
  return $op->next;
}

# coverage: 2,21,27,28,30
sub pp_and {
  my $op   = shift;
  my $next = $op->next;
  reload_lexicals();
  unshift( @bblock_todo, $next );
  if ( @stack >= 1 ) {
    my $obj  = pop @stack;
    my $bool = $obj->as_bool;
    write_back_stack();
    save_or_restore_lexical_state($$next);
    runtime(
      sprintf( 
        "if (!$bool) { PUSHs((SV*)%s); goto %s;}", $obj->as_sv, label($next) 
      ) 
    );
  }
  else {
    save_or_restore_lexical_state($$next);
    runtime( sprintf( "if (!%s) goto %s;", top_bool(), label($next) ),
      "*sp--;" );
  }
  return $op->other;
}

# Nearly identical to pp_and, but leaves stack unchanged.
sub pp_andassign {
  my $op   = shift;
  my $next = $op->next;
  reload_lexicals();
  unshift( @bblock_todo, $next );
  if ( @stack >= 1 ) {
    my $obj  = pop @stack;
    my $bool = $obj->as_bool;
    write_back_stack();
    save_or_restore_lexical_state($$next);
    runtime(
      sprintf(
        "PUSHs((SV*)%s); if (!$bool) { goto %s;}", $obj->as_sv, label($next)
      )
    );
  }
  else {
    save_or_restore_lexical_state($$next);
    runtime( sprintf( "if (!%s) goto %s;", top_bool(), label($next) ) );
  }
  return $op->other;
}

# coverage: 28
sub pp_or {
  my $op   = shift;
  my $next = $op->next;
  reload_lexicals();
  unshift( @bblock_todo, $next );
  if ( @stack >= 1 ) {
    my $obj  = pop @stack;
    my $bool = $obj->as_bool;
    write_back_stack();
    save_or_restore_lexical_state($$next);
    runtime(
      sprintf(
        "if ($bool) { PUSHs((SV*)%s); goto %s; }", $obj->as_sv, label($next)
      )
    );
  }
  else {
    save_or_restore_lexical_state($$next);
    runtime( sprintf( "if (%s) goto %s;", top_bool(), label($next) ),
      "*sp--;" );
  }
  return $op->other;
}

# Nearly identical to pp_or, but leaves stack unchanged.
sub pp_orassign {
  my $op   = shift;
  my $next = $op->next;
  reload_lexicals();
  unshift( @bblock_todo, $next );
  if ( @stack >= 1 ) {
    my $obj  = pop @stack;
    my $bool = $obj->as_bool;
    write_back_stack();
    save_or_restore_lexical_state($$next);
    runtime(
      sprintf(
        "PUSHs((SV*)%s); if ($bool) { goto %s; }", $obj->as_sv, label($next)
      )
    );
  }
  else {
    save_or_restore_lexical_state($$next);
    runtime( sprintf( "if (%s) goto %s;", top_bool(), label($next) ) );
  }
  return $op->other;
}

# coverage: 102
sub pp_cond_expr {
  my $op    = shift;
  my $false = $op->next;
  unshift( @bblock_todo, $false );
  reload_lexicals();
  my $bool = pop_bool();
  write_back_stack();
  save_or_restore_lexical_state($$false);
  runtime( sprintf( "if (!$bool) goto %s;\t/* cond_expr */", label($false) ) );
  return $op->other;
}

# coverage: 9,10,12,17,18,22,28,32
sub pp_padsv {
  my $op = shift;
  my $ix = $op->targ;
  push( @stack, $pad[$ix] ) if $pad[$ix];
  if ( $op->flags & OPf_MOD ) {
    my $private = $op->private;
    if ( $private & OPpLVAL_INTRO ) {
      # coverage: 9,10,12,17,18,19,20,22,27,28,31,32
      runtime("SAVECLEARSV(PL_curpad[$ix]);");
    }
    elsif ( $private & OPpDEREF ) {
      # coverage: 18
      runtime(sprintf( "Perl_vivify_ref(aTHX_ PL_curpad[%d], %d);",
                       $ix, $private & OPpDEREF ));
      $vivify_ref_defined++;
      $pad[$ix]->invalidate;
    }
  }
  return $op->next;
}

# coverage: 1-5,7-14,18-23,25,27-32
sub pp_const {
  my $op = shift;
  my $sv = $op->sv;
  my $obj;

  # constant could be in the pad (under useithreads)
  if ($$sv) {
    $obj = $constobj{$$sv};
    if ( !defined($obj) ) {
      $obj = $constobj{$$sv} = B::Stackobj::Const->new($sv);
    }
  }
  else {
    $obj = $pad[ $op->targ ];
  }
  # XXX looks like method_named has only const as prev op
  if ($op->next
      and $op->next->can('name')
      and $op->next->name eq 'method_named'
     ) {
    $package_pv = svop_or_padop_pv($op);
    debug "save package_pv \"$package_pv\" for method_name\n" if $debug{op};
  }
  push( @stack, $obj );
  return $op->next;
}

# coverage: 1-39, fails in 33
sub pp_nextstate {
  my $op = shift;
  if ($labels->{'nextstate'}->[-1] and $labels->{'nextstate'}->[-1] == $op) {
    pop_label 'nextstate';
  } else {
    write_label($op);
  }
  $curcop->load($op);
  @stack = ();
  debug( sprintf( "%s:%d\n", $op->file, $op->line ) ) if $debug{lineno};
  debug( sprintf( "CopLABEL %s\n", $op->label ) ) if $op->label and $debug{cxstack};
  runtime("TAINT_NOT;\t/* nextstate */") unless $omit_taint;
  #my $cxix  = $#cxstack;
  # XXX What symptom I'm fighting here? test 33
  #if ( $cxix >= 0 ) { # XXX
  runtime("sp = PL_stack_base + cxstack[cxstack_ix].blk_oldsp;");
  #} else {
  #  runtime("sp = PL_stack_base;");
  #}
  if ( $freetmps_each_bblock || $freetmps_each_loop ) {
    $need_freetmps = 1;
  }
  else {
    runtime("FREETMPS;");
  }
  return $op->next;
}

# Like pp_nextstate, but used instead when the debugger is active.
sub pp_dbstate { pp_nextstate(@_) }

#default_pp will handle this:
#sub pp_bless { $curcop->write_back; default_pp(@_) }
#sub pp_repeat { $curcop->write_back; default_pp(@_) }
# The following subs need $curcop->write_back if we decide to support arybase:
# pp_pos, pp_substr, pp_index, pp_rindex, pp_aslice, pp_lslice, pp_splice
#sub pp_caller { $curcop->write_back; default_pp(@_) }

# coverage: ny
sub bad_pp_reset {
  if ($inline_ops) {
    my $op = shift;
    warn "inlining reset\n" if $debug{op};
    $curcop->write_back if $curcop;
    runtime '{ /* pp_reset */';
    runtime '  const char * const tmps = (MAXARG < 1) ? (const char *)"" : POPpconstx;';
    runtime '  sv_reset(tmps, CopSTASH(PL_curcop));}';
    runtime 'PUSHs(&PL_sv_yes);';
    return $op->next;
  } else {
    default_pp(@_);
  }
}

# coverage: 20
sub pp_regcreset {
  if ($inline_ops) {
    my $op = shift;
    warn "inlining regcreset\n" if $debug{op};
    $curcop->write_back if $curcop;
    runtime 'PL_reginterp_cnt = 0;	/* pp_regcreset */';
    runtime 'TAINT_NOT;';
    return $op->next;
  } else {
    default_pp(@_);
  }
}

# coverage: 103
sub pp_stringify {
  if ($inline_ops and $] >= 5.008) {
    my $op = shift;
    warn "inlining stringify\n" if $debug{op};
    my $sv = top_sv();
    my $ix = $op->targ;
    my $targ = $pad[$ix];
    runtime "sv_copypv(PL_curpad[$ix], $sv);\t/* pp_stringify */";
    $stack[-1] = $targ if @stack;
    return $op->next;
  } else {
    default_pp(@_);
  }
}

# coverage: 9,10,27
sub bad_pp_anoncode {
  if ($inline_ops) {
    my $op = shift;
    warn "inlining anoncode\n" if $debug{op};
    my $ix = $op->targ;
    my $ppname = "pp_" . $op->name;
    write_back_lexicals() unless $skip_lexicals{$ppname};
    write_back_stack()    unless $skip_stack{$ppname};
    # XXX finish me. this works only with >= 5.10
    runtime '{ /* pp_anoncode */',
	'  CV *cv = MUTABLE_CV(PAD_SV(PL_op->op_targ));',
	'  if (CvCLONE(cv))',
	'    cv = MUTABLE_CV(sv_2mortal(MUTABLE_SV(Perl_cv_clone(aTHX_ cv))));',
	'  EXTEND(SP,1);',
	'  PUSHs(MUTABLE_SV(cv));',
	'}';
    invalidate_lexicals() unless $skip_invalidate{$ppname};
    return $op->next;
  } else {
    default_pp(@_);
  }
}

# coverage: 35
# XXX TODO get prev op. For now saved in pp_const.
sub pp_method_named {
  my ( $op ) = @_;
  my $name = svop_or_padop_pv($op);
  # The pkg PV is at [PL_stack_base+TOPMARK+1], the previous op->sv->PV.
  my $stash = $package_pv ? $package_pv."::" : "main::";
  $name = $stash . $name;
  debug "save method_name \"$name\"\n" if $debug{op};
  svref_2object( \&{$name} )->save;

  default_pp(@_);
}

# inconsequence: gvs are not passed around on the stack
# coverage: 26,103
sub bad_pp_srefgen {
  if ($inline_ops) {
    my $op = shift;
    warn "inlining srefgen\n" if $debug{op};
    my $ppname = "pp_" . $op->name;
    #$curcop->write_back;
    #write_back_lexicals() unless $skip_lexicals{$ppname};
    #write_back_stack()    unless $skip_stack{$ppname};
    my $svobj = $stack[-1]->as_sv;
    my $sv = pop_sv();
    # XXX fix me
    runtime "{ /* pp_srefgen */
	SV* rv;
	SV* sv = $sv;";
    # sv = POPs
    #B::svref_2object(\$sv);
    if (($svobj->flags & 0xff) == $SVt_PVLV
	and B::PVLV::LvTYPE($svobj) eq ord('y'))
    {
      runtime 'if (LvTARGLEN(sv))
	    vivify_defelem(sv);
	if (!(sv = LvTARG(sv)))
	    sv = &PL_sv_undef;
	else
	    SvREFCNT_inc_void_NN(sv);';
    }
    elsif (($svobj->flags & 0xff) == $SVt_PVAV) {
      runtime 'if (!AvREAL((const AV *)sv) && AvREIFY((const AV *)sv))
	    av_reify(MUTABLE_AV(sv));
	SvTEMP_off(sv);
	SvREFCNT_inc_void_NN(sv);';
    }
    #elsif ($sv->SvPADTMP && !IS_PADGV(sv)) {
    #  runtime 'sv = newSVsv(sv);';
    #}
    else {
      runtime 'SvTEMP_off(sv);
	SvREFCNT_inc_void_NN(sv);';
    }
    runtime 'rv = sv_newmortal();
	sv_upgrade(rv, SVt_IV);
	SvRV_set(rv, sv);
	SvROK_on(rv);
        PUSHBACK;
	}';
    return $op->next;
  } else {
    default_pp(@_);
  }
}

# coverage: 9,10,27
#sub pp_refgen

# coverage: 28, 14
sub pp_rv2gv {
  my $op = shift;
  $curcop->write_back if $curcop;
  my $ppname = "pp_" . $op->name;
  write_back_lexicals() unless $skip_lexicals{$ppname};
  write_back_stack()    unless $skip_stack{$ppname};
  my $sym = doop($op);
  if ( $op->private & OPpDEREF ) {
    $init->add( sprintf("((UNOP *)$sym)->op_first = $sym;") );
    $init->add( sprintf( "((UNOP *)$sym)->op_type = %d;", $op->first->type ) );
  }
  return $op->next;
}

# coverage: 18,19,25
sub pp_sort {
  my $op     = shift;
  #my $ppname = $op->ppaddr;
  if ( $op->flags & OPf_SPECIAL && $op->flags & OPf_STACKED ) {
    # This indicates the sort BLOCK Array case
    # Ugly surgery required. sort expects as block: pushmark rv2gv leave => enter
    # pp_sort() OP *kid = cLISTOP->op_first->op_sibling;/* skip over pushmark 4 to null */
    #	    kid = cUNOPx(kid)->op_first;		/* pass rv2gv (null'ed) */
    #	    kid = cUNOPx(kid)->op_first;		/* pass leave */
    #
    #3        <0> pushmark s ->4
    #8        <@> sort lKS* ->9
    #4           <0> pushmark s ->5
    #-           <1> null sK/1 ->5
    #-              <1> ex-leave sKP ->-
    #-                 <0> enter s ->-
    #                      some code doing cmp or ncmp
    #            Example with 3 const args: print sort { bla; $b <=> $a } 1,4,3
    #5           <$> const[IV 1] s ->6
    #6           <$> const[IV 4] s ->7
    #7           <$> const[IV 3] s ->8 => sort
    #
    my $root  = $op->first->sibling->first; #leave or null
    my $start = $root->first;  #enter
    warn "sort BLOCK Array: root=",$root->name,", start=",$start->name,"\n" if $debug{op};
    my $pushmark = $op->first->save; #pushmark sibling to null
    $op->first->sibling->save; #null->first to leave
    $root->save;               #ex-leave
    my $sym = $start->save;    #enter
    my $fakeop = cc_queue( "pp_sort" . $$op, $root, $start );
    $init->add( sprintf( "(%s)->op_next = %s;", $sym, $fakeop ) );
  }
  $curcop->write_back;
  write_back_lexicals();
  write_back_stack();
  doop($op);
  return $op->next;
}

# coverage: 2-4,6,7,13,15,21,24,26,27,30,31
sub pp_gv {
  my $op = shift;
  my $gvsym;
  if ($ITHREADS) {
    $gvsym = $pad[ $op->padix ]->as_sv;
    #push @stack, ($pad[$op->padix]);
  }
  else {
    $gvsym = $op->gv->save;
    # XXX
    #my $obj = new B::Stackobj::Const($op->gv);
    #push( @stack, $obj );
  }
  write_back_stack();
  runtime("XPUSHs((SV*)$gvsym);");
  return $op->next;
}

# coverage: 2,3,4,9,11,14,20,21,23,28
sub pp_gvsv {
  my $op = shift;
  my $gvsym;
  if ($ITHREADS) {
    #debug(sprintf("OP name=%s, class=%s\n",$op->name,class($op))) if $debug{pad};
    debug( sprintf( "GVSV->padix = %d\n", $op->padix ) ) if $debug{pad};
    $gvsym = $pad[ $op->padix ]->as_sv;
    debug( sprintf( "GVSV->private = 0x%x\n", $op->private ) ) if $debug{pad};
  }
  else {
    $gvsym = $op->gv->save;
  }
  write_back_stack();
  if ( $op->private & OPpLVAL_INTRO ) {
    runtime("XPUSHs(save_scalar($gvsym));");
    #my $obj = new B::Stackobj::Const($op->gv);
    #push( @stack, $obj );
  }
  else {
    # Expects GV*, not SV* PL_curpad
    $gvsym = "(GV*)$gvsym" if $gvsym =~ /PL_curpad/;
    $PERL510
      ? runtime("XPUSHs(GvSVn($gvsym));")
      : runtime("XPUSHs(GvSV($gvsym));");
  }
  return $op->next;
}

# coverage: 16, issue44
sub pp_aelemfast {
  my $op = shift;
  my $av;
  if ($op->flags & OPf_SPECIAL) {
    my $sv = $pad[ $op->targ ]->as_sv;
    $av = $] > 5.01000 ? "MUTABLE_AV($sv)" : $sv;
  } else {
    my $gvsym;
    if ($ITHREADS) { #padop XXX if it's only a OP, no PADOP? t/CORE/op/ref.t test 36
      if ($op->can('padix')) {
        warn "padix\n";
        $gvsym = $pad[ $op->padix ]->as_sv;
      } else {
        $gvsym = 'PL_incgv'; # XXX passes, but need to investigate why. cc test 43 5.10.1
        #write_back_stack();
        #runtime("PUSHs(&PL_sv_undef);");
        #return $op->next;
      }
    }
    else { #svop
      $gvsym = $op->gv->save;
    }
    $av = "GvAV($gvsym)";
  }
  my $ix   = $op->private;
  my $lval = $op->flags & OPf_MOD;
  write_back_stack();
  runtime(
    "{ AV* av = $av;",
    "  SV** const svp = av_fetch(av, $ix, $lval);",
    "  SV *sv = (svp ? *svp : &PL_sv_undef);",
    !$lval ? "  if (SvRMAGICAL(av) && SvGMAGICAL(sv)) mg_get(sv);" : "",
    "  PUSHs(sv);",
    "}"
  );
  return $op->next;
}

# coverage: ?
sub int_binop {
  my ( $op, $operator, $unsigned ) = @_;
  if ( $op->flags & OPf_STACKED ) {
    my $right = pop_int();
    if ( @stack >= 1 ) {
      my $left = top_int();
      $stack[-1]->set_int( &$operator( $left, $right ), $unsigned );
    }
    else {
      my $sv_setxv = $unsigned ? 'sv_setuv' : 'sv_setiv';
      runtime( sprintf( "$sv_setxv(TOPs, %s);", &$operator( "TOPi", $right ) ) );
    }
  }
  else {
    my $targ  = $pad[ $op->targ ];
    my $right = B::Pseudoreg->new( "IV", "riv" );
    my $left  = B::Pseudoreg->new( "IV", "liv" );
    runtime( sprintf( "$$right = %s; $$left = %s;", pop_int(), pop_int ) );
    $targ->set_int( &$operator( $$left, $$right ), $unsigned );
    push( @stack, $targ );
  }
  return $op->next;
}

sub INTS_CLOSED ()    { 0x1 }
sub INT_RESULT ()     { 0x2 }
sub NUMERIC_RESULT () { 0x4 }

# coverage: ?
sub numeric_binop {
  my ( $op, $operator, $flags ) = @_;
  my $force_int = 0;
  $force_int ||= ( $flags & INT_RESULT );
  $force_int ||=
    (    $flags & INTS_CLOSED
      && @stack >= 2
      && valid_int( $stack[-2] )
      && valid_int( $stack[-1] ) );
  if ( $op->flags & OPf_STACKED ) {
    my $right = pop_numeric();
    if ( @stack >= 1 ) {
      my $left = top_numeric();
      if ($force_int) {
        $stack[-1]->set_int( &$operator( $left, $right ) );
      }
      else {
        $stack[-1]->set_numeric( &$operator( $left, $right ) );
      }
    }
    else {
      if ($force_int) {
        my $rightruntime = B::Pseudoreg->new( "IV", "riv" );
        runtime( sprintf( "$$rightruntime = %s;", $right ) );
        runtime(
          sprintf(
            "sv_setiv(TOPs, %s);", &$operator( "TOPi", $$rightruntime )
          )
        );
      }
      else {
        my $rightruntime = B::Pseudoreg->new( "double", "rnv" );
        runtime( sprintf( "$$rightruntime = %s;", $right ) );
        runtime(
          sprintf(
            "sv_setnv(TOPs, %s);", &$operator( "TOPn", $$rightruntime )
          )
        );
      }
    }
  }
  else {
    my $targ = $pad[ $op->targ ];
    $force_int ||= ( $targ->{type} == T_INT );
    if ($force_int) {
      my $right = B::Pseudoreg->new( "IV", "riv" );
      my $left  = B::Pseudoreg->new( "IV", "liv" );
      runtime(
        sprintf( "$$right = %s; $$left = %s;", pop_numeric(), pop_numeric ) );
      $targ->set_int( &$operator( $$left, $$right ) );
    }
    else {
      my $right = B::Pseudoreg->new( "double", "rnv" );
      my $left  = B::Pseudoreg->new( "double", "lnv" );
      runtime(
        sprintf( "$$right = %s; $$left = %s;", pop_numeric(), pop_numeric ) );
      $targ->set_numeric( &$operator( $$left, $$right ) );
    }
    push( @stack, $targ );
  }
  return $op->next;
}

# coverage: 18
sub pp_ncmp {
  my ($op) = @_;
  if ( $op->flags & OPf_STACKED ) {
    my $right = pop_numeric();
    if ( @stack >= 1 ) {
      my $left = top_numeric();
      runtime sprintf( "if (%s > %s){", $left, $right );
      $stack[-1]->set_int(1);
      $stack[-1]->write_back();
      runtime sprintf( "}else if (%s < %s ) {", $left, $right );
      $stack[-1]->set_int(-1);
      $stack[-1]->write_back();
      runtime sprintf( "}else if (%s == %s) {", $left, $right );
      $stack[-1]->set_int(0);
      $stack[-1]->write_back();
      runtime sprintf("}else {");
      $stack[-1]->set_sv("&PL_sv_undef");
      runtime "}";
    }
    else {
      my $rightruntime = B::Pseudoreg->new( "double", "rnv" );
      runtime( sprintf( "$$rightruntime = %s;", $right ) );
      runtime sprintf( qq/if ("TOPn" > %s){/, $rightruntime );
      runtime sprintf("  sv_setiv(TOPs,1);");
      runtime sprintf( qq/}else if ( "TOPn" < %s ) {/, $$rightruntime );
      runtime sprintf("  sv_setiv(TOPs,-1);");
      runtime sprintf( qq/} else if ("TOPn" == %s) {/, $$rightruntime );
      runtime sprintf("  sv_setiv(TOPs,0);");
      runtime sprintf(qq/}else {/);
      runtime sprintf("  sv_setiv(TOPs,&PL_sv_undef;");
      runtime "}";
    }
  }
  else {
    my $targ  = $pad[ $op->targ ];
    my $right = B::Pseudoreg->new( "double", "rnv" );
    my $left  = B::Pseudoreg->new( "double", "lnv" );
    runtime(
      sprintf( "$$right = %s; $$left = %s;", pop_numeric(), pop_numeric ) );
    runtime sprintf( "if (%s > %s){ /*targ*/", $$left, $$right );
    $targ->set_int(1);
    $targ->write_back();
    runtime sprintf( "}else if (%s < %s ) {", $$left, $$right );
    $targ->set_int(-1);
    $targ->write_back();
    runtime sprintf( "}else if (%s == %s) {", $$left, $$right );
    $targ->set_int(0);
    $targ->write_back();
    runtime sprintf("}else {");
    $targ->set_sv("&PL_sv_undef");
    runtime "}";
    push( @stack, $targ );
  }
  #runtime "return NULL;";
  return $op->next;
}

# coverage: ?
sub sv_binop {
  my ( $op, $operator, $flags ) = @_;
  if ( $op->flags & OPf_STACKED ) {
    my $right = pop_sv();
    if ( @stack >= 1 ) {
      my $left = top_sv();
      if ( $flags & INT_RESULT ) {
        $stack[-1]->set_int( &$operator( $left, $right ) );
      }
      elsif ( $flags & NUMERIC_RESULT ) {
        $stack[-1]->set_numeric( &$operator( $left, $right ) );
      }
      else {
        # XXX Does this work?
        runtime(
          sprintf( "sv_setsv($left, %s);", &$operator( $left, $right ) ) );
        $stack[-1]->invalidate;
      }
    }
    else {
      my $f;
      if ( $flags & INT_RESULT ) {
        $f = "sv_setiv";
      }
      elsif ( $flags & NUMERIC_RESULT ) {
        $f = "sv_setnv";
      }
      else {
        $f = "sv_setsv";
      }
      runtime( sprintf( "%s(TOPs, %s);", $f, &$operator( "TOPs", $right ) ) );
    }
  }
  else {
    my $targ = $pad[ $op->targ ];
    runtime( sprintf( "right = %s; left = %s;", pop_sv(), pop_sv ) );
    if ( $flags & INT_RESULT ) {
      $targ->set_int( &$operator( "left", "right" ) );
    }
    elsif ( $flags & NUMERIC_RESULT ) {
      $targ->set_numeric( &$operator( "left", "right" ) );
    }
    else {
      # XXX Does this work?
      runtime(sprintf("sv_setsv(%s, %s);",
                      $targ->as_sv, &$operator( "left", "right" ) ));
      $targ->invalidate;
    }
    push( @stack, $targ );
  }
  return $op->next;
}

# coverage: ?
sub bool_int_binop {
  my ( $op, $operator ) = @_;
  my $right = B::Pseudoreg->new( "IV", "riv" );
  my $left  = B::Pseudoreg->new( "IV", "liv" );
  runtime( sprintf( "$$right = %s; $$left = %s;", pop_int(), pop_int() ) );
  my $bool = B::Stackobj::Bool->new( B::Pseudoreg->new( "int", "b" ) );
  $bool->set_int( &$operator( $$left, $$right ) );
  push( @stack, $bool );
  return $op->next;
}

# coverage: ?
sub bool_numeric_binop {
  my ( $op, $operator ) = @_;
  my $right = B::Pseudoreg->new( "double", "rnv" );
  my $left  = B::Pseudoreg->new( "double", "lnv" );
  runtime(
    sprintf( "$$right = %s; $$left = %s;", pop_numeric(), pop_numeric() ) );
  my $bool = B::Stackobj::Bool->new( B::Pseudoreg->new( "int", "b" ) );
  $bool->set_numeric( &$operator( $$left, $$right ) );
  push( @stack, $bool );
  return $op->next;
}

# coverage: ?
sub bool_sv_binop {
  my ( $op, $operator ) = @_;
  runtime( sprintf( "right = %s; left = %s;", pop_sv(), pop_sv() ) );
  my $bool = B::Stackobj::Bool->new( B::Pseudoreg->new( "int", "b" ) );
  $bool->set_numeric( &$operator( "left", "right" ) );
  push( @stack, $bool );
  return $op->next;
}

# coverage: ?
sub infix_op {
  my $opname = shift;
  return sub { "$_[0] $opname $_[1]" }
}

# coverage: ?
sub prefix_op {
  my $opname = shift;
  return sub { sprintf( "%s(%s)", $opname, join( ", ", @_ ) ) }
}

BEGIN {
  my $plus_op     = infix_op("+");
  my $minus_op    = infix_op("-");
  my $multiply_op = infix_op("*");
  my $divide_op   = infix_op("/");
  my $modulo_op   = infix_op("%");
  my $lshift_op   = infix_op("<<");
  my $rshift_op   = infix_op(">>");
  my $scmp_op     = prefix_op("sv_cmp");
  my $seq_op      = prefix_op("sv_eq");
  my $sne_op      = prefix_op("!sv_eq");
  my $slt_op      = sub { "sv_cmp($_[0], $_[1]) < 0" };
  my $sgt_op      = sub { "sv_cmp($_[0], $_[1]) > 0" };
  my $sle_op      = sub { "sv_cmp($_[0], $_[1]) <= 0" };
  my $sge_op      = sub { "sv_cmp($_[0], $_[1]) >= 0" };
  my $eq_op       = infix_op("==");
  my $ne_op       = infix_op("!=");
  my $lt_op       = infix_op("<");
  my $gt_op       = infix_op(">");
  my $le_op       = infix_op("<=");
  my $ge_op       = infix_op(">=");

  #
  # XXX The standard perl PP code has extra handling for
  # some special case arguments of these operators.
  #
  sub pp_add      { numeric_binop( $_[0], $plus_op ) }
  sub pp_subtract { numeric_binop( $_[0], $minus_op ) }
  sub pp_multiply { numeric_binop( $_[0], $multiply_op ) }
  sub pp_divide   { numeric_binop( $_[0], $divide_op ) }

  sub pp_modulo      { int_binop( $_[0], $modulo_op ) }    # differs from perl's
  # http://perldoc.perl.org/perlop.html#Shift-Operators:
  # If use integer is in force then signed C integers are used,
  # else unsigned C integers are used.
  sub pp_left_shift  { int_binop( $_[0], $lshift_op, VALID_UNSIGNED ) }
  sub pp_right_shift { int_binop( $_[0], $rshift_op, VALID_UNSIGNED ) }
  sub pp_i_add       { int_binop( $_[0], $plus_op ) }
  sub pp_i_subtract  { int_binop( $_[0], $minus_op ) }
  sub pp_i_multiply  { int_binop( $_[0], $multiply_op ) }
  sub pp_i_divide    { int_binop( $_[0], $divide_op ) }
  sub pp_i_modulo    { int_binop( $_[0], $modulo_op ) }

  sub pp_eq { bool_numeric_binop( $_[0], $eq_op ) }
  sub pp_ne { bool_numeric_binop( $_[0], $ne_op ) }
  # coverage: 21
  sub pp_lt { bool_numeric_binop( $_[0], $lt_op ) }
  # coverage: 28
  sub pp_gt { bool_numeric_binop( $_[0], $gt_op ) }
  sub pp_le { bool_numeric_binop( $_[0], $le_op ) }
  sub pp_ge { bool_numeric_binop( $_[0], $ge_op ) }

  sub pp_i_eq { bool_int_binop( $_[0], $eq_op ) }
  sub pp_i_ne { bool_int_binop( $_[0], $ne_op ) }
  sub pp_i_lt { bool_int_binop( $_[0], $lt_op ) }
  sub pp_i_gt { bool_int_binop( $_[0], $gt_op ) }
  sub pp_i_le { bool_int_binop( $_[0], $le_op ) }
  sub pp_i_ge { bool_int_binop( $_[0], $ge_op ) }

  sub pp_scmp { sv_binop( $_[0], $scmp_op, INT_RESULT ) }
  sub pp_slt { bool_sv_binop( $_[0], $slt_op ) }
  sub pp_sgt { bool_sv_binop( $_[0], $sgt_op ) }
  sub pp_sle { bool_sv_binop( $_[0], $sle_op ) }
  sub pp_sge { bool_sv_binop( $_[0], $sge_op ) }
  sub pp_seq { bool_sv_binop( $_[0], $seq_op ) }
  sub pp_sne { bool_sv_binop( $_[0], $sne_op ) }
}

# coverage: 3,4,9,10,11,12,17,18,20,21,23
sub pp_sassign {
  my $op        = shift;
  my $backwards = $op->private & OPpASSIGN_BACKWARDS;
  debug( sprintf( "sassign->private=0x%x\n", $op->private ) ) if $debug{op};
  my ( $dst, $src );
  if ( @stack >= 2 ) {
    $dst = pop @stack;
    $src = pop @stack;
    ( $src, $dst ) = ( $dst, $src ) if $backwards;
    my $type = $src->{type};
    if ( $type == T_INT ) {
      $dst->set_int( $src->as_int, $src->{flags} & VALID_UNSIGNED );
    }
    elsif ( $type == T_DOUBLE ) {
      $dst->set_numeric( $src->as_numeric );
    }
    else {
      $dst->set_sv( $src->as_sv );
    }
    push( @stack, $dst );
  }
  elsif ( @stack == 1 ) {
    if ($backwards) {
      my $src  = pop @stack;
      my $type = $src->{type};
      runtime("if (PL_tainting && PL_tainted) TAINT_NOT;");
      if ( $type == T_INT ) {
        if ( $src->{flags} & VALID_UNSIGNED ) {
          runtime sprintf( "sv_setuv(TOPs, %s);", $src->as_int );
        }
        else {
          runtime sprintf( "sv_setiv(TOPs, %s);", $src->as_int );
        }
      }
      elsif ( $type == T_DOUBLE ) {
        runtime sprintf( "sv_setnv(TOPs, %s);", $src->as_double );
      }
      else {
        runtime sprintf( "sv_setsv(TOPs, %s);", $src->as_sv );
      }
      runtime("SvSETMAGIC(TOPs);");
    }
    else {
      my $dst  = $stack[-1];
      my $type = $dst->{type};
      runtime("sv = POPs;");
      runtime("MAYBE_TAINT_SASSIGN_SRC(sv);");
      if ( $type == T_INT ) {
        $dst->set_int("SvIV(sv)");
      }
      elsif ( $type == T_DOUBLE ) {
        $dst->set_double("SvNV(sv)");
      }
      else {
        runtime("SvSetMagicSV($dst->{sv}, sv);");
        $dst->invalidate;
      }
    }
  }
  else {

    # empty perl stack, both at run-time
    if ($backwards) {
      runtime("src = POPs; dst = TOPs;");
    }
    else {
      runtime("dst = POPs; src = TOPs;");
    }
    runtime(
      "MAYBE_TAINT_SASSIGN_SRC(src);", "SvSetSV(dst, src);",
      "SvSETMAGIC(dst);",              "SETs(dst);"
    );
  }
  return $op->next;
}

# coverage: ny
sub pp_preinc {
  my $op = shift;
  if ( @stack >= 1 ) {
    my $obj  = $stack[-1];
    my $type = $obj->{type};
    if ( $type == T_INT || $type == T_DOUBLE ) {
      $obj->set_int( $obj->as_int . " + 1" );
    }
    else {
      runtime sprintf( "PP_PREINC(%s);", $obj->as_sv );
      $obj->invalidate();
    }
  }
  else {
    runtime sprintf("PP_PREINC(TOPs);");
  }
  return $op->next;
}

# coverage: 1-32,35
sub pp_pushmark {
  my $op = shift;
  write_back_stack();
  runtime("PUSHMARK(sp);");
  return $op->next;
}

# coverage: 28
sub pp_list {
  my $op = shift;
  write_back_stack();
  my $gimme = gimme($op);
  if ( not defined $gimme ) {
    runtime("PP_LIST(block_gimme());");
  } elsif ( $gimme == G_ARRAY ) {    # sic
    runtime("POPMARK;");        # need this even though not a "full" pp_list
  }
  else {
    runtime("PP_LIST($gimme);");
  }
  return $op->next;
}

# coverage: 6,8,9,10,24,26,27,31,35
sub pp_entersub {
  my $op = shift;
  $curcop->write_back if $curcop;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  my $sym = doop($op);
  runtime("while (PL_op != ($sym)->op_next && PL_op != (OP*)0 ){",
          "\tPL_op = (*PL_op->op_ppaddr)(aTHX);",
          "\tSPAGAIN;}");
  $know_op = 0;
  invalidate_lexicals( REGISTER | TEMPORARY );
  return $op->next;
}

# coverage: ny
sub pp_formline {
  my $op     = shift;
  my $ppname = "pp_" . $op->name;
  write_back_lexicals() unless $skip_lexicals{$ppname};
  write_back_stack()    unless $skip_stack{$ppname};
  my $sym = doop($op);

  # See comment in pp_grepwhile to see why!
  $init->add("((LISTOP*)$sym)->op_first = $sym;");
  runtime("if (PL_op == ((LISTOP*)($sym))->op_first) {");
  save_or_restore_lexical_state( ${ $op->first } );
  runtime( sprintf( "goto %s;", label( $op->first ) ),
           "}");
  return $op->next;
}

# coverage: 2,17,21,28,30
sub pp_goto {
  my $op     = shift;
  my $ppname = "pp_" . $op->name;
  write_back_lexicals() unless $skip_lexicals{$ppname};
  write_back_stack()    unless $skip_stack{$ppname};
  my $sym = doop($op);
  runtime("if (PL_op != ($sym)->op_next && PL_op != (OP*)0){return PL_op;}");
  invalidate_lexicals() unless $skip_invalidate{$ppname};
  return $op->next;
}

# coverage: 1-39, c_argv.t 2
sub pp_enter {
  # XXX fails with simple c_argv.t 2. no cxix. Disabled for now
  if (0 and $inline_ops) {
    my $op = shift;
    warn "inlining enter\n" if $debug{op};
    $curcop->write_back if $curcop;
    if (!($op->flags & OPf_WANT)) {
      my $cxix = $#cxstack;
      if ( $cxix >= 0 ) {
        if ( $op->flags & OPf_SPECIAL ) {
          runtime "gimme = block_gimme();";
        } else {
          runtime "gimme = cxstack[cxstack_ix].blk_gimme;";
        }
      } else {
        runtime "gimme = G_SCALAR;";
      }
    } else {
      runtime "gimme = OP_GIMME(PL_op, -1);";
    }
    runtime($] >= 5.011001 and $] < 5.011004
	    ? 'ENTER_with_name("block");' : 'ENTER;',
      "SAVETMPS;",
      "PUSHBLOCK(cx, CXt_BLOCK, SP);");
    return $op->next;
  } else {
    return default_pp(@_);
  }
}

# coverage: ny
sub pp_enterwrite { pp_entersub(@_) }

# coverage: 6,8,9,10,24,26,27,31
sub pp_leavesub {
  my $op = shift;
  my $ppname = "pp_" . $op->name;
  write_back_lexicals() unless $skip_lexicals{$ppname};
  write_back_stack()    unless $skip_stack{$ppname};
  runtime("if (PL_curstackinfo->si_type == PERLSI_SORT){",
          "\tPUTBACK;return 0;",
          "}");
  doop($op);
  return $op->next;
}

# coverage: ny
sub pp_leavewrite {
  my $op = shift;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  my $sym = doop($op);

  # XXX Is this the right way to distinguish between it returning
  # CvSTART(cv) (via doform) and pop_return()?
  #runtime("if (PL_op) PL_op = (*PL_op->op_ppaddr)(aTHX);");
  runtime("SPAGAIN;");
  $know_op = 0;
  invalidate_lexicals( REGISTER | TEMPORARY );
  return $op->next;
}

# coverage: ny
sub pp_entergiven { pp_enterwrite(@_) }
# coverage: ny
sub pp_leavegiven { pp_leavewrite(@_) }

sub doeval {
  my $op = shift;
  $curcop->write_back;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  my $sym    = loadop($op);
  my $ppaddr = $op->ppaddr;
  runtime("PP_EVAL($ppaddr, ($sym)->op_next);");
  $know_op = 1;
  invalidate_lexicals( REGISTER | TEMPORARY );
  return $op->next;
}

# coverage: 12
sub pp_entereval { doeval(@_) }
# coverage: ny
sub pp_dofile    { doeval(@_) }

# coverage: 28
#pp_require is protected by pp_entertry, so no protection for it.
sub pp_require {
  my $op = shift;
  $curcop->write_back;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  my $sym = doop($op);
  runtime("while (PL_op != ($sym)->op_next && PL_op != (OP*)0 ) {",
          #(test 28).
          "  PL_op = (*PL_op->op_ppaddr)(aTHX);",
          "  SPAGAIN;",
          "}");
  $know_op = 1;
  invalidate_lexicals( REGISTER | TEMPORARY );
  return $op->next;
}

# coverage: 32
sub pp_entertry {
  my $op = shift;
  $curcop->write_back;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  my $sym = doop($op);
  $entertry_defined = 1;
  if (!$op->can("other")) { # since 5.11.4
    debug "ENTERTRY label \$op->next (no other)\n";
    my $next = $op->next;
    my $l = label( $next );
    runtime(sprintf( "PP_ENTERTRY(%s);", $l));
    push_label ($next, $next->isa('B::COP') ? 'nextstate' : 'leavetry');
  } else {
    debug "ENTERTRY label \$op->other->next\n";
    runtime(sprintf( "PP_ENTERTRY(%s);",
		     label( $op->other->next ) ) );
    invalidate_lexicals( REGISTER | TEMPORARY );
    push_label ($op->other->next, 'leavetry');
    #write_label( $op->other->next );
  }
  invalidate_lexicals( REGISTER | TEMPORARY );
  return $op->next;
}

# coverage: 32
sub pp_leavetry {
  my $op = shift;
  pop_label 'leavetry' if $labels->{'leavetry'}->[-1] and $labels->{'leavetry'}->[-1] == $op;
  default_pp($op);
  runtime("PP_LEAVETRY;");
  return $op->next;
}

# coverage: ny
sub pp_grepstart {
  my $op = shift;
  if ( $need_freetmps && $freetmps_each_loop ) {
    runtime("FREETMPS;");    # otherwise the grepwhile loop messes things up
    $need_freetmps = 0;
  }
  write_back_stack();
  my $sym  = doop($op);
  my $next = $op->next;
  $next->save;
  my $nexttonext = $next->next;
  $nexttonext->save;
  save_or_restore_lexical_state($$nexttonext);
  runtime(
    sprintf( "if (PL_op == (($sym)->op_next)->op_next) goto %s;",
      label($nexttonext) )
  );
  return $op->next->other;
}

# coverage: ny
sub pp_mapstart {
  my $op = shift;
  if ( $need_freetmps && $freetmps_each_loop ) {
    runtime("FREETMPS;");    # otherwise the mapwhile loop messes things up
    $need_freetmps = 0;
  }
  write_back_stack();

  # pp_mapstart can return either op_next->op_next or op_next->op_other and
  # we need to be able to distinguish the two at runtime.
  my $sym  = doop($op);
  my $next = $op->next;
  $next->save;
  my $nexttonext = $next->next;
  $nexttonext->save;
  save_or_restore_lexical_state($$nexttonext);
  runtime(
    sprintf( "if (PL_op == (($sym)->op_next)->op_next) goto %s;",
      label($nexttonext) )
  );
  return $op->next->other;
}

# coverage: ny
sub pp_grepwhile {
  my $op   = shift;
  my $next = $op->next;
  unshift( @bblock_todo, $next );
  write_back_lexicals();
  write_back_stack();
  my $sym = doop($op);

  # pp_grepwhile can return either op_next or op_other and we need to
  # be able to distinguish the two at runtime. Since it's possible for
  # both ops to be "inlined", the fields could both be zero. To get
  # around that, we hack op_next to be our own op (purely because we
  # know it's a non-NULL pointer and can't be the same as op_other).
  $init->add("((LOGOP*)$sym)->op_next = $sym;");
  save_or_restore_lexical_state($$next);
  runtime( sprintf( "if (PL_op == ($sym)->op_next) goto %s;", label($next) ) );
  $know_op = 0;
  return $op->other;
}

# coverage: ny
sub pp_mapwhile { pp_grepwhile(@_) }

# coverage: 24
sub pp_return {
  my $op = shift;
  write_back_lexicals( REGISTER | TEMPORARY );
  write_back_stack();
  doop($op);
  runtime( "PUTBACK;", "return PL_op;" );
  $know_op = 0;
  return $op->next;
}

sub nyi {
  my $op = shift;
  warn sprintf( "%s not yet implemented properly\n", $op->ppaddr );
  return default_pp($op);
}

# coverage: 17
sub pp_range {
  my $op    = shift;
  my $flags = $op->flags;
  if ( !( $flags & OPf_WANT ) ) {
    if ($strict) {
      error("context of range unknown at compile-time\n");
    } else {
      warn("context of range unknown at compile-time\n");
      runtime('warn("context of range unknown at compile-time");');
    }
    return default_pp($op);
  }
  write_back_lexicals();
  write_back_stack();
  unless ( ( $flags & OPf_WANT ) == OPf_WANT_LIST ) {
    # We need to save our UNOP structure since pp_flop uses
    # it to find and adjust out targ. We don't need it ourselves.
    $op->save;
    save_or_restore_lexical_state( ${ $op->other } );
    runtime sprintf( "if (SvTRUE(PL_curpad[%d])) goto %s;",
      $op->targ, label( $op->other ) );
    unshift( @bblock_todo, $op->other );
  }
  return $op->next;
}

# coverage: 17, 30
sub pp_flip {
  my $op    = shift;
  my $flags = $op->flags;
  if ( !( $flags & OPf_WANT ) ) {
    if ($strict) {
      error("context of flip unknown at compile-time\n");
    } else {
      warn("context of flip unknown at compile-time\n");
      runtime('warn("context of flip unknown at compile-time");');
    }
    return default_pp($op);
  }
  if ( ( $flags & OPf_WANT ) == OPf_WANT_LIST ) {
    return $op->first->other;
  }
  write_back_lexicals();
  write_back_stack();
  # We need to save our UNOP structure since pp_flop uses
  # it to find and adjust out targ. We don't need it ourselves.
  $op->save;
  my $ix      = $op->targ;
  my $rangeix = $op->first->targ;
  runtime(
    ( $op->private & OPpFLIP_LINENUM )
    ? "if (PL_last_in_gv && SvIV(TOPs) == IoLINES(GvIOp(PL_last_in_gv))) {"
    : "if (SvTRUE(TOPs)) {"
  );
  runtime("\tsv_setiv(PL_curpad[$rangeix], 1);");
  if ( $op->flags & OPf_SPECIAL ) {
    runtime("sv_setiv(PL_curpad[$ix], 1);");
  }
  else {
    save_or_restore_lexical_state( ${ $op->first->other } );
    runtime( "\tsv_setiv(PL_curpad[$ix], 0);",
      "\tsp--;", sprintf( "\tgoto %s;", label( $op->first->other ) ) );
  }
  runtime( "}", qq{sv_setpv(PL_curpad[$ix], "");}, "SETs(PL_curpad[$ix]);" );
  $know_op = 0;
  return $op->next;
}

# coverage: 17
sub pp_flop {
  my $op = shift;
  default_pp($op);
  $know_op = 0;
  return $op->next;
}

sub enterloop {
  my $op     = shift;
  my $nextop = $op->nextop;
  my $lastop = $op->lastop;
  my $redoop = $op->redoop;
  $curcop->write_back if $curcop;
  debug "enterloop: pushing on cxstack\n" if $debug{cxstack};
  push(
    @cxstack,
    {
      type => $PERL511 ? CXt_LOOP_PLAIN : CXt_LOOP,
      op => $op,
      "label" => $curcop->[0]->label,
      nextop  => $nextop,
      lastop  => $lastop,
      redoop  => $redoop
    }
  );
  debug sprintf("enterloop: cxstack label %s\n", $curcop->[0]->label) if $debug{cxstack};
  $nextop->save;
  $lastop->save;
  $redoop->save;
  # We need to compile the corresponding pp_leaveloop even if it's
  # never executed. This is needed to get @cxstack right.
  # Use case:  while(1) { .. }
  unshift @bblock_todo, ($lastop);
  if (0 and $inline_ops and $op->name eq 'enterloop') {
    warn "inlining enterloop\n" if $debug{op};
    # XXX = GIMME_V fails on freebsd7 5.8.8 (28)
    # = block_gimme() fails on the rest, but passes on freebsd7
    runtime "gimme = GIMME_V;"; # XXX
    if ($PERL511) {
      runtime('ENTER_with_name("loop1");',
              'SAVETMPS;',
              'ENTER_with_name("loop2");',
              'PUSHBLOCK(cx, CXt_LOOP_PLAIN, SP);',
              'PUSHLOOP_PLAIN(cx, SP);');
    } else {
      runtime('ENTER;',
              'SAVETMPS;',
              'ENTER;',
              'PUSHBLOCK(cx, CXt_LOOP, SP);',
              'PUSHLOOP(cx, 0, SP);');
    }
    return $op->next;
  } else {
    return default_pp($op);
  }
}

# coverage: 6,21,28,30
sub pp_enterloop { enterloop(@_) }
# coverage: 2
sub pp_enteriter { enterloop(@_) }

# coverage: 6,21,28,30
sub pp_leaveloop {
  my $op = shift;
  if ( !@cxstack ) {
    die "panic: leaveloop, no cxstack";
  }
  debug "leaveloop: popping from cxstack\n" if $debug{cxstack};
  pop(@cxstack);
  return default_pp($op);
}

# coverage: ?
sub pp_next {
  my $op = shift;
  my $cxix;
  if ( $op->flags & OPf_SPECIAL ) {
    $cxix = dopoptoloop();
    if ( $cxix < 0 ) {
      warn "\"next\" used outside loop\n";
      return default_pp($op); # no optimization
    }
  }
  else {
    $cxix = dopoptolabel( $op->pv );
    if ( $cxix < 0 ) {
      warn(sprintf("Label not found at compile time for \"next %s\"\n", $op->pv ));
      return default_pp($op); # no optimization
    }
  }
  default_pp($op);
  my $nextop = $cxstack[$cxix]->{nextop};
  push( @bblock_todo, $nextop );
  save_or_restore_lexical_state($$nextop);
  runtime( sprintf( "goto %s;", label($nextop) ) );
  return $op->next;
}

# coverage: ?
sub pp_redo {
  my $op = shift;
  my $cxix;
  if ( $op->flags & OPf_SPECIAL ) {
    $cxix = dopoptoloop();
    if ( $cxix < 0 ) {
      warn("\"redo\" used outside loop\n");
      return default_pp($op); # no optimization
    }
  }
  else {
    $cxix = dopoptolabel( $op->pv );
    if ( $cxix < 0 ) {
      warn(sprintf("Label not found at compile time for \"redo %s\"\n", $op->pv ));
      return default_pp($op); # no optimization
    }
  }
  default_pp($op);
  my $redoop = $cxstack[$cxix]->{redoop};
  push( @bblock_todo, $redoop );
  save_or_restore_lexical_state($$redoop);
  runtime( sprintf( "goto %s;", label($redoop) ) );
  return $op->next;
}

# coverage: issue36
sub pp_last {
  my $op = shift;
  my $cxix;
  if ( $op->flags & OPf_SPECIAL ) {
    $cxix = dopoptoloop();
    if ( $cxix < 0 ) {
      warn("\"last\" used outside loop\n");
      return default_pp($op); # no optimization
    }
  }
  else {
    $cxix = dopoptolabel( $op->pv );
    if ( $cxix < 0 ) {
      warn( sprintf("Label not found at compile time for \"last %s\"\n", $op->pv ));
      return default_pp($op); # no optimization
    }

    # XXX Add support for "last" to leave non-loop blocks
    if ( CxTYPE_no_LOOP( $cxstack[$cxix] ) ) {
      warn("Use of \"last\" for non-loop blocks is not yet implemented\n");
      return default_pp($op); # no optimization
    }
  }
  default_pp($op);
  my $lastop = $cxstack[$cxix]->{lastop}->next;
  push( @bblock_todo, $lastop );
  save_or_restore_lexical_state($$lastop);
  runtime( sprintf( "goto %s;", label($lastop) ) );
  return $op->next;
}

# coverage: 3,4
sub pp_subst {
  my $op = shift;
  write_back_lexicals();
  write_back_stack();
  my $sym      = doop($op);
  my $replroot = $op->pmreplroot;
  if ($$replroot) {
    save_or_restore_lexical_state($$replroot);
    runtime sprintf(
      "if (PL_op == ((PMOP*)(%s))%s) goto %s;",
      $sym, $PERL510 ? "->op_pmreplrootu.op_pmreplroot" : "->op_pmreplroot",
      label($replroot)
    );
    $op->pmreplstart->save;
    push( @bblock_todo, $replroot );
  }
  invalidate_lexicals();
  return $op->next;
}

# coverage: 3
sub pp_substcont {
  my $op = shift;
  write_back_lexicals();
  write_back_stack();
  doop($op);
  my $pmop = $op->other;
  warn sprintf( "substcont: op = %s, pmop = %s\n", peekop($op), peekop($pmop) )
    if $verbose;

  #   my $pmopsym = objsym($pmop);
  my $pmopsym = $pmop->save;    # XXX can this recurse?
  warn "pmopsym = $pmopsym\n" if $verbose;
  save_or_restore_lexical_state( ${ $pmop->pmreplstart } );
  runtime sprintf(
    "if (PL_op == ((PMOP*)(%s))%s) goto %s;",
    $pmopsym,
    $PERL510 ? "->op_pmstashstartu.op_pmreplstart" : "->op_pmreplstart",
    label( $pmop->pmreplstart )
  );
  push( @bblock_todo, $pmop->pmreplstart );
  invalidate_lexicals();
  return $pmop->next;
}

# coverage: issue24
# resolve the DBM library at compile-time, not at run-time
sub pp_dbmopen {
  my $op = shift;
  require AnyDBM_File;
  my $dbm = $AnyDBM_File::ISA[0];
  svref_2object( \&{"$dbm\::bootstrap"} )->save;
  return default_pp($op);
}

sub default_pp {
  my $op     = shift;
  my $ppname = "pp_" . $op->name;
  if ( $curcop and $need_curcop{$ppname} ) {
    $curcop->write_back;
  }
  write_back_lexicals() unless $skip_lexicals{$ppname};
  write_back_stack()    unless $skip_stack{$ppname};
  doop($op);

  # XXX If the only way that ops can write to a TEMPORARY lexical is
  # when it's named in $op->targ then we could call
  # invalidate_lexicals(TEMPORARY) and avoid having to write back all
  # the temporaries. For now, we'll play it safe and write back the lot.
  invalidate_lexicals() unless $skip_invalidate{$ppname};
  return $op->next;
}

sub compile_op {
  my $op     = shift;
  my $ppname = "pp_" . $op->name;
  if ( exists $ignore_op{$ppname} ) {
    return $op->next;
  }
  debug peek_stack() if $debug{stack};
  if ( $debug{op} ) {
    debug sprintf( "%s [%s]\n",
      peekop($op), $op->flags & OPf_STACKED ? "OPf_STACKED" : $op->targ );
  }
  no strict 'refs';
  if ( defined(&$ppname) ) {
    $know_op = 0;
    return &$ppname($op);
  }
  else {
    return default_pp($op);
  }
}

sub compile_bblock {
  my $op = shift;
  warn "compile_bblock: ", peekop($op), "\n" if $verbose;
  save_or_restore_lexical_state($$op);
  write_label($op);
  $know_op = 0;
  do {
    $op = compile_op($op);
    if ($] < 5.013 and ($slow_signals or ($$op and $async_signals{$op->name}))) {
      runtime("PERL_ASYNC_CHECK();");
    }
  } while ( defined($op) && $$op && !exists( $leaders->{$$op} ) );
  write_back_stack();    # boo hoo: big loss
  reload_lexicals();
  return $op;
}

sub cc {
  my ( $name, $root, $start, @padlist ) = @_;
  my $op;
  if ( $done{$$start} ) {
    warn "repeat=>" . ref($start) . " $name,\n" if $verbose;
    $decl->add( sprintf( "#define $name  %s", $done{$$start} ) );
    return;
  }
  init_pp($name);
  load_pad(@padlist);
  %lexstate = ();
  B::Pseudoreg->new_scope;
  @cxstack = ();
  if ( $debug{timings} ) {
    warn sprintf( "Basic block analysis at %s\n", timing_info );
  }
  $leaders = find_leaders( $root, $start );
  my @leaders = keys %$leaders;
  if ( $#leaders > -1 ) {
    # Don't add basic blocks of dead code.
    # It would produce errors when processing $cxstack.
    # @bblock_todo = ( values %$leaders );
    # Instead, save $root (pp_leavesub) separately,
    # because it will not get compiled if located in dead code.
    $root->save;
    unshift @bblock_todo, ($start) if $$start;
  }
  else {
    runtime("return PL_op?PL_op->op_next:0;");
  }
  if ( $debug{timings} ) {
    warn sprintf( "Compilation at %s\n", timing_info );
  }
  while (@bblock_todo) {
    $op = shift @bblock_todo;
    warn sprintf( "Considering basic block %s\n", peekop($op) ) if $verbose;
    next if !defined($op) || !$$op || $done{$$op};
    warn "...compiling it\n" if $verbose;
    do {
      $done{$$op} = $name;
      $op = compile_bblock($op);
      if ( $need_freetmps && $freetmps_each_bblock ) {
        runtime("FREETMPS;");
        $need_freetmps = 0;
      }
    } while defined($op) && $$op && !$done{$$op};
    if ( $need_freetmps && $freetmps_each_loop ) {
      runtime("FREETMPS;");
      $need_freetmps = 0;
    }
    if ( !$$op ) {
      runtime( "PUTBACK;",
               "return NULL;" );
    }
    elsif ( $done{$$op} ) {
      save_or_restore_lexical_state($$op);
      runtime( sprintf( "goto %s;", label($op) ) );
    }
  }
  if ( $debug{timings} ) {
    warn sprintf( "Saving runtime at %s\n", timing_info );
  }
  declare_pad(@padlist);
  save_runtime();
}

sub cc_recurse {
  my $ccinfo;
  my $start;
  $start = cc_queue(@_) if @_;

  while ( $ccinfo = shift @cc_todo ) {
    debug "cc(ccinfo): @$ccinfo\n" if $debug{queue};
    cc(@$ccinfo);
  }
  return $start;
}

sub cc_obj {
  my ( $name, $cvref ) = @_;
  my $cv         = svref_2object($cvref);
  my @padlist    = $cv->PADLIST->ARRAY;
  my $curpad_sym = $padlist[1]->save;
  cc_recurse( $name, $cv->ROOT, $cv->START, @padlist );
}

sub cc_main {
  my @comppadlist = comppadlist->ARRAY;
  my $curpad_nam  = $comppadlist[0]->save;
  my $curpad_sym  = $comppadlist[1]->save;
  my $init_av     = init_av->save;
  my $start = cc_recurse( "pp_main", main_root, main_start, @comppadlist );

  # Do save_unused_subs before saving inc_hv
  save_unused_subs();
  cc_recurse();

  my $warner = $SIG{__WARN__};
  save_sig($warner);

  my $inc_hv          = svref_2object( \%INC )->save;
  my $inc_av          = svref_2object( \@INC )->save;
  my $amagic_generate = amagic_generation;
  return if $errors;
  if ( !defined($module) ) {
    $init->add(
      sprintf( "PL_main_root = s\\_%x;", ${ main_root() } ),
      "PL_main_start = $start;",
      "/* save context */",
      "PL_curpad = AvARRAY($curpad_sym);",
      "PL_comppad = $curpad_sym;",
      "av_store(CvPADLIST(PL_main_cv), 0, SvREFCNT_inc($curpad_nam));",
      "av_store(CvPADLIST(PL_main_cv), 1, SvREFCNT_inc($curpad_sym));",
      "PL_initav = (AV *) $init_av;",
      "GvHV(PL_incgv) = $inc_hv;",
      "GvAV(PL_incgv) = $inc_av;",
      "PL_amagic_generation = $amagic_generate;",
    );
  }

  seek( STDOUT, 0, 0 );   #prevent print statements from BEGIN{} into the output
  fixup_ppaddr();
  output_boilerplate();
  print "\n";
  output_all("perl_init");
  output_runtime();
  print "\n";
  output_main();

  if ( defined($module) ) {
    my $cmodule = $module;
    $cmodule =~ s/::/__/g;
    print <<"EOT";

#include "XSUB.h"
XS(boot_$cmodule)
{
    dXSARGS;
    perl_init();
    ENTER;
    SAVETMPS;
    SAVEVPTR(PL_curpad);
    SAVEVPTR(PL_op);
    PL_curpad = AvARRAY($curpad_sym);
    PL_op = $start;
    pp_main(aTHX);
    FREETMPS;
    LEAVE;
    ST(0) = &PL_sv_yes;
    XSRETURN(1);
}
EOT
  }
  if ( $debug{timings} ) {
    warn sprintf( "Done at %s\n", timing_info );
  }
}

sub compile {
  my @options = @_;
  my ( $option, $opt, $arg );
OPTION:
  while ( $option = shift @options ) {
    if ( $option =~ /^-(.)(.*)/ ) {
      $opt = $1;
      $arg = $2;
    }
    else {
      unshift @options, $option;
      last OPTION;
    }
    if ( $opt eq "-" && $arg eq "-" ) {
      shift @options;
      last OPTION;
    }
    elsif ( $opt eq "o" ) {
      $arg ||= shift @options;
      open( STDOUT, ">$arg" ) or return "open '>$arg': $!\n";
    }
    elsif ( $opt eq "v" ) {
      $verbose       = 1;
      *B::C::verbose = *verbose;
    }
    elsif ( $opt eq "n" ) {
      $arg ||= shift @options;
      $module_name = $arg;
    }
    elsif ( $opt eq "u" ) {
      $arg ||= shift @options;
      mark_unused( $arg, undef );
    }
    elsif ( $opt eq "strict" ) {
      $arg ||= shift @options;
      $strict++;
    }
    elsif ( $opt eq "f" ) {
      $arg ||= shift @options;
      my $value = $arg !~ s/^no-//;
      $arg =~ s/-/_/g;
      my $ref = $optimise{$arg};
      if ( defined($ref) ) {
        $$ref = $value;
      }
      else {
        warn qq(ignoring unknown optimisation option "$arg"\n);
      }
    }
    elsif ( $opt eq "O" ) {
      $arg = 1 if $arg eq "";
      my $ref;
      foreach $ref ( values %optimise ) {
        $$ref = 0;
      }
      if ($arg >= 2) {
        $freetmps_each_loop = 1;
        $B::C::destruct = 0 unless $] < 5.008; # fast_destruct
      }
      if ( $arg >= 1 ) {
        $freetmps_each_bblock = 1 unless $freetmps_each_loop;
      }
    }
    elsif ( $opt eq "m" ) {
      $arg ||= shift @options;
      $module = $arg;
      mark_unused( $arg, undef );
    }
    elsif ( $opt eq "p" ) {
      $arg ||= shift @options;
      $patchlevel = $arg;
    }
    elsif ( $opt eq "D" ) {
      $arg ||= shift @options;
      $verbose++;
      $arg = 'oOscprSqlt' if $arg eq 'full';
      foreach $arg ( split( //, $arg ) ) {
        if ( $arg eq "o" ) {
          B->debug(1);
        }
        elsif ( $arg eq "O" ) {
          $debug{op}++;
        }
        elsif ( $arg eq "s" ) {
          $debug{stack}++;
        }
        elsif ( $arg eq "c" ) {
          $debug{cxstack}++;
        }
        elsif ( $arg eq "p" ) {
          $debug{pad}++;
        }
        elsif ( $arg eq "r" ) {
          $debug{runtime}++;
        }
        elsif ( $arg eq "S" ) {
          $debug{shadow}++;
        }
        elsif ( $arg eq "q" ) {
          $debug{queue}++;
        }
        elsif ( $arg eq "l" ) {
          $debug{lineno}++;
        }
        elsif ( $arg eq "t" ) {
          $debug{timings}++;
        }
        elsif ( $arg eq "F" and eval "require B::Flags;" ) {
          $debug{flags}++;
          $B::C::debug{flags}++;
        }
      }
    }
  }

  # rgs didn't want opcodes to be added to Opcode. So I added it to a
  # seperate Opcodes.
  eval { require Opcodes; };
  if (!$@ and $Opcodes::VERSION) {
    my $MAXO = Opcodes::opcodes();
    for (0..$MAXO-1) {
      no strict 'refs';
      my $ppname = "pp_".Opcodes::opname($_);
      # opflags n: no args, no return values. don't need save/restore stack
      # But pp_enter, pp_leave use/change global stack.
      next if $ppname eq 'pp_enter' || $ppname eq 'pp_leave';
      $no_stack{$ppname} = 1
        if Opcodes::opflags($_) & 512;
      # XXX More Opcodes options to be added later
    }
  }
  #if ($debug{op}) {
  #  warn "no_stack: ",join(" ",sort keys %no_stack),"\n";
  #}

  # Set some B::C optimizations.
  # optimize_ppaddr is not needed with B::CC as CC does it even better.
  for (qw(optimize_warn_sv save_data_fh av_init save_sig destruct),
       $PERL510 ? () : "pv_copy_on_grow")
  {
    no strict 'refs';
    ${"B::C::$_"} = 1;
  }
  if (!$B::C::Flags::have_independent_comalloc) {
    $B::C::av_init = 1;
    $B::C::av_init2 = 0;
  } else {
    $B::C::av_init = 0;
    $B::C::av_init2 = 1;
  }
  init_sections();
  $init = B::Section->get("init");
  $decl = B::Section->get("decl");

  if (@options) {
    return sub {
      my ( $objname, $ppname );
      foreach $objname (@options) {
        $objname = "main::$objname" unless $objname =~ /::/;
        ( $ppname = $objname ) =~ s/^.*?:://;
        eval "cc_obj(qq(pp_sub_$ppname), \\&$objname)";
        die "cc_obj(qq(pp_sub_$ppname, \\&$objname) failed: $@" if $@;
        return if $errors;
      }
      my $warner = $SIG{__WARN__};
      save_sig($warner);
      fixup_ppaddr();
      output_boilerplate();
      print "\n";
      output_all( $module_name || "init_module" );
      output_runtime();
    }
  }
  else {
    return sub { cc_main() };
  }
}

1;

__END__

=head1 NAME

B::CC - Perl compiler's optimized C translation backend

=head1 SYNOPSIS

	perl -MO=CC[,OPTIONS] foo.pl

=head1 DESCRIPTION

This compiler backend takes Perl source and generates C source code
corresponding to the flow of your program with unrolled ops and optimised
stack handling and lexicals variable types. In other words, this backend is
somewhat a "real" compiler in the sense that many people think about
compilers. Note however that, currently, it is a very poor compiler in that
although it generates (mostly, or at least sometimes) correct code, it
performs relatively few optimisations.  This will change as the compiler
develops. The result is that running an executable compiled with this backend
may start up more quickly than running the original Perl program (a feature
shared by the B<C> compiler backend--see L<B::C>) and may also execute
slightly faster. This is by no means a good optimising compiler--yet.

=head1 OPTIONS

If there are any non-option arguments, they are taken to be
names of objects to be saved (probably doesn't work properly yet).
Without extra arguments, it saves the main program.

=over 4

=item B<-ofilename>

Output to filename instead of STDOUT

=item B<-v>

Verbose compilation (prints a few compilation stages).

=item B<-->

Force end of options

=item B<-uPackname>

Force apparently unused subs from package Packname to be compiled.
This allows programs to use eval "foo()" even when sub foo is never
seen to be used at compile time. The down side is that any subs which
really are never used also have code generated. This option is
necessary, for example, if you have a signal handler foo which you
initialise with C<$SIG{BAR} = "foo">.  A better fix, though, is just
to change it to C<$SIG{BAR} = \&foo>. You can have multiple B<-u>
options. The compiler tries to figure out which packages may possibly
have subs in which need compiling but the current version doesn't do
it very well. In particular, it is confused by nested packages (i.e.
of the form C<A::B>) where package C<A> does not contain any subs.

=item B<-mModulename>

Instead of generating source for a runnable executable, generate
source for an XSUB module. The boot_Modulename function (which
DynaLoader can look for) does the appropriate initialisation and runs
the main part of the Perl source that is being compiled.

=item B<-strict>

Fail with compile-time errors, which are otherwise deferred to run-time
warnings.  This happens only for range and flip without compile-time context.

=item B<-D>

Debug options (concatenated or separate flags like C<perl -D>).
Verbose debugging options are crucial, because we have no interactive
debugger at the early CHECK step, where the compilation happens.

=item B<-Dr>

Writes debugging output to STDERR just as it's about to write to the
program's runtime (otherwise writes debugging info as comments in
its C output).

=item B<-DO>

Outputs each OP as it's compiled

=item B<-Ds>

Outputs the contents of the shadow stack at each OP

=item B<-Dp>

Outputs the contents of the shadow pad of lexicals as it's loaded for
each sub or the main program.

=item B<-Dq>

Outputs the name of each fake PP function in the queue as it's about
to process it.

=item B<-Dl>

Output the filename and line number of each original line of Perl
code as it's processed (C<pp_nextstate>).

=item B<-Dt>

Outputs timing information of compilation stages.

=item B<-DF>

Add Flags info to the code.

=item B<-f>C<OPTIM>

Force optimisations on or off one at a time.

=item B<-ffreetmps-each-bblock>

Delays FREETMPS from the end of each statement to the end of the each
basic block.

=item B<-ffreetmps-each-loop>

Delays FREETMPS from the end of each statement to the end of the group
of basic blocks forming a loop. At most one of the freetmps-each-*
options can be used.

=item B<-fno-inline-ops>

Do not inline calls to certain small pp ops.

Most of the inlinable ops were already inlined.
Turns off inlining for some new ops.

AUTOMATICALLY inlined:

pp_null pp_stub pp_unstack pp_and pp_andassign pp_or pp_orassign pp_cond_expr
pp_padsv pp_const pp_nextstate pp_dbstate pp_rv2gv pp_sort pp_gv pp_gvsv
pp_aelemfast pp_ncmp pp_add pp_subtract pp_multiply pp_divide pp_modulo
pp_left_shift pp_right_shift pp_i_add pp_i_subtract pp_i_multiply pp_i_divide
pp_i_modulo pp_eq pp_ne pp_lt pp_gt pp_le pp_ge pp_i_eq pp_i_ne pp_i_lt
pp_i_gt pp_i_le pp_i_ge pp_scmp pp_slt pp_sgt pp_sle pp_sge pp_seq pp_sne
pp_sassign pp_preinc pp_pushmark pp_list pp_entersub pp_formline pp_goto
pp_enterwrite pp_leavesub pp_leavewrite pp_entergiven pp_leavegiven
pp_entereval pp_dofile pp_require pp_entertry pp_leavetry pp_grepstart
pp_mapstart pp_grepwhile pp_mapwhile pp_return pp_range pp_flip pp_flop
pp_enterloop pp_enteriter pp_leaveloop pp_next pp_redo pp_last pp_subst
pp_substcont

DONE with -finline-ops:

pp_enter pp_reset pp_regcreset pp_stringify

TODO with -finline-ops:

pp_anoncode pp_wantarray pp_srefgen pp_refgen pp_ref pp_trans pp_schop pp_chop
pp_schomp pp_chomp pp_not pp_sprintf pp_anonlist pp_shift pp_once pp_lock
pp_rcatline pp_close pp_time pp_alarm pp_av2arylen: no lvalue, pp_length: no
magic

=item B<-fomit-taint>

Omits generating code for handling perl's tainting mechanism.

=item B<-fslow-signals>

Add PERL_ASYNC_CHECK after every op as in the old Perl runloop before 5.13.

perl "Safe signals" check the state of incoming signals after every op.
See L<http://perldoc.perl.org/perlipc.html#Deferred-Signals-(Safe-Signals)>
We trade safety for more speed and delay the execution of non-IO signals
(IO signals are already handled in PerlIO) from after every single Perl op
to the same ops as used in 5.13.

Only with -fslow-signals we get the old slow and safe behaviour.

=item B<-On>

Optimisation level (n = 0, 1, 2). B<-O> means B<-O1>.

The following L<B::C> optimisations are applied automatically:

optimize_warn_sv save_data_fh av-init2|av_init save_sig destruct
pv_copy_on_grow

B<-O1> sets B<-ffreetmps-each-bblock>.

B<-O2> adds B<-ffreetmps-each-loop> and B<-fno-destruct> from L<B::C>.

B<-fomit-taint> and B<-fslow-signals> must be set explicitly.

=back

=head1 EXAMPLES

        perl -MO=CC,-O2,-ofoo.c foo.pl
        perl cc_harness -o foo foo.c

Note that C<cc_harness> lives in the C<B> subdirectory of your perl
library directory. The utility called C<perlcc> may also be used to
help make use of this compiler.

        perl -MO=CC,-mFoo,-oFoo.c Foo.pm
        perl cc_harness -shared -c -o Foo.so Foo.c

=head1 BUGS

Plenty. Current status: experimental.

=head1 DIFFERENCES

These aren't really bugs but they are constructs which are heavily
tied to perl's compile-and-go implementation and with which this
compiler backend cannot cope.

=head2 Loops

Standard perl calculates the target of "next", "last", and "redo"
at run-time. The compiler calculates the targets at compile-time.
For example, the program

    sub skip_on_odd { next NUMBER if $_[0] % 2 }
    NUMBER: for ($i = 0; $i < 5; $i++) {
        skip_on_odd($i);
        print $i;
    }

produces the output

    024

with standard perl but gives a compile-time error with the compiler.

=head2 Context of ".."

The context (scalar or array) of the ".." operator determines whether
it behaves as a range or a flip/flop. Standard perl delays until
runtime the decision of which context it is in but the compiler needs
to know the context at compile-time. For example,

    @a = (4,6,1,0,0,1);
    sub range { (shift @a)..(shift @a) }
    print range();
    while (@a) { print scalar(range()) }

generates the output

    456123E0

with standard Perl but gives a run-time warning with compiled Perl.

If the option B<-strict> is used it gives a compile-time error.

=head2 Arithmetic

Compiled Perl programs use native C arithmetic much more frequently
than standard perl. Operations on large numbers or on boundary
cases may produce different behaviour.

=head2 Deprecated features

Features of standard perl such as C<$[> which have been deprecated
in standard perl since Perl5 was released have not been implemented
in the compiler.

=head1 AUTHORS

Malcolm Beattie C<MICB at cpan.org> I<(retired)>,
Reini Urban C<perl-compiler@googlegroups.com>
Heinz Knutzen C<heinz.knutzen at gmx.de>

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 2
#   fill-column: 78
# End:
# vim: expandtab shiftwidth=2:
