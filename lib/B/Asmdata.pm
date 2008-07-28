# -#- buffer-read-only: t -#-
#
#      Copyright (c) 1996-1999 Malcolm Beattie
#      Copyright (c) 2008 Reini Urban
#
#      You may distribute under the terms of either the GNU General Public
#      License or the Artistic License, as specified in the README file.
#
#
#
# This file is autogenerated from bytecode.pl. Changes made here will be lost.
#
package B::Asmdata;

our $VERSION = '1.02_01';

use Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(%insn_data @insn_name @optype @specialsv_name);
our(%insn_data, @insn_name);

use B qw(@optype @specialsv_name);

# XXX insn_data is initialised this way because with a large
# %insn_data = (foo => [...], bar => [...], ...) initialiser
# I get a hard-to-track-down stack underflow and segfault.
$insn_data{comment} = [35, \&PUT_comment_t, "GET_comment_t"];
$insn_data{nop} = [10, \&PUT_none, "GET_none"];
$insn_data{ret} = [0, \&PUT_none, "GET_none"];
$insn_data{ldsv} = [1, \&PUT_svindex, "GET_svindex"];
$insn_data{ldop} = [2, \&PUT_opindex, "GET_opindex"];
$insn_data{stsv} = [3, \&PUT_U32, "GET_U32"];
$insn_data{stop} = [4, \&PUT_U32, "GET_U32"];
$insn_data{stpv} = [5, \&PUT_U32, "GET_U32"];
$insn_data{ldspecsv} = [6, \&PUT_U8, "GET_U8"];
$insn_data{ldspecsvx} = [7, \&PUT_U8, "GET_U8"];
$insn_data{newsv} = [8, \&PUT_U8, "GET_U8"];
$insn_data{newsvx} = [9, \&PUT_U32, "GET_U32"];
$insn_data{newop} = [11, \&PUT_U8, "GET_U8"];
$insn_data{newopx} = [12, \&PUT_U16, "GET_U16"];
$insn_data{newopn} = [13, \&PUT_U8, "GET_U8"];
$insn_data{newpv} = [14, \&PUT_PV, "GET_PV"];
$insn_data{pv_cur} = [15, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{pv_free} = [16, \&PUT_none, "GET_none"];
$insn_data{sv_upgrade} = [17, \&PUT_U8, "GET_U8"];
$insn_data{sv_refcnt} = [18, \&PUT_U32, "GET_U32"];
$insn_data{sv_refcnt_add} = [19, \&PUT_I32, "GET_I32"];
$insn_data{sv_flags} = [20, \&PUT_U32, "GET_U32"];
$insn_data{xrv} = [21, \&PUT_svindex, "GET_svindex"];
$insn_data{xpv} = [22, \&PUT_none, "GET_none"];
$insn_data{xpv_cur} = [23, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{xpv_len} = [24, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{xiv} = [25, \&PUT_IV, "GET_IV"];
$insn_data{xnv} = [26, \&PUT_NV, "GET_NV"];
$insn_data{xlv_targoff} = [27, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{xlv_targlen} = [28, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{xlv_targ} = [29, \&PUT_svindex, "GET_svindex"];
$insn_data{xlv_type} = [30, \&PUT_U8, "GET_U8"];
$insn_data{xbm_useful} = [31, \&PUT_I32, "GET_I32"];
$insn_data{xbm_previous} = [32, \&PUT_U16, "GET_U16"];
$insn_data{xbm_rare} = [33, \&PUT_U8, "GET_U8"];
$insn_data{xfm_lines} = [34, \&PUT_IV, "GET_IV"];
$insn_data{xio_lines} = [36, \&PUT_IV, "GET_IV"];
$insn_data{xio_page} = [37, \&PUT_IV, "GET_IV"];
$insn_data{xio_page_len} = [38, \&PUT_IV, "GET_IV"];
$insn_data{xio_lines_left} = [39, \&PUT_IV, "GET_IV"];
$insn_data{xio_top_name} = [40, \&PUT_pvindex, "GET_pvindex"];
$insn_data{xio_top_gv} = [41, \&PUT_svindex, "GET_svindex"];
$insn_data{xio_fmt_name} = [42, \&PUT_pvindex, "GET_pvindex"];
$insn_data{xio_fmt_gv} = [43, \&PUT_svindex, "GET_svindex"];
$insn_data{xio_bottom_name} = [44, \&PUT_pvindex, "GET_pvindex"];
$insn_data{xio_bottom_gv} = [45, \&PUT_svindex, "GET_svindex"];
$insn_data{xio_type} = [46, \&PUT_U8, "GET_U8"];
$insn_data{xio_flags} = [47, \&PUT_U8, "GET_U8"];
$insn_data{xcv_xsubany} = [48, \&PUT_svindex, "GET_svindex"];
$insn_data{xcv_stash} = [49, \&PUT_svindex, "GET_svindex"];
$insn_data{xcv_start} = [50, \&PUT_opindex, "GET_opindex"];
$insn_data{xcv_root} = [51, \&PUT_opindex, "GET_opindex"];
$insn_data{xcv_gv} = [52, \&PUT_svindex, "GET_svindex"];
$insn_data{xcv_file} = [53, \&PUT_pvindex, "GET_pvindex"];
$insn_data{xcv_depth} = [54, \&PUT_long, "GET_long"];
$insn_data{xcv_padlist} = [55, \&PUT_svindex, "GET_svindex"];
$insn_data{xcv_outside} = [56, \&PUT_svindex, "GET_svindex"];
$insn_data{xcv_outside_seq} = [57, \&PUT_U32, "GET_U32"];
$insn_data{xcv_flags} = [58, \&PUT_U16, "GET_U16"];
$insn_data{av_extend} = [59, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{av_pushx} = [60, \&PUT_svindex, "GET_svindex"];
$insn_data{av_push} = [61, \&PUT_svindex, "GET_svindex"];
$insn_data{xav_fill} = [62, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{xav_max} = [63, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{xav_flags} = [64, \&PUT_I32, "GET_I32"];
$insn_data{xhv_name} = [65, \&PUT_pvindex, "GET_pvindex"];
$insn_data{hv_store} = [66, \&PUT_svindex, "GET_svindex"];
$insn_data{sv_magic} = [67, \&PUT_U8, "GET_U8"];
$insn_data{mg_obj} = [68, \&PUT_svindex, "GET_svindex"];
$insn_data{mg_private} = [69, \&PUT_U16, "GET_U16"];
$insn_data{mg_flags} = [70, \&PUT_U8, "GET_U8"];
$insn_data{mg_name} = [71, \&PUT_pvcontents, "GET_pvcontents"];
$insn_data{mg_namex} = [72, \&PUT_svindex, "GET_svindex"];
$insn_data{xmg_stash} = [73, \&PUT_svindex, "GET_svindex"];
$insn_data{gv_fetchpv} = [74, \&PUT_strconst, "GET_strconst"];
$insn_data{gv_fetchpvx} = [75, \&PUT_strconst, "GET_strconst"];
$insn_data{gv_stashpv} = [76, \&PUT_strconst, "GET_strconst"];
$insn_data{gv_stashpvx} = [77, \&PUT_strconst, "GET_strconst"];
$insn_data{gp_sv} = [78, \&PUT_svindex, "GET_svindex"];
$insn_data{gp_refcnt} = [79, \&PUT_U32, "GET_U32"];
$insn_data{gp_refcnt_add} = [80, \&PUT_I32, "GET_I32"];
$insn_data{gp_av} = [81, \&PUT_svindex, "GET_svindex"];
$insn_data{gp_hv} = [82, \&PUT_svindex, "GET_svindex"];
$insn_data{gp_cv} = [83, \&PUT_svindex, "GET_svindex"];
$insn_data{gp_file} = [84, \&PUT_hekindex, "GET_hekindex"];
$insn_data{gp_io} = [85, \&PUT_svindex, "GET_svindex"];
$insn_data{gp_form} = [86, \&PUT_svindex, "GET_svindex"];
$insn_data{gp_cvgen} = [87, \&PUT_U32, "GET_U32"];
$insn_data{gp_line} = [88, \&PUT_U32, "GET_U32"];
$insn_data{gp_share} = [89, \&PUT_svindex, "GET_svindex"];
$insn_data{xgv_flags} = [90, \&PUT_U8, "GET_U8"];
$insn_data{op_next} = [91, \&PUT_opindex, "GET_opindex"];
$insn_data{op_sibling} = [92, \&PUT_opindex, "GET_opindex"];
$insn_data{op_ppaddr} = [93, \&PUT_strconst, "GET_strconst"];
$insn_data{op_targ} = [94, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{op_type} = [95, \&PUT_U16, "GET_U16"];
$insn_data{op_opt} = [96, \&PUT_U8, "GET_U8"];
$insn_data{op_latefree} = [97, \&PUT_U8, "GET_U8"];
$insn_data{op_latefreed} = [98, \&PUT_U8, "GET_U8"];
$insn_data{op_attached} = [99, \&PUT_U8, "GET_U8"];
$insn_data{op_flags} = [100, \&PUT_U8, "GET_U8"];
$insn_data{op_private} = [101, \&PUT_U8, "GET_U8"];
$insn_data{op_first} = [102, \&PUT_opindex, "GET_opindex"];
$insn_data{op_last} = [103, \&PUT_opindex, "GET_opindex"];
$insn_data{op_other} = [104, \&PUT_opindex, "GET_opindex"];
$insn_data{op_pmreplroot} = [105, \&PUT_opindex, "GET_opindex"];
$insn_data{op_pmreplstart} = [106, \&PUT_opindex, "GET_opindex"];
$insn_data{op_pmstashpv} = [107, \&PUT_pvindex, "GET_pvindex"];
$insn_data{op_pmreplrootpo} = [108, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{op_pmstash} = [109, \&PUT_svindex, "GET_svindex"];
$insn_data{op_pmreplrootgv} = [110, \&PUT_svindex, "GET_svindex"];
$insn_data{pregcomp} = [111, \&PUT_pvcontents, "GET_pvcontents"];
$insn_data{op_pmflags} = [112, \&PUT_U16, "GET_U16"];
$insn_data{op_sv} = [113, \&PUT_svindex, "GET_svindex"];
$insn_data{op_padix} = [114, \&PUT_PADOFFSET, "GET_PADOFFSET"];
$insn_data{op_pv} = [115, \&PUT_pvcontents, "GET_pvcontents"];
$insn_data{op_pv_tr} = [116, \&PUT_op_tr_array, "GET_op_tr_array"];
$insn_data{op_redoop} = [117, \&PUT_opindex, "GET_opindex"];
$insn_data{op_nextop} = [118, \&PUT_opindex, "GET_opindex"];
$insn_data{op_lastop} = [119, \&PUT_opindex, "GET_opindex"];
$insn_data{cop_label} = [120, \&PUT_pvindex, "GET_pvindex"];
$insn_data{cop_stash} = [121, \&PUT_svindex, "GET_svindex"];
$insn_data{cop_filegv} = [122, \&PUT_svindex, "GET_svindex"];
$insn_data{cop_seq} = [123, \&PUT_U32, "GET_U32"];
$insn_data{cop_line} = [124, \&PUT_U32, "GET_U32"];
$insn_data{cop_warnings} = [125, \&PUT_svindex, "GET_svindex"];
$insn_data{main_start} = [126, \&PUT_opindex, "GET_opindex"];
$insn_data{main_root} = [127, \&PUT_opindex, "GET_opindex"];
$insn_data{main_cv} = [128, \&PUT_svindex, "GET_svindex"];
$insn_data{curpad} = [129, \&PUT_svindex, "GET_svindex"];
$insn_data{push_begin} = [130, \&PUT_svindex, "GET_svindex"];
$insn_data{push_init} = [131, \&PUT_svindex, "GET_svindex"];
$insn_data{push_end} = [132, \&PUT_svindex, "GET_svindex"];
$insn_data{curstash} = [133, \&PUT_svindex, "GET_svindex"];
$insn_data{defstash} = [134, \&PUT_svindex, "GET_svindex"];
$insn_data{data} = [135, \&PUT_U8, "GET_U8"];
$insn_data{incav} = [136, \&PUT_svindex, "GET_svindex"];
$insn_data{load_glob} = [137, \&PUT_svindex, "GET_svindex"];
$insn_data{dowarn} = [138, \&PUT_U8, "GET_U8"];
$insn_data{comppad_name} = [139, \&PUT_svindex, "GET_svindex"];
$insn_data{xgv_stash} = [140, \&PUT_svindex, "GET_svindex"];
$insn_data{signal} = [141, \&PUT_strconst, "GET_strconst"];
$insn_data{formfeed} = [142, \&PUT_svindex, "GET_svindex"];

my ($insn_name, $insn_data);
while (($insn_name, $insn_data) = each %insn_data) {
    $insn_name[$insn_data->[0]] = $insn_name;
}
# Fill in any gaps
@insn_name = map($_ || "unused", @insn_name);

1;

__END__

=head1 NAME

B::Asmdata - Autogenerated data about Perl ops, used to generate bytecode

=head1 SYNOPSIS

	use B::Asmdata qw(%insn_data @insn_name @optype @specialsv_name);

=head1 DESCRIPTION

Provides information about Perl ops in order to generate bytecode via
a bunch of exported variables.  Its mostly used by B::Assembler and
B::Disassembler.

=over 4

=item %insn_data

  my($bytecode_num, $put_sub, $get_meth) = @$insn_data{$op_name};

For a given $op_name (for example, 'cop_label', 'sv_flags', etc...)
you get an array ref containing the bytecode number of the op, a
reference to the subroutine used to 'PUT' the op argument to the bytecode stream,
and the name of the method used to 'GET' op argument from the bytecode stream.

Most ops require one arg, in fact all ops without the PUT/GET_none methods,
and the GET and PUT methods are used to en-/decode the arg to binary bytecode.
The names are constructed from the GET/PUT prefix and the argument type,
such as U8, U16, U32, svindex, opindex, pvindex, ...

The PUT method is used in the L<B::Bytecode> compiler within L<B::Assembler>,
the GET method just for the L<B::Disassembler>.
The GET method is not used by the binary L<ByteLoader> module.

A full C<insn> table with version, opcode, name, lvalue, argtype and flags
is located as DATA in F<bytecode.pl>.

=item @insn_name

  my $op_name = $insn_name[$bytecode_num];

A simple mapping of the bytecode number to the name of the op.
Suitable for using with %insn_data like so:

  my $op_info = $insn_data{$insn_name[$bytecode_num]};

=item @optype

  my $op_type = $optype[$op_type_num];

A simple mapping of the op type number to its type (like 'COP' or 'BINOP').

Since Perl version 5.10 defined in L<B>.

=item @specialsv_name

  my $sv_name = $specialsv_name[$sv_index];

Certain SV types are considered 'special'.  They're represented by
B::SPECIAL and are referred to by a number from the specialsv_list.
This array maps that number back to the name of the SV (like 'Nullsv'
or '&PL_sv_undef').

Since Perl version 5.10 defined in L<B>.

=back

=head1 PORTABILITY  (TODO)

All bytecode values are already portable.
Cross-platform and cross-version portability is just not implemented yet.
Cross-version portability will be very limited, cross-platform will
do with the same threading model.

=head2 CROSS-PLATFORM PORTABILITY (TODO)

For different endian-ness there are ByteLoader converters planned.
Header entry: byteorder.

64int - 64all - 32int is portable. Header entry: ivsize

Threading: unsolvable. Header entry: archname has "-thread"

Cross-platform portability will be available only if threading
is on or off on both perls (compiler and runner). TODO: Check in
bytecode_header_check().

=head2 CROSS-VERSION PORTABILITY (TODO)

Bytecode ops:
We can only reliably load bytecode from previous versions and promise
that from 5.10.0 on future versions will only add new op numbers at
the end, but will never replace old opcodes with incompatible arguments.
On the first unknown bytecode op from a future version we will die.

TODO: Bytecode opcode op-matrix

We will need a table of all bytecode ops for all previous perl
versions. And replacements in the byteloader for all the unsupported
ops, like xiv64, cop_arybase.

TODO: Perl opcode op-matrix

The ByteLoader will need a op matrix of all previous perl versions
to be able to map the old bytecode op to the new perl pp function.

=head1 AUTHOR

Malcolm Beattie, C<mbeattie@sable.ox.ac.uk>

Reini Urban added the version logic, 5.10 support, portability.

=cut

# ex: set ro:
