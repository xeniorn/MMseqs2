#!/bin/sh -e
# Iterative sequence search workflow script
fail() {
    echo "Error: $1"
    exit 1
}

notExists() {
	[ ! -f "$1" ]
}

#pre processing
[ -z "$MMSEQS" ] && echo "Please set the environment variable \$MMSEQS to your MMSEQS binary." && exit 1;
# check amount of input variables
[ "$#" -ne 4 ] && echo "Please provide <queryDB> <targetDB> <outDB> <tmp>" && exit 1;
# check if files exists
[ ! -f "$1" ] &&  echo "$1 not found!" && exit 1;
[ ! -f "$2" ] &&  echo "$2 not found!" && exit 1;
[   -f "$3" ] &&  echo "$3 exists already!" && exit 1;
[ ! -d "$4" ] &&  echo "tmp directory $4 not found!" && mkdir -p "$4";

QUERYDB="$1"
TMP_PATH="$4"

STEP=0
# processing
[ -z "$NUM_IT" ] && NUM_IT=3;
while [ $STEP -lt $NUM_IT ]; do
    # call prefilter module
    if notExists "$TMP_PATH/pref_$STEP.dbtype"; then
        PARAM="PREFILTER_PAR_$STEP"
        eval TMP="\$$PARAM"
        # shellcheck disable=SC2086
        $RUNNER "$MMSEQS" prefilter "$QUERYDB" "$2" "$TMP_PATH/pref_$STEP" ${TMP} \
            || fail "Prefilter died"
    fi

    if [ $STEP -ge 1 ]; then
        if notExists "$TMP_PATH/pref_$STEP.hasnext"; then
            STEPONE=$((STEP+1))
            # shellcheck disable=SC2086

            "$MMSEQS" subtractdbs "$TMP_PATH/pref_$STEP" "$TMP_PATH/aln_$STEPONE" "$TMP_PATH/pref_$STEPONE" $SUBSTRACT_PAR \
            || fail "Substract died"
            #mv -f "$TMP_PATH/pref_next_$STEP" "$TMP_PATH/pref_$STEP"
            #mv -f "$TMP_PATH/pref_next_$STEP.index" "$TMP_PATH/pref_$STEP.index"
            touch "$TMP_PATH/pref_$STEP.hasnext"
        fi
    fi

	# call alignment module
	if notExists "$TMP_PATH/aln_$STEP.dbtype"; then
	    PARAM="ALIGNMENT_PAR_$STEP"
        eval TMP="\$$PARAM"
        STEPONE=$((STEP+1))
        STEPTWO=$((STEP+2))
        # shellcheck disable=SC2086
        if [ $STEP -eq 0 ]; then
            $RUNNER "$MMSEQS" "${ALIGN_MODULE}" "$QUERYDB" "$2" "$TMP_PATH/pref_$STEP" "$TMP_PATH/aln_$STEPTWO" ${TMP} \
                || fail "Alignment died"
        else
            $RUNNER "$MMSEQS" "${ALIGN_MODULE}" "$QUERYDB" "$2" "$TMP_PATH/pref_$STEPONE" "$TMP_PATH/aln_$STEP" ${TMP} \
                || fail "Alignment died"
        fi
    fi

    if [ $STEP -gt 0 ]; then
        if notExists "$TMP_PATH/aln_$STEP.hasmerge"; then
            STEPONE=$((STEP+1))
            STEPTWO=$((STEP+2))
            if [ $STEP -ne $((NUM_IT  - 1)) ]; then
                "$MMSEQS" mergedbs "$QUERYDB" "$TMP_PATH/aln_$STEPTWO" "$TMP_PATH/aln_$STEPONE" "$TMP_PATH/aln_$STEP" \
                    || fail "Alignment died"
            else
                "$MMSEQS" mergedbs "$QUERYDB" "$3" "$TMP_PATH/aln_$STEPONE" "$TMP_PATH/aln_$STEP" \
                        || fail "Alignment died"
            fi
            rm -f "$TMP_PATH/aln_$STEPONE*"
            touch "$TMP_PATH/aln_$STEP.hasmerge"
        fi
    fi

# create profiles
    if [ $STEP -ne $((NUM_IT  - 1)) ]; then
        if notExists "$TMP_PATH/profile_$STEP.dbtype"; then
            PARAM="PROFILE_PAR_$STEP"
            eval TMP="\$$PARAM"
            # shellcheck disable=SC2086
            $RUNNER "$MMSEQS" result2profile "$QUERYDB" "$2" "$TMP_PATH/aln_$STEPTWO" "$TMP_PATH/profile_$STEP" ${TMP} \
            || fail "Create profile died"
        fi
    fi
	QUERYDB="$TMP_PATH/profile_$STEP"

	STEP=$((STEP+1))
done

if [ -n "$REMOVE_TMP" ]; then
    echo "Remove temporary files"
    STEP=0
    while [ "$STEP" -lt "$NUM_IT" ]; do
        "$MMSEQS" rmdb "${TMP_PATH}/pref_$STEP"
        "$MMSEQS" rmdb "${TMP_PATH}/aln_$STEP"
        "$MMSEQS" rmdb "${TMP_PATH}/profile_$STEP"
        STEP=$((STEP+1))
    done
    rm -f "$TMP_PATH/blastpgp.sh"
fi

