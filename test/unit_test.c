#include <stdio.h>
#include <string.h>
#include "../utfpatgen.h"

void test_read_line() {
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

void print_outputs(struct outputs *ops) {
    for (size_t i = 1; i < ops->capacity+1; i++) {
        struct output *op = ops->data[i];
        if (op != NULL) {
            printf("Output %zu: value=%d, position=%zu\n", i, op->value, op->position);
        }
    }
    printf("Count: %zu, Max: %zu, Capacity: %zu\n", ops->count, ops->max, ops->capacity);
}

void test_parse_header(){
    
    struct params params;

    const char *full_header = " 510 xyz";
    const char *no_header = " a A  ";
    const char *incomplete_header = " 1   x  ";
    const char *bad_header = "baadf00d";

    const char *test_headers[4] = {full_header, no_header, incomplete_header, bad_header};

    for (size_t i = 0; i < 4; i++){
        struct string_buffer buf_mock = *mock_buffer(test_headers[i]);
        bool parsed = parse_header(&buf_mock, &params);
        printf("Header: '%s'\n", test_headers[i]);
        if (parsed) {
            printf("lefthyphenmin %d, righthyphenmin %d, bad '%c', missed '%c', good '%c'\n", params.left_hyphen_min, params.right_hyphen_min, params.bad_hyphen, params.missed_hyphen, params.good_hyphen);
        } else {
            printf("Header not parsed\n");
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
    struct trie *t = init_trie(4);
    if (t == NULL) {
        return;
    }

    if (!put_first_level(t)){
        destroy_trie(t);
        return;
    }

    // Further trie tests would go here
    const char *pattern = "test";
    struct outputs *ops = init_outputs(2);
    if (ops == NULL) {
        destroy_trie(t);
        return;
    }
    if (insert_pattern(t, pattern, ops, 1, 2)) {
        printf("Pattern  '%s' inserted successfully.\n", pattern);
    } else {
        printf("Failed to insert pattern '%s'.\n", pattern);
    }
    pattern = "top";
    if (insert_pattern(t, pattern, ops, 2, 2)) {
        printf("Pattern  '%s' inserted successfully.\n", pattern);
    } else {
        printf("Failed to insert pattern '%s'.\n", pattern);
    }
    print_trie(t);
    print_outputs(ops);
    struct output *retrieved_op = get_pattern_output(t, ops, pattern);
    if (retrieved_op != NULL) {
        printf("Retrieved output for pattern '%s': value=%d, position=%zu\n", pattern, retrieved_op->value, retrieved_op->position);
    } else {
        printf("No output found for pattern '%s'.\n", pattern);
    }

    // Cleanup
    destroy_outputs(ops);
    destroy_trie(t);
}

int main(void) {
    //printf("---- Read Line Test ----\n");
    //test_read_line();
    //printf("\n---- Parse Header Test ----\n");
    //test_parse_header();
    printf("\n---- Trie Test ----\n");
    test_trie();
    return 0;
}