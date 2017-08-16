reload.embedr <- function() {
	detach("package:embedr", unload = TRUE)
  library(embedr)
}

# These functions are all for Linux systems
# DMD works for Linux, as does LDC, but LDC support has not yet been added
# I think it should be trivial, but I need time to test it
computeLibs <- function(libs) {
	dependencies <- NULL
	for (lib in libs) {
		dependencies <- c(dependencies, getExportedValue(lib, "deps")())
	}
	return(unique(c(libs, dependencies)))
}

dmd <- function(name, dlibs="", other="", run=TRUE) {
	module <- paste0(find.package("embedr")[1], "/embedr/r.d")
	rinside <- paste0(find.package("RInsideC")[1], "/lib/libRInside.so")
	libr <- system("locate -b '\\libR.so' -l 1", intern=TRUE)

	# Construct the compilation line
	cmd <- paste0("dmd ", name, ".d -version=r -version=standalone ", module, " -L", libr, " ", rinside)
	
	# Add compilation information about any additional packages
	if (!isTRUE(dlibs == "")) {
		# Have to load dependencies of dependencies
		# Pull all dlibs until the vector stops changing
		v <- computeLibs(dlibs)
		difference <- 1
		while (difference > 0) {
			v.start <- v
			v <- computeLibs(v.start)
			difference <- length(v) - length(v.start)
		}
		allLibs <- v
		
		for (dlib in allLibs) {
			m <- getExportedValue(dlib, "modules")()
			mdir <- getExportedValue(dlib, "moddir")()
			mod <- paste0(find.package(dlib)[1], "/", mdir, "/", m, ".d", sep="", collapse=" ")
			flags <- getExportedValue(dlib, "flags")()
			fullAddition <- paste0(" ", mod, " ", flags)
			cmd <- paste0(cmd, fullAddition)
		}
	}
	
	# Add any additional flags passed by the caller and compile
	cmd <- paste0(cmd, " ", other)
	print(cmd)
	out <- system(cmd, intern=TRUE)
	print(out)

	# Run the executable
  if (run) {
    cmd <- paste0("./", name);
    print(cmd)
    cat("\n\n")
    system(cmd)
  }
}

# For right now, this only accommodates files that make use of Gretl
compile <- function(code, libname, deps="", other="", rebuild=FALSE) {
	if (file.exists(paste0("lib", libname, ".so")) & !rebuild) {
	  dyn.load(paste0("lib", libname, ".so"))
		return("Dynamic library already exists - pass argument rebuild=TRUE if you want to rebuild it.")
	}
	cat('import core.runtime;
import embedr.r, gretl.base;

struct DllInfo;

extern(C) {
	void R_init_lib', libname, '(DllInfo * info) {
		gretl_rand_init();
		Runtime.initialize();
	}
	
	void R_unload_lib', libname, '(DllInfo * info) {
		Runtime.terminate();
	}
}

', 
code, 
'
', file="__tmp__compile__file.d", sep="")
	# Save code to file with temporary name
	apiModule <- paste0(find.package("embedr")[1], "/embedr/r.d")
	
	# compile fPIC and so
	cmd.fpic <- paste0("dmd -c __tmp__compile__file.d -fPIC -version=inline ", apiModule, dmdgretl::fpicIncludes())
	cmd.so <- paste0("dmd -oflib", libname, ".so __tmp__compile__file.o r.o ", dmdgretl::soFlags(), " -shared -defaultlib=libphobos2.so");

	print(cmd.fpic)
	out.fpic <- system(cmd.fpic, intern=TRUE)
	print(out.fpic)
	
	print(cmd.so)
	out.so <- system(cmd.so, intern=TRUE)
	print(out.so)
	
	# Load the .so
	dyn.load(paste0("lib", libname, ".so"))
}

compileFile <- function(filename, libname, deps="", other="", rebuild=FALSE) {
	compile(paste(readLines(filename), collapse="\n"), libname, deps, other, rebuild)
}

# These functions are for Windows
# Only LDC can be used to produce shared libraries on Windows
defaultCompile <- function(filename) {
	loc <- paste0(path.expand("~"), "/embedr")
	compiler <- paste0('"', loc, '/ldc/ldc2-1.3.0-beta2-win64-msvc/bin/ldmd2.exe"')
	module <- paste0('"', loc, '/r.d"')
	lib <- paste0('"', loc, '/R.lib"')
	cmd <- paste0(compiler, " -shared -m64 ", filename, ".d ", module, " -version=inline ", lib)
	print(cmd)
	msg <- system(cmd, intern=TRUE)
	print(msg)
	dyn.load(paste0(filename, ".dll"))
}

customCompile <- function(filename, path) {
    loc <- checkSetup(TRUE)

    cmd <- paste0('"', path, '\\ldmd2.exe" -shared -m64 ', filename, '.d "', loc, '\\r.d" -version=inline "', loc, '\\R.lib"')
    print(cmd)
    msg <- system(cmd, intern=TRUE)
    print(msg)
    dyn.load(paste0(filename, ".dll"))
}

ldc <- function(filename, path="") {
	if (path == "") {
		defaultCompile(filename)
	} else {
		customCompile(filename, path)
	}
}

ldc.install <- function(download=TRUE) {
	loc <- paste0(path.expand("~"), "/embedr/ldc")
	if (!dir.exists(loc)) {
		dir.create(loc)
	}
	if (download) {
		download.file("https://github.com/ldc-developers/ldc/releases/download/v1.3.0/ldc2-1.3.0-win64-msvc.zip", 
			paste0(loc, "/ldc2-1.3.0-win64-msvc.zip"))
	}
	cat("Unzipping ", loc, "/ldc2-1.3.0-win64-msvc.zip into ", loc, "\n", sep="")
	unzip(paste0(loc, "/ldc2-1.3.0-win64-msvc.zip"), exdir=loc)
}

embedr.configure <- function() {
	loc <- paste0(path.expand("~"), "/embedr")
	if (!dir.exists(loc)) {
		dir.create(loc)
	}
	file.copy(paste0(find.package("embedr")[1], "/embedr/r.d"), loc, overwrite=TRUE)
	file.copy(paste0(find.package("embedr")[1], "/embedr/r.lib"), loc, overwrite=TRUE)
	file.copy(paste0(R.home(), "/bin/x64/R.dll"), loc, overwrite=TRUE)
}

checkSetup <- function(output=FALSE) {
    loc <- paste0(path.expand("~"), "/embedr")
    if (!dir.exists(loc)) {
        dir.create(loc)
    }

    origloc <- getwd()
    setwd(loc)
    embedrwinloc <- find.package("embedr")[1]

    if (!file.exists("R.lib")) {
        file.copy(paste0(embedrwinloc, "/embedr/r.lib"), loc)
    }
    if (!file.exists("r.d")) {
        file.copy(paste0(embedrwinloc, "/embedr/r.d"), loc)
    }
    if (!file.exists("R.dll")) {
        file.copy(paste0(R.home(), "/bin/x64/R.dll"), loc)
    }

    setwd(origloc)
    if (output) {
        loc
    }
}

