#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_LEVELS 256

struct trie
{
    size_t capacity;
    size_t occupied;
    size_t node_max;
    size_t base_max;
    size_t pattern_count;
    char *nodes;  // _c
    size_t *links;  // _l
    size_t *aux;  // _r
    char *taken;
};

struct trie *init_trie(size_t capacity);
bool put_first_level(struct trie *t);
struct trie *resize_trie(struct trie *t, size_t new_capacity);
void reset_trie(struct trie *t);
void destroy_trie(struct trie *t);

char get_node(struct trie *t, size_t index);
bool set_node(struct trie *t, size_t index, char value);

size_t get_link(struct trie *t, size_t index);
bool set_link(struct trie *t, size_t index, size_t link);

size_t get_aux(struct trie *t, size_t index);
bool set_aux(struct trie *t, size_t index, size_t aux);

bool copy_node(struct trie *from, size_t from_index, struct trie *to, size_t to_index);

bool get_base_used(struct trie *t, size_t index);
bool set_base_used(struct trie *t, size_t index, bool used);

bool set_links(struct trie *t, size_t from, size_t to);

bool is_node_occupied(struct trie *t, size_t index);

bool find_base_for_first_fit(struct trie *t, struct trie *q, uint8_t threshold, size_t *out_base);
bool link_trie_up_to(struct trie *t, size_t index);
bool first_fit(struct trie *t, struct trie *q, uint8_t threshold, size_t *out_base);
bool unpack(struct trie *from, size_t base, struct trie *to);
size_t traverse_trie(struct trie *t, const char *pattern);

struct output
{
    uint8_t value;
    size_t position;
    struct output *next;
};

struct output *new_output(uint8_t value, size_t position, struct output *next);
void destroy_output(struct output *op);

struct outputs
{
    size_t capacity;
    size_t max;
    size_t count;
    struct output **data;
};

struct outputs *init_outputs(size_t capacity);
struct outputs *resize_outputs(struct outputs *ops, size_t capacity, struct trie *t);
void destroy_outputs(struct outputs *ops);

bool new_trie_output(struct outputs *ops, struct trie *t, uint8_t value, size_t position, struct output *next, size_t *op_index);
size_t hash_trie_output(struct outputs *ops, uint8_t value, size_t position, struct output *next);

bool insert_pattern(struct trie *t, const char *pattern, size_t *out_op_index);
bool insert_substring(struct trie *t, const char *pattern, size_t end, size_t length, size_t *out_op_index);
bool repack(struct trie *t, struct trie *q, size_t *node, size_t *link, char value);
struct output *get_pattern_output(struct trie *t, struct outputs *ops, const char *pattern);
bool set_output(struct trie *t, size_t index, struct outputs *ops, uint8_t value, size_t position);

struct params
{
    uint8_t left_hyphen_min;
    uint8_t right_hyphen_min;
    char bad_hyphen;
    char missed_hyphen;
    char good_hyphen;
    uint8_t n_levels;
    uint8_t hyph_start;
    uint8_t hyph_finish;
    uint8_t pat_start[MAX_LEVELS];
    uint8_t pat_finish[MAX_LEVELS];
    uint8_t good_wt[MAX_LEVELS];
    uint8_t bad_wt[MAX_LEVELS];
    uint8_t thresh[MAX_LEVELS];
};

struct string_buffer {
    size_t capacity;
    size_t size;
    char *data;
    bool eof;
};

struct string_buffer *init_buffer(size_t capacity);
struct string_buffer *resize_buffer(struct string_buffer *buf, size_t new_capacity);
void reset_buffer(struct string_buffer *buf);
void destroy_buffer(struct string_buffer *buf);

bool read_line(FILE *stream, struct string_buffer *buf);
bool append_char(struct string_buffer *buf, char c);
bool append_string(struct string_buffer *buf, const char *str, size_t len);

bool parse_input(int argc, char *argv[], struct params *params);
bool read_translate(FILE *translate, struct params *params);  // TODO will need trie
bool parse_header(struct string_buffer *buf, struct params *params);
bool parse_letters(struct string_buffer *buf, struct trie *mapping, struct string_buffer *alphabet);  // TODO will need trie

bool read_dictionary(FILE *dictionary);  // TODO will need trie
bool parse_word(struct string_buffer *buf);  // TODO will need trie

void generate_patterns();
void clean(); // if necessary