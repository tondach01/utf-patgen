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

int main(void) {
    test_read_line();
    test_parse_header();
    return 0;
}