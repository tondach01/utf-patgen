% --- LIMBO SECTION (LaTeX settings) ---
\documentclass[a4paper,11pt]{cweb} % Use cweb class
\usepackage[utf8]{inputenc}        % UTF-8 encoding

\begin{document}

@* Beginning.
This is \texttt{utf-patgen} - reimplementation of the classic \texttt{patgen} program for pattern generation.

@c
@<Library includes@>@;

# ifndef TEST
int main(int argc, char *argv[]) {
    @<Greetings@>;
    return 0;
}
# endif

@* Implementation.

@<Library includes@>=
#include "utfpatgen.h"

@ Demo code.

@<Greetings@>=
printf("Hello world, it works!\n");

@* Requirements.
To ensure that the new implementation behaves in similar manner to the old one, we should specify desired behavior.

@ Input.
The program takes 4 arguments in this order:
\begin{itemize}
    \item \textbf{dictionary file}: contains set of hyphenated words, one per line. The hyphenation marks are specified
        in translate file. It must contain only the characters specified in translate file. If translate file is empty,
        it must contain only ASCII characters.
    \item \textbf{patterns file}: contains patterns generated in previous runs, one per line. The patterns must have
        only levels that are lower than current hyphenation level. The old patgen represented levels are ASCII characters
        '1' through '9'. We might want to rethink it for \texttt{utf-patgen} where more than 9 levels are possible.
        Anyway the back compatibilitywould be fine for testing and comparison with \texttt{patgen}.
    \item \textbf{output file}: where the hyphenated dictionary will be stored once all the pattern are generated.
    \item \textbf{translate file}: contains the characters that are contained in the dictionary. In the first line the
        hyphenation marks and \texttt{lefthyphenmin}, \texttt{righthyphenmin} parameters can be redefined:
        \begin{itemize}
            \item first line (optional): 'XXYY BMG', where 'XX' is the value of \texttt{lefthyphenmin}, 'YY' the value 
                of \texttt{righthyphenmin}, 'B' the symbol for bad hyphen (marked, not present in the data), 'M' the symbol
                for missed hyphen (not marked, present in the data), and 'G' the symbol for good hyphen (marked, present).
                If any of the parameters is left blank, the default is used: \texttt{lefthyphenmin}$=2$, \texttt{righthyphenmin}$=3$,
                bad hyphen '.', missed hyphen '-', good hyphen '*'.
            \item consequent lines: '$<>X<>Y_1<>...Y_n<><>$', where 'X' is a lower-case letter, '$Y_k$' arbitrary (even zero) 
                number of upper-case variants of 'X', and '$<>$' the delimiter, usually space.
        \end{itemize}
        For the sake of compatibility, the program should be able to read such format, although the inner representation
        must allow for using the bytes corresponding to these "reserved characters" also as pattern bytes.
\end{itemize}

@c
bool read_line(FILE *stream, struct string_buffer *buf){
    char c;
    while ((c = fgetc(stream)) != EOF) {
        if (buf->size >= buf->capacity) {
            void *new_ptr = realloc(buf->data, 2*buf->capacity);
            if (new_ptr == NULL) {
                fputs("Allocation error\n", stderr);
                return false;
            }
            buf->data = (char *) new_ptr;
            buf->capacity *= 2;
        }
        if (c == '\n'){
            if (buf->size > 0 && buf->data[buf->size-1] == '\r'){  // Windows /r/n end of line
                buf->size -= 1;
            }
            break;
        }
        buf->data[buf->size] = c;
        buf->size += 1;
    }
    buf->data[buf->size] = '\0';
    if (c == EOF) {
        buf->eof = true;
    }
    return true;
}

@* Index.
Automatically generates the list of used identifiers
\end{document}