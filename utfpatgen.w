% --- LIMBO SECTION (LaTeX settings) ---
\documentclass[a4paper,11pt]{cweb} % Use cweb class
\usepackage[utf8]{inputenc}        % UTF-8 encoding
\newcommand{\utfpatgen}{\texttt{utf-patgen }}
\newcommand{\patgen}{\texttt{patgen }}
\newcommand{\lefthyphenminpar}{\texttt{lefthyphenmin }}
\newcommand{\righthyphenminpar}{\texttt{righthyphenmin }}
\newcommand{\hyphstartpar}{\texttt{hyph\_start }}
\newcommand{\hyphfinishpar}{\texttt{hyph\_finish }}
\newcommand{\patstartpar}{\texttt{pat\_start }}
\newcommand{\patfinishpar}{\texttt{pat\_finish }}
\newcommand{\goodwtpar}{\texttt{good\_wt }}
\newcommand{\badwtpar}{\texttt{bad\_wt }}
\newcommand{\threshpar}{\texttt{thresh }}

\begin{document}

@* Introduction.
This is \utfpatgen -- reimplementation of the classic \patgen program for pattern generation. With \utfpatgen, we
intend to overcome several limitations of the original, such as the number of hyphenation levels possible, inability to
use some reserved characters in dictionary, and most importantly, we enable native usage of the UTF-8 encoding in
dictionaries that are no longer limited by the fixed number of lowercase characters permitted by \patgen.

We provide \utfpatgen open-source and free of charge under \textbf{TODO} license. Please note that there is no warranty
and despite our greatest effort, the program may contain bugs.

@* Glossary.
Before diving into the implementation part of the program, it is useful to mention several terms occurring frequently
throughout the text. It may come useful especially to those who are not thoroughly familiar with \patgen. The
definitions here are mostly informal and intended to ease reader's understanding of the topic.

\textbf{Hyphenation} is a process of splitting words so that they fit better to the paragraphs when typeset. It follows
the linguistic rules set for the language in which the text is written.

\textbf{Pattern} is a sequence of characters containing hyphenation information tied to some position (\textbf{dot
position}) on the edges of the pattern or in between the characters. Whether this information tells that the position
should or should not be hyphenated, we distinguish between \textbf{hyphenating} and \textbf{inhibiting patterns}.

\textbf{Hyphen} (in context of \patgen and \utfpatgen) is a mark between two characters holding the information whether
that position should be split during hyphenation and whether this split was detected by current patterns. There are
therefore 4 types of hyphens: \textbf{NO\_HYF} (not in the data, not marked), \textbf{MISS\_HYF} (in the data, not
marked), \textbf{BAD\_HYF} (not in the data, marked), and \textbf{GOOD\_HYF} (in the data, marked). Strictly speaking,
there is a hyphen between each pair of neighboring characters in the data, but NO\_HYF marking is omitted implicitly.

\textbf{Supporting occurences} of a pattern in the data are those that are in favor of the hyphenation information it
holds. For hyphenating patterns, these are the cases where the word has a MISS\_HYF on the dot position pointed by the
pattern. For inhibiting patterns, dot position with a BAD\_HYF is a supporting one. \textbf{Contradicting occurences}
are those that would break a correct hyphen, thus NO\_HYF for hyphenating, and GOOD\_HYF for inhibiting patterns. Note
that a occurence of a pattern can be neither supporting nor contradicting.

\textbf{Hyphenation level} marks the strength of a hyphenation. It is represented by a non-negative integer and creates
a hierarchy of patterns. Pattern with higher level always takes precedence over any pattern with lower level. At odd
levels, the patterns are hyphenating, at even levels inhibiting.

\textbf{Trie} is a data structure for storing n-ary trees. It can implemented using an associated array with highly
effective insertion, deletion and lookup. Furthermore, we can condense it via \textit{packing} to save space.

@* Implementation.
In general, we tried to adhere as tightly as possible to the original ideas of \patgen. Therefore, you may find the
names and functions similar to those in the \patgen technical report. We have nevertheless decided to rewrite several
parts of the algorithm in more "modern" way to improve its readability and testability. The main points to mention are:

\begin{itemize}
    \item the algorithm is implemented in CWEB (C being the laguage of the program), not WEB (with Pascal),
    \item instead of statically defining the sizes of structures (tries, buffers, etc.), these are allocated and
        reallocated dynamically, allowing for greater flexibility and possibly space savings,
    \item global variables are localized as much as possible,
    \item \texttt{goto} statements are eliminated.
\end{itemize}

You may also find a few unit tests appended to the code. These are by no means exhaustive, but feel free to run them
and add your own.

We decided to present \utfpatgen in top-down fashion -- starting with the full overview and moving to details in later
sections. Same goes for the structures which have their own dedicated sections.

@ Dependencies.
All external libraries used in \utfpatgen come from the standard C package, so we hope it to be widely portable without
greater trouble. All in all, we use fixed-size types from \texttt{<stdint.h>} and \texttt{<stdbool.h>}, IO support from
\texttt{<stdio.h>}, string manipulation methods from \texttt{<string.h>}, and memory management provided by
\texttt{<stdlib.h>}.

@<Library includes@>=
#include "utfpatgen.h"
#include <string.h>

@ Main body.
The general flow of the program is rather simple: initialize structures, get the parameters, generate patterns, and
optionally hyphenate the dictionary. For sure, it gets more complicated the deeper we dive.

@c
@<Library includes@>@;

# ifndef TEST
int main(int argc, char *argv[]) {
    for (int i = 0; i < argc; i++) {
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

@ Initialization sequence.
First, the input parameters provided to the program call are read, validated and processed. Unless asking for help
(\texttt{--help}) or version printout (\texttt{--version}), \utfpatgen takes exactly 4 inputs, representing 4 files:

\begin{itemize}
    \item \textbf{Dictionary file}: contains set of hyphenated words.
    \item \textbf{Patterns file}: stores patterns generated in previous runs.
    \item \textbf{Output file}: where the patterns will be stored after the run.
    \item \textbf{Translate file}: contains the mapping of characters from the dictionary and dictionary-specific
        parameters.
\end{itemize}

The required formats of these files are the same as for the \patgen program and are discussed in dedicated sections.

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
struct pass_stats ps;
if (!read_patterns(params, pt, tt, &ps)){
    destroy_params(params);
    destroy_tr_table(tt);
    destroy_pattern_trie(pt);
    return EXIT_FAILURE;
}

@ Level range specification.
Besides the command line parameters, the program prompts for the hyperparameters of the algorithm. The \hyphstartpar
and \hyphfinishpar specify the range of hyphenation levels covered during the run. The program can generate patterns up
to level 254.

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

@ Pattern generation loop.
The algorithm runs for each level within the specified range, going from \hyphstartpar up. The program prompts for
level-specific hyperparameters, generates and prunes the patterns.

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
    @<Level hyperparameters input@>;
    @<Level generation@>;
    if (!delete_bad_patterns(pt)){
        destroy_params(params);
        destroy_tr_table(tt);
        destroy_pattern_trie(pt);
        return EXIT_FAILURE;
    }
    printf("total of %zu patterns at hyph_level %u\n", ps.level_pattern_cnt, params->hyph_level);    
}

@ Level hyperparameters input.
The program again prompts for hyperparameter input. Firstly, it asks for \patstartpar and \patfinishpar that define the
lenght range of patterns for respective level. The maximum length of a pattern in \utfpatgen is set to 255.
Subsequently, the user is prompted to insert the three weights \goodwtpar, \badwtpar and \threshpar. These define the
acceptance criteria for candidate patterns -- in order to accept the pattern during the ongoing iteration, its number
of \textit{good} (supporting) and \textit{bad} (contradicting) occurences must make the following inequality to hold:
\begin{equation}
    good * good\_wt - bad * bad\_wt \geq thresh
\end{equation}
The maximum value for the weights and threshold in \utfpatgen is set to 255.

@<Level hyperparameters input@>=
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

@ Level generation.
The single pass of \utfpatgen at given hyphenation level comprises iterating through pattern lengths (\texttt{pat\_len}
parameter, in ascending order) and dot positions (\texttt{pat\_dot}, from the middle toward the edges) and processing
the dictionary. The algorithm collects supporting and contradicting occurences and eventually adds new patterns to the
set. It can happen that an iteration is skipped if it is known in advance that it will not yield any new patterns.

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


@ Final pass.
If the user wishes, the dictionary is traversed one last time and hyphenated according to found patterns. The output is
stored in file 'pattmp.X'.

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

@* Algorithm.
In this section we focus on the implementation details, each subsection devoted to one particular aspect of the
algorithm.

@ IO procedures.
Methods in this subsection stand on the interface between \utfpatgen and the user, together with the \texttt{main}
method. \texttt{parse\_inputs} attempts to open the 4 files provided as inputs into streams and save them for later
use. \texttt{read\_line} is a utility to simplify reading from these streams that stores the information read into
provided buffer. The \texttt{print\_help} and \texttt{print\_version} methods print out the desired information if the
user does not wish to proceed to pattern generation.

@c
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

@ Translate file processing.
Once the translate file has been successfully opened and its stream pointer stored, it is read line by line into
translate table. The purpose of the translate file is to list all the characters that occur in the dictionary, together
with their uppercase variants. Later during the pattern generation, all of these variants are treated as though they
were the same character. Besides, the first line of the file may redefine the language-specific parameters
\lefthyphenminpar, \righthyphenminpar, and the symbols used for marking hyphens in the dictionary. The format of the
translate file follows the same pattern as required by \patgen:
\begin{itemize}
    \item first line (optional): 'LLRR BMG', where 'LL' is the value of \lefthyphenminpar, 'RR' the value of
        \righthyphenminpar, 'B' the symbol for \texttt{BAD\_HYF}, 'M' the symbol for \texttt{MISS\_HYF}, and 'G' the
        symbol for \texttt{GOOD\_HYF}. Should any of these parameters stay blank, the default is used:
        \lefthyphenminpar$=2$, \righthyphenminpar$=3$, \texttt{BAD\_HYF} '.', \texttt{MISS\_HYF} '-',
        \texttt{GOOD\_HYF} '*'.
    \item consequent lines: '$\_X\_Y_1\_...Y_n\_\_$', where '$X$' is a lowercase letter, '$Y_k$' an arbitrary (even 0)
        number of upper-case variants of '$X$', and '$\_$' a delimiter, usually space.
\end{itemize}
Note that this format allows two-digit values of \lefthyphenminpar and \righthyphenminpar at most and one-byte
characters for hyphen symbols. Practically, this is not a problem.

The translate file must be provided as an input to \utfpatgen, but may be left empty. In that case, the default values
for parameters ASCII character mapping are used.

@c
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

@ Pattern file processing.
The user can provide \utfpatgen with initial set of patterns to work with. Similarly to the translate file, the pattern
file must be given as input, but may be left empty. Each line of the file represents one pattern, with following format
required:
\begin{quote}
    $<hyph. level><character><hyph. level>\dots<hyph. level>$
\end{quote}
Zero levels are omitted implicitly. The special character '.' denotes edges of the word (it can be only used as the
first or last character of a pattern). The original \patgen program that supports only levels up to 9 represents them
simply as ASCII numeric literals '0' to '9'. On the other hand, \utfpatgen expects each byte representing a level
preceded with a special \texttt{HYPHEN\_FLAG} byte of hexadecimal value '0xfe', so the range is extended up to 253.
This works thanks to the fact that '0xfe' byte is not used by any UTF-8 character by design.

The \texttt{read\_patterns} method iterates over the file, reads each entry into the buffer and proccesses it with
\texttt{parse\_pattern}. The parsed pattern is then inserted into the pattern trie by \texttt{insert\_new\_pattern}.

@c
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
        if (hyphenation_value > 0){
            ps->level_pattern_cnt++;
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
        ps->level_pattern_cnt++;
        if (!set_output(pt, node, hyphenation_value, current_len)){
            return false;
        }
    }
    return true;
}

@ Dictionary file processing.
The dictionary is the main source of data for pattern generation. The file indeed has to be provided as input, and
though no error is raised when it is empty, such case does not make much sense. Each line in the file represents single
hyphenated word, with hyphens marked using \texttt{GOOD\_HYF}, \texttt{MISS\_HYF}, and \texttt{BAD\_HYF}. Furthermore,
both the whole word and separate hyphens can be weighted by preceding the with \texttt{HYPHEN\_FLAG} and a value.
Similarly to the pattern file, the possible range of weights is increased to 253. If the hyphen weight is omitted, word
weight is used. If the word weight is omitted, \utfpatgen uses the default value 1. The lines of the dictionary file
thus look like this:
\begin{quote}
    $<word weigth><character><hyphen weight><hyphen><character>\dots<character>$
\end{quote}
The \texttt{process\_dictionary} method encompasses both reading through the dictionary file and generating patterns
afterwards. The reading itself is implemented in \texttt{process\_all\_words}: each word is read, translated to
lowercase and parsed (\texttt{parse\_word}), hyphenated, statistics collected (\texttt{count\_dots}), and processed
into the count trie (\texttt{process\_word}).

Since some patterns may be tied to the edges of the word, special byte symbol \texttt{EDGE\_OF\_WORD} was introduced
that marks the edges. Hexadecimal value of the symbol is '0xff' that is not used by the UTF-8 encoding.

@c
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
    bool has_weight = false;
    for (size_t i = 0; i < buf->size; i++){
        c = buf->data[i];
        if (has_weight){
            weight = (uint8_t) c;
            if (i == 1){
                params->word_weight = weight;
            }
            has_weight = false;
            continue;
        } else if (c == HYPHEN_FLAG){
            has_weight = true;
            continue;
        } else if (c == params->good_hyphen){
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

void count_dots(struct word *word, struct params *params, struct pass_stats *ps){
    if (word->length < (uint8_t) (params->right_hyphen_min + 1)){
        return;
    }
    size_t current_index = word->size;
    size_t current_pos = word->length;
    bool odd_level;
    size_t dot_index, hyphenation_value, weight;
    enum hyphen_class hyf;
    for (size_t dot_pos = word->length - params->right_hyphen_min - 1; dot_pos >= (uint8_t) (params->left_hyphen_min + 1); dot_pos--){
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

@ Pattern collection.
After the dictionary has been processed, the count trie contains the number of good (supporting) and bad
(contradicting) occurences of each candidate pattern found. There are 3 types of patterns based on these counts and the
\goodwtpar, \badwtpar, and \threshpar parameters:
\begin{itemize}
    \item \textbf{good patterns} for which inequality 
        \begin{equation}
            good * good\_wt - bad * bad\_wt \geq thresh
        \end{equation}
        holds. Good patterns are inserted into the pattern trie with corresponding hyphenation level.
    \item \textbf{bad patterns}: for which inequality
        \begin{equation}
            good * good\_wt < thresh
        \end{equation}
        holds. Bad patterns are inserted into the pattern trie with a special \texttt{BAD\_OP\_VALUE} level of value
        255. Neither them nor their superstrings can become good patterns and are deleted from the pattern trie in the
        end of the hyphenation level iteration.
    \item \textbf{undecided patterns}: for which none of the inequalities above holds. Some of their superstrings may
        become good or bad patterns later, so need for further investigation is raised by setting the
        \texttt{more\_to\_come} flag. 
\end{itemize}
The \texttt{collect\_count\_trie} method is an entry points for pattern collection. It calls
\texttt{traverse\_count\_trie} that does the actual pattern evaluation, and then prints out the statistics from the
process.

@c
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
        if (c == 0){ // overflow
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

@ Pattern pruning.

@c
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
                continue;
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
            pt->ops->data[h].next_op_index = pt->ops->data[0].next_op_index;
            pt->ops->data[0].next_op_index = h;
        }
    }
    printf("%zu nodes and %zu outputs deleted\n", old_trie_cnt - pt->t->occupied, old_op_cnt - pt->ops->count);
    return true;
}

@ Pattern output.

@c
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
                fputc('\xfe', pattern_file);
                fputc((uint8_t) level, pattern_file);
            }
            pattern_position++;
        }
        if (pattern->data[i] == EDGE_OF_WORD){
            fputc('.', pattern_file);
        } else {
            fputc(pattern->data[i], pattern_file);
        }
        
    }
    level = get_highest_level(ops, op_index, pattern_position);
    if (level > 0){
        fputc('\xfe', pattern_file);
        fputc((uint8_t) level, pattern_file);
    }
    fputc('\n', pattern_file);
}

size_t get_highest_level(struct outputs *ops, size_t start_index, size_t position){
    size_t highest = 0;
    size_t op_index = ops->lookup[start_index];
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

@ Hyphenation.

@c
bool hyphenate_word(struct word *word, struct pattern_trie *pt, struct params *params){
    size_t current_index = word->size;
    size_t current_pos = word->length;
    size_t node, base, start_index, dot_index, end_index, op_index, dot_pos, end_pos;
    struct output op;
    if (word->length < (uint8_t) (params->right_hyphen_min + 1)){
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
            op_index = pt->ops->lookup[get_aux(pt->t, node)];
            while (op_index > 0){
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

@ UTF-8 specifics.

@c
bool is_utf_start_byte(uint8_t byte){
    return (byte & 0xc0) != 0x80;
}

uint8_t n_utf_following_bytes(uint8_t c){
    if (c < 128 || c > 253){
        return 0;
    } else if (c < 208){
        return 1;
    } else if (c < 216){
        return 2;
    } else {
        return 3;
    }
}

@* Structures.

@ Trie.

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

bool deallocate_node(struct trie *t, size_t t_index){
    if (!set_links(t, t_index, get_link(t, 0)) || !set_links(t, 0, t_index) || !set_node(t, t_index, 0)){
        return false;
    }
    t->occupied--;
    return true;
}

@ Outputs.

@c
size_t hash_trie_output(struct outputs *ops, size_t value, size_t position, size_t next_op_index){
    size_t hash = ((next_op_index + 313*position + 361*value) % ops->lookup_cap) + 1;
    size_t op_index;
    while (true) {
        op_index = ops->lookup[hash];
        if (op_index == 0) {
            return hash;
        } else if (ops->data[op_index].value == value && ops->data[op_index].position == position && ops->data[op_index].next_op_index == next_op_index) {
            return hash;
        } else if (hash > 1) {
            hash -= 1;
        } else {
            hash = ops->lookup_cap;
        }
    }
    return 0;
}

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
    ops->data[0].next_op_index = 1;
    ops->lookup_cap = 2*capacity;
    ops->lookup_cnt = 0;
    ops->lookup = calloc(2*capacity, sizeof(size_t));
    if (ops->lookup == NULL) {
        fputs("Allocation error\n", stderr);
        free(ops->data);
        free(ops);
        return NULL;
    }
    return ops;
}

struct outputs *resize_outputs(struct outputs *ops, size_t capacity){
    struct output *new_data = realloc(ops->data, (capacity + 1) * sizeof(struct output)); 
    if (new_data == NULL) {
        fputs("Allocation error\n", stderr);
        return NULL;
    }
    ops->data = new_data;
    size_t diff = capacity - ops->capacity;
    memset(ops->data + ops->capacity + 1, 0, diff * sizeof(struct output));
    ops->capacity = capacity;
    return ops;
}

bool resize_lookup(struct outputs *ops, size_t new_cap, struct trie *t) {
    size_t *new_lookup = calloc(new_cap, sizeof(size_t));
    size_t *old_lookup = ops->lookup;
    if (new_lookup == NULL){
        return false;
    }
    ops->lookup = new_lookup;
    ops->lookup_cap = new_cap;
    size_t old_hash, new_hash, op_index;
    struct output op;
    for (size_t node = 0; node <= t->node_max; node++){
        if (!is_node_occupied(t, node) || get_aux(t, node) == 0){
            continue;
        }
        old_hash = get_aux(t, node);
        op_index = old_lookup[old_hash];
        op = ops->data[op_index];
        new_hash = hash_trie_output(ops, op.value, op.position, op.next_op_index);
        ops->lookup[new_hash] = op_index;
        if (!set_aux(t, node, new_hash)){
            return false;
        }
    }
    free(old_lookup);
    return true;
}

void destroy_outputs(struct outputs *ops){
    free(ops->data);
    free(ops->lookup);
    free(ops);
}

@ Pattern trie.

@c
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

bool new_trie_output(struct pattern_trie *pt, size_t value, size_t position, size_t next_op_index, size_t *op_index){
    if (pt->ops->count >= pt->ops->capacity - 1) {
        if (resize_outputs(pt->ops, pt->ops->capacity * 2) == NULL) {
            return false;
        }
    }
    if (pt->ops->lookup_cnt * 4 > pt->ops->lookup_cap * 3) {
        if (!resize_lookup(pt->ops, pt->ops->lookup_cap * 2, pt->t)){
            return false;
        }
    }
    size_t hash = hash_trie_output(pt->ops, value, position, next_op_index);
    if (pt->ops->lookup[hash] == 0) {
        pt->ops->count++;
        struct output new_op = {.value = value, .position = position, .next_op_index = next_op_index};
        size_t free_list_head = pt->ops->data[0].next_op_index;
        if (pt->ops->data[free_list_head].next_op_index == 0){
            pt->ops->data[0].next_op_index = pt->ops->count + 1;
        } else {
            pt->ops->data[0].next_op_index = pt->ops->data[free_list_head].next_op_index;
        }
        pt->ops->data[free_list_head] = new_op;
        pt->ops->lookup[hash] = free_list_head;
        pt->ops->lookup_cnt++;
    } 
    *op_index = hash;
    return true;
}

bool set_output(struct pattern_trie *pt, size_t node, size_t value, size_t position){
    size_t op_index;
    if (!new_trie_output(pt, value, position, pt->ops->lookup[get_aux(pt->t, node)], &op_index) || !set_aux(pt->t, node, op_index)) {
        return false;
    }
    return true;
}

bool link_around_bad_outputs(struct pattern_trie *pt, size_t t_index){
    size_t lookup_index = get_aux(pt->t, t_index);
    if (lookup_index == 0){
        return true;
    }
    size_t op_index = pt->ops->lookup[lookup_index];
    size_t free_list_head = pt->ops->data[0].next_op_index;
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
    if (h == 0){
        if (pt->ops->lookup[lookup_index] > 0){
            pt->ops->lookup[lookup_index] = 0;
            pt->ops->lookup_cnt--;
        }
        if (!set_aux(pt->t, t_index, 0)){
            return false;
        }
    } else {
        pt->ops->lookup[lookup_index] = pt->ops->data[0].next_op_index;
    }
    pt->ops->data[0].next_op_index = free_list_head;
    return true;
}

@ Pattern counts.

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

@ Count trie.

@c
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

@ Translation table.

@c
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

char *get_lower(struct translate_table *tt, const char *letter){
    size_t index = traverse_trie(tt->mapping, letter);
    if (index == 0 || get_aux(tt->mapping, index) >= tt->alphabet->size){
        return NULL;
    }
    return tt->alphabet->data + get_aux(tt->mapping, index);
}

@ Params.

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

@ Pass stats.

@ Stack.

@c
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

@ Word.

@c
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

@ Pattern.

@c
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

@* Index.
Automatically generates the list of used identifiers

\end{document}