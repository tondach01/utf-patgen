# Build
CXX = gcc
CXXFLAGS = -Wall -Wextra -pedantic
OPTIFLAG = -O2
DEBUGFLAG = -g
COVFLAG = --coverage
PROFFLAG = -pg

# Targets
.PHONY: all coverage profile debug execute
all: clean utfpatgen.pdf

execute: test/unit_test.c | utfpatgen.c build
	$(CXX) $(CXXFLAGS) $(OPTIFLAG) -o build/utfpatgen utfpatgen.c
	$(CXX) $(CXXFLAGS) $(OPTIFLAG) -DTEST -o build/unit_test utfpatgen.c test/unit_test.c

coverage: | utfpatgen.c test/unit_test.c build
	$(CXX) $(CXXFLAGS) $(COVFLAG) -o build/utfpatgen_cov utfpatgen.c
	$(CXX) $(CXXFLAGS) $(COVFLAG) -DTEST -o build/unit_test_cov utfpatgen.c test/unit_test.c

profile: | utfpatgen.c test/unit_test.c build
	$(CXX) $(CXXFLAGS) $(PROFFLAG) -o build/utfpatgen_prof utfpatgen.c
	$(CXX) $(CXXFLAGS) $(PROFFLAG) -DTEST -o build/unit_test_prof utfpatgen.c test/unit_test.c

debug: | utfpatgen.c test/unit_test.c build
	$(CXX) $(CXXFLAGS) $(DEBUGFLAG) -o build/utfpatgen_debug utfpatgen.c
	$(CXX) $(CXXFLAGS) $(DEBUGFLAG) -DTEST -o build/unit_test_debug utfpatgen.c test/unit_test.c

build:
	mkdir build

# PDF documentation
utfpatgen.tex: utfpatgen.w
	cweave $<

utfpatgen.pdf: utfpatgen.tex
	pdftex $<
	pdftex $<

# Executable
utfpatgen.c : utfpatgen.w
	ctangle $<

# File translation from patgen to utfpatgen format and vice versa
# this creates a circular dependency, but make deals with it
%.utfpatgen: %.patgen
	sed -b 's/1/\xFE\x01/g; s/2/\xFE\x02/g; s/3/\xFE\x03/g; s/4/\xFE\x04/g; s/5/\xFE\x05/g; s/6/\xFE\x06/g; s/7/\xFE\x07/g; s/8/\xFE\x08/g; s/9/\xFE\x09/g' $< > $@

%.patgen: %.utfpatgen
	sed -b 's/\xFE\x01/1/g; s/\xFE\x02/2/g; s/\xFE\x03/3/g; s/\xFE\x04/4/g; s/\xFE\x05/5/g; s/\xFE\x06/6/g; s/\xFE\x07/7/g; s/\xFE\x08/8/g; s/\xFE\x09/9/g' $< > $@

# Cleaning
.PHONY: clean
clean:
	rm -f *.c utfpatgen.tex utfpatgen.pdf *.log *.toc *.idx *.scn *.aux build pattmp.*