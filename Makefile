# Build
CXX = gcc
CXXFLAGS = -Wall -Wextra -pedantic
OPTIFLAG = -O2
DEBUGFLAG = -g
COVFLAG = --coverage
PROFFLAG = -g -pg

# Executables
UTFPATGEN_BIN = ./build/utfpatgen
UNITTEST_BIN = ./build/unit_test

ifeq ($(OS),Windows_NT)
    EXT = .exe
    EMPTY = NUL
else
    EXT =
    EMPTY = /dev/null
endif

# Targets
.PHONY: all coverage build-profile build-debug build-execute analyze-cov run run-tests
all: clean utfpatgen.pdf

run:
	$(UTFPATGEN_BIN) ./test/wortliste10k.wlh $(EMPTY) ./test/output.pat ./test/german.tr

run-tests:
	$(UNITEST_BIN)

build-execute: test/unit_test.c | utfpatgen.c build
	$(CXX) $(CXXFLAGS) $(OPTIFLAG) -o build/utfpatgen utfpatgen.c
	$(CXX) $(CXXFLAGS) $(OPTIFLAG) -DTEST -o build/unit_test utfpatgen.c test/unit_test.c
	$(eval UTFPATGEN_BIN = ./build/utfpatgen)
	$(eval UNITTEST_BIN = ./build/unit_test)

build-coverage: test/unit_test.c | utfpatgen.c build
	$(CXX) $(CXXFLAGS) $(COVFLAG) -o build/utfpatgen_cov utfpatgen.c
	$(CXX) $(CXXFLAGS) $(COVFLAG) -DTEST -o build/unit_test_cov utfpatgen.c test/unit_test.c
	$(eval UTFPATGEN_BIN = ./build/utfpatgen_cov)
	$(eval UNITTEST_BIN = ./build/unit_test_cov)

build-profile: test/unit_test.c | utfpatgen.c build
	$(CXX) $(CXXFLAGS) $(PROFFLAG) -o build/utfpatgen_prof utfpatgen.c
	$(CXX) $(CXXFLAGS) $(PROFFLAG) -DTEST -o build/unit_test_prof utfpatgen.c test/unit_test.c
	$(eval UTFPATGEN_BIN = ./build/utfpatgen_prof)
	$(eval UNITTEST_BIN = ./build/unit_test_prof)

analyze-prof: build-profile run
	gprof -b $(UTFPATGEN_BIN)$(EXT) ./gmon.out | gprof2dot | dot -Tpng -o profile_visual.png

build-debug: test/unit_test.c | utfpatgen.c build
	$(CXX) $(CXXFLAGS) $(DEBUGFLAG) -o build/utfpatgen_debug utfpatgen.c
	$(CXX) $(CXXFLAGS) $(DEBUGFLAG) -DTEST -o build/unit_test_debug utfpatgen.c test/unit_test.c
	$(eval UTFPATGEN_BIN = ./build/utfpatgen_debug)
	$(eval UNITTEST_BIN = ./build/unit_test_debug)

build:
	mkdir build

# PDF documentation
utfpatgen.tex: utfpatgen.w
	cweave $<

utfpatgen.pdf: utfpatgen.tex
	pdftex $<
	pdftex $<

# Executable
utfpatgen.c: utfpatgen.w
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