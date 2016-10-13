module embedr.r;

import std.algorithm, std.array, std.conv, std.exception, std.math, std.range, std.stdio, std.string, std.utf;

version(gretl) {
	import gretl.matrix;
}
version(inline) {
	private alias enforce = embedr.r.assertR;
}

struct sexprec {}
alias Robj = sexprec*;

// This enables reference counting of objects allocated by R
// Handles unprotecting for you
// DOES NOT DO THE *PROTECTING* OF AN R OBJECT
// It only stores a protected object and unprotects it when there are no further references to it
// You need to create the RObject when you allocate
// It is assumed that you will not touch the .robj directly
// unprotect is needed because only some Robj will need to be unprotected
struct RObjectStorage {
	Robj ptr;
	bool unprotect;
	int refcount;
}

struct RObject {
	RObjectStorage* data;
	alias data this;
	
	// x should already be protected
	// RObject is for holding an Robj, not for allocating it
	this(Robj x, bool u=false) {
		data = new RObjectStorage();
		data.ptr = x;
		data.refcount = 1;
		data.unprotect = u;
	}
	
	this(int val) {
		this(val.robj, true);
	}
	
	this(double val) {
		this(val.robj, true);
	}
	
	this(this) {
		if (data.unprotect) {
			enforce(data !is null, "data should never be null inside an RObject. You must have created an RObject without using the constructor.");
			data.refcount += 1;
		}
	}
	
	~this() {
		if (data.unprotect) {
			enforce(data !is null, "Calling the destructor on an RObject when data is null. You must have created an RObject without using the constructor.");
			data.refcount -= 1;
			if (data.refcount == 0) {
				Rf_unprotect_ptr(data.ptr);
			}
		}
	}
}

RObject robj_rc(T)(T x) {
	return RObject(x.robj, true);
}

void assertR(bool test, string msg) {
  if (!test) { 
    Rf_error( toUTFz!(char*)("Error in D code: " ~ msg) );
  }
}

//void assertR(int test, string msg) {
 	//assertR(test.to!bool, msg);
//}

void printR(Robj x) {
  Rf_PrintValue(x);
}

void printR(RObject x) {
	Rf_PrintValue(x.ptr);
}

int length(Robj x) {
  return Rf_length(x);
}

bool isVector(Robj x) {
  return to!bool(Rf_isVector(x));
}

bool isMatrix(Robj x) {
  return to!bool(Rf_isMatrix(x));
}

bool isNumeric(Robj x) {
  return to!bool(Rf_isNumeric(x));
}

bool isInteger(Robj x) {
  return to!bool(Rf_isInteger(x));
}

// RList is for passing data from R to D in a list
// and passing a list from D to R
// When working with it in D, use a RObject[] instead
// This is intended as a wrapper around a list received from R or to be passed to R
struct RList {
  RObject data;
  int length; // Length of the underlying Robj, which can never change
  private int counter = 0; // Used for foreach

  this(int n) {
		Robj temp;
    Rf_protect(temp = Rf_allocVector(19, n));
    data = RObject(temp, true);
    length = n;
  }

  // For an existing list - by default, assumes the list is already protected
  this(Robj v, bool u=false) {
		enforce(to!bool(Rf_isVectorList(v)), "Cannot pass a non-list to the constructor for an RList");
		data = RObject(v, u);
		length = v.length;
	}
	
  Robj opIndex(int ii) {
    enforce(ii < length, "RList index has to be less than the number of elements");
    return VECTOR_ELT(data.ptr, ii);
  }

  // Used when passing data to R
	// If you put an Robj in a list, it can be unprotected, because anything in a protected list is protected
  void opIndexAssign(Robj x, int ii) {
    enforce(ii < length, "RList index has to be less than the number of elements");
    SET_VECTOR_ELT(data.ptr, ii, x);
  }

  void opIndexAssign(RObject x, int ii) {
    enforce(ii < length, "RList index has to be less than the number of elements");
    SET_VECTOR_ELT(data.ptr, ii, x.ptr);
  }
  
  void opIndexAssign(RString rs, int ii) {
    enforce(ii < length, "RList index has to be less than the number of elements");
    opIndexAssign(rs.data, ii);
  }
  
  void opIndexAssign(string s, int ii) {
    opIndexAssign(RString(s), ii);
  }
  
  void opIndexAssign(string[] sv, int ii) {
    enforce(ii < length, "RList index has to be less than the number of elements");
    opIndexAssign(sv.robj, ii);
  }

  void opIndexAssign(RMatrix rm, int ii) {
    enforce(ii < length, "RList index has to be less than the number of elements");
    opIndexAssign(rm.data, ii);
  }

  void opIndexAssign(RVector rv, int ii) {
    enforce(ii < length, "RList index has to be less than the number of elements");
    opIndexAssign(rv.data, ii);
  }

  bool empty() {
    return counter == length;
  }

  Robj front() {
    return this[counter];
  }

  void popFront() {
    counter += 1;
  }
  
  Robj robj() {
		return data.ptr;
	}
}

private struct NamedRObject {
  RObject robj;
  string name;
}

// The NamedList is used to provide a heterogeneous data structure in D
// Holds a bunch of RObjects
// Not used to allocate data, so you have to take care of the protection yourself
// Protecting is always done on allocation
/* Can use this to
   - Convert a list from R into a NamedList, for easier access to elements
   - Access elements (RObjects) by name or by index, similar to what you do in R
   - Add elements by name. Every element has to have a name, so that's why there is no append or any other way to add elements.
   - Change an element by name or by index. If the name doesn't exist, it is added. If the index doesn't exist, an exception is thrown.
*/
struct NamedList {
  NamedRObject[] data;
  
  // In case you have an RList and want to work with it as a NamedList
  // This will only be used when pulling in data from R
  // If you allocate an R list from D, it won't have names
  // Maybe that can be added in the future
  // Assumes it is protected
  this(Robj x) {
		enforce(to!bool(Rf_isVectorList(x)), "Cannot pass a non-list to the constructor for a NamedList");
    foreach(int ii, name; x.names) {
      data ~= NamedRObject(RObject(VECTOR_ELT(x, ii)), name);
    }
  }
  
  RObject opIndex(int ii) {
    enforce(ii < data.length, "NamedList index is greater than the length");
    return data[ii].robj;
  }

  RObject opIndex(string name) {
    auto ind = countUntil!"a.name == b"(data, name);
    if (ind == -1) { enforce(false, "No element in the list with the name " ~ name); }
    return data[ind].robj;
  }

  void opIndexAssign(RObject r, long ii) {
    enforce(ii < data.length, "NamedList index is greater than the length");
    data[ii].robj = r;
  }

  void opIndexAssign(RObject r, string name) {
    auto ind = countUntil!"a.name == b"(data, name);
    if (ind == -1) {
      data ~= NamedRObject(r, name);
    } else {
      data[ind].robj = r;
    }
  }
  
  void opIndexAssign(int val, long ii) {
		opIndexAssign(val.robj_rc, ii);
	}
  
  void opIndexAssign(int val, string name) {
		opIndexAssign(val.robj_rc, name);
	}

  void opIndexAssign(double val, long ii) {
		opIndexAssign(val.robj_rc, ii);
	}
  
  void opIndexAssign(double val, string name) {
		opIndexAssign(val.robj_rc, name);
	}

  void opIndexAssign(RMatrix rm, long ii) {
    opIndexAssign(rm.data, ii);
  }
  
  void opIndexAssign(RMatrix rm, string name) {
    opIndexAssign(rm.data, name);
  }
  
  void opIndexAssign(RVector rv, long ii) {
    opIndexAssign(rv.data, ii);
  }
  
  void opIndexAssign(RVector rv, string name) {
    opIndexAssign(rv.data, name);
  }
  
  void opIndexAssign(RString rs, long ii) {
    opIndexAssign(rs.data, ii);
  }
  
  void opIndexAssign(RString rs, string name) {
    opIndexAssign(rs.data, name);
  }
  
  void opIndexAssign(string s, long ii) {
    opIndexAssign(RString(s), ii);
  }
  
  void opIndexAssign(string s, string name) {
    opIndexAssign(RString(s), name);
  }
  
  // Pretty sure this doesn't handle protection correctly
  // Should be using RObject, not Robj
  void opIndexAssign(string[] rs, long ii) {
    opIndexAssign(rs.robj, ii);
  }
  
  void opIndexAssign(string[] rs, string name) {
    opIndexAssign(rs.robj, name);
  }
  
  Robj robj() {
    auto rl = RList(to!int(data.length));
    string[] names;
    foreach(int ii, val; data) {
      rl[ii] = val.robj.ptr;
      names ~= val.name;
    }
    Robj result = rl.robj;
    setAttrib(result, "names", names.robj);
    return result;
  }

  void print() {
    foreach(val; data) {
      writeln(val.name, ":");
      printR(val.robj);
      writeln("");
    }
  }
}

string toString(Robj cstr) {
  return to!string(R_CHAR(cstr));
}

string toString(Robj sv, int ii) {
  return to!string(R_CHAR(STRING_ELT(sv, ii)));
}

string[] stringArray(Robj sv) {
  string[] result;
  foreach(ii; 0..Rf_length(sv)) {
    result ~= toString(sv, ii);
  }
  return result;
}

struct RString {
  RObject data;
  
  this(string str) {
		Robj temp;
    Rf_protect(temp = Rf_allocVector(16, 1));
    data = RObject(temp, true);
    SET_STRING_ELT(data.ptr, 0, Rf_mkChar(toUTFz!(char*)(str)));
  }

  Robj robj() {
		return data.ptr;
	}
}

Robj getAttrib(Robj x, string attr) {
  return Rf_getAttrib(x, RString(attr).robj);
}

Robj getAttrib(RObject x, string attr) {
  return Rf_getAttrib(x.ptr, RString(attr).robj);
}

Robj getAttrib(Robj x, RString attr) {
  return Rf_getAttrib(x, attr.robj);
}

Robj getAttrib(RObject x, RString attr) {
  return Rf_getAttrib(x.ptr, attr.robj);
}

string[] names(Robj x) {
  return stringArray(getAttrib(x, "names"));
}

void setAttrib(Robj x, string attr, RObject val) {
  Rf_setAttrib(x, RString(attr).robj, val.ptr);
}

void setAttrib(Robj x, RString attr, RObject val) {
  Rf_setAttrib(x, attr.robj, val.ptr);
}

Robj robj(double x) {
  return Rf_ScalarReal(x);
}

// Copies
Robj robj(double[] v) {
  return RVector(v).robj;
}

Robj robj(int x) {
  return Rf_ScalarInteger(x);
}

Robj robj(string s) {
  return RString(s).robj;
}

RObject robj(string[] sv) {
	Robj temp;
	Rf_protect(temp = Rf_allocVector(16, to!int(sv.length)));
	RObject result = RObject(temp, true);
	foreach(ii; 0..to!int(sv.length)) {
		SET_STRING_ELT(result.ptr, ii, Rf_mkChar(toUTFz!(char*)(sv[ii])));
	}
	return result;
}

ulong[3] tsp(Robj rv) {
  auto tsprop = RVector(getAttrib(rv, "tsp"));
  ulong[3] result;
  result[0] = lround(tsprop[0]*tsprop[2])+1;
  result[1] = lround(tsprop[1]*tsprop[2])+1;
  result[2] = lround(tsprop[2]);
  return result;
}

double scalar(Robj rx) {
  return Rf_asReal(rx); 
}

double scalar(T: double)(Robj rx) {
	return Rf_asReal(rx);
}

int scalar(T: int)(Robj rx) { 
  return Rf_asInteger(rx); 
}

long scalar(T: long)(Robj rx) { 
  return to!long(rx.scalar!int); 
}

ulong scalar(T: ulong)(Robj rx) { 
  return to!ulong(rx.scalar!int); 
}

string scalar(T: string)(Robj rx) { 
  return to!string(R_CHAR(STRING_ELT(rx,0))); 
}

double scalar(T: double)(string name) {
  return Rf_asReal(evalR(name)); 
}

int scalar(T: int)(string name) { 
  return Rf_asInteger(evalR(name)); 
}

long scalar(T: long)(string name) { 
  return to!long(evalR(name).scalar!int); 
}

ulong scalar(T: ulong)(string name) { 
  return to!ulong(evalR(name).scalar!int); 
}

string scalar(T: string)(string name) { 
  return to!string(R_CHAR(STRING_ELT(evalR(name),0))); 
}

struct RMatrix {
  RObject data;
  int rows;
  int cols;
  double * ptr;
  
  this(int r, int c) {
    Robj temp;
    Rf_protect(temp = Rf_allocMatrix(14, r, c));
    data = RObject(temp, true);
    ptr = REAL(robj);
    rows = r;
    cols = c;
  }
  
  version(gretl) {
  	GretlMatrix mat() {
  		GretlMatrix result;
  		result.rows = this.rows;
  		result.cols = this.cols;
  		result.ptr = this.ptr;
  		return result;
  	}
  	
  	alias mat this;
  }

  // Normally this will be a matrix allocated inside R, and as such, it will already be protected.
  // Nonetheless you have the option to protect by setting the second argument to false.
  this(Robj rm, bool u=false) {
    enforce(isMatrix(rm), "Constructing RMatrix from something not a matrix"); 
    enforce(isNumeric(rm), "Constructing RMatrix from something that is not numeric");
    data = RObject(rm, u);
    ptr = REAL(rm);
    rows = Rf_nrows(rm);
    cols = Rf_ncols(rm);
  }
  
	// Use this only with objects that don't need protection
	// For "normal" use that's not an issue
	this(RObject rm) {
		this(rm.ptr);
	}
	
	this(RVector v) {
		data = v.data;
		rows = v.rows;
		cols = 1;
		ptr = v.ptr;
	}

  double opIndex(int r, int c) {
    enforce(r < this.rows, "First index exceeds the number of rows");
    enforce(c < this.cols, "Second index exceeds the number of columns");
    return ptr[c*this.rows+r];
  }

  void opIndexAssign(double v, int r, int c) {
    ptr[c*rows+r] = v;
  }

  void opAssign(double val) {
    ptr[0..this.rows*this.cols] = val;
  }

  Robj robj() {
    return data.data.ptr;
  }
}

void print(RMatrix m, string msg="") {
  writeln(msg);
  foreach(row; 0..m.rows) {
    foreach(col; 0..m.cols) {
      write(m[row,col], " ");
    }
    writeln("");
  }
}

// Copies
RMatrix dup(RMatrix rm) { 
  RMatrix result = RMatrix(Rf_protect(Rf_duplicate(rm.robj)), true);
  return result;
}

struct RVector {
	int rows;
	double * ptr;
  RObject data;
  
  version(gretl) {
		GretlMatrix mat() {
			GretlMatrix result;
			result.rows = this.rows;
			result.cols = 1;
			result.ptr = this.ptr;
			return result;
		}
		
		alias mat this;
	}
  
  this(int r) {
    Robj temp;
    Rf_protect(temp = Rf_allocVector(14,r));
    data = RObject(temp, true);
    rows = r;
    ptr = REAL(temp);
  }

  this(Robj rv, bool u=false) {
    enforce(isVector(rv), "In RVector constructor: Cannot convert non-vector R object to RVector");
    enforce(isNumeric(rv), "In RVector constructor: Cannot convert non-numeric R object to RVector");
    data = RObject(rv, u);
    rows = rv.length;
    ptr = REAL(rv);
  }
  
  this(RObject rv, bool u=false) {
    this(rv.data.ptr, u);
  }

  this(T)(T v) {
    Robj temp;
    Rf_protect(temp = Rf_allocVector(14,to!int(v.length)));
    data = RObject(temp, true);
    rows = to!int(v.length);
    ptr = REAL(temp);
    foreach(ii; 0..to!int(v.length)) {
      ptr[ii] = v[ii];
    }
  }

  double opIndex(int r) {
    enforce(r < rows, "Index out of range: index on RVector is too large");
    return ptr[r];
  }

  void opIndexAssign(double v, int r) {
    enforce(r < rows, "Index out of range: index on RVector is too large");
    ptr[r] = v;
  }

  void opAssign(T)(T x) {
    enforce(x.length == rows, "Cannot assign to RVector from an object of a different length");
    foreach(ii; 0..to!int(x.length)) {
      this[ii] = x[ii];
    }
  }
  
  RVector opSlice(int i, int j) {
		enforce(j < rows, "Index out of range: index on RVector slice is too large");
		enforce(i < j, "First index has to be less than second index");
		RVector result = this;
		result.rows = j-i;
		result.ptr = &ptr[i];
		return result;
	}

  void print(string msg="") {
    if (msg != "") { writeln(msg, ":"); }
    foreach(val; this) {
      writeln(val);
    }
  }

	int length() {
		return rows;
	}
	
  bool empty() {
    return rows == 0;
  }

  double front() {
    return this[0];
  }

  void popFront() {
    ptr = &ptr[1];
    rows -= 1;
  }

  double[] array() {
    double[] result;
    result.reserve(rows);
    foreach(val; this) {
      result ~= val;
    }
    return result;
  }

  Robj robj() {
    return data.ptr;
  }
}

struct RIntVector {
  RObject data;
  ulong length;
  int * ptr;

  this(int r) {
    Robj temp;
    Rf_protect(temp = Rf_allocVector(13, r));
    data = RObject(temp);
    length = r;
    ptr = INTEGER(temp);
  }

  this(int[] v) {
    Robj temp;
    Rf_protect(temp = Rf_allocVector(13, to!int(v.length)));
    data = RObject(temp);
    length = v.length;
    ptr = INTEGER(temp);
    foreach(int ii, val; v) {
      this[ii] = val;
    }
  }

  this(Robj rv, bool u=false) {
    enforce(isVector(rv), "In RVector constructor: Cannot convert non-vector R object to RVector");
    enforce(isInteger(rv), "In RVector constructor: Cannot convert non-integer R object to RVector");
    data = RObject(rv);
    length = rv.length;
    ptr = INTEGER(rv);
  }

  int opIndex(int obs) {
    enforce(obs < length, "Index out of range: index on RIntVector is too large");
    return ptr[obs];
  }

  void opIndexAssign(int val, int obs) {
    enforce(obs < length, "Index out of range: index on RIntVector is too large");
    ptr[obs] = val;
  }

  void opAssign(int[] v) {
    foreach(int ii, val; v) {
      this[ii] = val;
    }
  }

  RIntVector opSlice(int i, int j) {
    enforce(j < length, "Index out of range: index on RIntVector slice is too large");
    enforce(i < j, "First index on RIntVector slice has to be less than the second index");
    RIntVector result;
    result.data = data;
    result.length = j-i;
    result.ptr = &ptr[i];
    return result;
  }

  int[] array() {
    int[] result;
    result.reserve(length);
    foreach(val; this) {
      result ~= val;
    }
    return result;
  }

  void print() {
    foreach(val; this) {
      writeln(val);
    }
  }

  bool empty() {
    return length == 0;
  }

  int front() {
    return this[0];
  }

  void popFront() {
    ptr = &ptr[1];
    length -= 1;
  }
  
  Robj robj() {
    return data.ptr;
  }
}

// Constants pulled from the R API, for compatibility
immutable double M_E=2.718281828459045235360287471353;
immutable double M_LOG2E=1.442695040888963407359924681002;
immutable double M_LOG10E=0.434294481903251827651128918917;
immutable double M_LN2=0.693147180559945309417232121458;
immutable double M_LN10=2.302585092994045684017991454684; 
immutable double M_PI=3.141592653589793238462643383280;
immutable double M_2PI=6.283185307179586476925286766559; 
immutable double M_PI_2=1.570796326794896619231321691640;
immutable double M_PI_4=0.785398163397448309615660845820;
immutable double M_1_PI=0.318309886183790671537767526745;
immutable double M_2_PI=0.636619772367581343075535053490;
immutable double M_2_SQRTPI=1.128379167095512573896158903122;
immutable double M_SQRT2=1.414213562373095048801688724210;
immutable double M_SQRT1_2=0.707106781186547524400844362105;
immutable double M_SQRT_3=1.732050807568877293527446341506;
immutable double M_SQRT_32=5.656854249492380195206754896838;
immutable double M_LOG10_2=0.301029995663981195213738894724;
immutable double M_SQRT_PI=1.772453850905516027298167483341;
immutable double M_1_SQRT_2PI=0.398942280401432677939946059934;
immutable double M_SQRT_2dPI=0.797884560802865355879892119869;
immutable double M_LN_SQRT_PI=0.572364942924700087071713675677;
immutable double M_LN_SQRT_2PI=0.918938533204672741780329736406;
immutable double M_LN_SQRT_PId2=0.225791352644727432363097614947;

extern (C) {
  double * REAL(Robj x);
  int * INTEGER(Robj x);
  const(char) * R_CHAR(Robj x);
  int * LOGICAL(Robj x);
  Robj STRING_ELT(Robj x, int i);
  Robj VECTOR_ELT(Robj x, int i);
  Robj SET_VECTOR_ELT(Robj x, int i, Robj v);
  void SET_STRING_ELT(Robj x, int i, Robj v);
  int Rf_length(Robj x);
  int Rf_ncols(Robj x);
  int Rf_nrows(Robj x);
  extern __gshared Robj R_NilValue;
  alias RNil = R_NilValue;
  
  void Rf_PrintValue(Robj x);
  int Rf_isArray(Robj x);
  int Rf_isInteger(Robj x);
  int Rf_isList(Robj x);
  int Rf_isLogical(Robj x);
  int Rf_isMatrix(Robj x);
  int Rf_isNull(Robj x);
  int Rf_isNumber(Robj x);
  int Rf_isNumeric(Robj x);
  int Rf_isReal(Robj x);
  int Rf_isVector(Robj x);
  int Rf_isVectorList(Robj x);
  Robj Rf_protect(Robj x);
  Robj Rf_unprotect(int n);
  Robj Rf_unprotect_ptr(Robj x);
  Robj Rf_listAppend(Robj x, Robj y);
  Robj Rf_duplicate(Robj x);
  double Rf_asReal(Robj x);
  int Rf_asInteger(Robj x);
  Robj Rf_ScalarReal(double x);
  Robj Rf_ScalarInteger(int x);
  Robj Rf_getAttrib(Robj x, Robj attr);
  Robj Rf_setAttrib(Robj x, Robj attr, Robj val);
  Robj Rf_mkChar(const char * str);
  void Rf_error(const char * msg);
    
  // type is 0 for NILSXP, 13 for integer, 14 for real, 19 for VECSXP
  Robj Rf_allocVector(uint type, int n);
  Robj Rf_allocMatrix(uint type, int rows, int cols);
        
  // I don't use these, and don't know enough about them to mess with them
  // They are documented in the R extensions manual.
  double gammafn(double);
  double lgammafn(double);
  double lgammafn_sign(double, int *);
  double digamma(double);
  double trigamma(double);
  double tetragamma(double);
  double pentagamma(double);
  double beta(double, double);
  double lbeta(double, double);
  double choose(double, double);
  double lchoose(double, double);
  double bessel_i(double, double, double);
  double bessel_j(double, double);
  double bessel_k(double, double, double);
  double bessel_y(double, double);
  double bessel_i_ex(double, double, double, double *);
  double bessel_j_ex(double, double, double *);
  double bessel_k_ex(double, double, double, double *);
  double bessel_y_ex(double, double, double *);
        
        
  /** Calculate exp(x)-1 for small x */
  double expm1(double);
        
  /** Calculate log(1+x) for small x */
  double log1p(double);
        
  /** Returns 1 for positive, 0 for zero, -1 for negative */
  double sign(double x);
        
  /** |x|*sign(y)
   *  Gives x the same sign as y
   */   
  double fsign(double x, double y);
        
  /** R's signif() function */
  double fprec(double x, double digits);
        
  /** R's round() function */
  double fround(double x, double digits);
        
  /** Truncate towards zero */
  double ftrunc(double x);
        
  /** Same arguments as the R functions */ 
  double dnorm4(double x, double mu, double sigma, int give_log);
  double pnorm(double x, double mu, double sigma, int lower_tail, int log_p);
  double qnorm(double p, double mu, double sigma, int lower_tail, int log_p);
  void pnorm_both(double x, double * cum, double * ccum, int i_tail, int log_p); /* both tails */
  /* i_tail in {0,1,2} means: "lower", "upper", or "both" :
     if(lower) return *cum := P[X <= x]
     if(upper) return *ccum := P[X > x] = 1 - P[X <= x] */

  /** Same arguments as the R functions */ 
  double dunif(double x, double a, double b, int give_log);
  double punif(double x, double a, double b, int lower_tail, int log_p);
  double qunif(double p, double a, double b, int lower_tail, int log_p);

  /** These do not allow for passing argument rate as in R 
      Confirmed that otherwise you call them the same as in R */
  double dgamma(double x, double shape, double scale, int give_log);
  double pgamma(double q, double shape, double scale, int lower_tail, int log_p);
  double qgamma(double p, double shape, double scale, int lower_tail, int log_p);
        
  /** Unless otherwise noted from here down, if the argument
   *  name is the same as it is in R, the argument is the same.
   *  Some R arguments are not available in C */
  double dbeta(double x, double shape1, double shape2, int give_log);
  double pbeta(double q, double shape1, double shape2, int lower_tail, int log_p);
  double qbeta(double p, double shape1, double shape2, int lower_tail, int log_p);

  /** Use these if you want to set ncp as in R */
  double dnbeta(double x, double shape1, double shape2, double ncp, int give_log);
  double pnbeta(double q, double shape1, double shape2, double ncp, int lower_tail, int log_p);
  double qnbeta(double p, double shape1, double shape2, double ncp, int lower_tail, int log_p);

  double dlnorm(double x, double meanlog, double sdlog, int give_log);
  double plnorm(double q, double meanlog, double sdlog, int lower_tail, int log_p);
  double qlnorm(double p, double meanlog, double sdlog, int lower_tail, int log_p);

  double dchisq(double x, double df, int give_log);
  double pchisq(double q, double df, int lower_tail, int log_p);
  double qchisq(double p, double df, int lower_tail, int log_p);

  double dnchisq(double x, double df, double ncp, int give_log);
  double pnchisq(double q, double df, double ncp, int lower_tail, int log_p);
  double qnchisq(double p, double df, double ncp, int lower_tail, int log_p);

  double df(double x, double df1, double df2, int give_log);
  double pf(double q, double df1, double df2, int lower_tail, int log_p);
  double qf(double p, double df1, double df2, int lower_tail, int log_p);

  double dnf(double x, double df1, double df2, double ncp, int give_log);
  double pnf(double q, double df1, double df2, double ncp, int lower_tail, int log_p);
  double qnf(double p, double df1, double df2, double ncp, int lower_tail, int log_p);

  double dt(double x, double df, int give_log);
  double pt(double q, double df, int lower_tail, int log_p);
  double qt(double p, double df, int lower_tail, int log_p);

  double dnt(double x, double df, double ncp, int give_log);
  double pnt(double q, double df, double ncp, int lower_tail, int log_p);
  double qnt(double p, double df, double ncp, int lower_tail, int log_p);

  double dbinom(double x, double size, double prob, int give_log);
  double pbinom(double q, double size, double prob, int lower_tail, int log_p);
  double qbinom(double p, double size, double prob, int lower_tail, int log_p);

  double dcauchy(double x, double location, double scale, int give_log);
  double pcauchy(double q, double location, double scale, int lower_tail, int log_p);
  double qcauchy(double p, double location, double scale, int lower_tail, int log_p);
        
  /** scale = 1/rate */
  double dexp(double x, double scale, int give_log);
  double pexp(double q, double scale, int lower_tail, int log_p);
  double qexp(double p, double scale, int lower_tail, int log_p);

  double dgeom(double x, double prob, int give_log);
  double pgeom(double q, double prob, int lower_tail, int log_p);
  double qgeom(double p, double prob, int lower_tail, int log_p);

  double dhyper(double x, double m, double n, double k, int give_log);
  double phyper(double q, double m, double n, double k, int lower_tail, int log_p);
  double qhyper(double p, double m, double n, double k, int lower_tail, int log_p);

  double dnbinom(double x, double size, double prob, int give_log);
  double pnbinom(double q, double size, double prob, int lower_tail, int log_p);
  double qnbinom(double p, double size, double prob, int lower_tail, int log_p);

  double dnbinom_mu(double x, double size, double mu, int give_log);
  double pnbinom_mu(double q, double size, double mu, int lower_tail, int log_p);

  double dpois(double x, double lambda, int give_log);
  double ppois(double x, double lambda, int lower_tail, int log_p);
  double qpois(double p, double lambda, int lower_tail, int log_p);

  double dweibull(double x, double shape, double scale, int give_log);
  double pweibull(double q, double shape, double scale, int lower_tail, int log_p);
  double qweibull(double p, double shape, double scale, int lower_tail, int log_p);

  double dlogis(double x, double location, double scale, int give_log);
  double plogis(double q, double location, double scale, int lower_tail, int log_p);
  double qlogis(double p, double location, double scale, int lower_tail, int log_p);

  double ptukey(double q, double nranges, double nmeans, double df, int lower_tail, int log_p);
  double qtukey(double p, double nranges, double nmeans, double df, int lower_tail, int log_p);
}

