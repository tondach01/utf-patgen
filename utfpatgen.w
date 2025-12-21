% --- LIMBO SECTION (LaTeX settings) ---
\documentclass[a4paper,11pt]{cweb} % Use cweb class (součást TeX Live)
\usepackage[utf8]{inputenc}       % UTF-8 encoding

\begin{document}

@* Beginning.
Example \emph{Hello World} program written in \textbf{CWEB}.
Shows C code connected with documentation written in \LaTeX.

@c
@<Library includes@>@;

int main() {
    @<Greetings@>;
    return 0;
}

@* Implementation.
Detailed code parts description. In logical order for the reader, not for the compiler.

@ We need IO library.
So we import \texttt{stdio.h}

@<Library includes@>=
#include <stdio.h>

@ Now the printout.
Comments are okay in the code, but better to write them to the TeX part

@<Greetings@>=
printf("Hello world, it works!");

@* Index.
Automatically generates the list of used identifiers
\end{document}