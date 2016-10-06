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
	cmd <- paste0("dmd ", name, ".d -version=r ", module, " -L", libr, " ", rinside)
	
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
		return("Dynamic library already exists - pass argument rebuild=TRUE if you want to rebuild it.")
	}
	cat('import core.runtime;
struct DllInfo;

extern(C) {
	void R_init_lib', libname, '(DllInfo * info) {
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
	apiModule <- paste0(find.package("embedr")[1], "/inline/libembedr.d")
#	libr <- system("locate -b '\\libR.so' -l 1", intern=TRUE)
	
	# compile fPIC and so
	cmd.fpic <- paste0("dmd -c __tmp__compile__file.d -fPIC -version=inline ", apiModule, dmdgretl::fpicIncludes())
	cmd.so <- paste0("dmd -oflib", libname, ".so __tmp__compile__file.o libembedr.o ", dmdgretl::soFlags(), " -shared -defaultlib=libphobos2.so");

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

reload.embedr <- function() {
	detach("package:embedr", unload = TRUE)
  library(embedr)
}
