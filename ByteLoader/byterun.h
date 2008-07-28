/* -*- buffer-read-only: t -*-
 *
 *      Copyright (c) 1996-1999 Malcolm Beattie
 *      Copyright (c) 2008 Reini Urban
 *
 *      You may distribute under the terms of either the GNU General Public
 *      License or the Artistic License, as specified in the README file.
 *
 */
/*
 * This file is autogenerated from bytecode.pl. Changes made here will be lost.
 */
#if PERL_VERSION < 10
#define PL_RSFP PL_rsfp
#else
#define PL_RSFP PL_parser->rsfp
#endif

struct byteloader_fdata {
    SV	*datasv;
    int next_out;
    int	idx;
};

struct byteloader_state {
    struct byteloader_fdata	*bs_fdata;
    SV				*bs_sv;
    void			**bs_obj_list;
    int				bs_obj_list_fill;
    int				bs_ix;
#if PERL_VERSION < 9
    XPV				bs_pv;
#else
    XPVIV			bs_pv;
#endif
    int				bs_iv_overflows;
};

int bl_getc(struct byteloader_fdata *);
int bl_read(struct byteloader_fdata *, char *, size_t, size_t);
extern int byterun(pTHX_ register struct byteloader_state *);
/*extern int jitrun(pTHX_ register struct byteloader_state *);*/

enum {
    INSN_RET,			/* 0 */
    INSN_LDSV,			/* 1 */
    INSN_LDOP,			/* 2 */
    INSN_STSV,			/* 3 */
    INSN_STOP,			/* 4 */
    INSN_STPV,			/* 5 */
    INSN_LDSPECSV,			/* 6 */
    INSN_LDSPECSVX,			/* 7 */
    INSN_NEWSV,			/* 8 */
    INSN_NEWSVX,			/* 9 */
    INSN_NOP,			/* 10 */
    INSN_NEWOP,			/* 11 */
    INSN_NEWOPX,			/* 12 */
    INSN_NEWOPN,			/* 13 */
    INSN_NEWPV,			/* 14 */
    INSN_PV_CUR,			/* 15 */
    INSN_PV_FREE,			/* 16 */
    INSN_SV_UPGRADE,			/* 17 */
    INSN_SV_REFCNT,			/* 18 */
    INSN_SV_REFCNT_ADD,			/* 19 */
    INSN_SV_FLAGS,			/* 20 */
    INSN_XRV,			/* 21 */
    INSN_XPV,			/* 22 */
    INSN_XPV_CUR,			/* 23 */
    INSN_XPV_LEN,			/* 24 */
    INSN_XIV,			/* 25 */
    INSN_XNV,			/* 26 */
    INSN_XLV_TARGOFF,			/* 27 */
    INSN_XLV_TARGLEN,			/* 28 */
    INSN_XLV_TARG,			/* 29 */
    INSN_XLV_TYPE,			/* 30 */
    INSN_XBM_USEFUL,			/* 31 */
    INSN_XBM_PREVIOUS,			/* 32 */
    INSN_XBM_RARE,			/* 33 */
    INSN_XFM_LINES,			/* 34 */
    INSN_COMMENT,			/* 35 */
    INSN_XIO_LINES,			/* 36 */
    INSN_XIO_PAGE,			/* 37 */
    INSN_XIO_PAGE_LEN,			/* 38 */
    INSN_XIO_LINES_LEFT,			/* 39 */
    INSN_XIO_TOP_NAME,			/* 40 */
    INSN_XIO_TOP_GV,			/* 41 */
    INSN_XIO_FMT_NAME,			/* 42 */
    INSN_XIO_FMT_GV,			/* 43 */
    INSN_XIO_BOTTOM_NAME,			/* 44 */
    INSN_XIO_BOTTOM_GV,			/* 45 */
    INSN_XIO_TYPE,			/* 46 */
    INSN_XIO_FLAGS,			/* 47 */
    INSN_XCV_XSUBANY,			/* 48 */
    INSN_XCV_STASH,			/* 49 */
    INSN_XCV_START,			/* 50 */
    INSN_XCV_ROOT,			/* 51 */
    INSN_XCV_GV,			/* 52 */
    INSN_XCV_FILE,			/* 53 */
    INSN_XCV_DEPTH,			/* 54 */
    INSN_XCV_PADLIST,			/* 55 */
    INSN_XCV_OUTSIDE,			/* 56 */
    INSN_XCV_OUTSIDE_SEQ,			/* 57 */
    INSN_XCV_FLAGS,			/* 58 */
    INSN_AV_EXTEND,			/* 59 */
    INSN_AV_PUSHX,			/* 60 */
    INSN_AV_PUSH,			/* 61 */
    INSN_XAV_FILL,			/* 62 */
    INSN_XAV_MAX,			/* 63 */
    INSN_XAV_FLAGS,			/* 64 */
    INSN_XHV_NAME,			/* 65 */
    INSN_HV_STORE,			/* 66 */
    INSN_SV_MAGIC,			/* 67 */
    INSN_MG_OBJ,			/* 68 */
    INSN_MG_PRIVATE,			/* 69 */
    INSN_MG_FLAGS,			/* 70 */
    INSN_MG_NAME,			/* 71 */
    INSN_MG_NAMEX,			/* 72 */
    INSN_XMG_STASH,			/* 73 */
    INSN_GV_FETCHPV,			/* 74 */
    INSN_GV_FETCHPVX,			/* 75 */
    INSN_GV_STASHPV,			/* 76 */
    INSN_GV_STASHPVX,			/* 77 */
    INSN_GP_SV,			/* 78 */
    INSN_GP_REFCNT,			/* 79 */
    INSN_GP_REFCNT_ADD,			/* 80 */
    INSN_GP_AV,			/* 81 */
    INSN_GP_HV,			/* 82 */
    INSN_GP_CV,			/* 83 */
    INSN_GP_FILE,			/* 84 */
    INSN_GP_IO,			/* 85 */
    INSN_GP_FORM,			/* 86 */
    INSN_GP_CVGEN,			/* 87 */
    INSN_GP_LINE,			/* 88 */
    INSN_GP_SHARE,			/* 89 */
    INSN_XGV_FLAGS,			/* 90 */
    INSN_OP_NEXT,			/* 91 */
    INSN_OP_SIBLING,			/* 92 */
    INSN_OP_PPADDR,			/* 93 */
    INSN_OP_TARG,			/* 94 */
    INSN_OP_TYPE,			/* 95 */
    INSN_OP_OPT,			/* 96 */
    INSN_OP_LATEFREE,			/* 97 */
    INSN_OP_LATEFREED,			/* 98 */
    INSN_OP_ATTACHED,			/* 99 */
    INSN_OP_FLAGS,			/* 100 */
    INSN_OP_PRIVATE,			/* 101 */
    INSN_OP_FIRST,			/* 102 */
    INSN_OP_LAST,			/* 103 */
    INSN_OP_OTHER,			/* 104 */
    INSN_OP_PMREPLROOT,			/* 105 */
    INSN_OP_PMREPLSTART,			/* 106 */
    INSN_OP_PMSTASHPV,			/* 107 */
    INSN_OP_PMREPLROOTPO,			/* 108 */
    INSN_OP_PMREPLROOTGV,			/* 109 */
    INSN_PREGCOMP,			/* 110 */
    INSN_OP_PMFLAGS,			/* 111 */
    INSN_OP_SV,			/* 112 */
    INSN_OP_PADIX,			/* 113 */
    INSN_OP_PV,			/* 114 */
    INSN_OP_PV_TR,			/* 115 */
    INSN_OP_REDOOP,			/* 116 */
    INSN_OP_NEXTOP,			/* 117 */
    INSN_OP_LASTOP,			/* 118 */
    INSN_COP_LABEL,			/* 119 */
    INSN_COP_STASHPV,			/* 120 */
    INSN_COP_FILE,			/* 121 */
    INSN_COP_SEQ,			/* 122 */
    INSN_COP_LINE,			/* 123 */
    INSN_COP_WARNINGS,			/* 124 */
    INSN_MAIN_START,			/* 125 */
    INSN_MAIN_ROOT,			/* 126 */
    INSN_MAIN_CV,			/* 127 */
    INSN_CURPAD,			/* 128 */
    INSN_PUSH_BEGIN,			/* 129 */
    INSN_PUSH_INIT,			/* 130 */
    INSN_PUSH_END,			/* 131 */
    INSN_CURSTASH,			/* 132 */
    INSN_DEFSTASH,			/* 133 */
    INSN_DATA,			/* 134 */
    INSN_INCAV,			/* 135 */
    INSN_LOAD_GLOB,			/* 136 */
    INSN_REGEX_PADAV,			/* 137 */
    INSN_DOWARN,			/* 138 */
    INSN_COMPPAD_NAME,			/* 139 */
    INSN_XGV_STASH,			/* 140 */
    INSN_SIGNAL,			/* 141 */
    INSN_FORMFEED,			/* 142 */
    MAX_INSN = 142
};

enum {
    OPt_OP,		/* 0 */
    OPt_UNOP,		/* 1 */
    OPt_BINOP,		/* 2 */
    OPt_LOGOP,		/* 3 */
    OPt_LISTOP,		/* 4 */
    OPt_PMOP,		/* 5 */
    OPt_SVOP,		/* 6 */
    OPt_PADOP,		/* 7 */
    OPt_PVOP,		/* 8 */
    OPt_LOOP,		/* 9 */
    OPt_COP		/* 10 */
};

/* ex: set ro: */
