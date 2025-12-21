# Project name
NAME = hello

# C compiler
CXX = gcc
CXXFLAGS = -O2 -Wall

# Targets
all: pdf exe

# 1. WEAVE: PDF documentation
# Run cweave (makes .tex) and twice pdflatex (cross-references)
pdf: $(NAME).w
	cweave $(NAME).w
	pdflatex $(NAME).tex
	pdflatex $(NAME).tex

# 2. TANGLE: executable
# Run ctangle (makes .c) and compiles
exe: $(NAME).w
	ctangle $(NAME).w
	$(CXX) $(CXXFLAGS) -o $(NAME) $(NAME).c

debug: $(NAME).w
	ctangle $(NAME).w
	$(CXX) -g $(NAME).c -o $(NAME) 

# Cleaning
clean:
	rm -f $(NAME).c $(NAME).cpp $(NAME).tex $(NAME).pdf $(NAME).log $(NAME).toc $(NAME).idx $(NAME).scn $(NAME).aux $(NAME)