cmdarg
======

[![Build Status](http://jenkins.aklabs.net/buildStatus/icon?job=cmdarg-test)](http://jenkins.aklabs.net/job/cmdarg-test/)

Requires bash >= 4.

    source cmdarg.sh

Enjoy

Usage
=====

cmdarg is a helper library I wrote for bash scripts because, at current, option parsing in bash (-foo bar, etc) is really hard, lots harder than it should be, given bash's target audience. So here's my solution. There are 4 functions you will care about:

    cmdarg
    cmdarg_info
    cmdarg_parse
    cmdarg_usage

cmdarg
======

This function is used to tell the library what command line arguments you accept. Check cmdarg.sh for the latest syntax.

    cmdarg 'l:' 'source_ldap' 'Source (old) LDAP URI'
    cmdarg 'u:' 'source_ldap_username' 'Source (old) LDAP Username'
    cmdarg 'c:' 'groupmap' 'A CSV file mapping usernames to groups that they should belong to post-conversion' '' 'test -e $OPTARG'

The first argument to cmdarg must be an argument specification. Argument specifications take the form 'NOT', where:

- N : The single letter Name of the argument
- O : Whether the option is optional or not. Use ':' here for a required argument, '?' for an optional argument. If you provide a default value for a required argument (:), then it becomes optional.
- T : The type. Leave empty for a string argument, use '[]' for an array argument, use '{}' for a hash argument.

If O and T are both unset, and only the single letter N is provided, then the argument is a boolean argument which will default to false.

The arguments can be set on the command line either via '-X' or '--Y', where X is the short option and Y is the long option. Example:

    cmdarg 'r:' 'required-thing' 'Some thing I require'
    cmdarg 'o?' 'optional-thing' 'Some optional thing'
    cmdarg 'b' 'boolean-thing' 'Some boolean thing'

    # your_script.sh -r some_thingy -b -o optional_thing
    # your_script.sh --required-thing some_thingy --boolean-thing

Because cmdarg does key off of the short options, you are limited to as many unique single characters are in your character set (likely 61 - 26 lower & upper alpha, +9 numerics).

cmdarg_info
===========

This function sets up information about your program for use when printing the help/usage message. Again, see cmdarg.sh for the latest syntax.

    cmdarg_info "header" "Some script that needed argument parsing"
    cmdarg_info "author" "Some Poor Bastard <somepoorbastard@hell.com>"
    cmdarg_info "copyright" "(C) 2013"

cmdarg_parse
============

This command does what you expect, parsing your command line arguments. However you must pass your command line arguments to it. Generally this means:

    cmdarg_parse "$@"

... Beware that "$@" will change depending on your context. So if you have a main() function called in your script, you need to make sure that you pass "$@" from the toplevel script in to it, otherwise the options will be blank when you pass them to cmdarg_parse.

Any argument parsed that has a validator assigned, and whose validator returns nonzero, is considered a failure. Any REQUIRED argument that is not specified is considered a failure. However, it is worth noting that if a required argument has a default value, and you provide an empty value to it, we won't know any better and that will be accepted (how do we know you didn't actually *mean* to do that?).

For every argument integer, boolean or string argument, a global associative array "cmdarg_cfg" is populated with the long version of the option. E.g., in the example above, '-c' would become ${cmdarg_cfg['groupmap']}, for friendlier access during scripting. 

    cmdarg 'x:' 'some required thing'
    cmdarg_parse "$@"
    echo ${cmdarg_cfg['x']}

For array and hash arguments, you must declare the hash or array beforehand for population:

    declare -a myarray
    cmdarg 'a?[]' 'myarray' 'Some array of stuff'
    cmdarg_parse "$@"
    # Now you will be able to access ${myarray[0]}, ${myarray[1]}, etc. Similarly with hashes, just use declare -A and {}.


Setting arrays and hashes
=========================

You can use the cmdarg function to accept arrays and hashes from the command line as well. Consider:

    declare -a array
    declare -A hash
    cmdarg 'a?[]' 'array' 'Some array you can set indexes in'
    cmdarg 'H?{}' 'hash' 'Some hash you can set keys in'


    your_script -a 32 --array something -H key=value --hash other_key=value


    echo ${array[0]}
    echo ${array[1]}
    echo ${hash['key']}
    echo ${hash['other_key']}

The long option names in this form must equal the name of a previously declared array or hash, appropriately. Cmdarg populates that variable directly with options for these arguments. Remember, arrays and hashes must be declared beforehand and must have the same name as the long argument given to their cmdarg option.

Positional arguments and --
===========================

Like any good option parsing framework, cmdarg understands '--' and positional arguments that are meant to be provided without any kind of option parsing applied to them. So if you have:

    myscript.sh -x 0 --longopt thingy file1 file2

... It would seem reasonable to assume that -x and --longopt would be parsed as expected; with arguments of 0 and thingy. But what to do with file1 and file2? cmdarg puts those into a bash indexed array called cmdarg_argv.

Similarly, cmdarg understands '--' which means "stop processing arguments, the rest of this stuff is just to be passed to the program directly". So in this case:

    myscript.sh -x 0 --longopt thingy -- --some-thing-with-dashes

... Cmdarg would parse -x and --longopt as expected, and then ${cmdarg_argv[0]} would hold "--some-thing-with-dashes", for your program to do with what it will.

getopt vs getopts
=================

cmdarg does not use getopt or getopts for option parsing. Its parser is written in 100% pure bash, and is self contained in cmdarg_parse. It will run the same way anywhere you have bash4.

Tests
=====

cmdarg is testable by the shunit bash unit testing tool (https://www.github.com/akesterson/shunit/). See the tests/ directory.
