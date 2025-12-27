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
Note that failure might mean that header was just not present and default parameters should be used.

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
The \texttt{trie} structure is used for storing patterns efficiently. The structure uses following fields:
\begin{itemize}
    \item \textbf{capacity}: total number of nodes allocated (but not necessarily used),
    \item \textbf{occupied}: number of nodes currently used,
    \item \textbf{node\_size}: size of each node in bytes (so that we can create tries with different node sizes),
    \item \textbf{node\_max}: highest index of used node,
    \item \textbf{base\_max}: highest index of used base,
    \item \textbf{nodes}: array of nodes,
    \item \textbf{links}: array of links, i.e., pointers to next base,
    \item \textbf{aux}: helper array: if a node is occupied, it stores a pointer to corresponding output, otherwise it points to neighboring empty spaces,
    \item \textbf{taken}: bit array indicating which nodes are used as bases.
\end{itemize}

@c
struct trie *init_trie(size_t capacity){
    struct trie *t = malloc(sizeof(struct trie));
    if (t == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }

    t->capacity = capacity;

    t->nodes = calloc(capacity, sizeof(char));
    t->links = calloc(capacity, sizeof(size_t));
    t->aux = calloc(capacity, sizeof(size_t));
    t->taken = calloc((capacity / 8 ) + 1, sizeof(char));  // bit array

    if (t->nodes == NULL || t->links == NULL || t->aux == NULL || t->taken == NULL) {
        fputs("Allocation error\n", stderr);
        free(t->nodes);
        free(t->links);
        free(t->aux);
        free(t->taken);
        free(t);
        return NULL;
    }

    t->node_max = 0;
    t->base_max = 0;
    t->occupied = 0;

    return t;
}

struct trie *resize_trie(struct trie *t, size_t new_capacity){
    void *new_nodes = realloc(t->nodes, new_capacity * sizeof(char));
    size_t *new_links = realloc(t->links, new_capacity * sizeof(size_t));
    size_t *new_aux = realloc(t->aux, new_capacity * sizeof(size_t));
    char *new_taken = realloc(t->taken, (new_capacity / 8 + 1) * sizeof(char));

    if (new_nodes == NULL || new_links == NULL || new_aux == NULL || new_taken == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }

    t->nodes = new_nodes;
    t->links = new_links;
    t->aux = new_aux;
    t->taken = new_taken;
    t->capacity = new_capacity;

    return t;
}

void reset_trie(struct trie *t){
    t->node_max = 0;
    t->base_max = 0;
    t->occupied = 0;
    memset(t->nodes, 0, t->capacity * sizeof(char));
    memset(t->links, 0, t->capacity * sizeof(size_t));
    memset(t->aux, 0, t->capacity * sizeof(size_t));
    memset(t->taken, 0, (t->capacity / 8 + 1) * sizeof(char));
}

void destroy_trie(struct trie *t){
    free(t->nodes);
    free(t->links);
    free(t->aux);
    free(t->taken);
    free(t);
}

char get_node(struct trie *t, size_t index){
    if (index >= t->capacity) {
        return '\0';
    }
    return t->nodes[index];
}

bool set_node(struct trie *t, size_t index, char value){
    if (index >= t->capacity) {
        size_t new_capacity = ((index / t->capacity) + 1)* t->capacity;
        if (resize_trie(t, new_capacity) == NULL) {
            return false;
        }
    }
    t->nodes[index] = value;
    t->occupied += 1;
    if (index >= t->node_max) {
        t->node_max = index;
    }
    return true;
}

size_t get_link(struct trie *t, size_t index){
    if (index >= t->capacity) {
        return 0;
    }
    return t->links[index];
}

bool set_link(struct trie *t, size_t index, size_t link){
    if (index >= t->capacity) {
        size_t new_capacity = ((index / t->capacity) + 1)* t->capacity;
        if (resize_trie(t, new_capacity) == NULL) {
            return false;
        }
    }
    t->links[index] = link;
    return true;
}

size_t get_aux(struct trie *t, size_t index){
    if (index >= t->capacity) {
        return 0;
    }
    return t->aux[index];
}

bool set_aux(struct trie *t, size_t index, size_t aux){
    if (index >= t->capacity) {
        size_t new_capacity = ((index / t->capacity) + 1)* t->capacity;
        if (resize_trie(t, new_capacity) == NULL) {
            return false;
        }
    }
    t->aux[index] = aux;
    return true;
}

bool copy_node(struct trie *from, size_t from_index, struct trie *to, size_t to_index){
    if(!set_node(to, to_index, get_node(from, from_index)) || !set_link(to, to_index, get_link(from, from_index)) || !set_aux(to, to_index, get_aux(from, from_index))) {
        return false;
    }
    to->occupied += 1;
    if (to_index >= to->node_max) {
        to->node_max = to_index;
    }
    return true;
}

bool get_base_used(struct trie *t, size_t index){
    if (index >= t->capacity) {
        return false;
    }
    size_t byte_index = index / 8;
    size_t bit_index = index % 8;
    return (t->taken[byte_index] & (1 << bit_index)) != 0;
}

bool set_base_used(struct trie *t, size_t index, bool used){
    if (index >= t->capacity) {
        if (resize_trie(t, index) == NULL) {
            return false;
        }
    }
    size_t byte_index = index / 8;
    size_t bit_index = index % 8;
    if (used) {
        t->taken[byte_index] |= (1 << bit_index);
    } else {
        t->taken[byte_index] &= ~(1 << bit_index);
    }

    return true;
}

bool set_links(struct trie *t, size_t from, size_t to){
    if (!set_link(t, from, to) || !set_aux(t, to, from)) {
        return false;
    }
    return true;
}

bool is_node_occupied(struct trie *t, size_t index){
    return get_node(t, index) != 0;
}

bool link_trie_up_to(struct trie *t, size_t index){
    while (t->base_max < index){
        t->base_max += 1;
        if (!set_node(t, t->base_max + 255, 0) || !set_links(t, t->base_max + 255, t->base_max + 256)) {
            return false;
        }
    }
    return true;
}

bool find_base_for_first_fit(struct trie *t, struct trie *q, uint8_t threshold, size_t *out_base){
    size_t t_index;
    if (q->node_max > threshold) {
        t_index = get_aux(t, t->node_max + 1);
    } else {
        t_index = 0;
    }
    while (true) {
        t_index = get_link(t, t_index);
        *out_base = t_index - get_node_as_char(q, 0);
        if (!link_trie_up_to(t, *out_base)) {
            return false;
        }
        if (is_base_used(t, *out_base)) {
            continue;
        }
        bool conflict = false;
        for (size_t q_index = q->node_max; q_index > 0; q_index--) {
            if(is_node_occupied(t, *out_base + get_node_as_char(q, q_index))){
                conflict = true;
                break;
            }
        }
        if (!conflict) {
            break;
        }
    }
    return true;
}

bool first_fit(struct trie *t, struct trie *q, uint8_t threshold){
    size_t base;
    if (!find_base_for_first_fit(t, q, threshold, &base)) {
        return false;
    }
    for (size_t q_index = 0; q_index < q->node_max; q_index++) {
        size_t t_index = base + get_node_as_char(q, q_index);
        if (!set_links(t, get_aux(t, t_index), get_link(t, t_index)) || !copy_node(q, q_index, t, t_index) || !set_base_used(t, t_index)) {
            return false;
        }
    }
    return true;
}

bool unpack(struct trie *from, size_t base, struct trie *to){
    for (char i = '\0'; i < '\256'; i++){
        size_t from_index = base + i;
        if (get_node(from, from_index) == i) {
            if (!copy_node(from, from_index, to, to->node_max + 1)) {
                return false;
            }
            if (!set_links(from, from_index, get_link(from, 0)) || !set_links(from, 0, from_index) || !set_node(from, from_index, 0)) {
                return false;
            }
        }
        if (!set_base_used(from, base, false)) {
            return false;
        }
    }
    return true;
}

@* Output.
The \texttt{output} structure is used for storing hyphenation outputs. The structure uses following fields:
\begin{itemize}
    \item \textbf{value}: hyphenation value,
    \item \textbf{position}: position in the pattern,
    \item \textbf{next}: pointer to the next output in the linked list.
\end{itemize}

Outputs are grouped together in \texttt{outputs} structure:
\begin{itemize}
    \item \textbf{capacity}: total number of outputs allocated (but not necessarily used),
    \item \textbf{max}: highest index of used output,
    \item \textbf{count}: number of outputs currently used,
    \item \textbf{data}: array of pointers to \texttt{output} structures.
\end{itemize}

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