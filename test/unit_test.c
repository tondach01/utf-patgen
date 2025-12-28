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
    for (size_t i = 0; i < ops->max; i++) {
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

void test_outputs() {
    struct outputs *ops = init_outputs(2);
    if (ops == NULL) {
        return;
    }

    add_output(ops, 5, 10, NULL);
    add_output(ops, 15, 20, NULL);
    add_output(ops, 25, 30, NULL);  // This should trigger a resize

    printf("After additions:\n");
    print_outputs(ops);
    remove_output(ops, 1);  // Remove the second output

    printf("After removal:\n");
    print_outputs(ops);
    
    destroy_outputs(ops);
}

int main(void) {
    printf("---- Read Line Test ----\n");
    test_read_line();
    printf("\n---- Parse Header Test ----\n");
    test_parse_header();
    printf("\n---- Outputs Test ----\n");
    test_outputs();
    return 0;
}