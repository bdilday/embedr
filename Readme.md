# Overview

D is a nice programming language, but I make my living doing econometrics, and there aren't many econometrics libraries for D. R has many libraries for econometrics, statistics, data transformation, and just about anything you want to do with data. One solution would be to port all of R's libraries to D. With a few million programmer hours, you could get a good start on that task. 

I took an alternative route. I used the excellent [RInside](https://github.com/eddelbuettel/rinside) to embed an R interpreter inside my D program. Data is passed efficiently because everything in R is a C struct (SEXPREC). These SEXPREC structs are allocated in either D or R and pointers to them are passed around.

This is a tutorial to help you get started. Everything here is Linux only. It will work on Windows and Mac as well, because the communication is done by RInside (which works on all three OSes), but I only have access to D machines for development. If you are using Windows 10, you can use Bash on Windows.

# Installation

1. Install R and the [dmd compiler](http://dlang.org/download.html) (obvious, I know, but I just want to be sure). I recommend updating to the latest version of R.
2. Install my slightly modified version of RInside, called [RInsideC](https://bitbucket.org/bachmeil/rinsidec) using devtools. In R:
    
    ```
    library(devtools)  
    install_bitbucket("bachmeil/rinsidec")
    ```
    
3. Install the embedr package using devtools:
    
    ```
    install_bitbucket("bachmeil/embedr")
    ```

That is it. If you have a standard installation (i.e., as long as you haven't done something strange to cause libR.so to be hidden in a place the system can't find it) there are no more steps to installation.
    
# Hello World

Let's start with an example that has R print "Hello, World!" to the screen. Put the following code in a file named hello.d:

```
import embedr.r;

void main() {
	evalRQ(`print("Hello, World!")`);
}
```

In the directory containing hello.d, run the following in R:

```
library(embedr)
dmd("hello")
```

This will tell dmd to compile your file, handling includes and linking for you, and then run it for you. You should see "Hello, World!" printed somewhere. The other examples are the same: save the code in a .d file, then call the dmd function to compile and run it.

# Passing a Matrix From D to R

Let's write a program that tells R to allocate a (2x2) matrix, fills the elements in D, and prints it out in both D and R.

```
import embedr.r;

void main() {
	auto m = RMatrix(2,2);
	m[0,0] = 1.5;
	m[0,1] = 2.5;
	m[1,0] = 3.5;
	m[1,1] = 4.5;
	m.print("Matrix allocated by R, but filled in D");
}
```

`RMatrix` is a struct that holds a pointer to an R object plus the dimensions of the matrix. When the constructor is called with two integer arguments, it has R allocate a matrix with those dimensions.

The library includes some basic functionality for working with `m`, including getting and setting elements, and printing. Alternatively, we could have passed `m` to R and told R to print it:

```
import embedr.r;

void main() {
	auto m = RMatrix(2,2);
	m[0,0] = 1.5;
	m[0,1] = 2.5;
	m[1,0] = 3.5;
	m[1,1] = 4.5;
  m.toR("mm"); // Now there is an object inside R called mm
  evalRQ(`print(mm)`);
```

# Passing a Matrix From R to D

We can also pass a matrix in the opposite direction. Let's allocate and fill a matrix in R and then work with it in D.

```
import embedr.r;

void main() {
  // Generate a (20x5) random matrix in R
  evalRQ(`m <- matrix(rnorm(100), ncol=5)`);
  
  // Create an RMatrix struct in D that holds a pointer to m
  auto dm = RMatrix("m");
  dm.print("This is a matrix that was created in R");
  
  // Change one element and verify that it has changed in R
  dm[0,0] = dm[0,0]*4.5;
  printR("m");
}
```

A comment on the last line: `printR` uses the R API printing function to print an R object. If you pass a string as the argument to `printR`, it will print the object with that name in R. It will *not* print the string that you pass to it as an argument. D does not know anything about `m`. It only knows about `dm`, which holds a pointer to `m`.

# RVector

A vector can be represented as a matrix with one column. In R, vectors and matrices are entirely different objects. That doesn't matter much in D because vectors *are* represented as matrices in D. I have added an `RVector` struct to allow the use of `foreach`. Here is an example:

```
import embedr.r;
import std.stdio;

void main() {
  // Have R allocate a vector with 5 elements and copy the elements of the double[] into it
	auto v = RVector([1.1, 2.2, 3.3, 4.4, 5.5]);
  
  // Pass v to R, creating variable rv inside the R interpreter
	v.toR("rv");
	printR("rv");
	
  // Use foreach to print the elements
	foreach(val; v) {
		writeln(val);
	}
}
```

# RVector Slices

You can slice an RVector, as shown in this example.

```
import embedr.r;
import std.stdio;

void main() {
	evalRQ(`v <- rnorm(15)`);
	auto rv = RVector("v");
	foreach(val; rv) {
		writeln(val);
	}
	rv[1..5].print("This is a slice of the vector");
}
```

# Working With R Lists

Lists are very important in R, as they are the most common way to construct a heterogeneous vector. Although you could work directly with an R list (there's an `RList` struct to do that) you lose most of the nice features when you do that. For that reason I created the `NamedList` struct. You can refer to elements by number (elements are ordered as they are in any array) or by name. You can add elements by name (but only that way, because you have to name every element in a `NamedList`).

```

import embedr.r;
import std.stdio;

void main() {
  // Create a list in R
	evalRQ(`rl <- list(a=rnorm(15), b=matrix(rnorm(100), ncol=4))`);
  
  // Create a NamedList struct to work with it in D
	auto dl = NamedList("rl");
	dl.print;
  
  // Pull out a matrix
	auto dlm = RMatrix(dl["b"]);
	dlm.print("This is the matrix from that list");
  
  // Pull out a vector
	auto dlv = RVector(dl["a"]);
	dlv.print("This is the vector from that list");

  // Create a NamedList in D and put some R objects into it
  // NamedList holds pointers to R objects, which can be pulled
  // out using .data
    NamedList nl;
	nl["a"] = dlm.data;
	nl["b"] = dlv.data;
  
  // Send to R as rl2
	nl.toR("rl2");
	
	// Can verify that the elements are reversed
	printR("rl2");
}
```

# Scalars and Strings

R does not have a scalar type. What appears to be a scalar is a vector with one element. On the D side, however, there are scalars, so you have to specify that you are working with a scalar your D code. On a different note, we can pass strings between R and D.

```
import embedr.r;
import std.stdio;

void main() {
  // Create some "scalars" in R
  evalRQ(`a <- 4L`);
	evalRQ(`b <- 4.5`);
	evalRQ(`d <- "hello world"`);
	
	// Print the values of those R variables from D
  // Pull the integer a from R into D
	writeln(scalar!int("a"));
  
  // Also pulls in an integer, but creates a long rather than int
	writeln(scalar!long("a"));
  
  // The default type of scalar is double, so it is not necessary to specify the type in that case
	writeln(scalar("b"));
  
  // Pull the string d from R into D
	writeln(scalar!string("d"));
	
  // Can also work with a string[]
	["foo", "bar", "baz"].toR("dstring");
	printR("dstring");
	
  // Create a vector of strings in R and pull it into D as a string[]
	evalRQ(`rstring <- c("under", "the", "bridge")`);
	writeln(stringArray("rstring"));
}
```

There is more functionality available (the entire R API, in fact) but the single goal of this library is to facilitate the passing of commonly-used data types between the two languages. Other libraries are available for the functions in the R standalone math library, optimization, and so on.

# Use With Dub

Easy to do, will explain later