#include <stdio.h>
#include <string.h>
#include "../utfpatgen.h"

void test_read_line() {
    printf("---- Read Line Test ----\n");
    FILE *file = fopen("test/read_line_test.txt", "r");
    if (file == NULL) {
        fputs("Could not open read_line_test.txt\n", stderr);
        return;
    }

    struct string_buffer *buf = init_buffer(128);
    
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

    for (size_t i = 0; i < 4; i++){
        struct string_buffer buf_mock = *mock_buffer(test_headers[i]);
        reset_params(params);
        bool parsed = parse_header(&buf_mock, params);
        printf("Header '%s'", test_headers[i]);
        if (parsed) {
            printf(": lefthyphenmin %d, righthyphenmin %d, bad '%c', missed '%c', good '%c'\n", params->left_hyphen_min, params->right_hyphen_min, params->bad_hyphen, params->missed_hyphen, params->good_hyphen);
        } else {
            printf(" was not parsed\n");
        }
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
    struct trie *t = init_trie(4);
    if (t == NULL) {
        return;
    }

    if (!put_first_level(t)){
        destroy_trie(t);
        return;
    }

    const char *patterns[] = {"test", "tea", "text"};
    size_t op_index;
    struct outputs *ops = init_outputs(2);
    if (ops == NULL) {
        destroy_trie(t);
        return;
    }
    for (size_t i = 0; i < 2; i++){
        if (insert_pattern(t, patterns[i], &op_index) && set_output(t, op_index, ops, (uint8_t)(i), i + 1)) {
            printf("Pattern '%s' inserted successfully.\n", patterns[i]);
        } else {
            printf("Failed to insert pattern '%s'.\n", patterns[i]);
        }
    }
    struct output retrieved_op;
    for (size_t i = 0; i < 3; i++){
        retrieved_op = get_pattern_output(t, ops, patterns[i]);
        if (retrieved_op.value != EMPTY_OP_VALUE) {
            printf("Retrieved output for pattern '%s': value=%zu, position=%zu\n", patterns[i], retrieved_op.value, retrieved_op.position);
        } else {
            printf("No output found for pattern '%s'.\n", patterns[i]);
        }
    }
    
    destroy_outputs(ops);
    destroy_trie(t);
}

void test_read_letters() {
    printf("\n---- Read Letters Test ----\n");
    struct string_buffer *buf = mock_buffer(" a A Á ˇA  ");
    struct trie *mapping = init_trie(128);
    if (mapping == NULL) {
        return;
    }
    if (!put_first_level(mapping)) {
        destroy_trie(mapping);
        return;
    }
    struct string_buffer *alphabet = init_buffer(64);
    if (alphabet == NULL) {
        destroy_trie(mapping);
        return;
    }
    if (!append_char(alphabet, '\0')) {
        destroy_trie(mapping);
        destroy_buffer(alphabet);
        return;
    }

    if (!default_ascii_mapping(mapping, alphabet)) {
        destroy_trie(mapping);
        destroy_buffer(alphabet);
        return;
    }
    printf("Default mapping loaded successfully.\n");

    size_t index = 0;
    char *letters[] = {"F", "ˇA", "ř"};
    for (size_t i = 0; i < 3; i++) {
        if ((index = traverse_trie(mapping, letters[i])) != 0) {
            printf("Letter '%s' found in trie, lower-case letter is '%s'\n", letters[i], alphabet->data + get_aux(mapping, index));
        } else {
            printf("Letter '%s' not found in trie.\n", letters[i]);
        }
    }
    
    if (parse_letters(buf, mapping, alphabet)) {
        printf("Parsed line '%s' successfully.\n", buf->data);
    } else {
        printf("Failed to parse line '%s'.\n", buf->data);
    }

    if ((index = traverse_trie(mapping, letters[1])) != 0) {
        printf("Letter '%s' found in trie, lower-case letter is '%s'\n", letters[1], alphabet->data + get_aux(mapping, index));
    } else {
        printf("Letter '%s' not found in trie.\n", letters[1]);
    }

    destroy_trie(mapping);
    destroy_buffer(alphabet);
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

    struct trie *mapping = init_trie(256);
    if (mapping == NULL) {
        destroy_params(params);
        fclose(file);
        return;
    }
    if (!put_first_level(mapping)) {
        destroy_trie(mapping);
        destroy_params(params);
        fclose(file);
        return;
    }

    struct string_buffer *alphabet = init_buffer(128);
    if (alphabet == NULL) {
        destroy_trie(mapping);
        destroy_params(params);
        fclose(file);
        return;
    }
    if (!append_char(alphabet, '\0')) {
        destroy_buffer(alphabet);
        destroy_trie(mapping);
        destroy_params(params);
        fclose(file);
        return;
    }

    if (read_translate(file, params, mapping, alphabet)) {
        printf("Translate file read successfully.\n");
    } else {
        printf("Failed to read translate file.\n");
    }

    char *letters[] = {"X", "ê", "ř", "ß", "Œ"};
    size_t index = 0;
    for (size_t i = 0; i < 5; i++) {
        if ((index = traverse_trie(mapping, letters[i])) != 0) {
            printf("Letter '%s' found in trie, lower-case letter is '%s'\n", letters[i], alphabet->data + get_aux(mapping, index));
        } else {
            printf("Letter '%s' not found in trie.\n", letters[i]);
        }
    }

    destroy_buffer(alphabet);
    destroy_trie(mapping);
    destroy_params(params);
    fclose(file);
}

int main(void) {
    test_read_line();
    test_parse_header();
    test_trie();
    test_read_letters();
    test_read_translate();
    return 0;
}