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
    for (size_t i = 0; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0) {
            print_help();
            return EXIT_SUCCESS;
        } else if (strcmp(argv[i], "--version") == 0) {
            print_version();
            return EXIT_SUCCESS;
        }
    }
    print_version();
    @<Initialization sequence@>;
    @<Level range specification@>;
    @<Pattern generation@>;
    @<Final pass@>;
    destroy_params(params);
    destroy_tr_table(tt);
    destroy_pattern_trie(pt);
    return EXIT_SUCCESS;
}
# endif

@* Implementation.
Main body of the program.

@<Library includes@>=
#include "utfpatgen.h"
#include <string.h>

@ Initialization sequence
Parse the passed parameters and store them into program internal structure.

@<Initialization sequence@>=
struct params *params = init_params();
if (params == NULL){
    return EXIT_FAILURE;
}
if (!parse_input(argv, argc, params)){
    destroy_params(params);
    return EXIT_FAILURE;
}
struct translate_table *tt = init_tr_table(256, 128);
if (tt == NULL){
    destroy_params(params);
    return EXIT_FAILURE;
}
if (!read_translate(params, tt)){
    destroy_params(params);
    destroy_tr_table(tt);
    return EXIT_FAILURE;
}
struct pattern_trie *pt = init_pattern_trie(256, 128);
if (pt == NULL){
    destroy_params(params);
    destroy_tr_table(tt);
    return EXIT_FAILURE;
}
struct pass_stats ps = {};
if (!read_patterns(params, pt, tt, &ps)){
    destroy_params(params);
    destroy_tr_table(tt);
    destroy_pattern_trie(pt);
    return EXIT_FAILURE;
}

@ Level range specification
Read the values for hyphenation level range from standard input, parse them, and feed in if acceptable.

@<Level range specification@>=
printf("hyph_start (lowest -), hyph_finish (highest hyphenation level): ");
size_t hyph_start, hyph_finish;
int result;
while (true){
    result = scanf("%zu %zu", &hyph_start, &hyph_finish);
    if (result == 2 && hyph_start >= 1 && hyph_start <= 254 && hyph_finish >= 1 && hyph_finish <= 254){
        break;
    } else {
        printf("Error: Specify 1 <= hyph_start, hyph_finish <= 254! Insert again: ");
        while(getchar() != '\n');
    }
}
params->hyph_start = (uint8_t) hyph_start;
if (hyph_start > hyph_finish){
    params->hyph_finish = ps.max_level;
    printf("Warning: hyph_start > hyph_finish, using hyph_finish = %u\n", ps.max_level);
} else {
    params->hyph_finish = (uint8_t) hyph_finish;
}

@ Pattern generation
Run the algorithm for every level in specified range. Read and parse hyperparameters and proceed to the generation itself.

@<Pattern generation@>=
size_t pat_start, pat_finish, good_wt, bad_wt, thresh;
for (size_t i = params->hyph_start; i <= params->hyph_finish; i++){
    params->hyph_level = i;
    ps.level_pattern_cnt = 0;
    if (params->hyph_level > params->hyph_start) {
        printf("\n");
    }
    if (params->hyph_start <= ps.max_level) {
        printf("Warning: Largest hyphenation value %u in patterns should be less than hyph_start\n", ps.max_level);
    }
    @<Hyperparameters input@>;
    @<Level generation@>;
    if (!delete_bad_patterns(pt)){
        destroy_params(params);
        destroy_tr_table(tt);
        destroy_pattern_trie(pt);
        return EXIT_FAILURE;
    }
    printf("total of %zu patterns at hyph_level %u\n", ps.level_pattern_cnt, params->hyph_level);    
}


@ Hyperparameters input
Read and parse the level-specific hyper parameters pat\_start, pat\_finish, good\_wt, bad\_wt, thresh.

@<Hyperparameters input@>=
printf("pat_start (shortest -), pat_finish (longest pattern explored): ");
while (true){
    result = scanf("%zu %zu", &pat_start, &pat_finish);
    if (result == 2 && pat_start >= 1 && pat_finish >= 1 && pat_start <= pat_finish && pat_start <= 255 && pat_finish <= 255){
        break;
    } else {
        printf("Error: Specify 1 <= pat_start <= pat_finish <= 255! Insert again: ");
        while (getchar() != '\n');
    }
}
params->pat_start = (uint8_t) pat_start;
params->pat_finish = (uint8_t) pat_finish;

printf("good_wt (good -), bad_wt (bad pattern weight), threshold: ");
while (true){
    result = scanf("%zu %zu %zu", &good_wt, &bad_wt, &thresh);
    if (result == 3 && good_wt >= 1 && bad_wt >= 1 && thresh >= 1 && good_wt <= 255 && bad_wt <= 255 && thresh <= 255){
        break;
    } else {
        printf("Error: Specify 1 <= good_wt, bad_wt, threshold <= 255! Insert again: ");
        while (getchar() != '\n');
    }
}
params->good_wt = (uint8_t) good_wt;
params->bad_wt = (uint8_t) bad_wt;
params->thresh = (uint8_t) thresh;

@ Level generation
Do single pass through the dictionary.

@<Level generation@>=
uint8_t aux_dot;
bool more_this_level[256];
for (size_t i = 0; i < 256; i++){
    more_this_level[i] = true;
}
for (size_t j = params->pat_start; j <= params->pat_finish; j++) {
    params->pat_len = j;
    params->pat_dot = params->pat_len / 2;
    aux_dot = params->pat_dot * 2;
    while (params->pat_dot != params->pat_len) {
        params->pat_dot = aux_dot - params->pat_dot;
        aux_dot = params->pat_len * 2 - aux_dot - 1;
        if (more_this_level[params->pat_dot]){
            if (!process_dictionary(params, tt, pt, &ps)){
                destroy_params(params);
                destroy_tr_table(tt);
                destroy_pattern_trie(pt);
                return EXIT_FAILURE;
            }
            more_this_level[params->pat_dot] = ps.more_to_come;
        }
    }
    for (size_t i = 255; i > 0; i--){
        if (!more_this_level[i-1]){
            more_this_level[i] = false;
        }
    }
}


@ Final pass
If the user wants, distionary is tranversed one last time and hyphenated according to found patterns. The output is stored in file 'pattmp.X'.

@<Final pass@>=
if (!output_patterns(pt, params->output_file)){
    destroy_params(params);
    destroy_tr_table(tt);
    destroy_pattern_trie(pt);
    return EXIT_FAILURE;
}
char c;
printf("hyphenate word list? (y/n): ");
if (scanf(" %c", &c) < 1){
    destroy_params(params);
    destroy_tr_table(tt);
    destroy_pattern_trie(pt);
    return EXIT_FAILURE;
}
if (c == 'y' || c == 'Y'){
    if (!hyphenate_dictionary(params, tt, pt, &ps)){
        destroy_params(params);
        destroy_tr_table(tt);
        destroy_pattern_trie(pt);
        return EXIT_FAILURE;
    }
}


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
    reset_buffer(buf);
    char c;
    while ((c = fgetc(stream)) != EOF) {
        if (buf->size >= buf->capacity - 1) {
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
bool parse_letters(struct string_buffer *buf, struct translate_table *tt){
    if (buf->size == 0){
        fprintf(stderr, "Empty line in translate file\n");
        return false;
    }
    char separator = buf->data[0];
    if (buf->size > 1 && buf->data[1] == separator){  // a comment
        return true;
    }
    size_t alphabet_index = tt->alphabet->size;
    size_t out_index;
    struct string_buffer *letter = init_buffer(4);
    if (letter == NULL) {
        return false;
    }
    bool lower = true;
    if (!append_char(buf, separator)){
        destroy_buffer(letter);
        return false;
    }
    for (size_t i = 1; i < buf->size; i++){
        char c = buf->data[i];
        if (c == separator){
            if (letter->size == 0){
                break;
            }
            if (!append_char(letter, '\0') || !insert_pattern(tt->mapping, letter->data, &out_index) || !set_aux(tt->mapping, out_index, alphabet_index)) {
                destroy_buffer(letter);
                return false;
            }
            if (lower) {
                if (!append_string(tt->alphabet, letter->data, letter->size)) {
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

bool default_ascii_mapping(struct translate_table *tt){
    size_t out_index;
    size_t alphabet_index;
    char upper;
    for (char c = 'a'; c <= 'z'; c++){
        alphabet_index = tt->alphabet->size;
        upper = c - ('a' - 'A');
        if (!insert_pattern(tt->mapping, (const char[]){c, '\0'}, &out_index) || !set_aux(tt->mapping, out_index, alphabet_index) || !append_string(tt->alphabet, (const char[]){c, '\0'}, 2)) {
            return false;
        }
        if (!insert_pattern(tt->mapping, (const char[]){upper, '\0'}, &out_index) || !set_aux(tt->mapping, out_index, alphabet_index)) {
            return false;
        }
    }
    alphabet_index = tt->alphabet->size;
    if (!insert_pattern(tt->mapping, (const char[]){EDGE_OF_WORD, '\0'}, &out_index) || !set_aux(tt->mapping, out_index, alphabet_index) || !append_string(tt->alphabet, (const char[]){EDGE_OF_WORD, '\0'}, 2)) {
        return false;
    }
    return true;
}

char *get_lower(struct translate_table *tt, const char *letter){
    size_t index = traverse_trie(tt->mapping, letter);
    if (index == 0 || get_aux(tt->mapping, index) >= tt->alphabet->size){
        return NULL;
    }
    return tt->alphabet->data + get_aux(tt->mapping, index);
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

    if (t->nodes == NULL || t->links == NULL || t->aux == NULL || t->taken == NULL || !set_base_used(t, 1, true)) {
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
    relink_trie(t);
    
    return t;
}

bool put_first_level(struct trie *t){
    size_t root = 1;
    size_t n_bytes = 256;
    size_t last_byte = 255;
    for (size_t i = 1; i <= last_byte; i++) {
        if (!set_node(t, root + i, (uint8_t) i) || !set_link(t, root + i, 0) || !set_aux(t, root + i, 0)){
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
    if (new_nodes == NULL) {
        fputs("Allocation error\n", stderr); return NULL;
    }
    t->nodes = new_nodes;
    
    size_t *new_links = realloc(t->links, new_capacity * sizeof(size_t));
    if (new_links == NULL) {
        fputs("Allocation error\n", stderr); return NULL;
    }
    t->links = new_links; 

    size_t *new_aux = realloc(t->aux, new_capacity * sizeof(size_t));
    if (new_aux == NULL) {
        fputs("Allocation error\n", stderr); return NULL;
    }
    t->aux = new_aux;

    size_t old_taken_bytes = (t->capacity / 8) + 1;
    size_t new_taken_bytes = (new_capacity / 8) + 1;
    char *new_taken = realloc(t->taken, new_taken_bytes * sizeof(char));
    if (new_taken == NULL) {
        fputs("Allocation error\n", stderr); return NULL;
    }
    t->taken = new_taken;

    if (new_taken_bytes > old_taken_bytes) {
        memset(t->taken + old_taken_bytes, 0, (new_taken_bytes - old_taken_bytes));
    }
    memset(t->nodes + t->capacity, 0, (new_capacity - t->capacity) * sizeof(char));
    t->capacity = new_capacity;
    relink_trie(t);
    return t;
}

void destroy_trie(struct trie *t){
    free(t->nodes);
    free(t->links);
    free(t->aux);
    free(t->taken);
    free(t);
}

void relink_trie(struct trie *t){
    size_t last_free = 0;
    for (size_t node = 2; node < t->capacity; node++){
        if (!is_node_occupied(t, node)) {
            set_links(t, last_free, node);
            last_free = node;
        }
    }
    set_links(t, last_free, 0);
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
        if (resize_trie(t, index + 1) == NULL) {
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
    uint8_t offset;
    t_index = 0;
    while (true) {
        t_index = get_link(t, t_index);
        if (t_index == 0) {
            if (!resize_trie(t, 2*t->capacity)){
                return false;
            }
            continue;
        }
        offset = (uint8_t) get_node(q, 1);
        if (t_index <= offset) {
            continue;
        }
        *out_base = t_index - offset;
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
        if (!copy_node(q, q_index, t, t_index)) {
            return false;
        }
    }
    relink_trie(t);
    if (!set_base_used(t, base, true)){
        return false;
    }
    *out_base = base;
    return true;
}

bool unpack(struct trie *from, size_t base, struct trie *to){
    to->node_max = 1;
    for (size_t i = 1; i < 256; i++){
        size_t from_index = base + i;
        if ((uint8_t) get_node(from, from_index) == i) {
            if (!copy_node(from, from_index, to, to->node_max) || !set_node(from, from_index, 0)) {
                return false;
            }
            to->node_max++;
        }
    }
    relink_trie(from);
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

bool new_trie_output(struct pattern_trie *pt, size_t value, size_t position, size_t next_op_index, size_t *op_index){
    if (pt->ops->count >= pt->ops->capacity - 1) {
        if (resize_outputs(pt->ops, pt->ops->capacity * 2, pt->t) == NULL) {
            return false;
        }
    }
    size_t hash = hash_trie_output(pt->ops, value, position, next_op_index);
    if (pt->ops->data[hash].value == 0) {
        pt->ops->count++;
        struct output new_op = {.value = value, .position = position, .next_op_index = next_op_index};
        pt->ops->data[hash] = new_op;
    } 
    *op_index = hash;
    return true;
}

size_t hash_trie_output(struct outputs *ops, size_t value, size_t position, size_t next_op_index){
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
    return 0;
}

bool insert_pattern(struct trie *t, const char *pattern, size_t *out_op_index){
    size_t length = strlen(pattern);
    return insert_substring(t, pattern, length, length, out_op_index);
}

bool insert_substring(struct trie *t, const char *pattern, size_t end, size_t length, size_t *out_op_index){
    size_t index = end - length;
    size_t base = 1;
    size_t node = base + (uint8_t) pattern[index];
    size_t fit;
    size_t node_prev = 0;
    struct trie *q = init_trie(256);
    if (q == NULL) {
        return false;
    }
    bool new_pattern = false;
    while (index < end && base > 0) {
        node = base + (uint8_t) pattern[index];
        if (get_node(t, node) != pattern[index]) {
            new_pattern = true;
            if (get_node(t, node) == 0) {
                if (!set_links(t, get_aux(t, node), get_link(t, node)) || !set_node(t, node, pattern[index]) || !set_aux(t, node, 0) || !set_link(t, node, 0)) {
                    destroy_trie(q);
                    return false;
                }
                if (node > t->node_max) {
                    t->node_max = node;
                }
            } else {
                if (!repack(t, q, &node_prev, &node, pattern[index])) {
                    destroy_trie(q);
                    return false;
                }
            }
            t->occupied++;
        }
        index++;
        node_prev = node;
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
        new_pattern = true;
    }
    *out_op_index = node;
    if (new_pattern){
        t->pattern_count++;
    }
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

bool set_output(struct pattern_trie *pt, size_t node, size_t value, size_t position){
    size_t op_index;
    if (!new_trie_output(pt, value, position, get_aux(pt->t, node), &op_index) || !set_aux(pt->t, node, op_index)) {
        return false;
    }
    return true;
}

@* Output.
The \texttt{output} structure is used for storing hyphenation outputs. The structure uses following fields:
\begin{itemize}
    \item \textbf{value}: hyphenation value,
    \item \textbf{position}: position in the pattern,
    \item \textbf{next\_op\_index}: index of the next output in the linked list.
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
    struct output *old_data = ops->data;
    ops->data = new_data;
    ops->capacity = capacity;
    for (size_t i = 0; i < t->capacity; i++) {
        if (is_node_occupied(t, i) && get_aux(t, i) != 0) {
            size_t old_index = get_aux(t, i);
            struct output old_op = old_data[old_index];
            size_t new_index = hash_trie_output(ops, old_op.value, old_op.position, old_op.next_op_index); // !!! old\_op\_index is invalid
            ops->data[new_index] = old_op;
            if (!set_aux(t, i, new_index)){
                free(old_data);
                return NULL;
            }
        }
    }
    free(old_data);
    return ops;
}

void destroy_outputs(struct outputs *ops){
    free(ops->data);
    free(ops);
}

struct pattern_trie *init_pattern_trie(size_t trie_capacity, size_t outputs_capacity){
    struct pattern_trie *pt = malloc(sizeof(struct pattern_trie));
    if (pt == NULL){
        return NULL;
    }
    pt->t = init_trie(trie_capacity);
    if (pt->t == NULL){
        free(pt);
        return NULL;
    }
    if (!put_first_level(pt->t)){
        free(pt->t);
        free(pt);
        return NULL;
    }
    pt->ops = init_outputs(outputs_capacity);
    if (pt->ops == NULL){
        free(pt->t);
        free(pt);
        return NULL;
    }
    return pt;
}

void destroy_pattern_trie(struct pattern_trie *pt){
    destroy_trie(pt->t);
    destroy_outputs(pt->ops);
    free(pt);
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

    p->word_weight = 1;

    p->dictionary_file = NULL;
    p->pattern_file = NULL;
    p->output_file = NULL;
    p->translate_file = NULL;
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
    if (p->dictionary_file != NULL){
        fclose(p->dictionary_file);
    }
    if (p->pattern_file != NULL){
        fclose(p->pattern_file);
    }
    if (p->output_file != NULL){
        fclose(p->output_file);
    }
    if (p->translate_file != NULL){
        fclose(p->translate_file);
    }
    free(p);
}

struct translate_table *init_tr_table(size_t mapping_capacity, size_t alphabet_capacity){
    struct translate_table *tt = malloc(sizeof(struct translate_table));
    if (tt == NULL){
        fprintf(stderr, "Allocation error\n");
        return NULL;
    }
    struct trie *mapping = init_trie(mapping_capacity);
    if (mapping == NULL){
        free(tt);
        return NULL;
    }
    struct string_buffer *alphabet = init_buffer(alphabet_capacity);
    if (alphabet == NULL){
        destroy_trie(mapping);
        free(tt);
        return NULL;
    }
    tt->mapping = mapping;
    tt->alphabet = alphabet;
    if (!append_char(tt->alphabet, '\0')){
        destroy_trie(tt->mapping);
        destroy_buffer(tt->alphabet);
        free(tt);
        return NULL;
    }
    return tt;
}

void destroy_tr_table(struct translate_table *tt){
    destroy_trie(tt->mapping);
    destroy_buffer(tt->alphabet);
    free(tt);
}

bool read_translate(struct params *params, struct translate_table *tt){
    rewind(params->translate_file);
    struct string_buffer *buf = init_buffer(64);
    if (buf == NULL) {
        return false;
    }
    if (!read_line(params->translate_file, buf)) {
        destroy_buffer(buf);
        return false;
    }
    if (buf->eof) {
        bool default_mapping = default_ascii_mapping(tt);
        destroy_buffer(buf);
        return default_mapping;
    }
    bool first_line = true;
    while (!buf->eof) {
        if (first_line && parse_header(buf, params)) {
            // header parsed successfully
        } else if (!parse_letters(buf, tt)) {
            destroy_buffer(buf);
            return false;
        }
        first_line = false;
        reset_buffer(buf);
        if (!read_line(params->translate_file, buf)) {
            destroy_buffer(buf);
            return false;
        }
    }
    destroy_buffer(buf);
    printf("left_hyphen_min = %u, right_hyphen_min = %u, %zu letters\n", params->left_hyphen_min, params->right_hyphen_min, tt->mapping->pattern_count);
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
    pc->good = calloc(capacity, sizeof(size_t));
    pc->bad = calloc(capacity, sizeof(size_t));
    if (pc->good == NULL || pc->bad == NULL){
        fprintf(stderr, "Allocation error\n");
        free(pc->good);
        free(pc->bad);
        free(pc);
        return NULL;
    }
    pc->capacity = capacity;
    pc->size = 1;
    return pc;
}

struct pattern_counts *resize_pattern_counts(struct pattern_counts *pc, size_t new_capacity){
    size_t *new_good = realloc(pc->good, new_capacity * sizeof(size_t));
    if (new_good == NULL){
        fprintf(stderr, "Allocation error\n");
        return NULL;
    }
    pc->good = new_good;
    size_t *new_bad = realloc(pc->bad, new_capacity * sizeof(size_t));
    if (new_bad == NULL){
        fprintf(stderr, "Allocation error\n");
        return NULL;
    }
    pc->bad = new_bad;
    size_t diff = new_capacity - pc->capacity;
    memset(pc->good + pc->capacity, 0, diff * sizeof(size_t));
    memset(pc->bad + pc->capacity, 0, diff * sizeof(size_t));
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
    if (index >= pc->capacity){
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
    if (index >= pc->capacity){
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

struct count_trie *init_count_trie(size_t trie_capacity, size_t counts_capacity){
    struct count_trie *ct = malloc(sizeof(struct count_trie));
    if (ct == NULL){
        return NULL;
    }
    ct->t = init_trie(trie_capacity);
    if (ct->t == NULL){
        free(ct);
        return NULL;
    }
    if (!put_first_level(ct->t)){
        free(ct->t);
        free(ct);
        return NULL;
    }
    ct->cnts = init_pattern_counts(counts_capacity);
    if (ct->cnts == NULL){
        free(ct->t);
        free(ct);
        return NULL;
    }
    return ct;
}

void destroy_count_trie(struct count_trie *ct){
    destroy_trie(ct->t);
    destroy_pattern_counts(ct->cnts);
    free(ct);
}

bool is_utf_start_byte(uint8_t byte){
    return (byte & 0xc0) != 0x80;
}

bool collect_count_trie(struct count_trie *ct, struct pattern_trie *pt, struct params *params, struct pass_stats *ps){
    double bad_eff = (double) params->thresh / (double) params->good_wt;
    ps->good_pat_cnt = 0;
    ps->bad_pat_cnt = 0;
    ps->good_cnt = 0;
    ps->bad_cnt = 0;
    ps->more_to_come = false;
    if (!traverse_count_trie(ct, pt, params, ps)){
        return false;
    }
    printf("%zu good and %zu bad patterns added", ps->good_pat_cnt, ps->bad_pat_cnt);
    ps->level_pattern_cnt += ps->good_pat_cnt;
    if (ps->more_to_come) {
        printf(" (more to come)\n");
    } else {
        printf("\n");
    }
    printf("finding %zu good and %zu bad hyphens", ps->good_cnt, ps->bad_cnt);
    if (ps->good_pat_cnt > 0) {
        printf(", efficiency = %.2lf\n", (double) ps->good_cnt / (ps->good_pat_cnt + ((double) ps->bad_cnt / bad_eff)));
    } else {
        printf("\n");
    }
    printf("pattern trie has %zu nodes, trie_max = %zu, %zu outputs\n", pt->t->occupied, pt->t->node_max, pt->ops->count);
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

struct word *init_word(size_t capacity){
    struct word *word = malloc(sizeof(struct word));
    if (word == NULL){
        return NULL;
    }
    word->lowercase = calloc(capacity, sizeof(char));
    if (word->lowercase == NULL){
        free(word);
        return NULL;
    }
    word->true_hyphens = calloc(capacity, sizeof(size_t));
    if (word->lowercase == NULL){
        free(word->lowercase);
        free(word);
        return NULL;
    }
    word->found_hyphens = calloc(capacity, sizeof(uint8_t));
    if (word->lowercase == NULL){
        free(word->lowercase);
        free(word->true_hyphens);
        free(word);
        return NULL;
    }
    word->no_more = calloc(capacity, sizeof(bool));
    if (word->lowercase == NULL){
        free(word->lowercase);
        free(word->true_hyphens);
        free(word->found_hyphens);
        free(word);
        return NULL;
    }
    word->size = 0;
    word->length = 0;
    word->capacity = capacity;
    return word;
}

struct word *resize_word(struct word *word, size_t new_capacity){
    char *new_lowercase = realloc(word->lowercase, new_capacity * sizeof(char));
    if (new_lowercase == NULL) { fprintf(stderr, "Allocation error\n"); return NULL; }
    word->lowercase = new_lowercase;

    size_t *new_true_hyphens = realloc(word->true_hyphens, new_capacity * sizeof(size_t));
    if (new_true_hyphens == NULL) { fprintf(stderr, "Allocation error\n"); return NULL; }
    word->true_hyphens = new_true_hyphens;

    uint8_t *new_found_hyphens = realloc(word->found_hyphens, new_capacity * sizeof(uint8_t));
    if (new_found_hyphens == NULL) { fprintf(stderr, "Allocation error\n"); return NULL; }
    word->found_hyphens = new_found_hyphens;

    bool *new_no_more = realloc(word->no_more, new_capacity * sizeof(bool));
    if (new_no_more == NULL) { fprintf(stderr, "Allocation error\n"); return NULL; }
    word->no_more = new_no_more;

    size_t diff = new_capacity - word->capacity;
    memset(word->lowercase + word->capacity, '\0', diff * sizeof(char));
    memset(word->true_hyphens + word->capacity, 0, diff * sizeof(size_t));
    memset(word->found_hyphens + word->capacity, 0, diff * sizeof(uint8_t));
    memset(word->no_more + word->capacity, false, diff * sizeof(bool));

    word->capacity = new_capacity;
    return word;
}

void reset_word(struct word *word){
    word->length = 0;
    word->size = 0;
    memset(word->lowercase, 0, word->capacity*sizeof(char));
    memset(word->true_hyphens, 0, word->capacity*sizeof(size_t));
    memset(word->found_hyphens, 0, word->capacity*sizeof(uint8_t));
    memset(word->no_more, false, word->capacity*sizeof(bool));
}

void destroy_word(struct word *word){
    free(word->lowercase);
    free(word->true_hyphens);
    free(word->found_hyphens);
    free(word->no_more);
    free(word);
}

bool append_char_to_word(struct word *word, char c){
    if (word->size >= word->capacity - 1){
        if (!resize_word(word, 2 * word->capacity)){
            return false;
        }
    }
    word->lowercase[word->size] = c;
    word->size++;
    if (is_utf_start_byte(c)){
        word->length++;
    }
    return true;
}

bool append_string_to_word(struct word *word, char *s, size_t length){
    if (word->size >= word->capacity - length){
        if (!resize_word(word, 2 * (word->capacity + length))){
            return false;
        }
    }
    for (size_t i = 0; i < length; i++) {
        if (is_utf_start_byte(s[i])){
            word->length++;
        }
        word->lowercase[word->size] = s[i];
        word->size++;
    }
    return true;
}

char get_char(struct word *word, size_t index){
    if (index >= word->size){
        return '\0';
    }
    return word->lowercase[index];
}

size_t get_true_hyphen(struct word *word, size_t index){
    if (index >= word->size){
        return 0;
    }
    return word->true_hyphens[index];
}

bool set_true_hyphen(struct word *word, size_t index, size_t value){
    if (index >= word->size){
        return false;
    }
    word->true_hyphens[index] = value;
    return true;
}

uint8_t get_found_hyphen(struct word *word, size_t index){
    if (index >= word->size) {
        return 0;
    }
    return word->found_hyphens[index];    
}

bool set_found_hyphen(struct word *word, size_t index, uint8_t value){
    if (index >= word->size){
        return false;
    }
    word->found_hyphens[index] = value;
    return true;
}

bool get_no_more(struct word *word, size_t index){
    if (index >= word->size){
        return false;
    }
    return word->no_more[index];
}

bool set_no_more(struct word *word, size_t index, bool value){
    if (index >= word->size){
        return false;
    }
    word->no_more[index] = value;
    return true;
}

uint8_t n_utf_following_bytes(uint8_t c){
    if (c < 128){
        return 0;
    } else if (c < 208){
        return 1;
    } else if (c < 216){
        return 2;
    } else {
        return 3;
    }
}

bool traverse_count_trie(struct count_trie *ct, struct pattern_trie *pt, struct params *params, struct pass_stats *ps) {
    size_t root = 1;
    size_t current_len = 0;
    uint8_t c;
    struct string_buffer *pattern = init_buffer(4 * params->pat_len);
    if (pattern == NULL){
        return false;
    }
    struct stack *s_base = init_stack(4 * params->pat_len);
    if (s_base == NULL) {
        destroy_buffer(pattern);
        return false;
    }
    if (!append_char(pattern, '\0') || !put_on_stack(s_base, root)){
        destroy_buffer(pattern);
        destroy_stack(s_base);
        return false;
    }
    size_t node, utf_bytes_to_end = 0, op_index, good, bad, cnt_index;
    while (s_base->top > 0){
        root = get_top_value(s_base);
        pattern->data[pattern->size - 1] += 1;
        c = (uint8_t) pattern->data[pattern->size - 1];
        if (c == 0){ // overflow, is this safe?
            pattern->size--;
            s_base->top--;
            if (pattern->size < 1 || is_utf_start_byte(pattern->data[pattern->size - 1])){
                current_len--;
            } else {
                utf_bytes_to_end++;
            }
            continue;
        }
        node = root + c;
        if ((uint8_t) get_node(ct->t, node) != c){
            continue;
        }
        if (is_utf_start_byte(c)) {
            current_len++;
            utf_bytes_to_end = n_utf_following_bytes((uint8_t) c);
        } else {
            utf_bytes_to_end -= 1;
        }
        if (current_len == params->pat_len && utf_bytes_to_end == 0){
            cnt_index = get_aux(ct->t, node);
            good = get_good(ct->cnts, cnt_index);
            bad = get_bad(ct->cnts, cnt_index);
            if (params->good_wt * good < params->thresh){
                if (!insert_substring(pt->t, pattern->data, pattern->size, pattern->size, &op_index) || !set_output(pt, op_index, BAD_OP_VALUE, params->pat_dot)){
                    destroy_buffer(pattern);
                    destroy_stack(s_base);
                    return false;
                }
                ps->bad_pat_cnt++;
            } else if (params->good_wt * good >= params->thresh + params->bad_wt * bad) {
                if (!insert_substring(pt->t, pattern->data, pattern->size, pattern->size, &op_index) || !set_output(pt, op_index, params->hyph_level, params->pat_dot)){
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
            if (is_utf_start_byte(c)) {
                current_len--;
            } else {
                utf_bytes_to_end++;
            }
            continue;
        }
        root = get_link(ct->t, node);
        if (root == 0){
            if (is_utf_start_byte(c)) {
                current_len--;
            } else {
                utf_bytes_to_end++;
            }
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

bool delete_patterns(struct pattern_trie *pt){
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
    size_t node;
    uint8_t c;
    while (s_base->top > 0){
        root = get_top_value(s_base);
        set_top_value(s_offset, (uint8_t) get_top_value(s_offset) + 1);
        c = (uint8_t) get_top_value(s_offset);
        if (c == 0){
            bool child_freed = (get_top_value(s_freed) == (size_t) true);
            if (child_freed){
                if (!set_base_used(pt->t, root, false)){
                    destroy_stack(s_base);
                    destroy_stack(s_offset);
                    destroy_stack(s_freed);
                    return false;
                }
            } 
            s_offset->top--;
            s_base->top--;
            s_freed->top--;
            if (s_base->top > 0) {
                size_t parent_root = get_top_value(s_base);
                uint8_t parent_c = (uint8_t) get_top_value(s_offset);
                size_t parent_node = parent_root + parent_c;
                if (child_freed) {
                    if (!set_link(pt->t, parent_node, 0)){
                        destroy_stack(s_base);
                        destroy_stack(s_offset);
                        destroy_stack(s_freed);
                        return false;
                    }
                    if (get_aux(pt->t, parent_node) == 0 && parent_root != 1) {
                        if (!deallocate_node(pt->t, parent_node)){
                            destroy_stack(s_base);
                            destroy_stack(s_offset);
                            destroy_stack(s_freed);
                            return false;
                        }
                    } else {
                        set_top_value(s_freed, (size_t) false);
                    }
                } else {
                    set_top_value(s_freed, (size_t) false);
                }
            }
            continue;
        }
        node = root + c;
        if ((uint8_t) get_node(pt->t, node) != c){
            continue;
        }
        if (!link_around_bad_outputs(pt, node)){
            destroy_stack(s_base);
            destroy_stack(s_offset);
            destroy_stack(s_freed);
            return false;
        }
        if (get_aux(pt->t, node) > 0 || root == 1){
            set_top_value(s_freed, (size_t) false);
        } else {
            if (get_link(pt->t, node) == 0){
                if (!deallocate_node(pt->t, node)){
                    destroy_stack(s_base);
                    destroy_stack(s_offset);
                    destroy_stack(s_freed);
                    return false;
                }
            }
            
        }
        root = get_link(pt->t, node);
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

bool link_around_bad_outputs(struct pattern_trie *pt, size_t t_index){
    size_t op_index = get_aux(pt->t, t_index);
    size_t h = 0;
    pt->ops->data[0].next_op_index = op_index;
    size_t n = pt->ops->data[0].next_op_index;
    while (n > 0){
        if (pt->ops->data[n].value == BAD_OP_VALUE){
            pt->ops->data[h].next_op_index = pt->ops->data[n].next_op_index;
        } else {
            h = n;
        }
        n = pt->ops->data[h].next_op_index;
    }
    if (!set_aux(pt->t, t_index, pt->ops->data[0].next_op_index)){
        return false;
    }
    return true;
}

bool deallocate_node(struct trie *t, size_t t_index){
    if (!set_links(t, t_index, get_link(t, 0)) || !set_links(t, 0, t_index) || !set_node(t, t_index, 0)){
        return false;
    }
    t->occupied--;
    return true;
}

bool delete_bad_patterns(struct pattern_trie *pt){
    size_t old_op_cnt = pt->ops->count;
    size_t old_trie_cnt = pt->t->occupied;
    if (!delete_patterns(pt)){
        return false;
    }
    for (size_t h = 1; h <= pt->ops->capacity; h++){
        if (pt->ops->data[h].value == BAD_OP_VALUE){
            pt->ops->data[h].value = EMPTY_OP_VALUE;
            pt->ops->count--;
        }
    }
    printf("%zu nodes and %zu outputs deleted\n", old_trie_cnt - pt->t->occupied, old_op_cnt - pt->ops->count);
    return true;
}

bool output_patterns(struct pattern_trie *pt, FILE *pattern_file){
    size_t root = 1;
    uint8_t c;
    struct string_buffer *pattern = init_buffer(16);
    if (pattern == NULL){
        return false;
    }

    struct stack *s_base = init_stack(16 * sizeof(size_t));
    if (s_base == NULL) {
        destroy_buffer(pattern);
        return false;
    }
    if (!append_char(pattern, '\0') || !put_on_stack(s_base, root)){
        destroy_buffer(pattern);
        destroy_stack(s_base);
        return false;
    }

    size_t node;
    while (s_base->top > 0){
        root = get_top_value(s_base);
        pattern->data[pattern->size - 1] += 1;
        c = (uint8_t) pattern->data[pattern->size - 1];
        if (c == 0){
            pattern->data[pattern->size - 1] = '\0';
            pattern->size--;
            s_base->top--;
            continue;
        }
        node = root + c;
        if ((uint8_t) get_node(pt->t, node) != c){
            continue;
        }
        if (get_aux(pt->t, node) > 0){
            output_pattern(pattern, pt->ops, get_aux(pt->t, node), pattern_file);
        }
        root = get_link(pt->t, node);
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

void output_pattern(struct string_buffer *pattern, struct outputs *ops, size_t op_index, FILE *pattern_file){
    if (op_index == 0){
        return;
    }
    size_t pattern_position = 0;
    size_t level;
    for (size_t i = 0; i < pattern->size; i++) {
        if (is_utf_start_byte(pattern->data[i])){
            level = get_highest_level(ops, op_index, pattern_position);
            if (level > 0){
                fprintf(pattern_file, "%zu", level);
            }
            pattern_position++;
        }
        fputc(pattern->data[i], pattern_file);
    }
    level = get_highest_level(ops, op_index, pattern_position);
    if (level > 0){
        fprintf(pattern_file, "%zu", level);
    }
    fputc('\n', pattern_file);
}

size_t get_highest_level(struct outputs *ops, size_t start_index, size_t position){
    size_t highest = 0;
    size_t op_index = start_index;
    struct output op;
    while (op_index > 0){
        op = ops->data[op_index];
        if (op.position == position && op.value != BAD_OP_VALUE && op.value > highest){
            highest = op.value;
        }
        op_index = op.next_op_index;
    }
    return highest;
}

@ Break

@c
bool parse_word(struct string_buffer *buf, struct translate_table *tt, struct params *params, struct word *out_word){
    reset_word(out_word);
    struct string_buffer *letter = init_buffer(4);
    if (letter == NULL) {
        return false;
    }
    uint8_t weight = params->word_weight;
    enum hyphen_class hyf = NO_HYF;
    if (!append_char_to_word(out_word, EDGE_OF_WORD)){
        destroy_buffer(letter);
        return false;
    }
    char c;
    char *lower;
    for (size_t i = 0; i < buf->size; i++){
        c = buf->data[i];
        if (is_ascii_number(buf->data[i])){
            weight = (uint8_t) (c - '0');
            if (i == 0){
                params->word_weight = weight;
            }
            continue;
        } else if (c == params->good_hyphen) {
            hyf = GOOD_HYF;
            continue;
        } else if (c == params->missed_hyphen){
            hyf = MISS_HYF;
            continue;
        } else if (c == params->bad_hyphen) {
            hyf = BAD_HYF;
            continue;
        } else if (is_utf_start_byte(c) && letter->size > 0){
            if (!append_char(letter, '\0')){
                destroy_buffer(letter);
                return false;
            }
            lower = get_lower(tt, letter->data);
            if (lower == NULL) {
                fprintf(stderr, "Character '%s' not known\n", letter->data);
                destroy_buffer(letter);
                return false;
            }
            if (!append_string_to_word(out_word, lower, strlen(lower))){
                destroy_buffer(letter);
                return false;
            }
            if (!set_true_hyphen(out_word, out_word->size-1, 4 * weight + hyf)){
                destroy_buffer(letter);
                return false;
            }
            hyf = NO_HYF;
            reset_buffer(letter);
        }
        weight = params->word_weight;
        if (!append_char(letter, c)){
            destroy_buffer(letter);
            return false;
        }
    }
    if (!append_char(letter, '\0')){
        destroy_buffer(letter);
        return false;
    }
    lower = get_lower(tt, letter->data);
    if (lower == NULL) {
        fprintf(stderr, "Character '%s' not known\n", letter->data);
        destroy_buffer(letter);
        return false;
    }
    if (!append_string_to_word(out_word, lower, strlen(lower)) || !append_char_to_word(out_word, EDGE_OF_WORD) || !set_true_hyphen(out_word, 0, 0)){
        destroy_buffer(letter);
        return false;
    }
    return true;
}

bool is_ascii_number(char c){
    return c >= '0' && c <= '9';
}

bool hyphenate_word(struct word *word, struct pattern_trie *pt, struct params *params){
    size_t current_index = word->size;
    size_t current_pos = word->length;
    size_t node, base, start_index, dot_index, end_index, op_index, dot_pos, end_pos;
    struct output op;
    if (word->length < params->right_hyphen_min + 1){
        return true;
    }
    size_t start_pos = word->length - params->right_hyphen_min;
    for (size_t i = 0; i < word->length - params->right_hyphen_min; i++) {
        start_pos--;
        while (current_pos > start_pos) {
            current_index--;
            if (is_utf_start_byte(get_char(word, current_index))) {
                current_pos--;
            }
        }
        start_index = current_index;
        end_index = current_index;
        end_pos = current_pos + 1;
        node = 1 + (uint8_t) get_char(word, start_index);
        while (get_node(pt->t, node) == get_char(word, end_index)){
            end_index++;
            if (is_utf_start_byte(get_char(word, end_index))){
                end_pos++;
            }
            op_index = get_aux(pt->t, node);
            while (op_index > 0){
                if (op_index > pt->ops->capacity){
                    fprintf(stderr, "Output index %zu out of bounds\n", op_index);
                    return false;
                }
                op = pt->ops->data[op_index];
                dot_pos = start_pos;
                dot_index = start_index;
                while (dot_pos < start_pos + op.position){
                    dot_index++;
                    if (is_utf_start_byte(get_char(word, dot_index))){
                        dot_pos++;
                    }
                }
                dot_index--;
                if (op.value < BAD_OP_VALUE && get_found_hyphen(word, dot_index) < op.value){
                    if (!set_found_hyphen(word, dot_index, op.value)){
                        return false;
                    }
                }
                if (op.value >= params->hyph_level){
                    if ((end_pos + params->pat_dot <= dot_pos + params->pat_len) && (dot_pos <= start_pos + params->pat_dot)){
                        if (!set_no_more(word, dot_index, true)){
                            return false;
                        }
                    }
                }
                op_index = op.next_op_index;
            }
            base = get_link(pt->t, node);
            if (base == 0){
                break;
            }
            node = base + (uint8_t) get_char(word, end_index);
        }
    }
    return true;
}

void count_dots(struct word *word, struct params *params, struct pass_stats *ps){
    if (word->length < params->right_hyphen_min + 1){
        return;
    }
    size_t current_index = word->size;
    size_t current_pos = word->length;
    bool odd_level;
    size_t dot_index, hyphenation_value, weight;
    enum hyphen_class hyf;
    for (size_t dot_pos = word->length - params->right_hyphen_min - 1; dot_pos >= params->left_hyphen_min + 1; dot_pos--){
        while (current_pos > dot_pos){
            current_index--;
            if (is_utf_start_byte(get_char(word, current_index))) {
                current_pos--;
            }
        }
        dot_index = current_index - 1;
        odd_level = (get_found_hyphen(word, dot_index) % 2 == 1);
        hyphenation_value = get_true_hyphen(word, dot_index);
        weight = hyphenation_value / 4;
        hyf = hyphenation_value % 4;
        if (hyphenation_value == 0){
            fprintf(stderr, "Code I hoped unreachable was reached\n");
            continue;
        } else if (hyf % 2 == 0) {
            if (odd_level) {
                ps->bad_cnt += weight;
            }
        } else {
            if (odd_level) {
                ps->good_cnt += weight;
            } else {
                ps->miss_cnt += weight;
            }
        }
    }
}

void output_hyphenated_word(FILE *pattmp, struct word *word, struct params *params){
    if (params->word_weight > 1){
        fprintf(pattmp, "%d", params->word_weight);
    }
    char c;
    size_t weight, dot_pos = 0;
    bool has_hyphen, found_hyphen;
    for (size_t i = 0; i < word->size; i++){
        has_hyphen = false;
        found_hyphen = (get_found_hyphen(word, i) % 2 == 1 );
        c = get_char(word, i);
        if (c == EDGE_OF_WORD){
            continue;
        }
        if (is_utf_start_byte(c)){
            dot_pos++;
        }
        fputc(c, pattmp);
        weight = get_true_hyphen(word, i);
        if (weight == 0 || dot_pos < params->left_hyphen_min || dot_pos >= word->length - params->right_hyphen_min - 1){
            continue;
        }
        if (weight % 2 == 1) {
            has_hyphen = true;
        }
        weight /= 4;
        if (weight != params->word_weight){
            fprintf(pattmp, "%zu", weight);
        }
        if (found_hyphen && has_hyphen){
            fputc((char) params->good_hyphen, pattmp);
        } else if (found_hyphen && !has_hyphen){
            fputc((char) params->bad_hyphen, pattmp);
        } else if (!found_hyphen && has_hyphen){
            fputc((char) params->missed_hyphen, pattmp);
        }
    }
    fputc('\n', pattmp);
}

bool process_word(struct word *word, struct count_trie *ct, struct params *params){
    uint8_t dot_min = params->pat_dot;
    uint8_t dot_max = params->pat_len - params->pat_dot;
    if (dot_min < params->left_hyphen_min + 1){
        dot_min = params->left_hyphen_min + 1;
    }
    if (dot_max < params->right_hyphen_min + 1){
        dot_max = params->right_hyphen_min + 1;
    }
    size_t start_pos, end_pos, start_index, dot_index, end_index, node, weight, cnt_index;
    size_t current_pos = word->length;
    size_t current_index = word->size;
    bool good_pattern;
    enum hyphen_class hyf;
    for (size_t dot_pos = word->length - dot_max; dot_pos >= dot_min; dot_pos--) {
        while (current_pos > dot_pos){
            current_index--;
            if (is_utf_start_byte(get_char(word, current_index))){
                current_pos--;
            }
        }
        dot_index = current_index - 1;
        if (get_no_more(word, dot_index)){
            continue;
        }
        hyf = get_true_hyphen(word, dot_index) % 4;
        if (get_found_hyphen(word, dot_index) % 2 == 1){
            hyf += 2;
        }
        if (hyf == params->good_dot){
            good_pattern = true;
        } else if (hyf == params->bad_dot){
            good_pattern = false;
        } else {
            continue;
        }
        start_pos = dot_pos;
        start_index = current_index;
        while (start_pos > dot_pos - params->pat_dot){
            start_index--;
            if (is_utf_start_byte(get_char(word, start_index))){
                start_pos--;
            }
        }
        end_pos = dot_pos;
        end_index = current_index;
        while (end_pos < start_pos + params->pat_len){
            end_index++;
            if (is_utf_start_byte(get_char(word, end_index))){
                end_pos++;
            }
        }
        if (!insert_substring(ct->t, word->lowercase, end_index, end_index - start_index, &node)){
            return false;
        }
        if (ct->cnts->size >= ct->cnts->capacity) {
            size_t new_capacity = ct->t->capacity;
            if (resize_pattern_counts(ct->cnts, new_capacity) == NULL) {
                return false;
            }
        }
        cnt_index = get_aux(ct->t, node);
        if (cnt_index == 0){
            cnt_index = ct->cnts->size;
            if (!set_aux(ct->t, node, cnt_index)){
                return false;
            }
            ct->cnts->size++;
        }
        weight = get_true_hyphen(word, dot_index) / 4;
        if (good_pattern){
            ct->cnts->good[cnt_index] += weight;
        } else {
            ct->cnts->bad[cnt_index] += weight;
        }
    }
    return true;
}

bool end_of_pattern(struct word *word, size_t pattern_len, size_t start_index, size_t *out_end_index){
    if (start_index >= word->size){
        return false;
    }
    size_t i = start_index;
    char c;
    size_t current_len = 0;
    while (current_len < pattern_len && i < word->size){
        c = get_char(word, i);
        if (is_utf_start_byte(c)){
            current_len++;
        }
        i++;
    }
    if (i == word->size) {
        current_len++;
    }
    if (current_len == pattern_len){
        *out_end_index = i;
        return true;
    }
    return false;
}

bool process_dictionary(struct params *params, struct translate_table *tt, struct pattern_trie *pt, struct pass_stats *ps){
    ps->good_cnt = 0;
    ps->bad_cnt = 0;
    ps->miss_cnt = 0;
    params->word_weight = 1;
    if (params->hyph_level % 2 == 1){
        params->good_dot = MISS_HYF;
        params->bad_dot = NO_HYF;
    } else {
        params->good_dot = BAD_HYF;
        params->bad_dot = GOOD_HYF;
    }
    struct count_trie *ct = init_count_trie(256, 256);
    if (ct == NULL){
        return false;
    }
    printf("processing dictionary with pat_len = %u, pat_dot = %u\n", params->pat_len, params->pat_dot);
    if (!process_all_words(params, tt, pt, ps, ct)){
        destroy_count_trie(ct);
        return false;
    }
    printf("\n%zu good, %zu bad, %zu missed\n", ps->good_cnt, ps->bad_cnt, ps->miss_cnt);
    if (ps->good_cnt + ps->miss_cnt > 0){
        printf("%.2f %%, %.2f %%, %.2f %%\n", (100* (float) ps->good_cnt / (float) (ps->good_cnt + ps->miss_cnt)), (100* (float) ps->bad_cnt/ (float) (ps->good_cnt + ps->miss_cnt)), (100* (float) ps->miss_cnt/ (float) (ps->good_cnt + ps->miss_cnt)));
    }
    printf("%zu patterns, %zu nodes in count trie, triec_max = %zu\n", ct->t->pattern_count, ct->t->occupied, ct->t->node_max);
    if (!collect_count_trie(ct, pt, params, ps)){
        destroy_count_trie(ct);
        return false;
    }
    destroy_count_trie(ct);
    return true;
}

bool process_all_words(struct params *params, struct translate_table *tt, struct pattern_trie *pt, struct pass_stats *ps, struct count_trie *ct){
    rewind(params->dictionary_file);
    uint8_t dot_min = params->pat_dot;
    uint8_t dot_max = params->pat_len - params->pat_dot;
    if (dot_min < params->left_hyphen_min + 1){
        dot_min = params->left_hyphen_min + 1;
    }
    if (dot_max < params->right_hyphen_min + 1){
        dot_max = params->right_hyphen_min + 1;
    }
    size_t dot_len = dot_min + dot_max;
    struct string_buffer *buf = init_buffer(64);
    if (buf == NULL){
        return false;
    }
    struct word *word = init_word(16);
    if (word == NULL){
        destroy_buffer(buf);
        return false;
    }

    if (!read_line(params->dictionary_file, buf)){
        destroy_buffer(buf);
        destroy_word(word);
        return false;
    }
    while (!buf->eof){
        if (!parse_word(buf, tt, params, word) || !hyphenate_word(word, pt, params)){
            destroy_buffer(buf);
            destroy_word(word);
            return false;
        }
        count_dots(word, params, ps);
        if (word->length >= dot_len){
            if (!process_word(word, ct, params)){
                destroy_buffer(buf);
                destroy_word(word);
                return false;
            }
        }
        if (!read_line(params->dictionary_file, buf)){
            destroy_buffer(buf);
            destroy_word(word);
            return false;
        }
    }
    destroy_buffer(buf);
    destroy_word(word);
    return true;
}

bool hyphenate_dictionary(struct params *params, struct translate_table *tt, struct pattern_trie *pt, struct pass_stats *ps){
    ps->good_cnt = 0;
    ps->bad_cnt = 0;
    ps->miss_cnt = 0;
    params->word_weight = 1;
     char *filename = malloc(11 * sizeof(char));
    if (filename == NULL){
        return false;
    }
    sprintf(filename, "pattmp.%u", params->hyph_level);
    FILE *pattmp = fopen(filename, "w");
    if (pattmp == NULL){
        free(filename);
        return false;
    }
    printf("writing %s\n", filename);
    free(filename);
    if (!hyphenate_all_words(params, tt, pt, ps, pattmp)){
        fclose(pattmp);
        return false;
    }
    fclose(pattmp);
    return true;
}

@ Break

@c
bool hyphenate_all_words(struct params *params, struct translate_table *tt, struct pattern_trie *pt, struct pass_stats *ps, FILE *pattmp){
    rewind(params->dictionary_file);
    struct string_buffer *buf = init_buffer(64);
    if (buf == NULL){
        return false;
    }
    struct word *word = init_word(16);
    if (word == NULL){
        destroy_buffer(buf);
        return false;
    }

    if (!read_line(params->dictionary_file, buf)){
        destroy_buffer(buf);
        destroy_word(word);
        return false;
    }
    while (!buf->eof){
        if (!parse_word(buf, tt, params, word) || !hyphenate_word(word, pt, params)){
            destroy_buffer(buf);
            destroy_word(word);
            return false;
        }
        count_dots(word, params, ps);
        if (word->length > 2){
            output_hyphenated_word(pattmp, word, params);
        }
        if (!read_line(params->dictionary_file, buf)){
            destroy_buffer(buf);
            destroy_word(word);
            return false;
        }
    }
    destroy_buffer(buf);
    destroy_word(word);
    return true;
}

struct pattern *init_pattern(size_t capacity){
    struct pattern *pat = malloc(sizeof(struct pattern));
    if(pat == NULL){
        return NULL;
    }
    pat->text = calloc(capacity, sizeof(char));
    if(pat->text == NULL){
        free(pat);
        return NULL;
    }
    pat->hyphens = calloc(capacity, sizeof(uint8_t));
    if(pat->hyphens == NULL){
        free(pat->text);
        free(pat);
        return NULL;
    }

    pat->length = 0;
    pat->size = 0;
    pat->capacity = capacity;
    return pat;
}

struct pattern *resize_pattern(struct pattern *pat, size_t new_capacity){
    char* new_text = realloc(pat->text, new_capacity*sizeof(char));
    uint8_t* new_hyphens= realloc(pat->hyphens, new_capacity*sizeof(uint8_t));

    if (new_text == NULL || new_hyphens == NULL){
        fprintf(stderr,"Allocation error\n");
        return NULL;
    }

    pat->text= new_text;
    pat->hyphens= new_hyphens;

    memset(pat->text + pat->capacity, '\0', (new_capacity - pat->capacity)*sizeof(char));
    memset(pat->hyphens + pat->capacity, 0, (new_capacity - pat->capacity)*sizeof(uint8_t));

    pat->capacity= new_capacity;
    return pat;
}

void reset_pattern(struct pattern *pat){
    pat->length = 0;
    pat->size = 0;
    memset(pat->text, '\0', pat->capacity * sizeof(char));
    memset(pat->hyphens, 0, pat->capacity * sizeof(uint8_t));
}

void destroy_pattern(struct pattern *pat){
    free(pat->text);
    free(pat->hyphens);
    free(pat);
}

bool append_char_to_pattern(struct pattern *pat, char c){
    if(pat->size >= pat->capacity - 1){
        if(!resize_pattern(pat, 2*pat->capacity)){
            return false;
        }
    }
    pat->text[pat->size]= c;
    pat->size++;
    if (is_utf_start_byte(c)){
        pat->length++;
    }
    return true;
}

bool append_string_to_pattern(struct pattern *pat, char *s, size_t length){
    if(pat->size >= pat->capacity - length){
        if(!resize_pattern(pat, 2*(pat->capacity + length))){
            return false;
        }
    }
    for (size_t i = 0; i < length; i++) {
        if (is_utf_start_byte(s[i])){
            pat->length++;
        }
        pat->text[pat->size] = s[i];
        pat->size++;
    }
    return true;
}

uint8_t get_hyphen(struct pattern *pat, size_t index){
    if (index >= pat->capacity){
        return 0;
    }
    return pat->hyphens[index];
}

bool set_hyphen(struct pattern *pat, size_t index, uint8_t value){
    if (index >= pat->capacity){
        return false;
    }
    pat->hyphens[index] = value;
    return true;
}

bool read_patterns(struct params *params, struct pattern_trie *pt, struct translate_table *tt, struct pass_stats *ps){
    ps->level_pattern_cnt = 0;
    ps->max_level = 0;
    struct string_buffer *buf = init_buffer(16);
    if (buf == NULL){
        return false;
    }
    struct pattern *pat = init_pattern(16);
    if (pat == NULL){
        destroy_buffer(buf);
        return false;
    }
    if (!read_line(params->pattern_file, buf)){
        destroy_pattern(pat);
        destroy_buffer(buf);
        return false;
    }
    while (!buf->eof){
        ps->level_pattern_cnt++;
        if (!parse_pattern(buf, pat, tt) || !insert_new_pattern(pat, pt, ps)){
            destroy_pattern(pat);
            destroy_buffer(buf);
            return false;
        }
        if (!read_line(params->pattern_file, buf)){
            destroy_pattern(pat);
            destroy_buffer(buf);
            return false;
        }
    }
    printf("%zu patterns read in\n", ps->level_pattern_cnt);
    printf("pattern trie has %zu nodes, trie_max = %zu, %zu outputs\n", pt->t->occupied, pt->t->node_max, pt->ops->count);
    destroy_pattern(pat);
    destroy_buffer(buf);
    return true;
}

@ Break

@c
bool parse_pattern(struct string_buffer *buf, struct pattern *out_pattern, struct translate_table *tt){
    reset_pattern(out_pattern);
    char c;
    char *lower;
    bool next_hyphen = false;
    struct string_buffer *letter = init_buffer(4);
    if (letter == NULL){
        return false;
    }
    for (size_t i = 0; i < buf->size; i++) {
        c = buf->data[i];
        if (c == EDGE_OF_WORD && i != 0 && i != buf->size - 1){
            fprintf(stderr, "Edge of word found inside a pattern.\n");
            destroy_buffer(letter);
            return false;
        }
        if (next_hyphen){
            if (!set_hyphen(out_pattern, out_pattern->size, (uint8_t) c)){
                destroy_buffer(letter);
                return false;
            }
            next_hyphen = false;
            continue;
        }
        if (is_utf_start_byte(c) && letter->size > 0){
            if (!append_char(letter, '\0')){
                destroy_buffer(letter);
                return false;
            }
            lower = get_lower(tt, letter->data);
            if (lower == 0){
                fprintf(stderr, "Unknown letter %s found in a pattern.\n", letter->data);
                destroy_buffer(letter);
                return false;
            }
            if (!append_string_to_pattern(out_pattern, lower, strlen(lower))){
                destroy_buffer(letter);
                return false;
            }
            reset_buffer(letter);
        }
        if (c == HYPHEN_FLAG){
            next_hyphen = true;
        } else if (!append_char(letter, c)){
            destroy_buffer(letter);
            return false;
        }
    }
    if (next_hyphen){
        if (!set_hyphen(out_pattern, out_pattern->size, (uint8_t) c)){
            destroy_buffer(letter);
            return false;
        }
    } else if (letter->size > 0){
        if (!append_char(letter, '\0')){
            destroy_buffer(letter);
            return false;
        }
        lower = get_lower(tt, letter->data);
        if (lower == 0){
            fprintf(stderr, "Unknown letter %s found in a pattern.\n", letter->data);
            destroy_buffer(letter);
            return false;
        }
        if (!append_string_to_pattern(out_pattern, lower, strlen(lower))){
            destroy_buffer(letter);
            return false;
        }
    }
    destroy_buffer(letter);
    return true;
}

bool insert_new_pattern(struct pattern *pat, struct pattern_trie *pt, struct pass_stats *ps){
    size_t hyphenation_value, node;
    size_t current_len = 0;
    if (!insert_pattern(pt->t, pat->text, &node)){
        return false;
    }
    for (size_t i = 0; i < pat->size; i++){
        hyphenation_value = get_hyphen(pat, i);
        if (hyphenation_value != 0){
            if (!set_output(pt, node, hyphenation_value, current_len)){
                return false;
            }
            if (hyphenation_value > ps->max_level){
                ps->max_level = hyphenation_value;
            }
        }
        if (is_utf_start_byte(pat->text[i])){
            current_len++;
        }
    }
    hyphenation_value = get_hyphen(pat, pat->size);
    if (hyphenation_value > 0){
        if (!set_output(pt, node, hyphenation_value, current_len)){
            return false;
        }
    }
    return true;
}

bool parse_input(char *argv[], int argc, struct params *params){
    if (argc != 5){
        fprintf(stderr, "UTF-patgen need exactly 4 arguments.\nTry `utfpatgen --help` for more information.\n");
        return false;
    }
    FILE *dictionary_file = fopen(argv[1], "rb");
    if (dictionary_file == NULL){
        fprintf(stderr, "Could not open dictionary file '%s'.\n", argv[1]);
        return false;
    }
    FILE *pattern_file = fopen(argv[2], "rb");
    if (pattern_file == NULL){
        fprintf(stderr, "Could not open pattern file '%s'.\n", argv[2]);
        fclose(dictionary_file);
        return false;
    }
    FILE *output_file = fopen(argv[3], "wb");
    if (output_file == NULL){
        fprintf(stderr, "Could not open output file '%s'.\n", argv[3]);
        fclose(dictionary_file);
        fclose(pattern_file);
        return false;
    }
    FILE *translate_file = fopen(argv[4], "rb");
    if (translate_file == NULL){
        fprintf(stderr, "Could not open translate file '%s'.\n", argv[4]);
        fclose(dictionary_file);
        fclose(pattern_file);
        fclose(output_file);
        return false;
    }
    params->dictionary_file = dictionary_file;
    params->pattern_file = pattern_file;
    params->output_file = output_file;
    params->translate_file = translate_file;
    return true;
}

@ Break

@c
void print_help(){
    printf("Usage: utfpatgen [OPTION]... DICTIONARY PATTERNS OUTPUT TRANSLATE\n");
    printf("\tGenerate the OUTPUT hyphenation file for use with TeX\n");
    printf("\tfrom the DICTIONARY, PATTERNS, and TRANSLATE files.\n");
    printf("\n--help        print this help and exit\n");
    printf("--version     output version information and exit\n");
}

void print_version(){
    printf("This is UTF-patgen version %s\n", UTFPATGEN_VERSION);
}

@* Index.
Automatically generates the list of used identifiers

\end{document}