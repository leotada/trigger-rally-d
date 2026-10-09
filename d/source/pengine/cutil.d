// cutil [pengine]
//
// Thin wrappers over the C library so that lenient C-style parsing (`atof`,
// `atoi`, `sscanf`) used all over the original data loaders keeps the exact
// same semantics in the D port.
module pengine.cutil;

import core.stdc.stdio : csscanf = sscanf;
import core.stdc.stdlib : catof = atof, catoi = atoi, catol = atol;
import std.string : toStringz;

double atof(string s) { return catof(s.toStringz); }
int atoi(string s) { return catoi(s.toStringz); }
long atol(string s) { return catol(s.toStringz); }

/// Wrapper around C `sscanf` taking D strings.
int sscanf(Args...)(string s, string fmt, Args args)
{
  return csscanf(s.toStringz, fmt.toStringz, args);
}
