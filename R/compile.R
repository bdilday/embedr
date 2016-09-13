dmdold <- function(name, dlibs="") {
	# Find the necessary libraries for RInside compilation
	librinsided <- paste0(find.package("embedr")[1], "/libs/librinsided.so")
	module <- paste0(find.package("embedr")[1], "/embedr/r.d")
	rinside <- paste0(find.package("RInsideC")[1], "/lib/libRInside.so")
	libr <- system("locate -b '\\libR.so' -l 1", intern=TRUE)

	# Construct the compilation line
	# librinsided.so is in this package's directory, so we need to set rpath
	cmd <- paste0("dmd ", name, ".d ", module, " -L", libr, " -L", librinsided, " ", rinside, " -L-rpath=", find.package("embedr")[1], "/libs")

	# Add compilation information about any additional packages
	if (dlibs != "") {
		m <- getExportedValue(dlibs, "modules")()
		mdir <- getExportedValue(dlibs, "moddir")()
		mod <- paste0(find.package(dlibs)[1], "/", mdir, "/", m, ".d", sep="", collapse=" ")
		flags <- getExportedValue(dlibs, "flags")()
		fullAddition <- paste0(" ", mod, " ", flags)
		cmd <- paste0(cmd, fullAddition)
	}
	print(cmd)
	out <- system(cmd, intern=TRUE)
	print(out)

	# Run the executable
	cmd <- paste0("LD_LIBRARY_PATH=", paste0(find.package("embedr"), "/libs"), " ./", name);
	print(cmd)
	cat("\n\n")
	system(cmd)
}

# This is experimental at this point. Requires RInsideC rather than RInside.
# You no longer need librinsided.so, which is a huge boost to installation.
# Experimental because it's not a good idea to immediately push it.
# You can continue to use dmd without changes.
dmd <- function(name, dlibs="") {
	module <- paste0(find.package("embedr")[1], "/embedr/r.d")
	rinside <- paste0(find.package("RInsideC")[1], "/lib/libRInside.so")
	libr <- system("locate -b '\\libR.so' -l 1", intern=TRUE)

	# Construct the compilation line
	# librinsided.so is in this package's directory, so we need to set rpath
	cmd <- paste0("dmd ", name, ".d ", module, " -L", libr, " ", rinside)

	# Add compilation information about any additional packages
	if (dlibs != "") {
		m <- getExportedValue(dlibs, "modules")()
		mdir <- getExportedValue(dlibs, "moddir")()
		mod <- paste0(find.package(dlibs)[1], "/", mdir, "/", m, ".d", sep="", collapse=" ")
		flags <- getExportedValue(dlibs, "flags")()
		fullAddition <- paste0(" ", mod, " ", flags)
		cmd <- paste0(cmd, fullAddition)
	}
	print(cmd)
	out <- system(cmd, intern=TRUE)
	print(out)

	# Run the executable
	cmd <- paste0("./", name);
	print(cmd)
	cat("\n\n")
	system(cmd)
}

