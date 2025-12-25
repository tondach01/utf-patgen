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
#include <string.h>

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

@* IO procedures.

@ String buffer.
Buffer is used for storing lines read from input files. We use dynamic allocation to allow for arbitrary length lines.

@c
struct string_buffer *init_buffer(size_t capacity){
    struct string_buffer *buf = malloc(sizeof(struct string_buffer));
    if (buf == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }
    buf->capacity = capacity;
    buf->size = 0;
    buf->data = (char *)malloc(capacity);
    buf->eof = false;
    if (buf->data == NULL) {
        fputs("Allocation error\n", stderr);
        free(buf);
        return NULL;
    }
    buf->data[0] = '\0';
    return buf;
}

void reset_buffer(struct string_buffer *buf){
    buf->eof = false;
    buf->size = 0;
    buf->data[0] = '\0';
}

void destroy_buffer(struct string_buffer *buf){
    free(buf->data);
    free(buf);
}

@ Read line.
Reads a line from the given stream into the provided string buffer. Returns true on success, false on failure.

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
            if ((buf->size > 0) && (buf->data[buf->size-1] == '\r')){  // Windows /r/n end of line
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

@ Parse header.
Parses the header line from the translate file to extract hyphenation parameters. Returns true on success, false on failure.
Note that failure might mean that default parameters should be used.

@c
bool is_integer(char c){
    return (c >= '0' && c <= '9');
}

bool is_space(char c){
    return (c == ' ');
}

bool parse_two_digit(struct string_buffer *buf, size_t pos, int8_t *out){
    if (pos + 1 >= buf->size) {
        return false;
    }
    char c1 = buf->data[pos];
    char c2 = buf->data[pos + 1];
    if (is_space(c1) && is_space(c2)) {
        return true;
    }
    
    if (is_space(c1)) {
        c1 = '0';
    }
    if (is_space(c2)) {
        c2 = '0';
    }
    if (!is_integer(c1) || !is_integer(c2)) {
        return false;
    }
    *out = (c1 - '0') * 10 + (c2 - '0');
    return true;
}

bool parse_header(struct string_buffer *buf, struct params *params){
    params->left_hyphen_min = 2;
    params->right_hyphen_min = 3;
    params->bad_hyphen = '.';
    params->missed_hyphen = '-';
    params->good_hyphen = '*';

    int8_t val = -1;
    if (!parse_two_digit(buf, 0, &val)) {
        return false;
    } else if (val != -1) {
        params->left_hyphen_min = val;
    }
    val = -1;
    if (!parse_two_digit(buf, 2, &val)) {
        return false;
    } else if (val != -1){
        params->right_hyphen_min = val;
    }
    if (buf->size >= 5){
        if (!is_space(buf->data[5])) {
                params->bad_hyphen = buf->data[5];
        }
    } else {
        return false;
    }
    if (buf->size >= 6){
        if (!is_space(buf->data[6])) {
                params->missed_hyphen = buf->data[6];
        }
    } else {
        return false;
    }
    if (buf->size >= 7){
        if (!is_space(buf->data[7])) {
                params->good_hyphen = buf->data[7];
        }
    } else {
        return false;
    }
    return true;
}

@* Trie structure.
The trie structure is used for storing patterns efficiently.

@c
struct trie *init_trie(size_t capacity, size_t node_size){
    struct trie *t = malloc(sizeof(struct trie));
    if (t == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }

    t->capacity = capacity;
    t->node_size = node_size;

    t->nodes = calloc(capacity, node_size);
    t->links = calloc(capacity, sizeof(size_t));
    t->right = calloc(capacity, sizeof(size_t));
    t->taken = calloc((capacity / 8 ) + 1, sizeof(char));  // bit array

    t->node_max = 0;
    t->base_max = 0;
    t->occupied = 0;

    if (t->nodes == NULL || t->links == NULL || t->right == NULL || t->taken == NULL) {
        fputs("Allocation error\n", stderr);
        free(t->nodes);
        free(t->links);
        free(t->right);
        free(t->taken);
        free(t);
        return NULL;
    }
    return t;
}

void reset_trie(struct trie *t){
    t->node_max = 0;
    t->base_max = 0;
    t->occupied = 0;
    memset(t->nodes, 0, t->capacity * t->node_size);
    memset(t->links, 0, t->capacity * sizeof(size_t));
    memset(t->right, 0, t->capacity * sizeof(size_t));
    memset(t->taken, 0, (t->capacity / 8 + 1) * sizeof(char));
}

void destroy_trie(struct trie *t){
    free(t->nodes);
    free(t->links);
    free(t->right);
    free(t->taken);
    free(t);
}

bool is_base_used(struct trie *t, size_t base){
    size_t byte_index = base / 8;
    size_t bit_index = base % 8;
    return (t->taken[byte_index] & (1 << bit_index)) != 0;
}

void set_base_used(struct trie *t, size_t base){
    size_t byte_index = base / 8;
    size_t bit_index = base % 8;
    t->taken[byte_index] |= (1 << bit_index);
}

@* Output.
The output structure is used for storing hyphenation outputs.

@c
struct output *new_output(uint8_t value, size_t position){
    struct output *op = malloc(sizeof(struct output));
    if (op == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }
    op->value = value;
    op->position = position;
    op->next = NULL;
    return op;
}

void destroy_output(struct output *op){
    free(op);
}

struct outputs *init_outputs(size_t capacity){
    struct outputs *ops = malloc(sizeof(struct outputs));
    if (ops == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }
    ops->capacity = capacity;
    ops->count = 0;
    ops->max = 0;
    ops->data = calloc(capacity, sizeof(struct output *));
    if (ops->data == NULL) {
        fputs("Allocation error\n", stderr);
        free(ops);
        return NULL;
    }
    return ops;
}

void add_output(struct outputs *ops, uint8_t value, size_t position){
    if (ops->max >= ops->capacity) {
        size_t new_capacity = ops->capacity * 2;
        struct output **new_data = realloc(ops->data, new_capacity * sizeof(struct output *));
        if (new_data == NULL) {
            fputs("Allocation error\n", stderr);
            return;
        }
        ops->data = new_data;
        ops->capacity = new_capacity;
    }
    struct output *op = new_output(value, position);
    if (op == NULL) {
        return;
    }
    ops->data[ops->max] = op;
    ops->count += 1;
    ops->max += 1;
}

void remove_output(struct outputs *ops, size_t index){
    if (index >= ops->count) {
        return;
    }
    destroy_output(ops->data[index]);
    ops->data[index] = NULL;
    if (index == ops->max) {
        while (ops->max > 0 && ops->data[ops->max - 1] == NULL) {
            ops->max -= 1;
        }
    }
    ops->count -= 1;
}

void destroy_outputs(struct outputs *ops){
    for (size_t i = 0; i < ops->max; i++) {
        if (ops->data[i] != NULL) {
            destroy_output(ops->data[i]);
        }
    }
    free(ops->data);
    free(ops);
}

@* Index.
Automatically generates the list of used identifiers
\end{document}