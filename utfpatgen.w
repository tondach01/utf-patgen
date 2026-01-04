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

struct string_buffer *resize_buffer(struct string_buffer *buf, size_t new_capacity){
    char *new_ptr = realloc(buf->data, new_capacity);
    if (new_ptr == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }
    buf->data = new_ptr;
    buf->capacity = new_capacity;
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
            if (resize_buffer(buf, 2*buf->capacity) == NULL) {
                return false;
            }
        }
        if (c == '\n'){
            if ((buf->size > 0) && (buf->data[buf->size-1] == '\r')){  // Windows /r/n end of line
                buf->size -= 1;
            }
            break;
        }
        buf->data[buf->size] = c;
        buf->size++;
    }
    buf->data[buf->size] = '\0';
    if (c == EOF) {
        buf->eof = true;
    }
    return true;
}

bool append_char(struct string_buffer *buf, char c){
    if (buf->size + 1 >= buf->capacity) {
        if (resize_buffer(buf, 2*buf->capacity) == NULL) {
            return false;
        }
    }
    buf->data[buf->size] = c;
    buf->size++;
    return true;
}

bool append_string(struct string_buffer *buf, const char *str, size_t len){
    if (buf->size + len >= buf->capacity) {
        if (resize_buffer(buf, 2*(buf->size + len)) == NULL) {
            return false;
        }
    }
    strcpy(&buf->data[buf->size], str);
    buf->size += len;
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
    if (buf->size >= 6 && !is_space(buf->data[5])) {
        params->bad_hyphen = buf->data[5];
    }
    if (buf->size >= 7 && !is_space(buf->data[6])) {
        params->missed_hyphen = buf->data[6];   
    }
    if (buf->size >= 8 && !is_space(buf->data[7])) {
        params->good_hyphen = buf->data[7];
    }
    return true;
}

@ Parse letters.
Parses the letter mappings from the translate file. Returns true on success, false on failure.

@c
bool parse_letters(struct string_buffer *buf, struct trie *mapping, struct string_buffer *alphabet){
    if (buf->size == 0){
        fprintf(stderr, "Empty line in translate file\n");
        return false;
    }
    char separator = buf->data[0];
    if (buf->size > 1 && buf->data[1] == separator){  // a comment, not forbidden
        return true;
    }
    size_t alphabet_index = alphabet->size;
    size_t out_index;
    struct string_buffer *letter = init_buffer(4);
    if (letter == NULL) {
        return false;
    }
    bool lower = true;
    if (!append_char(buf, separator)){  // just to be sure, if the translate file is in the format specified in patgen report, not necessary
        destroy_buffer(letter);
        return false;
    }
    for (size_t i = 1; i < buf->size; i++){
        char c = buf->data[i];
        if (c == separator){
            if (letter->size == 0){
                break;  // end of line
            }
            if (!append_char(letter, '\0') || !insert_pattern(mapping, letter->data, &out_index) || !set_aux(mapping, out_index, alphabet_index)) {
                destroy_buffer(letter);
                return false;
            }
            if (lower) {
                if (!append_string(alphabet, letter->data, letter->size)) {
                    destroy_buffer(letter);
                    return false;
                }
                lower = false;
            }
            reset_buffer(letter);
        } else {
            if (!append_char(letter, c)) {
                destroy_buffer(letter);
                return false;
            }
        }
    }
    return true;
}

bool default_ascii_mapping(struct trie *mapping, struct string_buffer *alphabet){
    size_t out_index;
    size_t alphabet_index;
    char upper;
    for (char c = 'a'; c <= 'z'; c++){
        alphabet_index = alphabet->size;
        upper = c - ('a' - 'A');
        if (!insert_pattern(mapping, (const char[]){c, '\0'}, &out_index) || !set_aux(mapping, out_index, alphabet_index) || !append_string(alphabet, (const char[]){c, '\0'}, 2)) {
            return false;
        }
        if (!insert_pattern(mapping, (const char[]){upper, '\0'}, &out_index) || !set_aux(mapping, out_index, alphabet_index)) {
            return false;
        }
    }
    return true;
}

char *get_lower(struct trie *mapping, struct string_buffer *alphabet, const char *letter){
    size_t index = traverse_trie(mapping, letter);
    if (index == 0 || index >= alphabet->size){
        return NULL;
    }
    return alphabet->data + get_aux(mapping, index);
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
    t->pattern_count = 0;
    
    return t;
}

bool put_first_level(struct trie *t){
    size_t root = 1;
    size_t n_bytes = 256;
    size_t last_byte = 255;
    for (size_t i = 0; i <= last_byte; i++) {
        if (!set_node(t, root + i, (uint8_t) i)){
            return false;
        }
    }

    t->node_max = root + last_byte;
    t->base_max = root;
    t->occupied = n_bytes;
    t->pattern_count = n_bytes;

    if (!set_base_used(t, root, true) || !set_links(t, 0, t->node_max + 1)) {
        return false;
    }
    return true;
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
    t->pattern_count = 0;
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
        t->base_max++;
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
        *out_base = t_index - (uint8_t) get_node(q, 1);
        if (!link_trie_up_to(t, *out_base)) {
            return false;
        }
        if (get_base_used(t, *out_base)) {
            continue;
        }
        bool conflict = false;
        for (size_t q_index = q->node_max; q_index >= 2; q_index--) {
            if(is_node_occupied(t, *out_base + (uint8_t) get_node(q, q_index))){
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

bool first_fit(struct trie *t, struct trie *q, uint8_t threshold, size_t *out_base){
    size_t base;
    if (!find_base_for_first_fit(t, q, threshold, &base)) {
        return false;
    }
    for (size_t q_index = 1; q_index <= q->node_max; q_index++) {
        size_t t_index = base + (uint8_t) get_node(q, q_index);
        if (!set_links(t, get_aux(t, t_index), get_link(t, t_index)) || !copy_node(q, q_index, t, t_index)) {
            return false;
        }
    }
    if (!set_base_used(t, base, true)){
        return false;
    }
    *out_base = base;
    return true;
}

bool unpack(struct trie *from, size_t base, struct trie *to){
    to->node_max = 1;
    for (size_t i = 0; i < 256; i++){
        size_t from_index = base + i;
        if ((uint8_t) get_node(from, from_index) == i) {
            if (!copy_node(from, from_index, to, to->node_max) || !set_links(from, from_index, get_link(from, 0)) || !set_links(from, 0, from_index) || !set_node(from, from_index, 0)) {
                return false;
            }
            to->node_max++;
        }
    }
    if (!set_base_used(from, base, false)) {
        return false;
    }
    return true;
}

size_t traverse_trie(struct trie *t, const char *pattern){
    size_t index = 1;
    size_t node = (uint8_t) pattern[0] + 1;
    size_t base = get_link(t, node);
    while (index < strlen(pattern) && base > 0) {
        base += (uint8_t) pattern[index];
        if (get_node(t, base) != pattern[index]) {
            return 0;
        }
        node = base;
        base = get_link(t, node);
        index++;
    }
    if (index < strlen(pattern)) {
        return 0;
    }
    return node;
}

bool new_trie_output(struct outputs *ops, struct trie *t, uint8_t value, size_t position, size_t next_op_index, size_t *op_index){
    if (ops->count >= ops->capacity - 1) {
        if (resize_outputs(ops, ops->capacity * 2, t) == NULL) {
            return false;
        }
    }
    size_t hash = hash_trie_output(ops, value, position, next_op_index);
    if (ops->data[hash].value == 0) {
        ops->count++;
        struct output new_op = {.value = value, .position = position, .next_op_index = next_op_index};
        ops->data[hash] = new_op;
        *op_index = hash;
        return true;
    } 
    *op_index = hash;
    return false;
}

size_t hash_trie_output(struct outputs *ops, uint8_t value, size_t position, size_t next_op_index){
    size_t hash = ((next_op_index + 313*position + 361*value) % ops->capacity) + 1;
    while (true) {
        if (ops->data[hash].value == 0) {
            return hash;
        } else if (ops->data[hash].value == value && ops->data[hash].position == position && ops->data[hash].next_op_index == next_op_index) {
            return hash;
        } else if (hash > 1) {
            hash -= 1;
        } else {
            hash = ops->capacity;
        }
    }
    return 0; // should not reach here
}

bool insert_pattern(struct trie *t, const char *pattern, size_t *out_op_index){
    size_t length = strlen(pattern);
    return insert_substring(t, pattern, length, length, out_op_index);
}

bool insert_substring(struct trie *t, const char *pattern, size_t end, size_t length, size_t *out_op_index){
    size_t index = end - length + 1;
    size_t node = (uint8_t) pattern[index - 1] + 1;
    size_t base = get_link(t, node);
    size_t fit;
    struct trie *q = init_trie(256);
    if (q == NULL) {
        return false;
    }
    while (index < end && base > 0) {
        base += (uint8_t) pattern[index];
        if (get_node(t, base) != pattern[index]) {
            if (get_node(t, base) == 0) {
                if (!set_links(t, get_aux(t, base), get_link(t, base)) || !set_node(t, base, pattern[index]) || !set_aux(t, base, 0) || !set_link(t, base, 0)) {
                    destroy_trie(q);
                    return false;
                }
                if (base > t->node_max) {
                    t->node_max = base;
                }
            } else {
                if (!repack(t, q, &node, &base, pattern[index])) {
                    destroy_trie(q);
                    return false;
                }
            }
            t->occupied++;
        }
        index++;
        node = base;
        base = get_link(t, node);
    }
    if (!set_link(q, 1, 0) || !set_aux(q, 1, 0)) {
        destroy_trie(q);
        return false;
    }
    q->node_max = 1;
    while (index < end) {
        if (!set_node(q, 1, pattern[index]) || !first_fit(t, q, 5, &fit) || !set_link(t, node, fit)) {
            destroy_trie(q);
            return false;
        }
        base = fit;
        node = base + (uint8_t) pattern[index];
        t->occupied++;
        index++;
    }
    *out_op_index = node;
    t->pattern_count++;
    destroy_trie(q);
    return true;
}

bool repack(struct trie *t, struct trie *q, size_t *node, size_t *base, char value){
    if (!unpack(t, *base - (uint8_t) value, q) || !set_node(q, q->node_max, value) || !set_link(q, q->node_max, 0) || !set_aux(q, q->node_max, 0)) {
        return false;
    }
    size_t fit;
    if (!first_fit(t, q, 5, &fit)) {
        return false;
    }
    *base = fit;
    if (!set_link(t, *node, *base)) {
        return false;
    }
    *base += (uint8_t) value;
    return true;
}

struct output get_pattern_output(struct trie *t, struct outputs *ops, const char *pattern){
    size_t trie_index = traverse_trie(t, pattern);
    struct output empty = {.value = 0};
    if (trie_index == 0) {
        return empty;
    }
    size_t op_index = get_aux(t, trie_index);
    if (op_index == 0) {
        return empty;
    }
    return ops->data[op_index];
}

bool set_output(struct trie *t, size_t node, struct outputs *ops, size_t value, size_t position){
    size_t op_index;
    if (!new_trie_output(ops, t, value, position, 0, &op_index) || !set_aux(t, node, op_index)) {
        return false;
    }
    return true;
}

@* Output.
The \texttt{output} structure is used for storing hyphenation outputs. The structure uses following fields:
\begin{itemize}
    \item \textbf{value}: hyphenation value,
    \item \textbf{position}: position in the pattern,
    \item \textbf{next_op_index}: index of the next output in the linked list.
\end{itemize}

Outputs are grouped together in \texttt{outputs} structure:
\begin{itemize}
    \item \textbf{capacity}: total number of outputs allocated (but not necessarily used),
    \item \textbf{count}: number of outputs currently used,
    \item \textbf{data}: array of \texttt{output} structures.
\end{itemize}

@c
struct outputs *init_outputs(size_t capacity){
    struct outputs *ops = malloc(sizeof(struct outputs));
    if (ops == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }
    ops->capacity = capacity;
    ops->count = 0;
    ops->data = calloc(capacity + 1, sizeof(struct output));
    if (ops->data == NULL) {
        fputs("Allocation error\n", stderr);
        free(ops);
        return NULL;
    }
    return ops;
}

// warning: computationally very expensive for larger tries!
struct outputs *resize_outputs(struct outputs *ops, size_t capacity, struct trie *t){
    struct output *new_data = calloc(capacity + 1, sizeof(struct output)); 
    if (new_data == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }
    ops->capacity = capacity;
    for (size_t i = 0; i < t->capacity; i++) {
        if (is_node_occupied(t, i) && get_aux(t, i) != 0) {
            size_t old_index = get_aux(t, i);
            struct output old_op = ops->data[old_index];
            size_t new_index = hash_trie_output(ops, old_op.value, old_op.position, old_op.next_op_index);
            new_data[new_index] = old_op;
        }
    }
    free(ops->data);
    ops->data = new_data;
    return ops;
}

void destroy_outputs(struct outputs *ops){
    free(ops->data);
    free(ops);
}

@* Translate file parsing.
Parses the translate file to build character mappings and hyphenation parameters. Returns true on success, false on failure.

@c
struct params *init_params(){
    struct params *p = malloc(sizeof(struct params));
    if (p == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }
    p->left_hyphen_min = 2;
    p->right_hyphen_min = 3;
    p->bad_hyphen = '.';
    p->missed_hyphen = '-';
    p->good_hyphen = '*';
    return p;
}

void reset_params(struct params *p){
    p->left_hyphen_min = 2;
    p->right_hyphen_min = 3;
    p->bad_hyphen = '.';
    p->missed_hyphen = '-';
    p->good_hyphen = '*';
}

void destroy_params(struct params *p){
    free(p);
}

bool read_translate(FILE *translate, struct params *params, struct trie *mapping, struct string_buffer *alphabet){
    struct string_buffer *buf = init_buffer(64);
    if (buf == NULL) {
        return false;
    }
    if (!read_line(translate, buf)) {
        destroy_buffer(buf);
        return false;
    }
    if (buf->eof) {
        bool default_mapping = default_ascii_mapping(mapping, alphabet);
        destroy_buffer(buf);
        return default_mapping;
    }
    bool first_line = true;
    while (!buf->eof) {
        if (first_line && parse_header(buf, params)) {
            // header parsed successfully
        } else if (!parse_letters(buf, mapping, alphabet)) {
            destroy_buffer(buf);
            return false;
        }
        first_line = false;
        reset_buffer(buf);
        if (!read_line(translate, buf)) {
            destroy_buffer(buf);
            return false;
        }
    }
    destroy_buffer(buf);
    return true;
}

@* Count trie traversing.

@c
struct pattern_counts *init_pattern_counts(size_t capacity){
    struct pattern_counts *pc = malloc(sizeof(struct pattern_counts));
    if (pc == NULL) {
        fprintf(stderr, "Allocation error\n");
        return NULL;
    }
    pc->good = malloc(capacity * sizeof(size_t));
    pc->bad = malloc(capacity * sizeof(size_t));
    if (pc->good == NULL || pc->bad == NULL){
        fprintf(stderr, "Allocation error\n");
        free(pc->good);
        free(pc->bad);
        free(pc);
        return NULL;
    }
    pc->capacity = capacity;
    pc->size = 0;
    return pc;
}

struct pattern_counts *resize_pattern_counts(struct pattern_counts *pc, size_t new_capacity){
    size_t *new_good = realloc(pc->good, new_capacity * sizeof(size_t));
    if (new_good == NULL){
        fprintf(stderr, "Allocation error\n");
        destroy_pattern_counts(pc);
        return NULL;
    }
    pc->good = new_good;
    size_t *new_bad = realloc(pc->bad, new_capacity * sizeof(size_t));
    if (new_good == NULL){
        fprintf(stderr, "Allocation error\n");
        destroy_pattern_counts(pc);
        return NULL;
    }
    pc->bad = new_bad;
    pc->capacity = new_capacity;
    return pc;
}

void reset_pattern_counts(struct pattern_counts *pc){
    pc->size = 0;
    memset(pc->good, 0, pc->capacity);
    memset(pc->bad, 0, pc->capacity);
}

void destroy_pattern_counts(struct pattern_counts *pc){
    free(pc->good);
    free(pc->bad);
    free(pc);
}

size_t get_good(struct pattern_counts *pc, size_t index){
    if (index >= pc->size){
        return 0;
    }
    return pc->good[index];
}

bool set_good(struct pattern_counts *pc, size_t index, size_t value){
    if (index >= pc->capacity) {
        size_t new_capacity = ((index / pc->capacity) + 1)* pc->capacity;
        if (resize_pattern_counts(pc, new_capacity) == NULL) {
            return false;
        }
    }
    pc->good[index] = value;
    return true;
}

size_t get_bad(struct pattern_counts *pc, size_t index){
    if (index >= pc->size){
        return 0;
    }
    return pc->bad[index];
}

bool set_bad(struct pattern_counts *pc, size_t index, size_t value){
    if (index >= pc->capacity) {
        size_t new_capacity = ((index / pc->capacity) + 1)* pc->capacity;
        if (resize_pattern_counts(pc, new_capacity) == NULL) {
            return false;
        }
    }
    pc->bad[index] = value;
    return true;
}

bool is_utf_start_byte(uint8_t byte){
    return (byte & 0xc0) != 0x80;
}

bool collect_count_trie(struct trie *counts, struct trie *patterns, struct outputs *ops, struct params *params, struct pattern_counts *pc, size_t *level_pattern_cnt){
    double bad_eff = (double) params->thresh / (double) params->good_wt;
    struct pass_stats ps = {
        .good_pat_cnt = 0,
        .bad_pat_cnt = 0,
        .good_cnt = 0,
        .bad_cnt = 0,
        .more_to_come = false
    };
    if (!traverse_count_trie(counts, patterns, params, &ps, ops, pc)){
        return false;
    }
    printf("%zu good and %zu bad patterns added", ps.good_pat_cnt, ps.bad_pat_cnt);
    *level_pattern_cnt += ps.good_pat_cnt;
    if (ps.more_to_come) {
        printf(" (more to come)\n");
    } else {
        printf("\n");
    }
    printf("finding %zu good and %zu bad hyphens", ps.good_cnt, ps.bad_cnt);
    if (ps.good_pat_cnt > 0) {
        printf(", efficiency = %.2lf\n", (double) ps.good_cnt / (ps.good_pat_cnt + ((double) ps.bad_cnt / bad_eff)));
    } else {
        printf("\n");
    }
    printf("pattern trie has %zu nodes, trie_max = %zu, %zu outputs\n", patterns->occupied, patterns->node_max, ops->count);
    return true;
}

struct stack *init_stack(size_t capacity){
    struct stack *s = malloc(sizeof(struct stack));
    if (s == NULL) {
        fprintf(stderr, "Allocation error\n");
        return NULL;
    }
    s->data = malloc(capacity * sizeof(size_t));
    if (s->data == NULL){
        fprintf(stderr, "Allocation error\n");
        free(s->data);
        free(s);
        return NULL;
    }
    s->capacity = capacity;
    s->top = 0;
    return s;
}

struct stack *resize_stack(struct stack *s, size_t new_capacity){
    size_t *new_stack = realloc(s->data, new_capacity * sizeof(size_t));
    if (new_stack == NULL){
        fprintf(stderr, "Allocation error\n");
        destroy_stack(s);
        return NULL;
    }
    s->data = new_stack;
    s->capacity = new_capacity;
    return s;
}

void destroy_stack(struct stack *s){
    free(s->data);
    free(s);
}

bool put_on_stack(struct stack *s, size_t value){
    if (s->top >= s->capacity){
        size_t new_capacity = 2*(s->top)*sizeof(size_t);
        if (resize_stack(s, new_capacity) == NULL){
            return false;
        }
    }
    s->data[s->top] = value;
    s->top++;
    return true;
}

size_t get_top_value(struct stack *s){
    if (s->top == 0){
        return 0;
    }
    return s->data[s->top - 1];
}

void set_top_value(struct stack *s, size_t value){
    if (s->top == 0){
        return;
    }
    s->data[s->top - 1] = value;
}

bool traverse_count_trie(struct trie *counts, struct trie *patterns, struct params *params, struct pass_stats *ps, struct outputs *ops, struct pattern_counts *pc) {
    size_t root = 1;
    size_t current_len = 0;
    uint8_t c;
    struct string_buffer *pattern = init_buffer(4 * params->pat_len);
    if (pattern == NULL){
        return false;
    }

    struct stack *s_base = init_stack(4 * params->pat_len * sizeof(size_t));
    if (s_base == NULL) {
        destroy_buffer(pattern);
        return false;
    }
    if (!append_char(pattern, '\0') || !put_on_stack(s_base, root)){
        destroy_buffer(pattern);
        destroy_stack(s_base);
        return false;
    }

    size_t counts_index, node;
    while (s_base->top > 0){
        root = get_top_value(s_base);
        c = (uint8_t) pattern->data[pattern->size - 1];
        if (c == 255){
            pattern->data[pattern->size - 1] = '\0';
            pattern->size--;
            s_base->top--;
            continue;
        }
        pattern->data[pattern->size - 1] += 1;
        node = root + c;
        if ((uint8_t) get_node(counts, node) != c){
            continue;
        }
        if (is_utf_start_byte((uint8_t) c)){
            if (current_len >= params->pat_len){
                if ((counts_index = get_aux(counts, node)) == 0){
                    continue;
                }
                size_t op_index;
                size_t good = get_good(pc, counts_index);
                size_t bad = get_bad(pc, counts_index);
                if (params->good_wt * good < params->thresh){
                    if (!insert_pattern(patterns, pattern->data, &op_index) || !set_output(patterns, op_index, ops, SIZE_MAX, params->pat_dot)){
                        destroy_buffer(pattern);
                        destroy_stack(s_base);
                        return false;
                    }
                    ps->bad_pat_cnt++;
                } else if (params->good_wt * good - params->bad_wt * bad >= params->thresh) {
                    if (!insert_pattern(patterns, pattern->data, &op_index) || !set_output(patterns, op_index, ops, params->hyph_level, params->pat_dot)){
                        destroy_buffer(pattern);
                        destroy_stack(s_base);
                        return false;
                    }
                    ps->good_pat_cnt++;
                    ps->good_cnt += good;
                    ps->bad_cnt += bad;
                } else {
                    ps->more_to_come = true;
                }
                continue;
            } else {
                current_len++;
            }
        }
        root = get_link(counts, root + c);
        if (root == 0){
            continue;
        }
        if (!append_char(pattern, '\0') || !put_on_stack(s_base, root)){
            destroy_buffer(pattern);
            destroy_stack(s_base);
            return false;
        }        
    }
    destroy_buffer(pattern);
    destroy_stack(s_base);
    return true;
}

bool delete_patterns(struct trie *t, struct outputs *ops){
    size_t root = 1;
    struct stack *s_base = init_stack(16);
    if (s_base == NULL){
        return false;
    }
    struct stack *s_offset = init_stack(16);
    if (s_offset == NULL){
        destroy_stack(s_base);
        return false;
    }
    struct stack *s_freed = init_stack(16);
    if (s_freed == NULL){
        destroy_stack(s_base);
        destroy_stack(s_offset);
        return false;
    }
    if (!put_on_stack(s_base, root) || !put_on_stack(s_offset, 0) || !put_on_stack(s_freed, (size_t) true)){
        destroy_stack(s_base);
        destroy_stack(s_offset);
        destroy_stack(s_freed);
        return false;
    }
    size_t node, offset;
    while (s_base->top > 0){
        root = get_top_value(s_base);
        offset = get_top_value(s_offset);
        if (offset == 255){
            if (get_top_value(s_freed) == (size_t) true){
                if (!set_base_used(t, root + offset, false)){
                    destroy_stack(s_base);
                    destroy_stack(s_offset);
                    destroy_stack(s_freed);
                    return false;
                }
            }
            s_offset->top--;
            s_base->top--;
            s_freed->top--;
            continue;
        }
        set_top_value(s_offset, get_top_value(s_offset) + 1);
        node = root + offset;
        if ((uint8_t) get_node(t, node) != offset){
            continue;
        }
        if (is_utf_start_byte((uint8_t) offset)){
            if (!link_around_bad_outputs(ops, t, node)){
                destroy_stack(s_base);
                destroy_stack(s_offset);
                destroy_stack(s_freed);
                return false;
            }
            if (get_link(t, node) > 0 || get_aux(t, node) > 0 || root == 1){
                set_top_value(s_freed, (size_t) false);
            } else {
                if (!deallocate_node(t, node)){
                    destroy_stack(s_base);
                    destroy_stack(s_offset);
                    destroy_stack(s_freed);
                    return false;
                }
            }
        }
        root = get_link(t, node);
        if (root == 0){
            continue;
        }
        if (!put_on_stack(s_base, root) || !put_on_stack(s_offset, 0) || !put_on_stack(s_freed, (size_t) true)){
            destroy_stack(s_base);
            destroy_stack(s_offset);
            destroy_stack(s_freed);
            return false;
        }        
    }
    destroy_stack(s_base);
    destroy_stack(s_offset);
    destroy_stack(s_freed);
    return true;
}

bool link_around_bad_outputs(struct outputs *ops, struct trie *t, size_t t_index){
    size_t op_index = get_aux(t, t_index);
    size_t h = 0;
    ops->data[0].next_op_index = op_index;
    size_t n = ops->data[0].next_op_index;
    while (n > 0){
        if (ops->data[n].value == SIZE_MAX){
            ops->data[h].next_op_index = ops->data[n].next_op_index;
        } else {
            h = n;
        }
        n = ops->data[h].next_op_index;
    }
    if (!set_aux(t, t_index, ops->data[0].next_op_index)){
        return false;
    }
    return true;
}

bool deallocate_node(struct trie *t, size_t t_index){
    if (!set_links(t, get_aux(t, t->node_max + 1), t_index) || !set_links(t, t_index, t->node_max + 1) || !set_node(t, t_index, '\0')){
        return false;
    }
    t->occupied--;
    return true;
}

bool delete_bad_patterns(struct trie *t, struct outputs *ops){
    size_t old_op_cnt = ops->count;
    size_t old_trie_cnt = t->occupied;
    if (!delete_patterns(t, ops)){
        return false;
    }
    for (size_t h = 1; h <= ops->capacity; h++){
        if (ops->data[h].value == SIZE_MAX){
            ops->data[h].value = 0;
            ops->count--;
        }
    }
    printf("%zu nodes and %zu outputs deleted\n", old_trie_cnt - t->occupied, old_op_cnt - ops->count);
    return true;
}

@* Index.
Automatically generates the list of used identifiers
\end{document}