#
#	Parse the provided input files for environment variable names and include
#	file entries.
#
#	Variables to be expanded have a similar syntax as shell, using $[] instead
#	of ${}. A name inside the brackets will be converted to the value found in
#	the corresponding environment variable. There is no special expansion such
#	as the shell idioms ${word:-default}. It is a straight translation. If no
#	environment variable is available with the name provided in the brackets,
#	the program will exit with a message and a status of 1.
#
#	(The idiom $[] is used instead of ${} because many config files use ${} to
#	indicate entries that should be substituted based upon environment variable
#	entries provided at runtime. This program is meant to keep those idioms
#	intact.)
#
#	The idiom $[include:filename] indicates a file to be parsed and included in
#	the output. The file identified by filename is read from the file system
#	relative to the current working directory. If the file cannot be found,
#	this program will exit with a message and a status of 1.
#
#	The idiom $[include:filename|inVariable>outVariable] indicates that the
#	file should be included for as many times as there are entries in the
#	environment variable inVariable. The include file gains access to the
#	current entry by referencing outVariable. Individual entries in the
#	variable are delimited by commas. White space is ignored between entries.
#	Quotes do NOT escape commas within entries.
#
#	The idiom $[loop:inVariable>outVariable] indicates that the lines between
#	$[loop:...] and $[endloop:] should be looped, once per comma-delimited
#	entry in inVariable. Note the presence of the colon at the end of
#	$[endLoop:]. The value for the current loop is placed in outVariable.
#	If $[loop:...] isn't matched with an $[endloop:] or vice versa, this
#	program will exit with a message a status of 1. It might exit because a
#	variable translation that was supposed to be in a missing $[loop:...]
#	is missing.
#
#	If an outVariable name conflicts with the name of an environment variable,
#	the environment variable value will be "shadowed" by the variable defined
#	by outVariable. Once the loop or include processing is completed, the
#	shadowed value will be exposed again. This also holds if an include or loop
#	defines a variable within the context of an outer include or loop that
#	defines the same variable name for something else.
#
#	If the raw text $[ needs to go directly to output, escape $[ as you would
#	escape a shell variable expansion, with $$[. $ by itself has no special
#	meaning, except when followed by a [, so needs no escaping or special
#	handling to be passed straight to output.
#
#	Any parsing errors (mismatched or incomplete $[] sequences, misformatted
#	$[include:filename|inVariable>outVariable], etc.) will cause the program
#	to exit with a message indicating the error, and a status of 1. ($[]
#	cannot be broken across lines.)
#
#	Output is sent to stdout. Redirect to a file if desired.
#

BEGIN {
	includeToken = "include"
	startLoopToken = "loop"
	endLoopToken = "endloop"

	nestData["length"] = 0 # create array for nesting data
}

{
	print parseLine($0)
}

#
#	Parses a line of content, populating any variables and handling includes
#	found in the line. Variables are populated from values found in environment
#	variables, unless the variable was stored in nestData.
#
#	file is only passed if the line comes from an external file. If it is not
#	included, the line is assumed to come from the current file provided on the
#	command line.
#
#	Returns the result of all of the substitutions in the line.
#
#	Exits with status 1 for any of the reasons described in this program's
#	documentation.
#
function parseLine(line, file,   count, tokens, i, variable, directive, options, output) {

	output = ""
	count = tokenizeLine(line, tokens)

	for (i = 1; i <= count; i++) {
		if (i % 2 == 1) { # plain content
			output = output (tokens[i])
		}
		else { # variable content
			variable = tokens[i]
			if ( match(variable, /^[^:]+:/) ) {
				if (count > 3 || output != "" || length(tokens[3]) > 0 ) {
					print "Directive is not on its own line in line " FNR ":\n" line | "cat 1>&2"
					exit 1
				}
				directive = substr(variable, 1, RLENGTH - 1)
				options = substr(variable, RLENGTH + 1)
				if ( directive == includeToken ) {
					output = parseInclude(options)
				}
				else if ( directive == startLoopToken ) {
					if (file) {
						output = parseLoop(options, file)
					}
					else {
						output = parseLoop(options)
					}
				}
				else if ( directive == endLoopToken ) { # These should be consumed by parseLoop. If this appears here, it is extra.
					print "Directive " directive " in line " FNR " isn't balanced by a starting $[" loopToken ":...]\n" line | "cat 1>&2"
					exit 1
				}
				else {
					print "Directive " directive " isn't recognized in line " FNR "\n" line | "cat 1>&2"
					exit 1
				}
			}
			else { # direct variable translation
				output = output getVariableContents(variable)
			}
		}
	}

	return output
}

#
#	Places the contents of line into the 1-based integer-indexed tokens array,
#	alternating between raw text and variable names. Odd-numbered elements are
#	raw text. Even-numbered elements are variable names. The first and last
#	entries are always raw text.
#
#	Returns the total number of items in the array
#
#	Exits with status 1 if a $[ exists that isn't properly balanced by a ]
#
function tokenizeLine(line, tokens,     digestedLine, tempText, variableStart, variableEnd, count) {
	count = 1
	split("", tokens)

	digestedLine = line
	tempText = "" # tempText is populated when we need to keep track of raw text past a $$[ escape
	while ( (variableStart = index(digestedLine, "$[") ) > 0) {

		# if $[ is escaped by a $, transfer line contents to tempText until an unescaped $[ is found
		if ( (variableStart > 1) && (substr(digestedLine, variableStart - 1, 1) == "$") ) {
			tempText = tempText substr(digestedLine, 1, variableStart - 1) "[" # cut back to the first $ and reinsert the [
			digestedLine = substr(digestedLine, variableStart + 2)
			continue;
		}

		tokens[count++] = variableStart == 1 ? tempText : (tempText substr(digestedLine, 1, variableStart - 1) )
		tempText = "" # clear tempText for future raw text processing
		digestedLine = substr(digestedLine, variableStart + 2)
		variableEnd = index(digestedLine, "]")
		if ( variableEnd == 0 ) {
			print "$[ isn't matched by ] in line " FNR ":\n" line | "cat 1>&2"
			exit 1
		}
		if ( variableEnd == 1 ) {
			print "$[] is empty in line " FNR ":\n" line | "cat 1>&2"
			exit 1
		}
		tokens[count++] = substr(digestedLine, 1, variableEnd - 1)
		digestedLine = substr(digestedLine, variableEnd + 1)
	}
	# including tempText in case only escaped $$[ existed in line. Entry regex wouldn't catch that.
	tokens[count] = tempText digestedLine
	return count
}

#
#	Parse the file identified in include, optionally looping for entries in an
#	environment variable. include provides content in one of the two following
#	formats:
#
#	include:filename
#	include:filename|inVariable>outVariable
#
#	In both cases, filename is taken relative to the current working directory.
#	If the file cannot be found, parseInclude exits with an error message and
#	a status value of 1. If include doesn't match either format, it will also
#	exit with an error message and a status value of 1.
#
#	If inVariable and outVariable are provided, they will be processed as
#	described at the top of this program.
#
#	Returns the fully parsed include file contents
#
#	Exits with status 1 if the include syntax is misformatted, or the include
#	file can't be found, or inVariable was provided but doesn't exist in the
#	environment or from an include that nests this invocation.
#	
function parseInclude(options,     i, tokens, variableCount, variableList, output) {

	tokens[SUBSEP]
	delete tokens[SUBSEP]
	i = parseIncludeTokens(options, tokens)

	if ( i == 0 ) {
		print tokens["error"] | "cat 1>&2"
		exit 1
	}

	if ( i == 1 ) {
		return parseFile(tokens["file"])
	}

	if ( i == 3 ) {
		variableCount = parseVariableForList(tokens["inVariable"], variableList)
		output = ""
		for (i = 1; i <= variableCount; i++) {
			nest(tokens["outVariable"], variableList[i])
			output = output parseFile(tokens["file"])
			unnest()
		}
		return output
	}
}

#
#	Parse the include content for its individual tokens. The tokens array will
#	include 1 or 3 elements if include is properly formatted:
#
#	tokens["filename"]: The name of the include file to process
#
#	tokens["inVariable"]: The name of the variable whose contents will be
#	                      processed
#
#	tokens["outVariable"]: The name of the variable that will receive the
#	                       processed contents of inVariable
#
#	The function returns 1 or 3, depending on whether the include defines just
#	a file name or also defines the variables.
#
#	If the include was improperly formatted, the function returns 0, with a
#	single entry, tokens["error"], which provides the reason for the error.
#
function parseIncludeTokens(options, tokens,    includeData, additionalTokenCount) {
	# Parsing this is a long convoluted mess because POSIX match() doesn't
	# provide access to regex captures. Need to parse it manually.
	includeData = options
	if ( length(includeData) ) {
		if ( match(includeData, /^[^|>]+/) ) { # filename data
			tokens["file"] = substr(includeData, 1, RLENGTH)
			includeData = substr(includeData, RLENGTH + 1)
			if (includeData == "") { # there is no more data; return just the file
				return 1
			}
			else { # there might be variables after the file name
				if ( substr(includeData, 1, 1) == "|" ) { # content after file name, parse for variables
					includeData = substr(includeData, 2)
					additionalTokenCount = parseVariableTokens(includeData, tokens)
					if ( additionalTokenCount > 0 ) {
						return 1 + additionalTokenCount
					}
					# error condition falls through to end
				}
				else { # content after file name begins with >, not |, which is invalid
					tokens["error"] = "\"" options "\" does not fit the format \"" includeToken "filename|inVariable>outVariable\": > appears before |"
				}
			}
		}
		else { # include has no file associated with it
			tokens["error"] = "\"" options "\" does not fit the format \"" includeToken "filename|inVariable>outVariable\": no file name appears before |"
		}
	}
	else { # no data provided
		tokens["error"] = "\"" options "\" needs at least a file name after " includeToken
	}
	delete tokens["file"]
	return 0
}

#
#	Given a string "inVariableName>outVariableName" populate the tokens array
#	with the value preceding > in "inVariable" and the value after > in
#	"outVariable".
#
#	The method modifies tokens and returns 2 (the number of added entries) if
#	variables is properly formatted. If variables is not properly formatted,
#	this method returns 0, with an error message stored in tokens["error"].
#
function parseVariableTokens(variables, tokens,   inVariable, outVariable) {
	if ( match(variables, /^[^>]+>/) ) {
		inVariable = substr(variables, 1, RLENGTH - 1)
		outVariable = substr(variables, RLENGTH + 1)
		if ( length(outVariable) > 0 ) {
			tokens["inVariable"] = inVariable
			tokens["outVariable"] = outVariable
			return 2
		}
		else { # no output variable name
			tokens["error"] = "\"" variables "\" does not fit the format \"inVariable>outVariable\": no outVariable name appears after >"
		}
	}
	else { # no input variable name
		tokens["error"] = "\"" variables "\" does not fit the format \"inVariable>outVariable\": no inVariable name appears before >"
	}
	return 0
}

#
#	Given a variable name, populates variableList with the comma-delimited list
#	of values found in that variable. Spaces surrounding the commas are
#	stripped.
#
#	This method returns the number of items in variableList.
#
function parseVariableForList(variable, variableList,   data) {
	data = getVariableContents(variable)
	return split(data, variableList, /[ \t\n]*,[ \t\n]*/)
}

#
#	Given a file name, parse the file.
#
#	Returns the parsed content of the provided file
#
#	Exits with status 1 if the file cannot be found relative to the current
#	working directory
#
function parseFile(file,   result, line, output) {
	output = ""
	while ( (result = getline line < file ) > 0 ) {
		output = output "\n" parseLine(line, file)
	}
	if (result < 0) { # an error occurred reading file
		print "Include file " file " couldn't be read from line " FNR | "cat 1>&2"
		exit 1
	}
	close(file)
	return substr(output, 2)
}

#
#	Parses lines within a loop, given the variable information and optional
#	file reference. The loop must be defined with input and output variables,
#	as in $[loop:inVariable>outVariable]. inVariable can contain a
#	comma-delimited list of items. The lines between $[loop:...] and $[endloop:]
#	will be processed once per item.
#
#	If there is no variable information, or $[loop:...] isn't balanced by a
#	closing $[endloop:], an error will be output and the program will exit with
#	a status of 1.
#
#	If file is provided, the lines will be read from that file. Otherwise the
#	file provided to awk on the command line will be read. This value should
#	match where the loop was started from. If the loop is started in one file
#	and the contents are read from another, who knows what will happen.
#
#	The processed lines of output are returned.
#
function parseLoop(options, file,   tokens, i, variables, itemCount, lineCount, lines, j, output) {
	tokens[SUBSEP]
	delete tokens[SUBSEP]
	i = parseVariableTokens(options, tokens)

	if ( i == 0 ) {
		print tokens["error"] | "cat 1>&2"
		exit 1
	}

	lineCount = 0
	while ( (file ? (i = getline line < file) : (i = getline line) ) == 1) {
		if (line == "$[" endLoopToken ":]") {
			break
		}
		lines[++lineCount] = line
	}
	if ( i == 0 ) {
		print "Loop $[" startLoopToken ":" options "] was not closed properly" | "cat 1>&2"
		exit 1
	}
	if ( i < 0 ) {
		print "Lines following the start of loop $[" startLoopToken ":" options "] at line " FNR " could not be read from the file" | "cat 1>&2"
		exit 1
	}

	variables[SUBSEP]
	delete variables[SUBSEP]
	itemCount = parseVariableForList(tokens["inVariable"], variables)

	output = ""
	for (i = 1; i <= itemCount; i++) {
		nest(tokens["outVariable"], variables[i])
		for (j = 1; j <= lineCount; j++) {
			output = output "\n" ( file ? parseLine(lines[j], file) : parseLine(lines[j]) )
		}
		unnest()
	}

	return substr(output, 2)
}

#
#	Add a variable value to the loop/include stack. If the contents of a
#	variable are requested, the request will go through this list to see if the
#	value has been substituted in a previous loop/include.
#
#	Calls to nest() must be matched with a closing call to unnest().
#
function nest(name, value,   depth) {
	depth = nestData["length"]
	depth++
	nestData[depth] = name ":" value
	nestData["length"] = depth
	return depth
}

#
#	Closes a previous call to nest(). Removes the most recent addition to the
#	stack of variable substitutions.
#
#	Calling unnest() when there wasn't a previous call to nest() will exit the
#	program with an error.
#
function unnest(   depth) {
	depth = nestData["length"]
	delete nestData[depth]
	depth--
	nestData["length"] = depth

	if (depth < 0) {
		print "unnest() has been called without a matching call to nest() near line " FNR | "cat 1>&2"
		exit 1
	}

	return depth
}

#
#	Given a variable name, searches nestData, then the environment, for a
#	corresponding entry.
#
#	Returns the value found in nestData or the environment
#
#	Exits with status 1 if there are no entries for the provided name in
#	nestData or the environment.
#
function getVariableContents(variableName,   depth, i) {
	depth = nestData["length"]
	for (i = depth; i > 0; i--) {
		if ( match(nestData[i], ("^" variableName ":") ) ) {
			return substr(nestData[i], RLENGTH + 1)
		}
	}
	if (variableName in ENVIRON) {
		return ENVIRON[variableName]
	}
	else {
		print "Variable " variableName " isn't populated at line " FNR | "cat 1>&2"
		exit 1
	}
}
