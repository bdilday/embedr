#include <RInside.h>
#include <string>

RInside rr;

extern "C" {
	void passToR(SEXP x, char * name) {
		std::string str(name);
		rr.assign(x, str);
	}
	
	SEXP evalInR(char * cmd) {
		std::string str(cmd);
		return rr.parseEval(str);
	}
	
	void evalQuietlyInR(char * cmd) {
		std::string str(cmd);
		rr.parseEvalQ(str);
	}
}
