CXXFLAGS=-std=c++20 -Wall -Wextra -Wshadow -Wtautological-unsigned-zero-compare

# Boost build: eml-boost uses Boost.Multiprecision's cpp_complex_50 instead of
# std::complex<double>. Override the Boost location on the command line, e.g.
# make eml-boost BOOST_INCLUDE=/path/to/boost/include
BOOST_INCLUDE ?= /opt/local/libexec/boost/1.91/include

all: eml infix

# The infix front end. Warnings are all on except a few that are noisy for
# a single-file program (4, 9, 40-42, 44, 45) or ask for an .mli (70).
OCAMLFLAGS = -w +a-4-9-40-41-42-44-45-70

infix: infix.ml
	ocamlopt $(OCAMLFLAGS) -o $@ infix.ml
	rm -f infix.cmi infix.cmx infix.o

eml-boost: eml.cpp
	$(CXX) $(CXXFLAGS) -isystem $(BOOST_INCLUDE) -DEML_USE_BOOST -o $@ eml.cpp

test: eml infix
	./tests/run.sh

test-boost: eml-boost infix
	EML=./eml-boost ./tests/run.sh

.PHONY: all test test-boost
