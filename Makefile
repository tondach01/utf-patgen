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

# File translation from patgen to utfpatgen format and vice versa
# this creates a circular dependency, but make deals with it
%.utfpatgen: %.patgen
	sed -b 's/1/\xFE\x01/g; s/2/\xFE\x02/g; s/3/\xFE\x03/g; s/4/\xFE\x04/g; s/5/\xFE\x05/g; s/6/\xFE\x06/g; s/7/\xFE\x07/g; s/8/\xFE\x08/g; s/9/\xFE\x09/g' $< > $@

%.patgen: %.utfpatgen
	sed -b 's/\xFE\x01/1/g; s/\xFE\x02/2/g; s/\xFE\x03/3/g; s/\xFE\x04/4/g; s/\xFE\x05/5/g; s/\xFE\x06/6/g; s/\xFE\x07/7/g; s/\xFE\x08/8/g; s/\xFE\x09/9/g' $< > $@

# Cleaning
.PHONY: clean
clean:
	rm -f *.c *.tex $(NAME).pdf *.log *.toc *.idx *.scn *.aux $(NAME) test/unit_test pattmp.*