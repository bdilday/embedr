dmd <- function(name, dlibs="", other="") {
	module <- paste0(find.package("embedr")[1], "/embedr/r.d")
	rinside <- paste0(find.package("RInsideC")[1], "/lib/libRInside.so")
	libr <- system("locate -b '\\libR.so' -l 1", intern=TRUE)

	# Construct the compilation line
	cmd <- paste0("dmd ", name, ".d ", module, " -L", libr, " ", rinside)

	# Add compilation information about any additional packages
	if (dlibs != "") {
		for (dlib in dlibs) {
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
	cmd <- paste0("./", name);
	print(cmd)
	cat("\n\n")
	system(cmd)
}

#dmdold <- function(name, dlibs="") {
#	# Find the necessary libraries for RInside compilation
#	librinsided <- paste0(find.package("embedr")[1], "/libs/librinsided.so")
#	module <- paste0(find.package("embedr")[1], "/embedr/r.d")
#	rinside <- paste0(find.package("RInsideC")[1], "/lib/libRInside.so")
#	libr <- system("locate -b '\\libR.so' -l 1", intern=TRUE)

#	# Construct the compilation line
#	# librinsided.so is in this package's directory, so we need to set rpath
#	cmd <- paste0("dmd ", name, ".d ", module, " -L", libr, " -L", librinsided, " ", rinside, " -L-rpath=", find.package("embedr")[1], "/libs")

#	# Add compilation information about any additional packages
#	if (dlibs != "") {
#		m <- getExportedValue(dlibs, "modules")()
#		mdir <- getExportedValue(dlibs, "moddir")()
#		mod <- paste0(find.package(dlibs)[1], "/", mdir, "/", m, ".d", sep="", collapse=" ")
#		flags <- getExportedValue(dlibs, "flags")()
#		fullAddition <- paste0(" ", mod, " ", flags)
#		cmd <- paste0(cmd, fullAddition)
#	}
#	print(cmd)
#	out <- system(cmd, intern=TRUE)
#	print(out)

#	# Run the executable
#	cmd <- paste0("LD_LIBRARY_PATH=", paste0(find.package("embedr"), "/libs"), " ./", name);
#	print(cmd)
#	cat("\n\n")
#	system(cmd)
#}
