#include <stdio.h>
#include "../utfpatgen.h"

void test_read_line() {
    FILE *file = fopen("test/read_line_test.txt", "r");
    if (file == NULL) {
        fputs("Could not open read_line_test.txt\n", stderr);
        return;
    }

    struct string_buffer buf;
    buf.capacity = 128;
    buf.size = 0;
    buf.data = (char *)malloc(buf.capacity);
    buf.eof = false;
    if (buf.data == NULL) {
        fputs("Allocation error\n", stderr);
        fclose(file);
        return;
    }

    while (read_line(file, &buf)) {
        if (buf.eof) {
            break; // End of file
        }
        printf("Read line: '%s'\n", buf.data);
        buf.size = 0; // Reset for next line
    }

    free(buf.data);
    fclose(file);
}

int main(void) {
    test_read_line();
    return 0;
}