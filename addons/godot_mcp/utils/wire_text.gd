@tool
extends RefCounted
class_name WireText
## Keeps captured subprocess output from breaking the wire.
##
## Godot's JSON.stringify does not escape C0 control characters, so a string
## carrying one produces JSON the server cannot parse. It logs
## "Bad control character in string literal" and drops the message — the tool
## call then hangs until its timeout, with the editor perfectly healthy and the
## result already computed.
##
## That is how the GUT runner looked broken for this whole release: GUT prints
## its summary in colour, the escape byte rode along in the job's `log`, and
## every get_gut_status for a finished job died on the way back. Nothing said
## so; the call simply never returned.
##
## Sanitising at the transport means no tool can reintroduce it. Tabs and
## newlines are kept: JSON escapes those, and a log without line breaks is not
## worth reading.

## Strip whole ANSI escape sequences, then any remaining control character.
##
## The sequence goes first on purpose: dropping the escape byte alone leaves
## "[90m[1m" behind as literal text, which is noise no terminal will render and
## is paid for in context on every read.
static func clean(text: String) -> String:
	var ansi := RegEx.new()
	ansi.compile("\\x1b\\[[0-9;]*[A-Za-z]|\\[[0-9;]+m")
	var stripped := ansi.sub(text, "", true)

	var out := ""
	for i in range(stripped.length()):
		var c: int = stripped.unicode_at(i)
		if c == 9 or c == 10 or (c >= 32 and c != 127):
			out += stripped[i]
	return out


## Same, applied through a dictionary/array tree. Returns a cleaned copy; values
## that cannot carry a control character are passed through untouched.
static func clean_tree(value: Variant, depth: int = 0) -> Variant:
	if depth > 32:
		return value
	match typeof(value):
		TYPE_STRING:
			return clean(value)
		TYPE_STRING_NAME:
			return clean(String(value))
		TYPE_DICTIONARY:
			var out_dict := {}
			for key in (value as Dictionary):
				out_dict[key] = clean_tree((value as Dictionary)[key], depth + 1)
			return out_dict
		TYPE_ARRAY:
			var out_array := []
			for item in (value as Array):
				out_array.append(clean_tree(item, depth + 1))
			return out_array
	return value
