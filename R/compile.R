dmd <- function(name) {
	librinsided <- paste0(find.package("embedr")[1], "/libs/librinsided.so")
	module <- paste0(find.package("embedr")[1], "/rembed/r.d")
	rinside <- paste0(find.package("RInside")[1], "/lib/libRInside.so")
	libr <- system("locate -b '\\libR.so' -l 1", intern=TRUE)
	cmd <- paste0("dmd ", name, ".d ", module, " -L", libr, " -L", librinsided, " ", rinside, " -L-rpath=", find.package("embedr")[1], "/libs")
	print(cmd)
	out <- system(cmd, intern=TRUE)
	print(out)
	cmd <- paste0("LD_LIBRARY_PATH=", paste0(find.package("embedr"), "/libs"), " ./", name);
	print(cmd)
	cat("\n\n")
	system(cmd)
}
	
