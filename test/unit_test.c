#include <stdio.h>
#include <string.h>
#include "../utfpatgen.h"

struct output get_pattern_output(struct pattern_trie *pt, const char *pattern){
    size_t trie_index = traverse_trie(pt->t, pattern);
    struct output empty = {.value = EMPTY_OP_VALUE};
    if (trie_index == 0) {
        return empty;
    }
    size_t op_index = get_aux(pt->t, trie_index);
    if (op_index == 0) {
        return empty;
    }
    return pt->ops->data[pt->ops->lookup[op_index]];
}

void test_read_line() {
    printf("---- Read Line Test ----\n");
    FILE *file = fopen("test/read_line_test.txt", "r");
    if (file == NULL) {
        fputs("Could not open read_line_test.txt\n", stderr);
        return;
    }

    struct string_buffer *buf = init_buffer(8);
    
    if (buf == NULL) {
        fclose(file);
        return;
    }

    while (read_line(file, buf)) {
        if (buf->eof) {
            break;
        }
        printf("Read line: '%s'\n", buf->data);
        reset_buffer(buf);
    }

    destroy_buffer(buf);
    fclose(file);
}

struct string_buffer *mock_buffer(const char *str) {
    struct string_buffer *buf = init_buffer(strlen(str) + 1);
    if (buf != NULL) {
        strcpy(buf->data, str);
        buf->size = strlen(str);
    }
    return buf;
}

void print_buffer(struct string_buffer *buf) {
    printf("Buffer(size=%zu, capacity=%zu, eof=%d):\n", buf->size, buf->capacity, buf->eof);
    for (size_t i = 0; i < buf->size; i++) {
        printf(" buf[%zu] = '%c' (0x%02x)\n", i, buf->data[i], (uint8_t)buf->data[i]);
    }
}

void print_outputs(struct outputs *ops) {
    for (size_t i = 1; i < ops->capacity+1; i++) {
        struct output op = ops->data[i];
        if (op.value != EMPTY_OP_VALUE) {
            printf("Output %zu: value=%zu, position=%zu\n", i, op.value, op.position);
        }
    }
    printf("Count: %zu, Capacity: %zu\n", ops->count, ops->capacity);
}

void test_parse_header(){
    printf("\n---- Parse Header Test ----\n");
    struct params *params = init_params();
    if (params == NULL) {
        return;
    }

    const char *full_header = " 510 xyz";
    const char *no_header = " a A  ";
    const char *incomplete_header = " 1   x";
    const char *bad_header = "baadf00d";

    const char *test_headers[4] = {full_header, no_header, incomplete_header, bad_header};

    struct string_buffer *buf_mock;
    for (size_t i = 0; i < 4; i++){
        buf_mock = mock_buffer(test_headers[i]);
        reset_params(params);
        bool parsed = parse_header(buf_mock, params);
        printf("Header '%s'", test_headers[i]);
        if (parsed) {
            printf(": lefthyphenmin %d, righthyphenmin %d, bad '%c', missed '%c', good '%c'\n", params->left_hyphen_min, params->right_hyphen_min, params->bad_hyphen, params->missed_hyphen, params->good_hyphen);
        } else {
            printf(" was not parsed\n");
        }
        destroy_buffer(buf_mock);
    }
}

void print_trie(struct trie *t) {
    printf("Trie capacity: %zu, occupied: %zu, node_max: %zu, base_max: %zu\n", t->capacity, t->occupied, t->node_max, t->base_max);
    printf("Index|Node|Link| Aux|Base|\n");
    for (size_t i = 0; i < t->capacity; i++) {
        if ((i > 256 && get_node(t, i) != 0) || get_aux(t, i) == 2) printf("%5ld|%4d|%4zu|%4zu|%4d|\n", i, (uint8_t) t->nodes[i], t->links[i], t->aux[i], get_base_used(t, i));
    }
}

void test_trie() {
    printf("\n---- Trie Test ----\n");
    struct pattern_trie *pt = init_pattern_trie(4, 2);
    if (pt == NULL) {
        return;
    }

    const char *patterns[] = {"test", "tea", "text"};
    size_t op_index;
    for (size_t i = 0; i < 2; i++){
        if (insert_pattern(pt->t, patterns[i], &op_index) && set_output(pt, op_index, (uint8_t)(i+1), i + 1)) {
            printf("Pattern '%s' inserted successfully.\n", patterns[i]);
        } else {
            printf("Failed to insert pattern '%s'.\n", patterns[i]);
        }
    }
    struct output retrieved_op;
    for (size_t i = 0; i < 3; i++){
        retrieved_op = get_pattern_output(pt, patterns[i]);
        if (retrieved_op.value != EMPTY_OP_VALUE) {
            printf("Retrieved output for pattern '%s': value=%zu, position=%zu\n", patterns[i], retrieved_op.value, retrieved_op.position);
        } else {
            printf("No output found for pattern '%s'.\n", patterns[i]);
        }
    }
    
    destroy_pattern_trie(pt);
}

void test_read_letters() {
    printf("\n---- Read Letters Test ----\n");
    struct string_buffer *buf = mock_buffer(" a A Á ˇA  ");
    struct translate_table *tt = init_tr_table(16, 16);
    if (tt == NULL){
        destroy_buffer(buf);
        return;
    }
    if (!default_ascii_mapping(tt)) {
        destroy_tr_table(tt);
        destroy_buffer(buf);
        return;
    }
    printf("Default mapping loaded successfully.\n");

    char *lower;
    char *letters[] = {"F", "ˇA", "ř"};
    for (size_t i = 0; i < 3; i++) {
        if ((lower = get_lower(tt, letters[i])) != 0) {
            printf("Letter '%s' found in trie, lower-case letter is '%s'\n", letters[i], lower);
        } else {
            printf("Letter '%s' not found in trie.\n", letters[i]);
        }
    }
    
    if (parse_letters(buf, tt)) {
        printf("Parsed line '%s' successfully.\n", buf->data);
    } else {
        printf("Failed to parse line '%s'.\n", buf->data);
    }

    if ((lower = get_lower(tt, letters[1])) != 0) {
        printf("Letter '%s' found in trie, lower-case letter is '%s'\n", letters[1], lower);
    } else {
        printf("Letter '%s' not found in trie.\n", letters[1]);
    }

    destroy_tr_table(tt);
    destroy_buffer(buf);
}

void test_read_translate() {
    printf("\n---- Read Translate Test ----\n");
    FILE *file = fopen("test/german.tr", "r");
    if (file == NULL) {
        fputs("Could not open german.tr\n", stderr);
        return;
    }

    struct params *params = init_params();
    if (params == NULL) {
        fclose(file);
        return;
    }
    params->translate_file = file;

    struct translate_table *tt = init_tr_table(16, 16);
    if (tt == NULL){
        destroy_params(params);
        return;
    }
    if (!default_ascii_mapping(tt)) {
        destroy_tr_table(tt);
        destroy_params(params);
        return;
    }
    printf("Default mapping loaded successfully.\n");

    if (read_translate(params, tt)) {
        printf("Translate file read successfully.\n");
    } else {
        printf("Failed to read translate file.\n");
    }

    char *letters[] = {"X", "ê", "ř", "ß", "Œ"};
    char *lower;
    for (size_t i = 0; i < 5; i++) {
        if ((lower = get_lower(tt, letters[i])) != 0) {
            printf("Letter '%s' found in trie, lower-case letter is '%s'\n", letters[i], lower);
        } else {
            printf("Letter '%s' not found in trie.\n", letters[i]);
        }
    }

    destroy_tr_table(tt);
    destroy_params(params);
}

void test_parse_word() {
    printf("\n---- Parse Word Test ----\n");
    struct params *params = init_params();
    if (params == NULL) {
        return;
    }
    struct translate_table *tt = init_tr_table(16, 16);
    if (tt == NULL){
        destroy_params(params);
        return;
    }
    if (!default_ascii_mapping(tt)) {
        destroy_tr_table(tt);
        destroy_params(params);
        return;
    }
    printf("Default mapping loaded successfully.\n");
    struct word *word = init_word(8);
    if (word == NULL){
        destroy_tr_table(tt);
        destroy_params(params);
        return;
    }

    struct string_buffer *buf = mock_buffer("\xfe\x07te\xfe\x02-S.t");

    if (!parse_word(buf, tt, params, word)){
        destroy_tr_table(tt);
        destroy_params(params);
        destroy_buffer(buf);
        destroy_word(word);
        return;
    }

    printf("Word weight = %d\n", params->word_weight);
    for (size_t i = 0; i < word->size; i++){
        printf("| %c (%d) | %zu (%zu) ", get_char(word, i), (uint8_t) get_char(word, i), get_true_hyphen(word, i)/4, get_true_hyphen(word, i)%4);
    }
    printf("|\n");

    destroy_tr_table(tt);
    destroy_params(params);
    destroy_buffer(buf);
    destroy_word(word);
}

void test_hyphenate_word(){
    printf("\n---- Hyphenate Word Test ----\n");
    struct params params = {.hyph_level = 3, .pat_len = 2, .word_weight = 1, .good_hyphen = '*', .bad_hyphen = '.', .missed_hyphen = '-', .right_hyphen_min = 1};
    struct word *word = init_word(11);
    if (word == NULL){
        return;
    }

    if (!append_string_to_word(word, "\xfftesting\xff", 9)){
        destroy_word(word);
        return;
    }

    struct pattern_trie *pt = init_pattern_trie(256, 2);
    if (pt == NULL){
        destroy_word(word);
        return;
    }

    const char *patterns[4] = {"\xffte", "ing\xff", "tex", "ti"};
    size_t positions[4] = {2, 0, 2, 1};
    uint8_t values[4] = {2, 1, 2, 3};
    size_t index;
    for (size_t i = 0; i < 4; i++) {
        if (!insert_pattern(pt->t, patterns[i], &index) || index == 0 || !set_output(pt, index, values[i], positions[i])){
            destroy_pattern_trie(pt);
            destroy_word(word);
            return;
        }
    }
    printf("Patterns inserted successfully.\n");

    if (!hyphenate_word(word, pt, &params)){
        destroy_pattern_trie(pt);
        destroy_word(word);
        return;
    }

    size_t true_hyphens[] = {0,8,4,4,5,4,4,0};
    for (size_t i = 0; i < 8; i++){
        if (!set_true_hyphen(word, i, true_hyphens[i])){
            destroy_pattern_trie(pt);
            destroy_word(word);
            return;
        }
    }

    printf("Hyphenated word: ");
    output_hyphenated_word(stdout, word, &params);
    destroy_pattern_trie(pt);
    destroy_word(word);
}

void test_patterns(){
    printf("\n---- Patterns Test ----\n");
    struct string_buffer *buf = mock_buffer("\x65\x73\xfe\x10\x74\xff");
    if (buf == NULL){
        return;
    }
    struct translate_table * tt = init_tr_table(256, 256);
    if (tt == NULL){
        destroy_buffer(buf);
        return;
    }
    if (!default_ascii_mapping(tt)){
        destroy_tr_table(tt);
        destroy_buffer(buf);
        return;
    }
    printf("Default mapping inserted succesfully.\n");
    struct pattern *pat = init_pattern(16);
    if (pat == NULL){
        destroy_tr_table(tt);
        destroy_buffer(buf);
        return;
    }
    struct pattern_trie *pt = init_pattern_trie(256, 2);
    if (pt == NULL){
        destroy_pattern(pat);
        destroy_tr_table(tt);
        destroy_buffer(buf); 
        return;
    }

    if (!parse_pattern(buf, pat, tt)){
        destroy_pattern_trie(pt);
        destroy_pattern(pat);
        destroy_tr_table(tt);
        destroy_buffer(buf); 
        return;   
    }
    printf("Pattern %s parsed.\n", buf->data);
    struct pass_stats ps = {};
    if (!insert_new_pattern(pat, pt, &ps)){
        destroy_pattern_trie(pt);
        destroy_pattern(pat);
        destroy_tr_table(tt);
        destroy_buffer(buf); 
        return;
    }
    printf("Pattern inserted successfully.\n");
    struct output retrieved_op = get_pattern_output(pt, pat->text);
    if (retrieved_op.value != EMPTY_OP_VALUE) {
        printf("Retrieved output for pattern '%s': value=%zu, position=%zu\n", pat->text, retrieved_op.value, retrieved_op.position);
    } else {
        printf("No output found for pattern '%s'.\n", pat->text);
    }

    destroy_pattern_trie(pt);
    destroy_pattern(pat);
    destroy_tr_table(tt);
    destroy_buffer(buf);
}

int main(void) {
    test_read_line();
    test_parse_header();
    test_trie();
    test_read_letters();
    test_read_translate();
    test_parse_word();
    test_hyphenate_word();
    test_patterns();
    return 0;
}