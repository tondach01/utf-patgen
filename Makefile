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
$(NAME).tex: $(NAME).w
	cweave $(NAME).w

$(NAME).pdf: $(NAME).tex
	pdflatex $(NAME).tex
	pdflatex $(NAME).tex

# Executable
$(NAME).c : $(NAME).w
	ctangle $(NAME).w

$(NAME): $(NAME).c
	$(CXX) $(CXXFLAGS) -o $(NAME) $(NAME).c

# Unit tests
test/unit_test: $(NAME).c
	$(CXX) $(CXXFLAGS) -DTEST -o test/unit_test $(NAME).c test/unit_test.c

# Cleaning
.PHONY: clean
clean:
	rm -f $(NAME).c $(NAME).tex $(NAME).pdf $(NAME).log $(NAME).toc $(NAME).idx $(NAME).scn $(NAME).aux $(NAME) test/unit_test pattmp.*