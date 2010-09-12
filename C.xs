/* This XS part is unused since B-C-1.18 for all perls > 5.7 */

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#ifndef PM_GETRE
# if defined(USE_ITHREADS) && (PERL_VERSION > 8)
#  define PM_GETRE(o)     (INT2PTR(REGEXP*,SvIVX(PL_regex_pad[(o)->op_pmoffset])))
# else
#  define PM_GETRE(o)     ((o)->op_pmregexp)
# endif
#endif

typedef struct magic* B__MAGIC;

#if PERL_VERSION < 7

static int
my_runops(pTHX)
{
    HV* regexp_hv = get_hv( "B::C::REGEXP", 0 );
    SV* key = newSViv( 0 );

    do {
	PERL_ASYNC_CHECK();

        if( PL_op->op_type == OP_QR ) {
            PMOP* op;
            REGEXP* rx = PM_GETRE( (PMOP*)PL_op );
            SV* rv = newSViv( 0 );

            New(0, op, 1, PMOP );
            Copy( PL_op, op, 1, PMOP );
            /* we need just the flags */
            op->op_next = NULL;
            op->op_sibling = NULL;
            op->op_first = NULL;
            op->op_last = NULL;

            op->op_pmreplroot = NULL;
            op->op_pmreplstart = NULL;
            op->op_pmnext = NULL;
            op->op_pmregexp = 0;

            sv_setiv( key, PTR2IV( rx ) );
            sv_setref_iv( rv, "B::PMOP", PTR2IV( op ) );

            hv_store_ent( regexp_hv, key, rv, 0 );
        }
    } while ((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX)));

    SvREFCNT_dec( key );

    TAINT_NOT;
    return 0;
}
#endif

MODULE = B__MAGIC	PACKAGE = B::MAGIC

#if PERL_VERSION < 7

SV*
precomp(mg)
        B::MAGIC        mg
    CODE:
        if (mg->mg_type == 'r') {
            REGEXP* rx = (REGEXP*)mg->mg_obj;
            RETVAL = Nullsv;
            if( rx )
                RETVAL = newSVpvn( rx->precomp, rx->prelen );
        }
        else {
            croak( "precomp is only meaningful on r-magic" );
        }
    OUTPUT:
        RETVAL

#endif

MODULE=B__C 	PACKAGE=B::C

PROTOTYPES: DISABLE

#if PERL_VERSION < 7

BOOT:
    PL_runops = my_runops;

#endif
