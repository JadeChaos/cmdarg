#!/bin/bash

if (( BASH_VERSINFO[0] < 4 )); then
    echo "cmdarg is incompatible with bash versions < 4, please upgrade bash" >&2
    exit 1
fi

CMDARG_ERROR_BEHAVIOR=return

CMDARG_FLAG_NOARG=0
CMDARG_FLAG_REQARG=2
CMDARG_FLAG_OPTARG=4

CMDARG_TYPE_ARRAY=1
CMDARG_TYPE_HASH=2
CMDARG_TYPE_STRING=3
CMDARG_TYPE_BOOLEAN=4

function cmdarg
{
    # cmdarg <option> <key> <description> [default value] [validator function]
    #
    # option : The short name (single letter) of the option
    # key : The long key that should be placed into cmdarg_cfg[] for this option
    # description : The text description for this option to be used in cmdarg_usage
    #
    # default value : The default value, if any, for the argument
    # validator : This is passed through eval(), with $OPTARG equal to the current
    #             value of the argument in question, and must return non-zero if
    #             the argument value is invalid. Can be straight bash, but it really
    #             should be the name of a function. This may be enforced in future versions
    #             of the library.
    shortopt=${1:0:1}
    key="$2"
    if [[ "$shortopt" == "h" ]]; then
	echo "-h is reserved for cmdarg usage" >&2
	${CMDARG_ERROR_BEHAVIOR} 1
    fi
    if  [[ "$(type -t cmdarg_$key)" != "" ]] || \
	[[ "${CMDARG_FLAGS[$shortopt]}" != "" ]] || \
	[[ "${CMDARG_TYPES[$key]}" != "" ]]; then
	echo "command line key '$shortopt ($key)' is reserved by cmdarg or defined twice" >&2
	${CMDARG_ERROR_BEHAVIOR} 1
    fi

    declare -A argtypemap
    argtypemap[':']=$CMDARG_FLAG_REQARG
    argtypemap['?']=$CMDARG_FLAG_OPTARG
    argtype=${1:1:1}
    if [[ "$argtype" =~ ^[\[{]$ ]]; then
	echo "Flags required [:?] when specifying Hash or Array arguments (${argtype})" >&2
	${CMDARG_ERROR_BEHAVIOR} 1
    elif [[ "$argtype" != "" ]]; then
	CMDARG_FLAGS[$shortopt]=${argtypemap["$argtype"]}
	if [[ "${1:2:4}" == "[]" ]]; then
	    declare -p ${key} >/dev/null 2>&1
	    if [[ $? -ne 0 ]]; then
		echo 'Array variable '"${key}"' does not exist. Array variables MUST be declared by the user!' >&2
		${CMDARG_ERROR_BEHAVIOR} 1
	    fi
	    CMDARG_TYPES[$key]=$CMDARG_TYPE_ARRAY
	elif [[ "${1:2:4}" == "{}" ]]; then
	    declare -p ${key} >/dev/null 2>&1
	    if [[ $? -ne 0 ]]; then
		echo 'Hash variable '"${key}"' does not exist. Hash variables MUST be declared by the user!' >&2
		${CMDARG_ERROR_BEHAVIOR} 1
	    fi
	    CMDARG_TYPES[$key]=$CMDARG_TYPE_HASH
	else
	    CMDARG_TYPES[$key]=$CMDARG_TYPE_STRING
	fi
    else
	CMDARG_FLAGS[$shortopt]=$CMDARG_FLAG_NOARG
	CMDARG_TYPES[$key]=$CMDARG_TYPE_BOOLEAN
	cmdarg_cfg[$key]=false
    fi

    CMDARG["$shortopt"]=$2
    CMDARG_REV["$2"]=$shortopt
    CMDARG_DESC["$shortopt"]=$3
    CMDARG_DEFAULT["$shortopt"]=${4:-}
    if [[ ${CMDARG_FLAGS[$shortopt]} -eq $CMDARG_FLAG_REQARG ]] && [[ "${4:-}" == "" ]]; then
	CMDARG_REQUIRED+=($shortopt)
    else
	CMDARG_OPTIONAL+=($shortopt)
    fi
    cmdarg_cfg["$2"]="${4:-}"
    local validatorfunc
    validatorfunc=${5:-}
    if [[ "$validatorfunc" != "" ]] && [[ "$(declare -F $validatorfunc)" == "" ]]; then
	echo "Validators must be bash functions accepting 1 argument (not '$validatorfunc')" >&2
	${CMDARG_ERROR_BEHAVIOR} 1
    fi
    CMDARG_VALIDATORS["$shortopt"]="$validatorfunc"
    CMDARG_GETOPTLIST="${CMDARG_GETOPTLIST}$1"
}

function cmdarg_info
{
    # cmdarg_info <flag> <value>
    #
    # Sets various flags about your script that are printed during cmdarg_usage
    #
    FLAGS="header|copyright|footer|author"
    echo "$1" | grep -E "$FLAGS" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
	echo "cmdarg_info <flag> <value>" >&2
	echo "Where <flag> is one of $FLAGS" >&2
	${CMDARG_ERROR_BEHAVIOR} 1
    fi
    CMDARG_INFO["$1"]=$2
}

function cmdarg_describe
{
    local longopt opt argtype default description flags validator
    longopt=${CMDARG[$1]}
    opt=$1
    argtype=${CMDARG_TYPES[$longopt]}
    default=${CMDARG_DEFAULT[$opt]}
    description=${CMDARG_DESC[$opt]}
    flags="${CMDARG_FLAGS[$opt]}"
    validator="${CMDARG_VALIDATORS[$opt]}"

    ${cmdarg_helpers['describe']} $longopt $opt $argtype "${default}" "${description}" "${flags}" "${validator}"
}

function cmdarg_describe_default
{
    set -u
    local longopt opt argtype default description flags validator
    longopt=$1
    opt=$2
    argtype=$3
    default="$4"
    description="$5"
    flags="$6"
    validator="${7:-}"
    set +u

    if [ "${default}" != "" ]; then
	default="(Default \"${default}\")"
    fi
    case ${argtype} in
	$CMDARG_TYPE_STRING)
	    echo "-${opt},--${longopt} v : String. ${description} ${default}"
	    ;;
	$CMDARG_TYPE_BOOLEAN)
	    echo "-${opt},--${longopt} : Boolean. ${description} ${default}"
	    ;;
	$CMDARG_TYPE_ARRAY)
	    echo "-${opt},--${longopt} v[, ...] : Array. ${description}. Pass this argument multiple times for multiple values. ${default}"
	    ;;
	$CMDARG_TYPE_HASH)
	    echo "-${opt},--${longopt} k=v{, ..} : Hash. ${description}. Pass this argument multiple times for multiple key/value pairs. ${default}"
	    ;;
	*)
	    echo "Unable to return string description for ${opt}; unknown type ${argtype}" >&2
	    ${CMDARG_ERROR_BEHAVIOR} 1
	    ;;
    esac

}

function cmdarg_usage
{
    # cmdarg_usage
    #
    # Prints a very helpful usage message about the current program.
    echo "$(basename $0) ${CMDARG_INFO['copyright']} : ${CMDARG_INFO['author']}"
    echo
    echo "${CMDARG_INFO['header']}"
    echo
    local key
    if [[ "${!CMDARG_REQUIRED[@]}" != "" ]]; then
	echo "Required Arguments:"
	for key in "${CMDARG_REQUIRED[@]}"
	do
	    echo "    $(cmdarg_describe $key)"
	done
	echo
    fi
    if [[ "${!CMDARG_OPTIONAL[@]}" != "" ]]; then
	echo "Optional Arguments":
	for key in "${CMDARG_OPTIONAL[@]}"
	do
	    echo "    $(cmdarg_describe $key)"
	done
    fi
    echo
    echo "${CMDARG_INFO['footer']}"
}

function cmdarg_validate
{
    set -u
    local longopt value
    longopt=$1
    value=$2
    hashkey=${3:-}
    set +u

    shortopt=${CMDARG_REV[$longopt]}
    if [ "${CMDARG_VALIDATORS[$shortopt]}" != "" ]; then
        ( ${CMDARG_VALIDATORS[${shortopt}]} "$value" "$hashkey")
	if [ $? -ne 0 ]; then
	    echo "Invalid value for -$shortopt : ${value}" >&2
	    return 1
	fi
    fi
    return 0
}

function cmdarg_set_opt
{
    set -u
    local key arg
    key=$1
    arg="$2"
    set +u

    case ${CMDARG_TYPES[$key]} in
	$CMDARG_TYPE_STRING)
	    cmdarg_cfg[$key]=$arg
	    cmdarg_validate "$key" "$arg" || ${CMDARG_ERROR_BEHAVIOR} 1
	    ;;
	$CMDARG_TYPE_BOOLEAN)
	    cmdarg_cfg[$key]=true
	    cmdarg_validate "$key" "$arg" || ${CMDARG_ERROR_BEHAVIOR} 1
	    ;;
	$CMDARG_TYPE_ARRAY)
	    arrname="${key}"
	    str='${#'"$arrname"'[@]}'
	    prevlen=$(eval "echo $str")
	    eval "${arrname}[$((prevlen + 1))]=\"$arg\""
	    cmdarg_validate "$key" "$arg" || ${CMDARG_ERROR_BEHAVIOR} 1
	    ;;
	$CMDARG_TYPE_HASH)
	    local k=${arg%%=*}
	    local v=${arg#*=}
	    if [[ "$k" == "$arg" ]] && [[ "$v" == "$arg" ]] && [[ "$k" == "$v" ]]; then
		echo "Malformed hash argument: $arg" >&2
		${CMDARG_ERROR_BEHAVIOR} 1
	    fi
	    eval "$key[\$k]=\$v"
	    cmdarg_validate "$key" "$v" "$k" || ${CMDARG_ERROR_BEHAVIOR} 1
	    ;;
	*)
	    echo "Unable to return string description for ${key}; unknown type ${CMDARG_TYPES[$key]}" >&2
	    ${CMDARG_ERROR_BEHAVIOR} 1
	    ;;
    esac
    return 0
}

function cmdarg_check_empty
{
    local key longopt
    key=$1
    longopt=${CMDARG[$key]}
    type=${CMDARG_TYPES[$longopt]}

    case $type in
	$CMDARG_TYPE_STRING)
            echo ${cmdarg_cfg[$longopt]}
            ;;
	$CMDARG_TYPE_BOOLEAN)
	    echo ${cmdarg_cfg[$longopt]}
	    ;;
	$CMDARG_TYPE_ARRAY)
	    arrname="${longopt}"
	    lval='${!'"${arrname}"'[@]}'
	    eval "echo $lval"
	    ;;
	$CMDARG_TYPE_HASH)
	    arrname="${longopt}"
	    lval='${!'"${arrname}"'[@]}'
	    eval "echo $lval"
	    ;;
	*)
	    echo "${cmdarg_cfg[$longopt]}"
	    ;;
    esac
}

function cmdarg_parse
{
    # cmdarg_parse "$@"
    #
    # Call it EXACTLY LIKE THAT, and it will parse your arguments for you.
    # This function only knows about the arguments that you previously called 'cmdarg' for.
    local OPTIND parsing fullopt opt optarg longopt tmpopt failed missing
    failed=0
    missing=""

    parsing=0
    while [[ "$@" != "" ]]; do
	optarg=""
	opt=""
	longopt=""
	fullopt=$1
	is_equals_arg=1
	shift
	if [[ "${fullopt}"  =~ ^(--[a-zA-Z0-9_\-]+|^-[a-zA-Z0-9])= ]]; then
	    tmpopt=$fullopt
	    fullopt=$(echo "$tmpopt" | cut -d = -f 1)
	    optarg=$(echo "$tmpopt" | cut -d = -f 2)
	    is_equals_arg=0
	fi

	if [[ "$fullopt" == "--" ]] && [[ $parsing -eq 0 ]]; then
	    cmdarg_argv+=($@)
	    break
	elif [[ "${fullopt:0:2}" == "--" ]]; then
	    longopt=${fullopt:2}
	    opt=${CMDARG_REV[$longopt]}
	elif [[ "${fullopt:0:1}" == "-" ]] && [[ ${#fullopt} -eq 2 ]]; then
	    opt=${fullopt:1}
	    longopt=${CMDARG[$opt]}
	elif [[ "${fullopt:0:1}" != "-" ]]; then
	    cmdarg_argv+=("$fullopt")
	    continue
	else
	    echo "Malformed argument: ${fullopt}" >&2
	    echo "While parsing: $@" >&2
	    ${cmdarg_helpers['usage']} >&2
	    ${CMDARG_ERROR_BEHAVIOR} 1
	fi

    	if [[ "$opt" == "h" ]] || [[ "$longopt" == "help" ]]; then
	    ${cmdarg_helpers['usage']} >&2
    	    ${CMDARG_ERROR_BEHAVIOR} 1
    	fi

	if [[ $is_equals_arg -eq 1 ]]; then
	    if [[ ${CMDARG_FLAGS[$opt]} -eq ${CMDARG_FLAG_REQARG} ]] || \
		[[ ${CMDARG_FLAGS[$opt]} -eq ${CMDARG_FLAG_OPTARG} ]]; then
		optarg=$1
		shift
	    fi
	fi

	if [ ${CMDARG["${opt}"]+abc} ]; then
	    cmdarg_set_opt "${CMDARG[$opt]}" "$optarg"
	    rc=$?
	    failed=$((failed + $rc))
    	else
	    echo "Unknown argument or invalid value : -${opt} | --${longopt}" >&2
    	    ${cmdarg_helpers['usage']} >&2
    	    ${CMDARG_ERROR_BEHAVIOR} 1
    	fi
    done

    # --- Don't ${CMDARG_ERROR_BEHAVIOR} early during validation, tell the user
    # everything they did wrong first

    for key in "${CMDARG_REQUIRED[@]}"
    do
	if [[ "$(cmdarg_check_empty $key)" == "" ]]; then
	    missing="${missing} -${key}"
	    failed=$((failed + 1))
	fi
    done

    if [ $failed -gt 0 ]; then
	if [[ "$missing" != "" ]]; then
	    echo "Missing arguments : ${missing}" >&2
	fi
	echo >&2
	${cmdarg_helpers['usage']} >&2
	${CMDARG_ERROR_BEHAVIOR} 1
    fi

    if [ ! -z "${cmdarg_cfg[cfgfile]}" ]; then
	. ${cmdarg_cfg[cfgfile]}
    fi
}

function cmdarg_traceback
{
    # This code lifted from http://blog.yjl.im/2012/01/printing-out-call-stack-in-bash.html
    local i=0
    local FRAMES=${#BASH_LINENO[@]}
    # FRAMES-2 skips main, the last one in arrays
    for ((i=FRAMES-2; i>=1; i--)); do
	echo '  File' \"${BASH_SOURCE[i+1]}\", line ${BASH_LINENO[i]}, probably in ${FUNCNAME[i+1]} >&2
	# Grab the source code of the line
	sed -n "${BASH_LINENO[i]}{s/^/    /;p}" "${BASH_SOURCE[i+1]}" >&2
    done
    echo "  Error: $LASTERR"
    unset FRAMES
}

function cmdarg_dump
{
    for key in ${!cmdarg_cfg[@]}
    do
	repr="${key}:${CMDARG_TYPES[$key]}"
	if [[ ${CMDARG_TYPES[$key]} == $CMDARG_TYPE_ARRAY ]] || [[ ${CMDARG_TYPES[$key]} == $CMDARG_TYPE_HASH ]] ; then
	    arrname="${key}"
	    echo "${repr} => "
	    keys='${!'"$arrname"'[@]}'
	    for idx in $(eval "echo $keys")
	    do
		ref='${'"$arrname"'[$idx]}'
		value=$(eval "echo $ref")
		echo "        ${idx} => $value"
	    done
	else
	    echo "${repr} => ${cmdarg_cfg[$key]}"
	fi
    done
}

function cmdarg_purge
{
    arrays="cmdarg_cfg CMDARG CMDARG_REV CMDARG_OPTIONAL CMDARG_REQUIRED"
    arrays="$arrays CMDARG_DESC CMDARG_DEFAULT CMDARG_VALIDATORS CMDARG_INFO"
    arrays="$arrays CMDARG_FLAGS CMDARG_TYPES"
    for arr in $arrays
    do
	eval "$arr=()"
    done
    CMDARG_GETOPTLIST="h"
}

# Holds the final map of configuration options
declare -xA cmdarg_cfg
# Maps (short arg) -> (long arg)
declare -xA CMDARG
# Maps (long arg) -> (short arg)
declare -xA CMDARG_REV
# A list of optional arguments (e.g., no :)
declare -xa CMDARG_OPTIONAL
# A list of required arguments (e.g., :)
declare -xa CMDARG_REQUIRED
# Maps (short arg) -> (description)
declare -xA CMDARG_DESC
# Maps (short arg) -> default
declare -xA CMDARG_DEFAULT
# Maps (short arg) -> validator
declare -xA CMDARG_VALIDATORS
# Miscellanious info about this script
declare -xA CMDARG_INFO
# Map of (short arg) -> flags
declare -xA CMDARG_FLAGS
# Map of (short arg) -> type (string, array, hash)
declare -xA CMDARG_TYPES
# Array of all elements found after --
declare -xa cmdarg_argv
# Hash of functions that are used for user-extensible functionality
declare -xA cmdarg_helpers
cmdarg_helpers['describe']=cmdarg_describe_default
cmdarg_helpers['usage']=cmdarg_usage

CMDARG_GETOPTLIST="h"
