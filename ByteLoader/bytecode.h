typedef char *pvcontents;
typedef char *strconst;
typedef U32 PV; /* hack */
typedef char *op_tr_array;
typedef int comment_t;
typedef SV *svindex;
typedef OP *opindex;
typedef char *pvindex;
/*typedef HEK *hekindex;*/
typedef IV IV64;

static int force = 0;
/* need to swab bytes to the target byteorder */
static int bget_swab = 0;

#if (PERL_VERSION <= 8) && (PERL_SUBVERSION < 8)
#include "ppport.h"
#endif

#define BGET_FREAD(argp, len, nelem)	\
	 bl_read(bstate->bs_fdata,(char*)(argp),(len),(nelem))
#define BGET_FGETC() bl_getc(bstate->bs_fdata)

#define BGET_U8(arg) STMT_START {					\
	const int _arg = BGET_FGETC();					\
	if (_arg < 0) {							\
	    Perl_croak(aTHX_						\
		       "EOF or error while trying to read 1 byte for U8"); \
	}								\
	arg = (U8) _arg;						\
    } STMT_END

/* with platform conversion from bl_header. */
#define BGET_U16(arg)	STMT_START {					\
	BGET_OR_CROAK(arg, U16);					\
        if (bget_swab) {arg=_swab_16_(arg);}				\
    } STMT_END
#define BGET_I32(arg)	STMT_START {					\
	BGET_OR_CROAK(arg, U32);					\
	if (bget_swab) {arg=_swab_32_(arg);}				\
    } STMT_END
#define BGET_U32(arg)	STMT_START {					\
	BGET_OR_CROAK(arg, U32);					\
	if (bget_swab) {arg=_swab_32_(arg);}				\
    } STMT_END
#define BGET_IV(arg) STMT_START {				        \
	if (BGET_FREAD(&arg, bl_header.ivsize, 1) < 1) {		\
	    Perl_croak(aTHX_						\
		       "EOF or error while trying to read %d bytes for %s", \
		       bl_header.ivsize, "IV");				\
	}								\
	if (bl_header.ivsize != IVSIZE) {				\
	    Perl_warn(aTHX_						\
		       "Different IVSIZE: .plc %d, perl %d", 		\
		      bl_header.ivsize, IVSIZE);			\
	}								\
	if (bget_swab) {arg = _swab_iv_(arg, IVSIZE);}			\
    } STMT_END
/*
 * In the following, sizeof(IV)*4 is just a way of encoding 32 on 64-bit-IV
 * machines such that 32-bit machine compilers don't whine about the shift
 * count being too high even though the code is never reached there.
 */
#define BGET_IV64(arg) STMT_START {			\
	U32 hi, lo;					\
	BGET_U32(hi);					\
	BGET_U32(lo);					\
	if (bget_swab) { U32 tmp=hi; hi=lo; lo=tmp; }	\
	if (sizeof(IV) == 8) {				\
	    arg = ((IV)hi << (sizeof(IV)*4) | (IV)lo);	\
	} else if (((I32)hi == -1 && (I32)lo < 0)	\
		 || ((I32)hi == 0 && (I32)lo >= 0)) {	\
	    arg = (I32)lo;				\
	}						\
	else {						\
	    bstate->bs_iv_overflows++;			\
	    arg = 0;					\
	}						\
    } STMT_END

#define BGET_PADOFFSET(arg)	STMT_START {                            \
        BGET_OR_CROAK(arg, PADOFFSET);                                  \
        if (bget_swab) {                                                \
            arg=(sizeof(PADOFFSET)==4)?_swab_32_(arg):_swab_64_(arg); }	\
    } STMT_END

#define BGET_long(arg) STMT_START {				        \
	if (BGET_FREAD(&arg, bl_header.longsize, 1) < 1) {		\
	    Perl_croak(aTHX_						\
		       "EOF or error while trying to read %d bytes for %s", \
		       bl_header.ivsize, "IV");				\
	}								\
	if (bget_swab) { arg = _swab_iv_(arg, bl_header.longsize); }	\
	if (bl_header.longsize != LONGSIZE) {				\
	    Perl_warn(aTHX_						\
		       "Different LONGSIZE .plc %d, perl %d",		\
		      bl_header.longsize, LONGSIZE);			\
	}								\
    } STMT_END

/* svtype is an enum of 16 values. 32bit or 16bit? */
#define BGET_svtype(arg)	STMT_START {	       			\
    BGET_OR_CROAK(arg, svtype);						\
    if (bget_swab) {arg = _swab_iv_(arg, sizeof(svtype))}               \
    } STMT_END

#define BGET_OR_CROAK(arg, type) STMT_START {				\
	if (BGET_FREAD(&arg, sizeof(type), 1) < 1) {			\
	    Perl_croak(aTHX_						\
		       "EOF or error while trying to read %d bytes for %s", \
		       sizeof(type), STRINGIFY(type));			\
	}								\
    } STMT_END

#define BGET_PV(arg)	STMT_START {					\
	BGET_U32(arg);							\
	if (arg) {							\
	    New(666, bstate->bs_pv.xpv_pv, (U32)arg, char);		\
	    bl_read(bstate->bs_fdata, bstate->bs_pv.xpv_pv, (U32)arg, 1); \
	    bstate->bs_pv.xpv_len = (U32)arg;				\
	    bstate->bs_pv.xpv_cur = (U32)arg - 1;			\
	} else {							\
	    bstate->bs_pv.xpv_pv = 0;					\
	    bstate->bs_pv.xpv_len = 0;					\
	    bstate->bs_pv.xpv_cur = 0;					\
	}								\
    } STMT_END

#ifdef BYTELOADER_LOG_COMMENTS
#  define BGET_comment_t(arg) \
    STMT_START {							\
	char buf[1024];							\
	int i = 0;							\
	do {								\
	    arg = BGET_FGETC();						\
	    buf[i++] = (char)arg;					\
	} while (arg != '\n' && arg != EOF);				\
	buf[i] = '\0';							\
	PerlIO_printf(PerlIO_stderr(), "%s", buf);			\
    } STMT_END
#else
#  define BGET_comment_t(arg) \
	do { arg = BGET_FGETC(); } while (arg != '\n' && arg != EOF)
#endif

#define BGET_op_tr_array(arg) do {			\
	unsigned short *ary, len;			\
	BGET_U16(len);					\
	New(666, ary, len, unsigned short);		\
	BGET_FREAD(ary, sizeof(unsigned short), len);	\
	arg = (char *) ary;				\
    } while (0)

#define BGET_pvcontents(arg)	arg = bstate->bs_pv.xpv_pv
/* read until \0. optionally limit the max stringsize for buffer overflow attempts */
#define BGET_strconst(arg, maxsize) STMT_START {	\
	char *end = NULL; 				\
        if (maxsize) { end = PL_tokenbuf+maxsize; }	\
	for (arg = PL_tokenbuf;				\
	     (*arg = BGET_FGETC()) && (maxsize ? arg<end : 1);	\
	    arg++) /* nothing */;			\
	arg = PL_tokenbuf;				\
    } STMT_END

#define BGET_NV(arg) STMT_START {	\
	char *str;			\
	BGET_strconst(str,80);		\
	arg = Atof(str);		\
    } STMT_END

#define BGET_objindex(arg, type) STMT_START {	\
	BGET_U32(ix);				\
	arg = (type)bstate->bs_obj_list[ix];	\
    } STMT_END
#define BGET_svindex(arg) BGET_objindex(arg, svindex)
#define BGET_opindex(arg) BGET_objindex(arg, opindex)
/*#define BGET_hekindex(arg) BGET_objindex(arg, hekindex)*/
#define BGET_pvindex(arg) STMT_START {			\
	BGET_objindex(arg, pvindex);			\
	arg = arg ? savepv(arg) : arg;			\
    } STMT_END

#define BSET_ldspecsv(sv, arg) STMT_START {				\
	if(arg >= sizeof(specialsv_list) / sizeof(specialsv_list[0])) {	\
	    Perl_croak(aTHX_ "Out of range special SV number %d", arg);	\
	}								\
	sv = specialsv_list[arg];					\
    } STMT_END

#define BSET_ldspecsvx(sv, arg) STMT_START {	\
	BSET_ldspecsv(sv, arg);			\
	BSET_OBJ_STOREX(sv);			\
    } STMT_END

#define BSET_stpv(pv, arg) STMT_START {		\
	BSET_OBJ_STORE(pv, arg);		\
	SAVEFREEPV(pv);				\
    } STMT_END
				    
#define BSET_sv_refcnt_add(svrefcnt, arg)	svrefcnt += arg
#define BSET_gp_refcnt_add(gprefcnt, arg)	gprefcnt += arg
#define BSET_gp_share(sv, arg) STMT_START {	\
	gp_free((GV*)sv);			\
	GvGP(sv) = GvGP(arg);			\
    } STMT_END

#define BSET_gv_fetchpv(sv, arg)	sv = (SV*)gv_fetchpv(arg, TRUE, SVt_PV)
#define BSET_gv_fetchpvx(sv, arg) STMT_START {	\
	BSET_gv_fetchpv(sv, arg);		\
	BSET_OBJ_STOREX(sv);			\
    } STMT_END

#define BSET_gv_stashpv(sv, arg)	sv = (SV*)gv_stashpv(arg, TRUE)
#define BSET_gv_stashpvx(sv, arg) STMT_START {	\
	BSET_gv_stashpv(sv, arg);		\
	BSET_OBJ_STOREX(sv);			\
    } STMT_END

#define BSET_sv_magic(sv, arg)	sv_magic(sv, Nullsv, arg, 0, 0)
/* mg_name was previously called mg_pv. we keep the new name and the old index */
#define BSET_mg_name(mg, arg)	mg->mg_ptr = arg; mg->mg_len = bstate->bs_pv.xpv_cur
#define BSET_mg_namex(mg, arg)			\
	(mg->mg_ptr = (char*)SvREFCNT_inc((SV*)arg),	\
	 mg->mg_len = HEf_SVKEY)
#define BSET_xmg_stash(sv, arg) *(SV**)&(((XPVMG*)SvANY(sv))->xmg_stash) = (arg)
#define BSET_sv_upgrade(sv, arg)	(void)SvUPGRADE(sv, arg)
#define BSET_xrv(sv, arg) SvRV_set(sv, arg)
#define BSET_xpv(sv)	do {	\
	SvPV_set(sv, bstate->bs_pv.xpv_pv);	\
	SvCUR_set(sv, bstate->bs_pv.xpv_cur);	\
	SvLEN_set(sv, bstate->bs_pv.xpv_len);	\
    } while (0)
#define BSET_xpv_cur(sv, arg) SvCUR_set(sv, arg)
#define BSET_xpv_len(sv, arg) SvLEN_set(sv, arg)
#define BSET_xiv(sv, arg) SvIV_set(sv, arg)
#define BSET_xnv(sv, arg) SvNV_set(sv, arg)

#define BSET_av_extend(sv, arg)	av_extend((AV*)sv, arg)

#define BSET_av_push(sv, arg)	av_push((AV*)sv, arg)
#define BSET_av_pushx(sv, arg)	(AvARRAY(sv)[++AvFILLp(sv)] = arg)
#define BSET_hv_store(sv, arg)	\
	hv_store((HV*)sv, bstate->bs_pv.xpv_pv, bstate->bs_pv.xpv_cur, arg, 0)
#define BSET_pv_free(pv)	Safefree(pv.xpv_pv)

#if PERL_VERSION > 13 || defined(CvGV_set)
#define BSET_xcv_gv(sv, arg)	((SvANY((CV*)bstate->bs_sv))->xcv_gv = (GV*)arg)
#else
#define BSET_xcv_gv(sv, arg)	(*(SV**)&CvGV(bstate->bs_sv) = arg)
#endif
#if PERL_VERSION > 13 || defined(CvSTASH_set)
#define BSET_xcv_stash(sv, arg)	(CvSTASH_set((CV*)bstate->bs_sv, (HV*)arg))
#else
#define BSET_xcv_stash(sv, arg)	(*(SV**)&CvSTASH(bstate->bs_sv) = arg)
#endif

#ifdef USE_ITHREADS

/* Copied after the code in newPMOP().
   Since 5.13d PM_SETRE(op, NULL) fails
 */
#if (PERL_VERSION >= 11)
#define BSET_pregcomp(o, arg)						\
    STMT_START {                                                        \
      if (arg) {							\
        PM_SETRE(cPMOPx(o),						\
	         CALLREGCOMP(newSVpvn(arg, strlen(arg)), cPMOPx(o)->op_pmflags)); \
      }									\
    } STMT_END
#endif
#if (PERL_VERSION >= 10) && (PERL_VERSION < 11)
/* see op.c:newPMOP
 * Must use a SV now. build it on the fly from the given pv. 
 * TODO: 5.11 could use newSVpvn_flags with SVf_TEMP
 * PM_SETRE adjust no PL_regex_pad, so repoint manually.
 */
#define BSET_pregcomp(o, arg)						\
    STMT_START {                                                        \
        SV* repointer;                                                  \
	REGEXP* rx = arg                                                \
            ? CALLREGCOMP(newSVpvn(arg, strlen(arg)), cPMOPx(o)->op_pmflags) \
            : Null(REGEXP*);                                            \
        if(av_len((AV*)PL_regex_pad[0]) > -1) {                         \
            repointer = av_pop((AV*)PL_regex_pad[0]);                   \
            cPMOPx(o)->op_pmoffset = SvIV(repointer);                   \
            SvREPADTMP_off(repointer);                                  \
            sv_setiv(repointer, PTR2IV(rx));                            \
        } else {                                                        \
            repointer = newSViv(PTR2IV(rx));                            \
            av_push(PL_regex_padav, SvREFCNT_inc(repointer));           \
            cPMOPx(o)->op_pmoffset = av_len(PL_regex_padav);            \
            PL_regex_pad = AvARRAY(PL_regex_padav);                     \
        }                                                               \
    } STMT_END
#endif
/* 5.8 and earlier had no PM_SETRE, so repoint manually */
#if (PERL_VERSION > 7) && (PERL_VERSION < 10)
#define BSET_pregcomp(o, arg)                   \
    STMT_START {                                \
        SV* repointer;                          \
	REGEXP* rx = arg                                                \
	    ? CALLREGCOMP(aTHX_ arg, arg + bstate->bs_pv.xpv_cur, cPMOPx(o)) \
	    : Null(REGEXP*);                                            \
        if(av_len((AV*)PL_regex_pad[0]) > -1) {                         \
            repointer = av_pop((AV*)PL_regex_pad[0]);                   \
            cPMOPx(o)->op_pmoffset = SvIV(repointer);                   \
            SvREPADTMP_off(repointer);                                  \
            sv_setiv(repointer, PTR2IV(rx));                            \
        } else {                                                        \
            repointer = newSViv(PTR2IV(rx));                            \
            av_push(PL_regex_padav, SvREFCNT_inc(repointer));           \
            cPMOPx(o)->op_pmoffset = av_len(PL_regex_padav);            \
            PL_regex_pad = AvARRAY(PL_regex_padav);                     \
        }                                                               \
    } STMT_END

#endif

#else /* ! USE_ITHREADS */

#if (PERL_VERSION >= 8) && (PERL_VERSION < 10)
/* PM_SETRE only since 5.8 */
#define BSET_pregcomp(o, arg) \
    STMT_START {                        \
	(((PMOP*)o)->op_pmregexp = (arg \
            ? CALLREGCOMP(aTHX_ arg, arg + bstate->bs_pv.xpv_cur, cPMOPx(o)) \
            : Null(REGEXP*)));          \
    } STMT_END
#endif
#if (PERL_VERSION >= 10)
#define BSET_pregcomp(o, arg)				\
    STMT_START {					\
      if (arg) {					\
        PM_SETRE((PMOP*)(o),				\
	         CALLREGCOMP(newSVpvn(arg, strlen(arg)), cPMOPx(o)->op_pmflags)); \
      }							\
    } STMT_END
#endif

#endif /* USE_ITHREADS */

#if PERL_VERSION < 8
#define BSET_pregcomp(o, arg)	    \
    ((PMOP*)o)->op_pmregexp = arg   \
        ? CALLREGCOMP(aTHX_ arg, arg + bstate->bs_pv.xpv_cur, ((PMOP*)o)) : 0
#endif


#define BSET_newsv(sv, arg)				\
	    switch(arg) {				\
	    case SVt_PVAV:				\
		sv = (SV*)newAV();			\
		break;					\
	    case SVt_PVHV:				\
		sv = (SV*)newHV();			\
		break;					\
	    default:					\
		sv = newSV(0);				\
		SvUPGRADE(sv, (arg));			\
	    }
#define BSET_newsvx(sv, arg) STMT_START {		\
	    BSET_newsv(sv, arg & SVTYPEMASK);		\
	    SvFLAGS(sv) = arg;				\
	    BSET_OBJ_STOREX(sv);			\
	} STMT_END

#if (PERL_VERSION > 6)
#define BSET_newop(o, size)	NewOpSz(666, o, size)
#else
#define BSET_newop(o, size)	(o=(OP*)safemalloc(size), memzero(o, size))
#endif
/* arg is encoded as type <<7 and size */
#define BSET_newopx(o, arg) STMT_START {	\
	register int size = arg & 0x7f;		\
	register OP* newop;			\
	BSET_newop(newop, size);		\
	/* newop->op_next = o; XXX */		\
	o = newop;				\
	arg >>= 7;				\
	BSET_op_type(o, arg);			\
	BSET_OBJ_STOREX(o);			\
    } STMT_END

#define BSET_newopn(o, arg) STMT_START {	\
	OP *oldop = o;				\
	BSET_newop(o, arg);			\
	oldop->op_next = o;			\
    } STMT_END

#define BSET_ret(foo) STMT_START {		\
	Safefree(bstate->bs_obj_list);		\
	return 0;				\
    } STMT_END

#define BSET_op_pmstashpv(op, arg)	PmopSTASHPV_set(op, arg)

/* 
 * stolen from toke.c: better if that was a function.
 * in toke.c there are also #ifdefs for dosish systems and i/o layers
 */

#if defined(HAS_FCNTL) && defined(F_SETFD)
#define set_clonex(fp)				\
	STMT_START {				\
	    int fd = PerlIO_fileno(fp);		\
	    fcntl(fd,F_SETFD,fd >= 3);		\
	} STMT_END
#else
#define set_clonex(fp)
#endif

#ifndef PL_preprocess
#define PL_preprocess 0
#endif

#define BSET_data(dummy,arg)						\
    STMT_START {							\
	GV *gv;								\
	char *pname = "main";						\
	if (arg == 'D')							\
	    pname = HvNAME(PL_curstash ? PL_curstash : PL_defstash);	\
	gv = gv_fetchpv(Perl_form(aTHX_ "%s::DATA", pname), TRUE, SVt_PVIO);\
	GvMULTI_on(gv);							\
	if (!GvIO(gv))							\
	    GvIOp(gv) = newIO();					\
	IoIFP(GvIOp(gv)) = PL_RSFP;					\
	set_clonex(PL_RSFP);						\
	/* Mark this internal pseudo-handle as clean */			\
	IoFLAGS(GvIOp(gv)) |= IOf_UNTAINT;				\
	if ((PERL_VERSION < 11) && PL_preprocess)			\
	    IoTYPE(GvIOp(gv)) = IoTYPE_PIPE;				\
	else if ((PerlIO*)PL_RSFP == PerlIO_stdin())			\
	    IoTYPE(GvIOp(gv)) = IoTYPE_STD;				\
	else								\
	    IoTYPE(GvIOp(gv)) = IoTYPE_RDONLY;				\
	Safefree(bstate->bs_obj_list);					\
	return 1;							\
    } STMT_END

/* stolen from op.c */
#define BSET_load_glob(foo, gv)						\
    STMT_START {							\
        GV *glob_gv;							\
        ENTER;								\
        Perl_load_module(aTHX_ PERL_LOADMOD_NOIMPORT,			\
                newSVpvn("File::Glob", 10), Nullsv, Nullsv, Nullsv);	\
        glob_gv = gv_fetchpv("File::Glob::csh_glob", FALSE, SVt_PVCV);	\
        GvCV(gv) = GvCV(glob_gv);					\
        SvREFCNT_inc((SV*)GvCV(gv));					\
        GvIMPORTED_CV_on(gv);						\
        LEAVE;								\
    } STMT_END

/*
 * Kludge special-case workaround for OP_MAPSTART
 * which needs the ppaddr for OP_GREPSTART. Blech.
 */
#define BSET_op_type(o, arg) STMT_START {	\
	o->op_type = arg;			\
	if (arg == OP_MAPSTART)			\
	    arg = OP_GREPSTART;			\
	o->op_ppaddr = PL_ppaddr[arg];		\
    } STMT_END
#define BSET_op_ppaddr(o, arg) Perl_croak(aTHX_ "op_ppaddr not yet implemented")
#define BSET_curpad(pad, arg) STMT_START {	\
	PL_comppad = (AV *)arg;			\
	PL_curpad = AvARRAY(arg);		\
    } STMT_END

#ifdef USE_ITHREADS
#define BSET_cop_file(cop, arg)		CopFILE_set(cop,arg)
#define BSET_cop_stashpv(cop, arg)	CopSTASHPV_set(cop,arg)
/* only warn, not croak, because those are not really important. stash could be. */
#define BSET_cop_filegv(cop, arg)	Perl_warn(aTHX_ "cop_filegv with ITHREADS not yet implemented")
#define BSET_cop_stash(cop,arg)		Perl_warn(aTHX_ "cop_stash with ITHREADS not yet implemented")
#else
/* this works now that Sarathy's changed the CopFILE_set macro to do the SvREFCNT_inc()
	-- BKS 6-2-2000 */
/* that really meant the actual CopFILEGV_set */
#define BSET_cop_filegv(cop, arg)	CopFILEGV_set(cop,arg)
#define BSET_cop_stash(cop,arg)		CopSTASH_set(cop,(HV*)arg)
#define BSET_cop_file(cop, arg)		Perl_warn(aTHX_ "cop_file without ITHREADS not yet implemented")
#define BSET_cop_stashpv(cop, arg)	Perl_warn(aTHX_ "cop_stashpv without ITHREADS not yet implemented")
#endif
#if PERL_VERSION < 11
# define BSET_cop_label(cop, arg)	(cop)->cop_label = arg
#else
/* See op.c:Perl_newSTATEOP. Test 21 */
# if (PERL_VERSION < 13) || ((PERL_VERSION == 13) && (PERL_SUBVERSION < 5))
#  if defined(_WIN32) || (defined(__CYGWIN__) && (__GNUC__ > 3)) || defined(AIX)
#   define BSET_cop_label(cop, arg)      /* XXX not exported */
#  else
#   define BSET_cop_label(cop, arg)	(cop)->cop_hints_hash = \
        Perl_store_cop_label(aTHX_ (cop)->cop_hints_hash, arg)
#  endif
# else
/* changed with 5.13.4-5 a77ac40c5b8 */
#  define BSET_cop_label(cop, arg)	Perl_store_cop_label(aTHX_ (cop), arg, strlen(arg), 0)
# endif
#endif

/* This is stolen from the code in newATTRSUB() */
#if PERL_VERSION < 10
#define PL_HINTS_PRIVATE (PL_hints & HINT_PRIVATE_MASK)
#else
/* Hints are now stored in a dedicated U32, so the bottom 8 bits are no longer
   special and there is no need for HINT_PRIVATE_MASK for COPs. */
#define PL_HINTS_PRIVATE (PL_hints)
#endif

#if (PERL_VERSION < 8)
/* this is simply stolen from the code in newATTRSUB() */
#define BSET_push_begin(ary,cv)				\
	STMT_START {					\
	    I32 oldscope = PL_scopestack_ix;		\
	    ENTER;					\
	    SAVECOPFILE(&PL_compiling);			\
	    SAVECOPLINE(&PL_compiling);			\
	    save_svref(&PL_rs);				\
	    sv_setsv(PL_rs, PL_nrs);			\
	    if (!PL_beginav)				\
		PL_beginav = newAV();			\
	    av_push(PL_beginav, cv);			\
	    call_list(oldscope, PL_beginav);		\
	    PL_curcop = &PL_compiling;			\
	    PL_compiling.op_private = PL_hints;		\
	    LEAVE;					\
	} STMT_END
#endif
#if (PERL_VERSION >= 8) && (PERL_VERSION < 10)
#define BSET_push_begin(ary,cv)				\
	STMT_START {					\
            I32 oldscope = PL_scopestack_ix;		\
            ENTER;					\
            SAVECOPFILE(&PL_compiling);			\
            SAVECOPLINE(&PL_compiling);			\
            if (!PL_beginav)				\
                PL_beginav = newAV();			\
            av_push(PL_beginav, (SV*)cv);		\
	    GvCV(CvGV(cv)) = 0;               /* cv has been hijacked */\
            call_list(oldscope, PL_beginav);		\
            PL_curcop = &PL_compiling;			\
            PL_compiling.op_private = (U8)(PL_hints & HINT_PRIVATE_MASK);\
            LEAVE;					\
	} STMT_END
#endif
#if (PERL_VERSION >= 10)
#define BSET_push_begin(ary,cv)				\
	STMT_START {					\
            I32 oldscope = PL_scopestack_ix;		\
            ENTER;					\
            SAVECOPFILE(&PL_compiling);			\
            SAVECOPLINE(&PL_compiling);			\
            if (!PL_beginav)				\
                PL_beginav = newAV();			\
            av_push(PL_beginav, (SV*)cv);		\
	    SvANY((CV*)cv)->xcv_gv = 0;/* cv has been hijacked */ \
            call_list(oldscope, PL_beginav);		\
            PL_curcop = &PL_compiling;			\
            CopHINTS_set(&PL_compiling, (U8)PL_HINTS_PRIVATE);	\
            LEAVE;					\
	} STMT_END
#endif
#define BSET_push_init(ary,cv)				\
	STMT_START {					\
	    av_unshift((PL_initav ? PL_initav : 	\
		(PL_initav = newAV(), PL_initav)), 1); 	\
	    av_store(PL_initav, 0, cv);			\
	} STMT_END
#define BSET_push_end(ary,cv)				\
	STMT_START {					\
	    av_unshift((PL_endav ? PL_endav : 		\
	    (PL_endav = newAV(), PL_endav)), 1);	\
	    av_store(PL_endav, 0, cv);			\
	} STMT_END
#define BSET_OBJ_STORE(obj, ix)			\
	((I32)ix > bstate->bs_obj_list_fill ?	\
	 bset_obj_store(aTHX_ bstate, obj, (I32)ix) : \
	 (bstate->bs_obj_list[ix] = obj),	\
	 bstate->bs_ix = ix+1)
#define BSET_OBJ_STOREX(obj)			\
	(bstate->bs_ix > bstate->bs_obj_list_fill ?	\
	 bset_obj_store(aTHX_ bstate, obj, bstate->bs_ix) : \
	 (bstate->bs_obj_list[bstate->bs_ix] = obj),	\
	 bstate->bs_ix++)

#define BSET_signal(cv, name)						\
	mg_set(*hv_store(GvHV(gv_fetchpv("SIG", TRUE, SVt_PVHV)),	\
		name, strlen(name), cv, 0))
/* 5.008? */
#ifndef hv_name_set
#define hv_name_set(hv,name,length,flags) \
    (HvNAME((hv)) = (name) ? savepvn(name, length) : 0)
#endif
#define BSET_xhv_name(hv, name)	hv_name_set((HV*)hv, name, strlen(name), 0)
#define BSET_cop_arybase(c, b) CopARYBASE_set(c, b)
#if PERL_VERSION < 10
#define BSET_cop_warnings(c, sv) c->cop_warnings = sv;
#else
#define BSET_cop_warnings(c, w) \
	STMT_START {							\
	    if (specialWARN((STRLEN *)w)) {				\
		c->cop_warnings = (STRLEN *)w;				\
	    } else {							\
		STRLEN len;						\
		const char *const p = SvPV_const(w, len);		\
		c->cop_warnings =					\
		    Perl_new_warnings_bitfield(aTHX_ NULL, p, len);	\
		SvREFCNT_dec(w);					\
	    }								\
	} STMT_END
#endif

#if PERL_VERSION < 10
#define BSET_gp_sv(gv, arg)		GvSV((GV*)gv) = arg
#else
#define BSET_gp_sv(gv, arg)		\
    isGV_with_GP_on((GV*)gv);		\
    GvSVn((GV*)gv) = arg
#endif

#if PERL_VERSION < 10
# define BSET_gp_file(gv, file)	GvFILE((GV*)gv) = file
#else
/* unshare_hek not public */
# if defined(WIN32)
#  define BSET_gp_file(gv, file) \
	STMT_START {							\
	    STRLEN len = strlen(file);					\
	    U32 hash;							\
	    PERL_HASH(hash, file, len);					\
	    GvFILE_HEK(gv) = share_hek(file, len, hash);		\
	    Safefree(file);						\
	} STMT_END
# else
#  define BSET_gp_file(gv, file) \
	STMT_START {							\
	    STRLEN len = strlen(file);					\
	    U32 hash;							\
	    PERL_HASH(hash, file, len);					\
	    if(GvFILE_HEK(gv)) {					\
		Perl_unshare_hek(aTHX_ GvFILE_HEK(gv));			\
	    }								\
	    GvFILE_HEK(gv) = share_hek(file, len, hash);		\
	    Safefree(file);						\
	} STMT_END
# endif
#endif

/* NOTE: The bytecode header only sanity-checks the bytecode. If a script cares about
 * what version of Perl it's being called under, it should do a 'use 5.006_001' or
 * equivalent. However, since the header includes checks required an exact match in
 * ByteLoader versions (we can't guarantee forward compatibility), you don't 
 * need to specify one.
 * 	use ByteLoader;
 * is all you need.
 *	-- BKS, June 2000
 * TODO: Want to guarantee backwards compatibility. -- rurban 2008-02
 *       Just need to verify the valid opcode version table (syntax enhancement 8-10 ?), 
 *       the perl opnum table and to define the converters.
 */

#define HEADER_FAIL(f)	\
	Perl_croak(aTHX_ "ERROR Invalid bytecode: " f)
#define HEADER_FAIL1(f, arg1)	\
	Perl_croak(aTHX_ "ERROR Invalid bytecode: " f, arg1)
#define HEADER_FAIL2(f, arg1, arg2)	\
	Perl_croak(aTHX_ "ERROR Invalid bytecode: " f, arg1, arg2)
#define HEADER_WARN(f)	\
	Perl_warn(aTHX_ "WARNING Convert bytecode: " f)
#define HEADER_WARN1(f, arg1)	\
	Perl_warn(aTHX_ "WARNING Convert bytecode: " f, arg1)
#define HEADER_WARN2(f, arg1, arg2)	\
	Perl_warn(aTHX_ "WARNING Convert bytecode: " f, arg1, arg2)

/*
 * Local variables:
 *   c-indent-level: 4
 * End:
 * vim: expandtab shiftwidth=4:
 */
