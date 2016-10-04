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
	cmd <- paste0("dmd ", name, ".d ", module, " -L", libr, " ", rinside)
	
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

compile <- function(code, libname, deps="", other="") {
	dcode <- paste0('import core.runtime;
struct DllInfo;

extern(C) {
	void R_init_lib', libname, '(DllInfo * info) {
		Runtime.initialize();
	}
	
	void R_unload_lib', libname, '(DllInfo * info) {
		Runtime.terminate();
	}
}

', code, '
}
')
	# Save code to file with temporary name
	module <- paste0(find.package("embedr")[1], "/embedr/r.d")
	libr <- system("locate -b '\\libR.so' -l 1", intern=TRUE)
	
	# Compilation line when there are no dependencies
	cmd <- paste0("dmd -c lib", libname, ".d -fPIC ", module, " -L", libr)
	
	# Now we need to get information about any dependencies
	# Add compilation information about any additional packages
	if (!isTRUE(dlibs == "")) {
		# The while loop is used to load dependencies of dependencies
		# Keeps pulling dependency information until there are no new dependencies
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
	
	# Now that we have added dependency information to the compilation line, we can do the first compilation
	print(cmd)
	out1 <- system(cmd, intern=TRUE)
	print(out1)
	
	# Create the .so
	cmd2 <- paste0("dmd -oflib", libname, ".so lib", libname, ".o -shared -defaultlib=libphobos2.so");
	print(cmd2)
	out2 <- system(cmd2, intern=TRUE)
	print(out2)
	
	# Load the .so
	dyn.load(paste0("lib", libname, ".so"))
}

compileFile <- function(filename, libname, deps="", other="") {
	compile(paste(readLines(filename), collapse="\n"), libname, deps, other)
}

reload.embedr <- function() {
	detach("package:embedr", unload = TRUE)
  library(embedr)
}
