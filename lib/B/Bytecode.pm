# B::Bytecode.pm
# Copyright (c) 1994-1999 Malcolm Beattie. All rights reserved.
# Copyright (c) 2003 Enache Adrian. All rights reserved.
# Copyright (c) 2008,2009,2010 Reini Urban <rurban@cpan.org>. All rights reserved.
# This module is free software; you can redistribute and/or modify
# it under the same terms as Perl itself.

# Based on the original Bytecode.pm module written by Malcolm Beattie.
#
# Reviving 5.6 support here is work in progress:
#   So far the original is used instead, even if the list of failed tests
#   is impressive: 3,6,8..10,12,15,16,18,25..28. Pretty broken.

package B::Bytecode;

our $VERSION = '1.09';

#use 5.008;
use B qw(class main_cv main_root main_start
	 begin_av init_av end_av cstring comppadlist
	 OPf_SPECIAL OPf_STACKED OPf_MOD
	 OPpLVAL_INTRO SVf_READONLY SVf_ROK);
use B::Assembler qw(asm newasm endasm);

BEGIN {
  if ( $] < 5.009 ) {
    B::Asmdata->import(qw(@specialsv_name @optype));
    eval q[
      sub SVp_NOK() {}; # unused
      sub SVf_NOK() {}; # unused
   ];
  }
  else {
    B->import(qw(SVp_NOK SVf_NOK @specialsv_name @optype));
  }
  if ( $] > 5.007 ) {
    B->import(qw(defstash curstash inc_gv dowarn
		 warnhook diehook SVt_PVGV
		 SVf_FAKE));
  } else {
    B->import(qw(walkoptree walksymtable));
  }
}
use strict;
use Config;
use B::Concise;

#################################################

my $PERL56  = ( $] <  5.008001 );
my $PERL510 = ( $] >= 5.009005 );
my $PERL511 = ( $] >= 5.011 );
my $PERL513 = ( $] >= 5.013002 );
my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
our ($quiet, %debug);
my ( $varix, $opix, $savebegins, %walked, %files, @cloop );
my %strtab  = ( 0, 0 );
my %svtab   = ( 0, 0 );
my %optab   = ( 0, 0 );
my %spectab = $PERL56 ? () : ( 0, 0 ); # we need the special Nullsv on 5.6 (?)
my $tix     = $PERL56 ? 0 : 1;
my %ops     = ( 0, 0 );
my @packages;    # list of packages to compile. 5.6 only

# sub asm ($;$$) { }
sub nice ($) { }

my %optype_enum;
my ($SVt_PV, $SVt_PVGV, $SVf_FAKE, $POK);
if ($PERL56) {
  sub dowarn {};
  $SVt_PV = 4;
  $SVt_PVGV = 13;
  $SVf_FAKE = 0x00100000;
  $POK = 0x00040000 | 0x04000000;
  sub MAGICAL56 { $_[0]->FLAGS & 0x000E000 } #(SVs_GMG|SVs_SMG|SVs_RMG)
} else {
  no strict 'subs';
  $SVt_PV = 4;
  $SVt_PVGV = SVt_PVGV;
  $SVf_FAKE = SVf_FAKE;
}
for ( my $i = 0 ; $i < @optype ; $i++ ) {
  $optype_enum{ $optype[$i] } = $i;
}

BEGIN {
  my $ithreads = $Config{'useithreads'} eq 'define';
  eval qq{
	sub ITHREADS() { $ithreads }
	sub VERSION() { $] }
    };
  die $@ if $@;
}


#################################################

# This is for -S commented assembler output
sub op_flags {
  return '' if $quiet;
  # B::Concise::op_flags($_[0]); # too terse
  # common flags (see BASOP.op_flags in op.h)
  my ($x) = @_;
  my (@v);
  push @v, "WANT_VOID"   if ( $x & 3 ) == 1;
  push @v, "WANT_SCALAR" if ( $x & 3 ) == 2;
  push @v, "WANT_LIST"   if ( $x & 3 ) == 3;
  push @v, "KIDS"        if $x & 4;
  push @v, "PARENS"      if $x & 8;
  push @v, "REF"         if $x & 16;
  push @v, "MOD"         if $x & 32;
  push @v, "STACKED"     if $x & 64;
  push @v, "SPECIAL"     if $x & 128;
  return join( ",", @v );
}

# This is also for -S commented assembler output
sub sv_flags {
  return '' if $quiet or $B::Concise::VERSION < 0.74;    # or ($] == 5.010);
  return '' unless $debug{Comment};
  return 'B::SPECIAL' if $_[0]->isa('B::SPECIAL');
  my ($sv) = @_;
  my %h;

  # TODO: Check with which Concise and B versions this works. 5.10.0 fails.
  # B::Concise 0.66 fails also
  sub B::Concise::fmt_line { return shift; }
  %h = B::Concise::concise_op( $ops{ $tix - 1 } ) if ref $ops{ $tix - 1 };
  B::Concise::concise_sv( $_[0], \%h, 0 );
}

sub pvstring {
  my $pv = shift;
  defined($pv) ? cstring( $pv . "\0" ) : "\"\"";
}

sub pvix {
  my $str = pvstring shift;
  my $ix  = $strtab{$str};
  defined($ix) ? $ix : do {
    asm "newpv", $str;
    asm "stpv", $strtab{$str} = $tix;
    $tix++;
  }
}

sub B::OP::ix {
  my $op = shift;
  my $ix = $optab{$$op};
  defined($ix) ? $ix : do {
    nice "[" . $op->name . " $tix]";
    $ops{$tix} = $op;
    # Note: This left-shift 7 encoding of the optype has nothing to do with OCSHIFT in opcode.pl
    # The counterpart is hardcoded in Byteloader/bytecode.h: BSET_newopx
    my $arg = $PERL56 ? $optype_enum{class($op)} : $op->size | $op->type << 7;
    my $opsize = $PERL56 ? '?' : $op->size;
    if (ref($op) eq 'B::OP') { # check wrong BASEOPs
      # [perl #80622] Introducing the entrytry hack, needed since 5.12, fixed with 5.13.8 a425677
      #   ck_eval upgrades the UNOP entertry to a LOGOP, but B gets us just a B::OP (BASEOP).
      #   op->other points to the leavetry op, which is needed for the eval scope.
      if ($op->name eq 'entertry') {
	$opsize = $op->size + (2*$Config{ptrsize});
	$arg = $PERL56 ? $optype_enum{LOGOP} : $opsize | $optype_enum{LOGOP} << 7;
        warn "[perl #80622] Upgrading entertry from BASEOP to LOGOP...\n"
	  unless $quiet;
        bless $op, 'B::LOGOP';
      } elsif ($op->name eq 'aelemfast') {
        if (0) {
          my $class = ITHREADS ? 'PADOP' : 'SVOP';
          my $type  = ITHREADS ? $optype_enum{PADOP} : $optype_enum{SVOP};
          $opsize = $op->size + $Config{ptrsize};
          $arg = $PERL56 ? $type : $opsize | $type << 7;
          warn "Upgrading aelemfast from BASEOP to $class...\n"
            unless $quiet;
          bless $op, "B::$class";
        }
      } elsif ($DEBUGGING) { # only needed when we have to check for new wrong BASEOP's
	if (eval "require Opcodes;") {
	  my $class = Opcodes::opclass($op->type);
	  if ($class > 0) {
	    my $classname = $optype[$class];
	    my $name = $op->name;
            warn "Upgrading $name BASEOP to $classname...\n";
	    bless $op, "B::".$classname if $classname;
	  }
	} else {
          # 5.10 only
	  my %baseops = map { $_ => 1} qw(3 184 2 5 6 7 8 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 181 182 183 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255 256 257 258 259 260 261 262 263 264 265 266 267 268 269 270 271 272 273 274 275 276 277 278 279 280 281 282 283 284 285 286 287 288 289 290 291 292 295 296 297 298 300 301 302 303 306 307 308 309 310 311 312 313 314 315 316 317 318 319 320 321 322 323 324 325 326 327 328 330 331 333 334 336 337 339 340 341 342 347 348 352 353 358 359 360);
	  warn "unknown OP class for ".$op->name."\n" unless $baseops{$op->type};
	}
      }
    }
    B::Assembler::maxopix($tix) if $debug{A};
    asm "newopx", $arg, sprintf( "$arg=size:%s,type:%d", $opsize, $op->type );
    asm "stop", $tix if $PERL56;
    $optab{$$op} = $opix = $ix = $tix++;
    $op->bsave($ix);
    $ix;
  }
}

sub B::SPECIAL::ix {
  my $spec = shift;
  my $ix   = $spectab{$$spec};
  defined($ix) ? $ix : do {
    asm "ldspecsvx", $$spec, $specialsv_name[$$spec];
    asm "stsv", $tix if $PERL56;
    $spectab{$$spec} = $varix = $tix++;
  }
}

sub B::SV::ix {
  my $sv = shift;
  my $ix = $svtab{$$sv};
  defined($ix) ? $ix : do {
    nice '[' . class($sv) . ']';
    B::Assembler::maxsvix($tix) if $debug{A};
    asm "newsvx", $sv->FLAGS, $debug{Comment} ? sv_flags($sv) : '';
    asm "stsv", $tix if $PERL56;
    $svtab{$$sv} = $varix = $ix = $tix++;

    #nice "\tsvtab ".$$sv." => bsave(".$ix.");
    $sv->bsave($ix);
    $ix;
  }
}

sub B::GV::ix {
  my ( $gv, $desired ) = @_;
  my $ix = $svtab{$$gv};
  defined($ix) ? $ix : do {
    if ( $debug{G} and !$PERL510 ) {
      eval "require B::Debug;";
      $gv->B::GV::debug;
    }
    if ( ( $PERL510 and $gv->isGV_with_GP )
      or ( !$PERL510 and !$PERL56 and $gv->GP ) )
    {    # only gv with gp
      my ( $svix, $avix, $hvix, $cvix, $ioix, $formix );
      nice "[GV]";

      # 510 without debugging misses B::SPECIAL::NAME
      my $name;
      if ( $PERL510
        and ( $gv->STASH->isa('B::SPECIAL') or $gv->isa('B::SPECIAL') ) )
      {
        $name = '_';
        return 0;
      }
      else {
        $name = $gv->STASH->NAME . "::"
          . ( class($gv) eq 'B::SPECIAL' ? '_' : $gv->NAME );
      }
      asm "gv_fetchpvx", cstring $name;
      asm "stsv", $tix if $PERL56;
      $svtab{$$gv} = $varix = $ix = $tix++;
      asm "sv_flags",  $gv->FLAGS;
      asm "sv_refcnt", $gv->REFCNT;
      asm "xgv_flags", $gv->GvFLAGS;

      asm "gp_refcnt", $gv->GvREFCNT;
      asm "load_glob", $ix if $name eq "CORE::GLOBAL::glob";
      return $ix
        unless $desired || desired $gv;
      $svix = $gv->SV->ix;
      $avix = $gv->AV->ix;
      $hvix = $gv->HV->ix;

      # XXX {{{{
      my $cv = $gv->CV;
      $cvix = $$cv && defined $files{ $cv->FILE } ? $cv->ix : 0;
      my $form = $gv->FORM;
      $formix = $$form && defined $files{ $form->FILE } ? $form->ix : 0;

      $ioix = $name !~ /STDOUT$/ ? $gv->IO->ix : 0;

      # }}}} XXX

      nice "-GP-", asm "ldsv", $varix = $ix, sv_flags($gv) unless $ix == $varix;
      asm "gp_sv", $svix, sv_flags( $gv->SV );
      asm "gp_av", $avix, sv_flags( $gv->AV );
      asm "gp_hv", $hvix, sv_flags( $gv->HV );
      asm "gp_cv", $cvix, sv_flags( $gv->CV );
      asm "gp_io", $ioix;
      asm "gp_cvgen", $gv->CVGEN;
      asm "gp_form",  $formix;
      asm "gp_file",  pvix $gv->FILE;
      asm "gp_line",  $gv->LINE;
      asm "formfeed", $svix if $name eq "main::\cL";
    }
    else {
      nice "[GV]";
      asm "newsvx", $gv->FLAGS, $debug{Comment} ? sv_flags($gv) : '';
      asm "stsv", $tix if $PERL56;
      $svtab{$$gv} = $varix = $ix = $tix++;
      if ( !$PERL510 ) {
        #GV_without_GP has no GvFlags
        asm "xgv_flags", $gv->GvFLAGS;
      }
      if ( !$PERL510 and !$PERL56 and $gv->STASH ) {
        my $stashix = $gv->STASH->ix;
        asm "xgv_stash", $stashix;
      }
      if ($PERL510 and $gv->FLAGS & 0x40000000) { # SVpbm_VALID
        my $bm = bless $gv, "B::BM";
        $bm->bsave($ix); # also saves magic
      } else {
        $gv->B::PVMG::bsave($ix);
      }
    }
    $ix;
  }
}

sub B::HV::ix {
  my $hv = shift;
  my $ix = $svtab{$$hv};
  defined($ix) ? $ix : do {
    my ( $ix, $i, @array );
    my $name = $hv->NAME;
    if ($name) {
      nice "[STASH]";
      asm "gv_stashpvx", cstring $name;
      asm "ldsv", $tix if $PERL56;
      asm "sv_flags",    $hv->FLAGS;
      $svtab{$$hv} = $varix = $ix = $tix++;
      asm "xhv_name", pvix $name;

      # my $pmrootix = $hv->PMROOT->ix;	# XXX
      asm "ldsv", $varix = $ix unless $ix == $varix;

      # asm "xhv_pmroot", $pmrootix;	# XXX
    }
    else {
      nice "[HV]";
      asm "newsvx", $hv->FLAGS, $debug{Comment} ? sv_flags($hv) : '';
      asm "stsv", $tix if $PERL56;
      $svtab{$$hv} = $varix = $ix = $tix++;
      my $stashix = $hv->SvSTASH->ix;
      for ( @array = $hv->ARRAY ) {
        next if $i = not $i;
        $_ = $_->ix;
      }
      nice "-HV-", asm "ldsv", $varix = $ix unless $ix == $varix;
      ( $i = not $i ) ? asm( "newpv", pvstring $_) : asm( "hv_store", $_ )
        for @array;
      if ( VERSION < 5.009 ) {
        asm "xnv", $hv->NVX;
      }
      asm "xmg_stash", $stashix;
      asm( "xhv_riter", $hv->RITER ) if VERSION < 5.009;
    }
    asm "sv_refcnt", $hv->REFCNT;
    $ix;
  }
}

sub B::NULL::ix {
  my $sv = shift;
  $$sv ? $sv->B::SV::ix : 0;
}

sub B::NULL::opwalk { 0 }

#################################################

sub B::NULL::bsave {
  my ( $sv, $ix ) = @_;

  nice '-' . class($sv) . '-', asm "ldsv", $varix = $ix, sv_flags($sv)
    unless $ix == $varix;
  if ($PERL56) {
    asm "stsv", $ix;
  } else {
    asm "sv_refcnt", $sv->REFCNT;
  }
}

sub B::SV::bsave;
*B::SV::bsave = *B::NULL::bsave;

sub B::RV::bsave {
  my ( $sv, $ix ) = @_;
  my $rvix = $sv->RV->ix;
  $sv->B::NULL::bsave($ix);
  # RV with DEBUGGING already requires sv_flags before SvRV_set
  asm "sv_flags", $sv->FLAGS;
  asm "xrv", $rvix;
}

sub B::PV::bsave {
  my ( $sv, $ix ) = @_;
  $sv->B::NULL::bsave($ix);
  if ($PERL56) {
    #$sv->B::SV::bsave;
    if ($sv->FLAGS & $POK) {
      asm  "newpv", pvstring $sv->PV ;
      asm  "xpv";
    }
  } else {
    asm "newpv", pvstring $sv->PVBM;
    asm "xpv";
  }
}

sub B::IV::bsave {
  my ( $sv, $ix ) = @_;
  return $sv->B::RV::bsave($ix)
    if $PERL511 and $sv->FLAGS & B::SVf_ROK;
  $sv->B::NULL::bsave($ix);
  if ($PERL56) {
    asm $sv->needs64bits ? "xiv64" : "xiv32", $sv->IVX;
  } else {
    asm "xiv", $sv->IVX;
  }
}

sub B::NV::bsave {
  my ( $sv, $ix ) = @_;
  $sv->B::NULL::bsave($ix);
  asm "xnv", sprintf "%.40g", $sv->NVX;
}

sub B::PVIV::bsave {
  my ( $sv, $ix ) = @_;
  if ($PERL56) {
    $sv->B::PV::bsave($ix);
  } else {
      $sv->POK ? $sv->B::PV::bsave($ix)
    : $sv->ROK ? $sv->B::RV::bsave($ix)
    :            $sv->B::NULL::bsave($ix);
  }
  if ($PERL510) { # See note below in B::PVNV::bsave
    return if $sv->isa('B::AV');
    return if $sv->isa('B::HV');
    return if $sv->isa('B::CV');
    return if $sv->isa('B::GV');
    return if $sv->isa('B::IO');
    return if $sv->isa('B::FM');
  }
  bwarn( sprintf( "PVIV sv:%s flags:0x%x", class($sv), $sv->FLAGS ) )
    if $debug{M};

  if ($PERL56) {
    my $iv = $sv->IVX;
    asm $sv->needs64bits ? "xiv64" : "xiv32", $iv;
  } else {
    # PVIV GV 8009, GV flags & (4000|8000) illegal (SVpgv_GP|SVp_POK)
    asm "xiv", !ITHREADS
      && $sv->FLAGS & ( $SVf_FAKE | SVf_READONLY ) ? "0 # but true" : $sv->IVX;
  }
}

sub B::PVNV::bsave {
  my ( $sv, $ix ) = @_;
  $sv->B::PVIV::bsave($ix);
  if ($PERL510) {
    # getting back to PVMG
    return if $sv->isa('B::AV');
    return if $sv->isa('B::HV');
    return if $sv->isa('B::CV');
    return if $sv->isa('B::FM');
    return if $sv->isa('B::GV');
    return if $sv->isa('B::IO');

    # cop_seq range instead of a double. (IV, NV)
    unless ($sv->FLAGS & (SVf_NOK|SVp_NOK)) {
      asm "cop_seq_low", $sv->COP_SEQ_RANGE_LOW;
      asm "cop_seq_high", $sv->COP_SEQ_RANGE_HIGH;
      return;
    }
  }
  asm "xnv", sprintf "%.40g", $sv->NVX;
}

sub B::PVMG::domagic {
  my ( $sv, $ix ) = @_;
  nice '-MAGICAL-'; # XXX TODO no empty line before
  my @mglist = $sv->MAGIC;
  my ( @mgix, @namix );
  for (@mglist) {
    push @mgix, $_->OBJ->ix;
    push @namix, $_->PTR->ix if $_->LENGTH == B::HEf_SVKEY;
  }

  nice '-' . class($sv) . '-', asm "ldsv", $varix = $ix unless $ix == $varix;
  for (@mglist) {
    asm "sv_magic", cstring $_->TYPE;
    asm "mg_obj",   shift @mgix;
    my $length = $_->LENGTH;
    if ( $length == B::HEf_SVKEY and !$PERL56) {
      asm "mg_namex", shift @namix;
    }
    elsif ($length) {
      asm "newpv", pvstring $_->PTR;
      $PERL56
        ? asm "mg_pv"
        : asm "mg_name";
    }
  }
}

sub B::PVMG::bsave {
  my ( $sv, $ix ) = @_;
  my $stashix = $sv->SvSTASH->ix;
  $sv->B::PVNV::bsave($ix);
  asm "xmg_stash", $stashix;
  # XXX added SV->MAGICAL to 5.6 for compat
  $sv->domagic($ix) if $PERL56 ? MAGICAL56($sv) : $sv->MAGICAL;
}

sub B::PVLV::bsave {
  my ( $sv, $ix ) = @_;
  my $targix = $sv->TARG->ix;
  $sv->B::PVMG::bsave($ix);
  asm "xlv_targ",    $targix unless $PERL56; # XXX really? xlv_targ IS defined there
  asm "xlv_targoff", $sv->TARGOFF;
  asm "xlv_targlen", $sv->TARGLEN;
  asm "xlv_type",    $sv->TYPE;
}

sub B::BM::bsave {
  my ( $sv, $ix ) = @_;
  $sv->B::PVMG::bsave($ix);
  asm "xpv_cur",      $sv->CUR if $] > 5.008;
  asm "xbm_useful",   $sv->USEFUL;
  asm "xbm_previous", $sv->PREVIOUS;
  asm "xbm_rare",     $sv->RARE;
}

sub B::IO::bsave {
  my ( $io, $ix ) = @_;
  my $topix    = $io->TOP_GV->ix;
  my $fmtix    = $io->FMT_GV->ix;
  my $bottomix = $io->BOTTOM_GV->ix;
  $io->B::PVMG::bsave($ix);
  asm "xio_lines",       $io->LINES;
  asm "xio_page",        $io->PAGE;
  asm "xio_page_len",    $io->PAGE_LEN;
  asm "xio_lines_left",  $io->LINES_LEFT;
  asm "xio_top_name",    pvix $io->TOP_NAME;
  asm "xio_top_gv",      $topix;
  asm "xio_fmt_name",    pvix $io->FMT_NAME;
  asm "xio_fmt_gv",      $fmtix;
  asm "xio_bottom_name", pvix $io->BOTTOM_NAME;
  asm "xio_bottom_gv",   $bottomix;
  asm "xio_subprocess",  $io->SUBPROCESS unless $PERL510;
  asm "xio_type",        ord $io->IoTYPE;
  if ($PERL56) {
    asm "xio_flags",     $io->IoFLAGS;
  }
  # XXX IOf_NOLINE off was added with 5.8, but not used (?)
  # asm "xio_flags", ord($io->IoFLAGS) & ~32;		# XXX IOf_NOLINE 32
}

sub B::CV::bsave {
  my ( $cv, $ix ) = @_;
  my $stashix   = $cv->STASH->ix;
  my $gvix      = $cv->GV->ix;
  my $padlistix = $cv->PADLIST->ix;
  my $outsideix = $cv->OUTSIDE->ix;
  my $startix   = $cv->START->opwalk;
  my $rootix    = $cv->ROOT->ix;

  $cv->B::PVMG::bsave($ix);
  asm "xcv_stash",       $stashix;
  asm "xcv_start",       $startix;
  asm "xcv_root",        $rootix;
  unless ($PERL56) {
    asm "xcv_xsubany",   $cv->CONST ? $cv->XSUBANY->ix : 0;
  }
  asm "xcv_padlist",     $padlistix;
  asm "xcv_outside",     $outsideix;
  asm "xcv_outside_seq", $cv->OUTSIDE_SEQ unless $PERL56;
  asm "xcv_depth",       $cv->DEPTH;
  asm "xcv_flags",       $cv->CvFLAGS;
  asm "xcv_gv",          $gvix;
  asm "xcv_file",        pvix $cv->FILE if $cv->FILE;    # XXX AD
}

sub B::FM::bsave {
  my ( $form, $ix ) = @_;

  $form->B::CV::bsave($ix);
  asm "xfm_lines", $form->LINES;
}

sub B::AV::bsave {
  my ( $av, $ix ) = @_;
  return $av->B::PVMG::bsave($ix) if !$PERL56 and $av->MAGICAL;
  my @array = $av->ARRAY;
  $_ = $_->ix for @array; # hack. walks the ->ix methods to save the elements
  my $stashix = $av->SvSTASH->ix;
  nice "-AV-",
    asm "ldsv", $varix = $ix, sv_flags($av) unless $ix == $varix;

  if ($PERL56) {
    asm "sv_flags", $av->FLAGS & ~SVf_READONLY; # SvREADONLY_off($av) in case PADCONST
    $av->domagic($ix) if MAGICAL56($av);
    asm "xav_flags", $av->AvFLAGS;
    asm "xav_max", -1;
    asm "xav_fill", -1;
    if ($av->FILL > -1) {
      asm "av_push", $_ for @array;
    } else {
      asm "av_extend", $av->MAX if $av->MAX >= 0;
    }
    asm "sv_flags", $av->FLAGS if $av->FLAGS & SVf_READONLY; # restore flags
  } else {
    #$av->domagic($ix) if $av->MAGICAL;
    asm "av_extend", $av->MAX if $av->MAX >= 0;
    asm "av_pushx", $_ for @array;
    if ( !$PERL510 ) {        # VERSION < 5.009
      asm "xav_flags", $av->AvFLAGS;
    }
    # asm "xav_alloc", $av->AvALLOC if $] > 5.013002; # XXX new but not needed
  }
  asm "sv_refcnt", $av->REFCNT;
  asm "xmg_stash", $stashix;
}

sub B::GV::desired {
  my $gv = shift;
  my ( $cv, $form );
  if ( $debug{G} and !$PERL510 ) {
    eval "require B::Debug;";
    $gv->debug;
  }
  #unless ($] > 5.013005 and $hv->NAME eq 'B')
  $files{ $gv->FILE } && $gv->LINE
    || ${ $cv   = $gv->CV }   && $files{ $cv->FILE }
    || ${ $form = $gv->FORM } && $files{ $form->FILE };
}

sub B::HV::bwalk {
  my $hv = shift;
  return if $walked{$$hv}++;
  my %stash = $hv->ARRAY;
  while ( my ( $k, $v ) = each %stash ) {
    if ( !$PERL56 and $v->SvTYPE == $SVt_PVGV ) {
      my $hash = $v->HV;
      if ( $$hash && $hash->NAME ) {
        $hash->bwalk;
      }
      # B since 5.13.6 (744aaba0598) pollutes our namespace. Keep it clean
      # XXX This fails if our source really needs any B constant
      unless ($] > 5.013005 and $hv->NAME eq 'B') {
	$v->ix(1) if desired $v;
      }
    }
    else {
      if ($] > 5.013005 and $hv->NAME eq 'B') { # see above. omit B prototypes
	return;
      }
      nice "[prototype]";
      # XXX when? do not init empty prototypes. But only 64-bit fails.
      if ($PERL510 and $v->SvTYPE == $SVt_PVGV) {
	asm "newpv", cstring $hv->NAME . "::$k";
	# Beware of special gv_fetchpv GV_* flags.
	# gv_fetchpvx uses only GV_ADD, which fails e.g. with *Fcntl::O_SHLOCK,
	# if "Your vendor has not defined Fcntl macro O_SHLOCK"
	asm "gv_fetchpvn_flags", 0x20; 	# GV_NOADD_NOINIT
      } else {
	asm "gv_fetchpvx", cstring $hv->NAME . "::$k";
      }
      $svtab{$$v} = $varix = $tix;
      # we need the sv_flags before, esp. for DEBUGGING asserts
      asm "sv_flags",  $v->FLAGS;
      $v->bsave( $tix++ );
    }
  }
}

######################################################

sub B::OP::bsave_thin {
  my ( $op, $ix ) = @_;
  bwarn( B::peekop($op), ", ix: $ix" ) if $debug{o};
  my $next   = $op->next;
  my $nextix = $optab{$$next};
  $nextix = 0, push @cloop, $op unless defined $nextix;
  if ( $ix != $opix ) {
    nice '-' . $op->name . '-', asm "ldop", $opix = $ix;
  }
  asm "op_next",    $nextix;
  asm "op_targ",    $op->targ if $op->type;             # tricky
  asm "op_flags",   $op->flags, op_flags( $op->flags );
  asm "op_private", $op->private;                       # private concise flags?
}

sub B::OP::bsave;
*B::OP::bsave = *B::OP::bsave_thin;

sub B::UNOP::bsave {
  my ( $op, $ix ) = @_;
  my $name    = $op->name;
  my $flags   = $op->flags;
  my $first   = $op->first;
  my $firstix = $name =~ /fl[io]p/

    # that's just neat
    || ( !ITHREADS && $name eq 'regcomp' )

    # trick for /$a/o in pp_regcomp
    || $name eq 'rv2sv'
    && $op->flags & OPf_MOD
    && $op->private & OPpLVAL_INTRO

    # change #18774 made my life hard
    ? $first->ix
    : 0;

  $op->B::OP::bsave($ix);
  asm "op_first", $firstix;
}

sub B::BINOP::bsave {
  my ( $op, $ix ) = @_;
  if ( $op->name eq 'aassign' && $op->private & B::OPpASSIGN_HASH() ) {
    my $last   = $op->last;
    my $lastix = do {
      local *B::OP::bsave   = *B::OP::bsave_fat;
      local *B::UNOP::bsave = *B::UNOP::bsave_fat;
      $last->ix;
    };
    asm "ldop", $lastix unless $lastix == $opix;
    asm "op_targ", $last->targ;
    $op->B::OP::bsave($ix);
    asm "op_last", $lastix;
  }
  else {
    $op->B::OP::bsave($ix);
  }
}

# not needed if no pseudohashes

*B::BINOP::bsave = *B::OP::bsave if $PERL510;    #VERSION >= 5.009;

# deal with sort / formline

sub B::LISTOP::bsave {
  my ( $op, $ix ) = @_;
  bwarn( $op->peekop, ", ix: $ix" ) if $debug{o};
  my $name = $op->name;
  sub blocksort() { OPf_SPECIAL | OPf_STACKED }
  if ( $name eq 'sort' && ( $op->flags & blocksort ) == blocksort ) {
    my $first    = $op->first;
    my $pushmark = $first->sibling;
    my $rvgv     = $pushmark->first;
    my $leave    = $rvgv->first;

    my $leaveix = $leave->ix;

    my $rvgvix = $rvgv->ix;
    asm "ldop", $rvgvix unless $rvgvix == $opix;
    asm "op_first", $leaveix;

    my $pushmarkix = $pushmark->ix;
    asm "ldop", $pushmarkix unless $pushmarkix == $opix;
    asm "op_first", $rvgvix;

    my $firstix = $first->ix;
    asm "ldop", $firstix unless $firstix == $opix;
    asm "op_sibling", $pushmarkix;

    $op->B::OP::bsave($ix);
    asm "op_first", $firstix;
  }
  elsif ( $name eq 'formline' ) {
    $op->B::UNOP::bsave_fat($ix);
  }
  else {
    $op->B::OP::bsave($ix);
  }
}

# fat versions

sub B::OP::bsave_fat {
  my ( $op, $ix ) = @_;
  my $siblix = $op->sibling->ix;

  $op->B::OP::bsave_thin($ix);
  asm "op_sibling", $siblix;

  # asm "op_seq", -1;			XXX don't allocate OPs piece by piece
}

sub B::UNOP::bsave_fat {
  my ( $op, $ix ) = @_;
  my $firstix = $op->first->ix;

  $op->B::OP::bsave($ix);
  asm "op_first", $firstix;
}

sub B::BINOP::bsave_fat {
  my ( $op, $ix ) = @_;
  my $last   = $op->last;
  my $lastix = $op->last->ix;
  bwarn( B::peekop($op), ", ix: $ix $last: $last, lastix: $lastix" )
    if $debug{o};
  if ( !$PERL510 && $op->name eq 'aassign' && $last->name eq 'null' ) {
    asm "ldop", $lastix unless $lastix == $opix;
    asm "op_targ", $last->targ;
  }

  $op->B::UNOP::bsave($ix);
  asm "op_last", $lastix;
}

sub B::LOGOP::bsave {
  my ( $op, $ix ) = @_;
  my $otherix = $op->other->ix;
  bwarn( B::peekop($op), ", ix: $ix" ) if $debug{o};

  $op->B::UNOP::bsave($ix);
  asm "op_other", $otherix;
}

sub B::PMOP::bsave {
  my ( $op, $ix ) = @_;
  my ( $rrop, $rrarg, $rstart );

  # my $pmnextix = $op->pmnext->ix;	# XXX
  bwarn( B::peekop($op), " ix: $ix" ) if $debug{M} or $debug{o};
  if (ITHREADS) {
    if ( $op->name eq 'subst' ) {
      $rrop   = "op_pmreplroot";
      $rrarg  = $op->pmreplroot->ix;
      $rstart = $op->pmreplstart->ix;
    }
    elsif ( $op->name eq 'pushre' ) {
      $rrarg = $op->pmreplroot;
      $rrop  = "op_pmreplrootpo";
    }
    $op->B::BINOP::bsave($ix);
    if ( !$PERL56 and $op->pmstashpv )
    {    # avoid empty stash? if (table) pre-compiled else re-compile
      if ( !$PERL510 ) {
        asm "op_pmstashpv", pvix $op->pmstashpv;
      }
      else {
        # XXX crash in 5.10, 5.11. Only used in OP_MATCH, with PMf_ONCE set
        if ( $op->name eq 'match' and $op->op_pmflags & 2) {
          asm "op_pmstashpv", pvix $op->pmstashpv;
        } else {
          bwarn("op_pmstashpv ignored") if $debug{M};
        }
      }
    }
    elsif ($PERL56) { # ignored
      ;
    }
    else {
      bwarn("op_pmstashpv main") if $debug{M};
      asm "op_pmstashpv", pvix "main" unless $PERL510;
    }
  } # ithreads
  else {
    $rrop  = "op_pmreplrootgv";
    $rrarg  = $op->pmreplroot->ix;
    $rstart = $op->pmreplstart->ix if $op->name eq 'subst';
    # 5.6 walks down the pmreplrootgv here
    # $op->pmreplroot->save($rrarg) unless $op->name eq 'pushre';
    my $stashix = $op->pmstash->ix unless $PERL56;
    $op->B::BINOP::bsave($ix);
    asm "op_pmstash", $stashix unless $PERL56;
  }

  asm $rrop, $rrarg if $rrop;
  asm "op_pmreplstart", $rstart if $rstart;

  if ( !$PERL510 ) {
    bwarn( "PMOP op_pmflags: ", $op->pmflags ) if $debug{M};
    asm "op_pmflags",     $op->pmflags;
    asm "op_pmpermflags", $op->pmpermflags;
    asm "op_pmdynflags",  $op->pmdynflags unless $PERL56;
    # asm "op_pmnext", $pmnextix;	# XXX broken
    # Special sequence: This is the arg for the next pregcomp
    asm "newpv", pvstring $op->precomp;
    asm "pregcomp";
  }
  elsif ($PERL510) {
    # Since PMf_BASE_SHIFT we need a U32, which is a new bytecode for backwards compat
    asm "op_pmflags", $op->pmflags;
    bwarn("PMOP op_pmflags: ", $op->pmflags) if $debug{M};
    my $pv = $op->precomp;
    asm "newpv", pvstring $pv;
    asm "pregcomp";
    # pregcomp does not set the extflags correctly, just the pmflags
    asm "op_reflags", $op->reflags if $pv; # so overwrite the extflags
  }
}

sub B::SVOP::bsave {
  my ( $op, $ix ) = @_;
  my $svix = $op->sv->ix;

  $op->B::OP::bsave($ix);
  asm "op_sv", $svix;
}

sub B::PADOP::bsave {
  my ( $op, $ix ) = @_;

  $op->B::OP::bsave($ix);

  # XXX crashed in 5.11 (where, why?)
  #if ($PERL511) {
  asm "op_padix", $op->padix;
  #}
}

sub B::PVOP::bsave {
  my ( $op, $ix ) = @_;
  $op->B::OP::bsave($ix);
  return unless my $pv = $op->pv;

  if ( $op->name eq 'trans' ) {
    asm "op_pv_tr", join ',', length($pv) / 2, unpack( "s*", $pv );
  }
  else {
    asm "newpv", pvstring $pv;
    asm "op_pv";
  }
}

sub B::LOOP::bsave {
  my ( $op, $ix ) = @_;
  my $nextix = $op->nextop->ix;
  my $lastix = $op->lastop->ix;
  my $redoix = $op->redoop->ix;

  $op->B::BINOP::bsave($ix);
  asm "op_redoop", $redoix;
  asm "op_nextop", $nextix;
  asm "op_lastop", $lastix;
}

sub B::COP::bsave {
  my ( $cop, $ix ) = @_;
  my $warnix = $cop->warnings->ix;
  if (ITHREADS) {
    $cop->B::OP::bsave($ix);
    asm "cop_stashpv", pvix $cop->stashpv, $cop->stashpv;
    asm "cop_file",    pvix $cop->file,    $cop->file;
  }
  else {
    my $stashix = $cop->stash->ix;
    my $fileix  = $PERL56 ? pvix($cop->file) : $cop->filegv->ix(1);
    $cop->B::OP::bsave($ix);
    asm "cop_stash",  $stashix;
    asm "cop_filegv", $fileix;
  }
  asm "cop_label", pvix $cop->label, $cop->label if $cop->label;    # XXX AD
  asm "cop_seq", $cop->cop_seq;
  asm "cop_arybase", $cop->arybase unless $PERL510;
  asm "cop_line", $cop->line;
  asm "cop_warnings", $warnix;
  if ( !$PERL510 and !$PERL56 ) {
    asm "cop_io", $cop->io->ix;
  }
}

sub B::OP::opwalk {
  my $op = shift;
  my $ix = $optab{$$op};
  defined($ix) ? $ix : do {
    my $ix;
    my @oplist = ($PERL56 and $op->isa("B::COP"))
      ? () : $op->oplist; # 5.6 may be called by a COP
    push @cloop, undef;
    $ix = $_->ix while $_ = pop @oplist;
    print "\n# rest of cloop\n";
    while ( $_ = pop @cloop ) {
      asm "ldop",    $optab{$$_};
      asm "op_next", $optab{ ${ $_->next } };
    }
    $ix;
  }
}

sub save_cq {
  my $av;
  if ( ( $av = begin_av )->isa("B::AV") ) {
    if ($savebegins) {
      for ( $av->ARRAY ) {
        next unless $_->FILE eq $0;
        asm "push_begin", $_->ix;
      }
    }
    else {
      for ( $av->ARRAY ) {
        next unless $_->FILE eq $0;

        # XXX BEGIN { goto A while 1; A: }
        for ( my $op = $_->START ; $$op ; $op = $op->next ) {
	  # special cases for:
	  # 1. push|unshift @INC, "libpath"
	  if ($op->name =~ /^(unshift|push)$/) {
	    asm "push_begin", $_->ix;
	    last;
	  }
	  # 2. use|require ... unless in tests
          next unless $op->name eq 'require' ||

              # this kludge needed for tests
              $op->name eq 'gv' && do {
                my $gv =
                  class($op) eq 'SVOP'
                  ? $op->gv
                  : ( ( $_->PADLIST->ARRAY )[1]->ARRAY )[ $op->padix ];
                $$gv && $gv->NAME =~ /use_ok|plan/;
              };
          asm "push_begin", $_->ix;
          last;
        }
      }
    }
  }
  if ( ( $av = init_av )->isa("B::AV") ) {
    for ( $av->ARRAY ) {
      next unless $_->FILE eq $0;
      asm "push_init", $_->ix;
    }
  }
  if ( ( $av = end_av )->isa("B::AV") ) {
    for ( $av->ARRAY ) {
      next unless $_->FILE eq $0;
      asm "push_end", $_->ix;
    }
  }
}

################### perl 5.6 backport only ###################################

sub B::GV::bytecodecv {
  my $gv = shift;
  my $cv = $gv->CV;
  if ( $$cv && !( $gv->FLAGS & 0x80 ) ) { # GVf_IMPORTED_CV / && !saved($cv)
    if ($debug{cv}) {
      warn sprintf( "saving extra CV &%s::%s (0x%x) from GV 0x%x\n",
        $gv->STASH->NAME, $gv->NAME, $$cv, $$gv );
    }
    $gv->bsave;
  }
}

sub symwalk {
  no strict 'refs';
  my $ok = 1
    if grep { ( my $name = $_[0] ) =~ s/::$//; $_ eq $name; } @packages;
  if ( grep { /^$_[0]/; } @packages ) {
    walksymtable( \%{"$_[0]"}, "desired", \&symwalk, $_[0] );
  }
  warn "considering $_[0] ... " . ( $ok ? "accepted\n" : "rejected\n" )
    if $debug{b};
  $ok;
}

################### end perl 5.6 backport ###################################

sub compile {
  my ( $head, $scan, $T_inhinc, $keep_syn );
  my $cwd = '';
  $files{$0} = 1;

  sub keep_syn {
    $keep_syn         = 1;
    *B::OP::bsave     = *B::OP::bsave_fat;
    *B::UNOP::bsave   = *B::UNOP::bsave_fat;
    *B::BINOP::bsave  = *B::BINOP::bsave_fat;
    *B::LISTOP::bsave = *B::LISTOP::bsave_fat;
  }
  sub bwarn { print STDERR "Bytecode.pm: @_\n" unless $quiet; }

  for (@_) {
    if (/^-q(q?)/) {
      $quiet = 1;
    }
    elsif (/^-S/) {
      $debug{Comment} = 1;
      $debug{-S} = 1;
      *newasm = *endasm = sub { };
      *asm = sub($;$$) {
        undef $_[2] if defined $_[2] and $quiet;
        ( defined $_[2] )
          ? print $_[0], " ", $_[1], "\t# ", $_[2], "\n"
          : print "@_\n";
      };
      *nice = sub ($) { print "\n# @_\n" unless $quiet; };
    }
    elsif (/^-v/) {
      warn "conflicting -q ignored" if $quiet;
      *nice = sub ($) { print "\n# @_\n"; print STDERR "@_\n" };
    }
    elsif (/^-H/) {
      require ByteLoader;
      my $version = $ByteLoader::VERSION;
      $head = "#! $^X
use ByteLoader '$ByteLoader::VERSION';
";

      # Maybe: Fix the plc reader, if 'perl -MByteLoader <.plc>' is called
    }
    elsif (/^-k/) {
      keep_syn;
    }
    elsif (/^-o(.*)$/) {
      open STDOUT, ">$1" or die "open $1: $!";
    }
    elsif (/^-f(.*)$/) {
      $files{$1} = 1;
    }
    elsif (/^-D(.*)$/) {
      $debug{$1}++;
    }
    elsif (/^-s(.*)$/) {
      $scan = length($1) ? $1 : $0;
    }
    elsif (/^-b/) {
      $savebegins = 1;
    } # this is here for the testsuite
    elsif (/^-TI/) {
      $T_inhinc = 1;
    }
    elsif (/^-TF(.*)/) {
      my $thatfile = $1;
      *B::COP::file = sub { $thatfile };
    }
    elsif (/^-u(.*)/ and $PERL56) {
      my $arg ||= $1;
      push @packages, $arg;
    }
    else {
      bwarn "Ignoring '$_' option";
    }
  }
  if ($scan) {
    my $f;
    if ( open $f, $scan ) {
      while (<$f>) {
        /^#\s*line\s+\d+\s+("?)(.*)\1/ and $files{$2} = 1;
        /^#/ and next;
        if ( /\bgoto\b\s*[^&]/ && !$keep_syn ) {
          bwarn "keeping the syntax tree: \"goto\" op found";
          keep_syn;
        }
      }
    }
    else {
      bwarn "cannot rescan '$scan'";
    }
    close $f;
  }
  binmode STDOUT;
  return sub {
    if ($debug{-S}) {
      my $header = B::Assembler::gen_header_hash;
      asm sprintf("#%-10s\t","magic").sprintf("0x%x",$header->{magic});
      for (qw(archname blversion ivsize ptrsize byteorder longsize archflag perlversion)) {
	asm sprintf("#%-10s\t",$_).$header->{$_};
      }
    }
    print $head if $head;
    newasm sub { print @_ };

    if (!$PERL56) {
      defstash->bwalk;
    } else {
      if ( !@packages ) {
        # support modules?
	@packages = qw(main);
      }
      for (@packages) {
	no strict qw(refs);
        #B::svref_2object( \%{"$_\::"} )->bwalk;
	walksymtable( \%{"$_\::"}, "bytecodecv", \&symwalk );
      }
      walkoptree( main_root, "bsave" ) unless ref(main_root) eq "B::NULL";
    }
    asm "main_start", $PERL56 ? main_start->ix : main_start->opwalk;
    #asm "main_start", main_start->opwalk;
    asm "main_root",  main_root->ix;
    asm "main_cv",    main_cv->ix;
    asm "curpad",     ( comppadlist->ARRAY )[1]->ix;

    asm "signal", cstring "__WARN__"    # XXX
      if !$PERL56 and warnhook->ix;
    asm "incav", inc_gv->AV->ix if $T_inhinc;
    save_cq;
    asm "incav", inc_gv->AV->ix if $T_inhinc;
    asm "dowarn", dowarn unless $PERL56;

    {
      no strict 'refs';
      nice "<DATA>";
      my $dh = $PERL56 ? *main::DATA : *{ defstash->NAME . "::DATA" };
      unless ( eof $dh ) {
        local undef $/;
        asm "data", ord 'D' if !$PERL56;
        print <$dh>;
      }
      else {
        asm "ret";
      }
    }

    endasm;
    }
}

1;

=head1 NAME

B::Bytecode - Perl compiler's bytecode backend

=head1 SYNOPSIS

B<perl -MO=Bytecode>[B<,-H>][B<,-o>I<script.plc>] I<script.pl>

=head1 DESCRIPTION

Compiles a Perl script into a bytecode format that could be loaded
later by the ByteLoader module and executed as a regular Perl script.
This saves time for the optree parsing and compilation and space for
the sourcecode in memory.

=head1 EXAMPLE

    $ perl -MO=Bytecode,-H,-ohi -e 'print "hi!\n"'
    $ perl hi
    hi!

=head1 OPTIONS

=over 4

=item B<-H>

Prepend a C<use ByteLoader VERSION;> line to the produced bytecode.

=item B<-b>

Save all the BEGIN blocks.

Normally only BEGIN blocks that C<require>
other files (ex. C<use Foo;>) or push|unshift
to @INC are saved.

=item B<-k>

Keep the syntax tree - it is stripped by default.

=item B<-o>I<outfile>

Put the bytecode in <outfile> instead of dumping it to STDOUT.

=item B<-s>

Scan the script for C<# line ..> directives and for <goto LABEL>
expressions. When gotos are found keep the syntax tree.

=item B<-S>

Output assembler source rather than piping it through the assembler
and outputting bytecode.
Without -q the assembler source is commented.

=item B<-u>I<package>

use package. Might be needed of the package is not automatically detected.

=item B<-q>

Be quiet.

=item B<-v>

Be verbose.

=item B<-TI>

Restore full @INC for running within the CORE testsuite.

=item B<-TF> I<cop file>

Set the COP file - for running within the CORE testsuite.

=item B<-Do>

OPs, prints each OP as it's processed

=item B<-D>I<M>

Debugging flag for more verbose STDERR output.

B<M> for Magic and Matches.

=item B<-D>I<G>

Debug GV's

=item B<-D>I<A>

Set developer B<A>ssertions, to help find possible obj-indices out of range.

=back

=head1 KNOWN BUGS

=over 4

=item *

5.10 threaded fails with setting the wrong MATCH op_pmflags
5.10 non-threaded fails calling anoncode, ...

=item *

C<BEGIN { goto A: while 1; A: }> won't even compile.

=item *

C<?...?> and C<reset> do not work as expected.

=item *

variables in C<(?{ ... })> constructs are not properly scoped.

=item *

Scripts that use source filters will fail miserably.

=item *

Special GV's fail.

=back

=head1 NOTICE

There are also undocumented bugs and options.

THIS CODE IS HIGHLY EXPERIMENTAL. USE AT YOUR OWN RISK.

=head1 AUTHORS

Originally written by Malcolm Beattie and
modified by Benjamin Stuhl <sho_pi@hotmail.com>.

Rewritten by Enache Adrian <enache@rdslink.ro>, 2003 a.d.

Enhanced by Reini Urban <rurban@cpan.org>, 2008, 2009

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 2
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=2:
