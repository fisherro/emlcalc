CXXFLAGS=-std=c++20 -Wall -Wextra -Wshadow -Wtautological-unsigned-zero-compare

# Boost build: eml-boost uses Boost.Multiprecision's cpp_complex_50 instead of
# std::complex<double>. Override the Boost location on the command line, e.g.
# make eml-boost BOOST_INCLUDE=/path/to/boost/include
BOOST_INCLUDE ?= /opt/local/libexec/boost/1.91/include

all: eml

eml-boost: eml.cpp
	$(CXX) $(CXXFLAGS) -isystem $(BOOST_INCLUDE) -DEML_USE_BOOST -o $@ eml.cpp

test: eml
	./tests/run.sh

test-boost: eml-boost
	EML=./eml-boost ./tests/run.sh

.PHONY: all test test-boost
