If you want to build your program with SCons instead of calling the
functions included in this package, you can see the example in this
directory. Note that this example only works for D functions you want to
call from R, and has only been tested on Linux.

Steps:

1. Create the .d file holding all of the functions you want to expose to
R. They need to be extern(C) to be called from R.

2. Create a directory titled embedr and put r.d inside there.

3. Create the SConstruct file and build the shared library by calling scons.

4. Open R, use dyn.load to load the shared library, and use .Call to call
your D functions.
