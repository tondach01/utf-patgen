#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_LEVELS 256

struct trie
{
    size_t capacity;
    size_t occupied;
    size_t node_size;
    size_t node_max;
    size_t base_max;
    void *nodes;  // _c
    size_t *links;  // _l
    size_t *aux;  // _r
    char *taken;
};

struct trie *init_trie(size_t capacity, size_t node_size);
void reset_trie(struct trie *buf);
void destroy_trie(struct trie *buf);

bool is_base_used(struct trie *t, size_t base);
void set_base_used(struct trie *t, size_t base);

struct output
{
    uint8_t value;
    size_t position;
    struct output *next;
};

struct output *new_output(uint8_t value, size_t position);
void destroy_output(struct output *op);

struct outputs
{
    size_t capacity;
    size_t max;
    size_t count;
    struct output **data;
};

struct outputs *init_outputs(size_t capacity);
void add_output(struct outputs *ops, uint8_t value, size_t position);
void remove_output(struct outputs *ops, size_t index);
void destroy_outputs(struct outputs *ops);

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
void reset_buffer(struct string_buffer *buf);
void destroy_buffer(struct string_buffer *buf);


bool parse_input(int argc, char *argv[], struct params *params);
bool read_translate(FILE *translate, struct params *params);  // TODO will need trie
bool parse_header(struct string_buffer *buf, struct params *params);
bool parse_letters(struct string_buffer *buf);  // TODO will need trie

bool read_dictionary(FILE *dictionary);  // TODO will need trie
bool parse_word(struct string_buffer *buf);  // TODO will need trie

bool read_line(FILE *stream, struct string_buffer *buf);

void generate_patterns();
void clean(); // if necessary