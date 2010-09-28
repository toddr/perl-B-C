#!/bin/bash
# t/testm.sh File::Temp
# => $^X -Mblib blib/script/perlcc -S -e 'use File::Temp; print "ok"' -o file_temp
#
# How to installed skip modules: 
# t/testm.sh -s runs:
#   grep ^skip log.modules-$ver|cut -c6-| xargs perl$ver -S cpan
# perl$ver -S cpan `grep -v '#' t/mymodules`
#
# -t runs CPAN::Shell->testcc($module)

function help {
  echo "t/testm.sh [OPTIONS] [module|modules-file]..."
  echo " -k                 keep temp. files on PASS"
  echo " -D<arg>            add debugging flags"
  echo " -l                 log"
  echo " -o                 orig. no -Mblib, use installed modules (5.6, 5.8)"
  echo " -t                 run the module tests also, not only use Module (experimental)"
  echo " -s                 install skipped (missing) modules"
  echo " -T                 time compilation and run"
  echo " -h                 help"
}

# use the actual perl from the Makefile (perl5.8.8, 
# perl5.10.0d-nt, perl5.11.0, ...)
PERL=`grep "^PERL =" Makefile|cut -c8-`
PERL=${PERL:-perl}
Mblib=-Mblib

function vcmd {
    test -n "$QUIET" || echo $*
    $*
}

function pass {
    echo -e -n "\e[1;32mPASS \e[0;0m"
    shift
    echo $*
    echo
}
function fail {
    echo -e -n "\e[1;31mFAIL \e[0;0m"
    shift
    echo $*
    echo
}

while getopts "hokltTsD:O:f:" opt
do
  if [ "$opt" = "o" ]; then Mblib=" "; init; fi
  if [ "$opt" = "k" ]; then KEEP="$KEEP -S"; fi
  if [ "$opt" = "D" ]; then KEEP="$KEEP -Wb=-D${OPTARG}"; fi
  if [ "$opt" = "O" ]; then KEEP="$KEEP -Wb=-O${OPTARG}"; fi
  if [ "$opt" = "f" ]; then KEEP="$KEEP -Wb=-f${OPTARG}"; fi
  if [ "$opt" = "l" ]; then TEST="-log"; fi
  if [ "$opt" = "t" ]; then TEST="-t"; fi
  if [ "$opt" = "T" ]; then PERLCC_OPTS="$PERLCC_OPTS --time"; PERLCC_TIMEOUT=120; fi
  if [ "$opt" = "s" ]; then 
      v=$($PERL -It -Mmodules -e'print perlversion')
      if [ -f log.modules-$v ]; then # and not older than a few days
          grep ^skip log.modules-$v | perl -anle 'print $F[1]' | xargs $PERL -S cpan
      else
          $PERL -S cpan $($PERL $Mblib -It -Mmodules -e'$,=" "; print skip_modules')
      fi
      exit
  fi
  if [ "$opt" = "h" ]; then help; exit; fi
done

if [ -z "$QUIET" ]; then
    make 
else
    make --silent >/dev/null
fi

# need to shift the options
while [ -n "$1" -a "${1:0:1}" = "-" ]; do shift; done

PERLCC_TIMEOUT=120
if [ -n "$1" ]; then
    if [ -f "$1" ]; then
	# run a mymodules.t like test
	$PERL $Mblib t/modules.t $TEST "$1"
    else
	while [ -n "$1" ]; do
	    # single module. update,setup,install are UAC terms
	    name="$(perl -e'$a=shift;$a=~s{::}{_}g;$a=~s{(install|setup|update)}{substr($1,0,4)}ie;print lc($a)' $1)"
	    if [ "${KEEP:0:2}" = "-D" ]; then
	      echo $PERL $Mblib -MO=C,$KEEP,-o$name.c -e "\"use $1; print 'ok'\""
	      $PERL $Mblib -MO=C,$KEEP,-o$name.c -e "use $1; print 'ok'"
	      if [ -f $name.c ]; then
		echo $PERL $Mblib script/cc_harness -d -g3 -o$name $name.c
		$PERL $Mblib script/cc_harness -d -g3 -o$name $name.c
		if [ -f $name ]; then
		  echo "running ./$name"
		  ./$name
		fi
	      fi
	    else
	      echo $PERL $Mblib blib/script/perlcc $PERLCC_OPTS -r $KEEP -e "\"use $1; print 'ok'\"" -o $name
	      $PERL $Mblib blib/script/perlcc $PERLCC_OPTS -r $KEEP -e "use $1; print 'ok'" -o $name
              test -f a.out.c && mv a.out.c $name.c
            fi
	    [ -n "$TEST" ] && $PERL $Mblib -It -MCPAN -Mmodules -e"CPAN::Shell->testcc(q($1))"
	    shift
	done
    fi
else
    $PERL $Mblib t/modules.t $TEST
fi
