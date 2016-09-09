// This file compiles the C interface to RInside
// You can set rinsidedir, rcppdir, rh, and libr manually as explained in the comments below
// Normally should not need to do so
// May get a message like "/bin/sh: 2: -Wl,--export-dynamic: not found" but you can ignore it
import std.conv, std.path, std.process, std.string, std.stdio;


void main() {
  // Installation directory for RInside
  // Can set rinsidedir manually if you want, but shouldn't need to
  // Can be found by running `find.package("RInside")` in R
  auto w = executeShell(`Rscript -e 'cat(find.package("RInside"))'`);
  string rinsidedir = w.output.to!string;
  writeln("Found RInside package in ", rinsidedir);
  
  // Installation directory for Rcpp
  // Can set rcppdir manually if you want, but shouldn't need to
  // Can be found by running `find.package("Rcpp")` in R
  w = executeShell(`Rscript -e 'cat(find.package("Rcpp"))'`);
  string rcppdir = w.output.to!string;
  writeln("Found Rcpp package in ", rcppdir);

  // Path to R.h
  // Can be found with `locate -b '\R.h'`
  // Can set rh manually if you want, but shouldn't need to
  w = executeShell(`locate -b '\R.h' -l 1`);
  string rh = strip(dirName(w.output.to!string));
  writeln("Found R.h in ", rh);

  // Path to libR.so
  // Can be found with `locate libR.so`
  // Note that it is common to have multiple libR.so installed
  // If you set this manually, you need only the path to libR.so
  w = executeShell(`locate -b '\libR.so' -l 1`);
  string libr = strip(w.output.to!string);
  writeln("Found libR.so in ", libr);
  
  // -lRInside -lR
  string cmd = "gcc -c -fPIC librinsided.cpp -L" ~ rinsidedir ~ "/lib -I" ~ rinsidedir ~ "/include -I" ~ rcppdir ~ "/include -I" ~ rh ~ " -L" ~ libr;
  writeln(cmd);
  
  auto v = executeShell(cmd);
  writeln(v.output);
  v = executeShell("gcc -shared -Wl,-soname,librinsided.so -o librinsided.so librinsided.o");
  writeln(v.output);
}
