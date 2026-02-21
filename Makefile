# Project name
NAME = utfpatgen

# Build
CXX = gcc
CXXFLAGS = -O2 -Wall -Wextra -pedantic

.PHONY: debug
debug:
	$(eval CXXFLAGS = -g)

# Targets
.PHONY: all
all: clean $(NAME).pdf $(NAME) test/unit_test

# PDF documentation
%.tex: %.w
	cweave $<

%.pdf: %.tex
	pdflatex $<
	pdflatex $<

# Executable
%.c : %.w
	ctangle $<

%: %.c
	$(CXX) $(CXXFLAGS) -o $@ $<

# Unit tests
test/unit_test: $(NAME).c
	$(CXX) $(CXXFLAGS) -DTEST -o test/unit_test $(NAME).c test/unit_test.c

# Cleaning
.PHONY: clean
clean:
	rm -f *.c *.tex $(NAME).pdf *.log *.toc *.idx *.scn *.aux $(NAME) test/unit_test pattmp.* *.utfpatgen