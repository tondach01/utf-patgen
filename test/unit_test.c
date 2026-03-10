#include <stdio.h>
#include <string.h>
#include "../utfpatgen.h"

/* Test context structure holding commonly used test fixtures */
struct test_context {
    struct trie *helper_trie;
    struct pattern_trie *pt;
    struct translate_table *tt;
    struct params *params;
    struct string_buffer *buf;
    struct pattern *pat;
    struct word *word;
};

/* Initialize test context with all structures pre-allocated */
struct test_context *setup_test_context() {
    struct test_context *ctx = malloc(sizeof(struct test_context));
    if (ctx == NULL) {
        return NULL;
    }

    /* Initialize all structures */
    ctx->helper_trie = init_trie(256);
    ctx->pt = init_pattern_trie(256, 256);
    ctx->tt = init_tr_table(256, 256);
    ctx->params = init_params();
    ctx->buf = init_buffer(256);
    ctx->pat = init_pattern(256);
    ctx->word = init_word(256);

    /* Check if any allocation failed */
    if (ctx->helper_trie == NULL || ctx->pt == NULL || ctx->tt == NULL ||
        ctx->params == NULL || ctx->buf == NULL || ctx->pat == NULL || ctx->word == NULL) {
        /* Clean up any successful allocations */
        if (ctx->helper_trie != NULL) destroy_trie(ctx->helper_trie);
        if (ctx->pt != NULL) destroy_pattern_trie(ctx->pt);
        if (ctx->tt != NULL) destroy_tr_table(ctx->tt);
        if (ctx->params != NULL) destroy_params(ctx->params);
        if (ctx->buf != NULL) destroy_buffer(ctx->buf);
        if (ctx->pat != NULL) destroy_pattern(ctx->pat);
        if (ctx->word != NULL) destroy_word(ctx->word);
        free(ctx);
        return NULL;
    }

    return ctx;
}

/* Clean up test context and all allocated resources */
void teardown_test_context(struct test_context *ctx) {
    if (ctx == NULL) {
        return;
    }
    if (ctx->helper_trie != NULL) {
        destroy_trie(ctx->helper_trie);
    }
    if (ctx->pt != NULL) {
        destroy_pattern_trie(ctx->pt);
    }
    if (ctx->tt != NULL) {
        destroy_tr_table(ctx->tt);
    }
    if (ctx->params != NULL) {
        destroy_params(ctx->params);
    }
    if (ctx->buf != NULL) {
        destroy_buffer(ctx->buf);
    }
    if (ctx->pat != NULL) {
        destroy_pattern(ctx->pat);
    }
    if (ctx->word != NULL) {
        destroy_word(ctx->word);
    }
    free(ctx);
}

/* Run a test function with automatic setup and teardown */
void run_test(void (*test_func)(struct test_context *)) {
    struct test_context *ctx = setup_test_context();
    if (ctx != NULL) {
        test_func(ctx);
        teardown_test_context(ctx);
    } else {
        printf("ERROR: Failed to setup test context\n");
    }
}

/* Helper function to get pattern output */
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

/* Helper function to create mock buffer */
struct string_buffer *mock_buffer(const char *str) {
    struct string_buffer *buf = init_buffer(strlen(str) + 1);
    if (buf != NULL) {
        strcpy(buf->data, str);
        buf->size = strlen(str);
    }
    return buf;
}

/* Helper function to print buffer contents */
void print_buffer(struct string_buffer *buf) {
    printf("Buffer(size=%zu, capacity=%zu, eof=%d):\n", buf->size, buf->capacity, buf->eof);
    for (size_t i = 0; i < buf->size; i++) {
        printf(" buf[%zu] = '%c' (0x%02x)\n", i, buf->data[i], (uint8_t)buf->data[i]);
    }
}

/* Helper function to print outputs */
void print_outputs(struct outputs *ops) {
    for (size_t i = 1; i < ops->capacity+1; i++) {
        struct output op = ops->data[i];
        if (op.value != EMPTY_OP_VALUE) {
            printf("Output %zu: value=%zu, position=%zu\n", i, op.value, op.position);
        }
    }
    printf("Count: %zu, Capacity: %zu\n", ops->count, ops->capacity);
}

/* ===== TEST FUNCTIONS ===== */

void test_read_line(struct test_context *ctx) {
    printf("---- Read Line Test ----\n");
    FILE *file = fopen("test/read_line_test.txt", "r");
    if (file == NULL) {
        fputs("Could not open read_line_test.txt\n", stderr);
        return;
    }

    while (read_line(file, ctx->buf)) {
        if (ctx->buf->eof) {
            break;
        }
        printf("Read line: '%s'\n", ctx->buf->data);
        reset_buffer(ctx->buf);
    }

    fclose(file);
}

void test_parse_header(struct test_context *ctx){
    printf("\n---- Parse Header Test ----\n");

    const char *full_header = " 510 xyz";
    const char *no_header = " a A  ";
    const char *incomplete_header = " 1   x";
    const char *bad_header = "baadf00d";

    const char *test_headers[4] = {full_header, no_header, incomplete_header, bad_header};

    struct string_buffer *buf_mock;
    for (size_t i = 0; i < 4; i++){
        buf_mock = mock_buffer(test_headers[i]);
        reset_params(ctx->params);
        bool parsed = parse_header(buf_mock, ctx->params);
        printf("Header '%s'", test_headers[i]);
        if (parsed) {
            printf(": lefthyphenmin %d, righthyphenmin %d, bad '%c', missed '%c', good '%c'\n",
                   ctx->params->left_hyphen_min, ctx->params->right_hyphen_min,
                   ctx->params->bad_hyphen, ctx->params->missed_hyphen, ctx->params->good_hyphen);
        } else {
            printf(" was not parsed\n");
        }
        destroy_buffer(buf_mock);
    }
}

void test_trie(struct test_context *ctx) {
    printf("\n---- Trie Test ----\n");

    const char *patterns[] = {"test", "tea", "text"};
    size_t op_index;
    for (size_t i = 0; i < 2; i++){
        if (insert_pattern(ctx->pt->t, patterns[i], &op_index, ctx->helper_trie) &&
            set_output(ctx->pt, op_index, (uint8_t)(i+1), i + 1)) {
            printf("Pattern '%s' inserted successfully.\n", patterns[i]);
        } else {
            printf("Failed to insert pattern '%s'.\n", patterns[i]);
        }
    }

    struct output retrieved_op;
    for (size_t i = 0; i < 3; i++){
        retrieved_op = get_pattern_output(ctx->pt, patterns[i]);
        if (retrieved_op.value != EMPTY_OP_VALUE) {
            printf("Retrieved output for pattern '%s': value=%zu, position=%zu\n",
                   patterns[i], retrieved_op.value, retrieved_op.position);
        } else {
            printf("No output found for pattern '%s'.\n", patterns[i]);
        }
    }
}

void test_read_letters(struct test_context *ctx) {
    printf("\n---- Read Letters Test ----\n");

    strcpy(ctx->buf->data, " a A Á ˇA  ");
    ctx->buf->size = strlen(ctx->buf->data);

    if (!default_ascii_mapping(ctx->tt, ctx->helper_trie)) {
        return;
    }
    printf("Default mapping loaded successfully.\n");

    char *lower;
    char *letters[] = {"F", "ˇA", "ř"};
    for (size_t i = 0; i < 3; i++) {
        if ((lower = get_lower(ctx->tt, letters[i])) != 0) {
            printf("Letter '%s' found in trie, lower-case letter is '%s'\n", letters[i], lower);
        } else {
            printf("Letter '%s' not found in trie.\n", letters[i]);
        }
    }

    if (parse_letters(ctx->buf, ctx->tt, ctx->helper_trie)) {
        printf("Parsed line '%s' successfully.\n", ctx->buf->data);
    } else {
        printf("Failed to parse line '%s'.\n", ctx->buf->data);
    }

    if ((lower = get_lower(ctx->tt, letters[1])) != 0) {
        printf("Letter '%s' found in trie, lower-case letter is '%s'\n", letters[1], lower);
    } else {
        printf("Letter '%s' not found in trie.\n", letters[1]);
    }
}

void test_read_translate(struct test_context *ctx) {
    printf("\n---- Read Translate Test ----\n");
    FILE *file = fopen("test/german.tr", "r");
    if (file == NULL) {
        fputs("Could not open german.tr\n", stderr);
        return;
    }

    ctx->params->translate_file = file;

    if (read_translate(ctx->params, ctx->tt)) {
        printf("Translate table read successfully.\n");
    } else {
        printf("Failed to read translate table.\n");
    }
}

void test_parse_word(struct test_context *ctx) {
    printf("\n---- Parse Word Test ----\n");

    strcpy(ctx->buf->data, "te-st");
    ctx->buf->size = strlen(ctx->buf->data);

    if (!default_ascii_mapping(ctx->tt, ctx->helper_trie)) {
        return;
    }

    if (parse_word(ctx->buf, ctx->tt, ctx->params, ctx->word)) {
        printf("Word parsed: '%s', length=%zu\n", ctx->word->lowercase, ctx->word->length);
        printf("True hyphens at positions: ");
        for (size_t i = 0; i < ctx->word->length; i++) {
            if (get_true_hyphen(ctx->word, i) % 4 > 0) {
                printf("%zu ", i);
            }
        }
        printf("\n");
    } else {
        printf("Failed to parse word '%s'.\n", ctx->buf->data);
    }
}

void test_hyphenate_word(struct test_context *ctx){
    printf("\n---- Hyphenate Word Test ----\n");

    strcpy(ctx->buf->data, "\xfftest\xff");
    ctx->buf->size = strlen(ctx->buf->data);

    ctx->params->hyph_level = 1;

    size_t op_index;
    if (!insert_pattern(ctx->pt->t, "\xffte", &op_index, ctx->helper_trie) ||
        !set_output(ctx->pt, op_index, 1, 2)){
        printf("Failed to insert pattern.\n");
        return;
    }

    for (size_t i = 0; i < ctx->buf->size; i++) {
        if (!append_char_to_word(ctx->word, ctx->buf->data[i])) {
            printf("Failed to build word.\n");
            return;
        }
    }

    if (hyphenate_word(ctx->word, ctx->pt, ctx->params)) {
        printf("Word hyphenated: '%s'\n", ctx->word->lowercase);
        printf("Found hyphens: ");
        for (size_t i = 0; i < ctx->word->length; i++) {
            uint8_t h = get_found_hyphen(ctx->word, i);
            if (h > 0) {
                printf("[%zu]=%d ", i, h);
            }
        }
        printf("\n");
    } else {
        printf("Failed to hyphenate word.\n");
    }
}

void test_patterns(struct test_context *ctx){
    printf("\n---- Patterns Test ----\n");

    strcpy(ctx->buf->data, "\xfe\x02st\xff");
    ctx->buf->size = strlen(ctx->buf->data);

    if (!default_ascii_mapping(ctx->tt, ctx->helper_trie)) {
        return;
    }

    if (!parse_pattern(ctx->buf, ctx->pat, ctx->tt)){
        return;
    }
    printf("Pattern %s parsed.\n", ctx->buf->data);

    struct pass_stats ps;
    if (!insert_new_pattern(ctx->pat, ctx->pt, &ps, ctx->helper_trie)){
        return;
    }
    printf("Pattern inserted successfully.\n");

    struct output retrieved_op = get_pattern_output(ctx->pt, ctx->pat->text);
    if (retrieved_op.value != EMPTY_OP_VALUE) {
        printf("Retrieved output for pattern '%s': value=%zu, position=%zu\n",
               ctx->pat->text, retrieved_op.value, retrieved_op.position);
    } else {
        printf("No output found for pattern '%s'.\n", ctx->pat->text);
    }
}

void test_free_list_integrity(struct test_context *ctx) {
    printf("\n---- Free List Integrity Test ----\n");

    /* Insert many patterns to trigger repacking and free list manipulation */
    const char *test_patterns[] = {
        "a", "ab", "abc", "abcd", "abcde",
        "b", "bc", "bcd", "bcde",
        "c", "cd", "cde",
        "test", "testing", "tester",
        "pattern", "patterns",
        "free", "freedom", "freeze"
    };
    size_t op_index;

    for (size_t i = 0; i < sizeof(test_patterns) / sizeof(test_patterns[0]); i++) {
        if (!insert_pattern(ctx->pt->t, test_patterns[i], &op_index, ctx->helper_trie)) {
            printf("Failed to insert pattern '%s'\n", test_patterns[i]);
            return;
        }
    }

    struct trie *t = ctx->pt->t;

    /* Check for loops in free list */
    printf("Checking free list for loops...");
    size_t visited[1024] = {0};
    size_t current = t->links[0];
    size_t count = 0;
    bool loop_detected = false;

    while (current != 0 && count < t->capacity) {
        if (current >= t->capacity) {
            printf("ERROR: Free list node %zu is out of bounds (capacity=%zu)\n", current, t->capacity);
            loop_detected = true;
            break;
        }
        if (visited[current]) {
            printf("ERROR: Loop detected in free list at node %zu\n", current);
            loop_detected = true;
            break;
        }
        visited[current] = 1;
        current = t->links[current];
        count++;
    }

    if (!loop_detected) {
        printf("No loops detected. Traversed %zu free nodes.\n", count);
    }

    /* Verify all free nodes have value 0 */
    printf("Verifying free nodes have value 0...");
    size_t free_with_value = 0;
    current = t->links[0];
    while (current != 0 && current < t->capacity) {
        if (t->nodes[current] != 0) {
            printf("ERROR: Free node %zu has non-zero value: %d\n", current, t->nodes[current]);
            free_with_value++;
        }
        current = t->links[current];
    }

    if (free_with_value == 0) {
        printf("All free nodes have value 0.\n");
    } else {
        printf("ERROR: %zu free nodes have non-zero values!\n", free_with_value);
    }

    /* Verify occupied count matches actual occupied nodes */
    printf("Verifying occupied count...");
    size_t actual_occupied = 0;
    for (size_t i = 0; i < t->capacity; i++) {
        if (t->nodes[i] != 0) {
            actual_occupied++;
        }
    }

    if (actual_occupied == t->occupied) {
        printf("Occupied count matches: %zu\n", t->occupied);
    } else {
        printf("ERROR: Occupied count mismatch! Actual %zu, expected %zu\n", t->occupied, actual_occupied);
    }
}

void test_stress_patterns(struct test_context *ctx) {
    printf("\n---- Stress Test: Many Patterns ----\n");

    /* Insert a large number of patterns to stress test the trie */
    const char *prefixes[] = {"a", "b", "c", "d", "e", "f", "g", "h"};
    const char *middles[] = {"t", "n", "s", "r", "l"};
    const char *suffixes[] = {"ing", "ed", "er", "ly", "tion"};

    size_t op_index;
    size_t success_count = 0;
    size_t total_patterns = 0;

    /* Generate combinations */
    for (size_t i = 0; i < sizeof(prefixes) / sizeof(prefixes[0]); i++) {
        for (size_t j = 0; j < sizeof(middles) / sizeof(middles[0]); j++) {
            for (size_t k = 0; k < sizeof(suffixes) / sizeof(suffixes[0]); k++) {
                char pattern[64];
                snprintf(pattern, sizeof(pattern), "%s%s%s", prefixes[i], middles[j], suffixes[k]);
                total_patterns++;
                if (insert_pattern(ctx->pt->t, pattern, &op_index, ctx->helper_trie)) {
                    success_count++;
                }
            }
        }
    }

    printf("Inserted %zu/%zu patterns successfully\n", success_count, total_patterns);

    /* Verify free list integrity after stress test */
    struct trie *t = ctx->pt->t;
    size_t current = t->links[0];
    size_t count = 0;
    bool loop_detected = false;

    while (current != 0 && count < t->capacity) {
        if (current >= t->capacity) {
            printf("ERROR: Free list corrupted\n");
            loop_detected = true;
            break;
        }
        current = t->links[current];
        count++;
    }

    if (!loop_detected) {
        printf("Free list integrity maintained after stress test\n");
    }
}

void test_duplicate_patterns(struct test_context *ctx) {
    printf("\n---- Test: Duplicate Pattern Insertion ----\n");

    const char *pattern = "test";
    size_t op_index1, op_index2;

    if (!insert_pattern(ctx->pt->t, pattern, &op_index1, ctx->helper_trie)) {
        printf("Failed to insert pattern first time\n");
        return;
    }
    printf("First insertion: op_index=%zu\n", op_index1);

    size_t occupied_after_first = ctx->pt->t->occupied;

    if (!insert_pattern(ctx->pt->t, pattern, &op_index2, ctx->helper_trie)) {
        printf("Failed to insert pattern second time\n");
        return;
    }
    printf("Second insertion: op_index=%zu\n", op_index2);

    size_t occupied_after_second = ctx->pt->t->occupied;

    if (op_index1 == op_index2) {
        printf("Duplicate pattern correctly returned same node\n");
    } else {
        printf("WARNING: Duplicate pattern returned different nodes\n");
    }

    if (occupied_after_first == occupied_after_second) {
        printf("Occupied count correctly unchanged: %zu\n", occupied_after_first);
    } else {
        printf("ERROR: Occupied changed from %zu to %zu\n", occupied_after_first, occupied_after_second);
    }
}

void test_empty_and_single_char_patterns(struct test_context *ctx) {
    printf("\n---- Test: Edge Case Patterns ----\n");

    size_t op_index;

    /* Single character patterns */
    const char *single_chars[] = {"a", "z", "1", "9"};
    for (size_t i = 0; i < sizeof(single_chars) / sizeof(single_chars[0]); i++) {
        if (insert_pattern(ctx->pt->t, single_chars[i], &op_index, ctx->helper_trie)) {
            printf("Single char pattern '%s' inserted successfully\n", single_chars[i]);
        } else {
            printf("Failed to insert single char pattern '%s'\n", single_chars[i]);
        }
    }

    /* Two character patterns */
    const char *two_chars[] = {"ab", "zy", "12"};
    for (size_t i = 0; i < sizeof(two_chars) / sizeof(two_chars[0]); i++) {
        if (insert_pattern(ctx->pt->t, two_chars[i], &op_index, ctx->helper_trie)) {
            printf("Two char pattern '%s' inserted successfully\n", two_chars[i]);
        } else {
            printf("Failed to insert two char pattern '%s'\n", two_chars[i]);
        }
    }

    /* Verify occupied count */
    size_t actual_occupied = 0;
    for (size_t i = 0; i < ctx->pt->t->capacity; i++) {
        if (ctx->pt->t->nodes[i] != 0) {
            actual_occupied++;
        }
    }

    if (actual_occupied == ctx->pt->t->occupied) {
        printf("Occupied count correct: %zu\n", ctx->pt->t->occupied);
    } else {
        printf("ERROR: Occupied mismatch! Expected %zu, got %zu\n", ctx->pt->t->occupied, actual_occupied);
    }
}

void test_long_patterns(struct test_context *ctx) {
    printf("\n---- Test: Long Patterns ----\n");

    /* Test with increasingly long patterns */
    char pattern[128];
    size_t op_index;

    for (size_t len = 5; len <= 50; len += 5) {
        memset(pattern, 'a', len);
        pattern[len] = '\0';

        if (insert_pattern(ctx->pt->t, pattern, &op_index, ctx->helper_trie)) {
            printf("Pattern of length %zu inserted successfully\n", len);
        } else {
            printf("Failed to insert pattern of length %zu\n", len);
            return;
        }
    }

    /* Check free list */
    struct trie *t = ctx->pt->t;
    size_t current = t->links[0];
    size_t count = 0;

    while (current != 0 && count < t->capacity) {
        if (current >= t->capacity) {
            printf("ERROR: Free list corrupted after long patterns\n");
            return;
        }
        current = t->links[current];
        count++;
    }

    printf("Free list intact after long patterns, %zu free nodes\n", count);
}

void test_deallocate_and_reallocate(struct test_context *ctx) {
    printf("\n---- Test: Deallocate and Reallocate ----\n");

    /* Insert some patterns */
    const char *patterns[] = {"temp1", "temp2", "temp3"};
    size_t op_indices[3];

    for (size_t i = 0; i < 3; i++) {
        if (!insert_pattern(ctx->pt->t, patterns[i], &op_indices[i], ctx->helper_trie)) {
            printf("Failed to insert pattern '%s'\n", patterns[i]);
            return;
        }
    }

    size_t occupied_before = ctx->pt->t->occupied;
    printf("Occupied before deallocate: %zu\n", occupied_before);

    /* Deallocate middle pattern's node */
    if (deallocate_node(ctx->pt->t, op_indices[1])) {
        printf("Deallocated node at index %zu\n", op_indices[1]);
    }

    size_t occupied_after_dealloc = ctx->pt->t->occupied;
    printf("Occupied after deallocate: %zu\n", occupied_after_dealloc);

    if (occupied_after_dealloc == occupied_before - 1) {
        printf("Occupied count correctly decremented\n");
    } else {
        printf("ERROR: Occupied count incorrect after deallocate\n");
    }

    /* Insert a new pattern - should reuse freed space */
    size_t new_op_index;
    if (insert_pattern(ctx->pt->t, "newpattern", &new_op_index, ctx->helper_trie)) {
        printf("New pattern inserted after deallocation\n");
    }

    /* Verify free list integrity */
    struct trie *t = ctx->pt->t;
    size_t current = t->links[0];
    size_t count = 0;
    bool loop_detected = false;

    while (current != 0 && count < t->capacity) {
        if (current >= t->capacity) {
            loop_detected = true;
            break;
        }
        current = t->links[current];
        count++;
    }

    if (!loop_detected) {
        printf("Free list integrity maintained after deallocate/reallocate\n");
    } else {
        printf("ERROR: Free list corrupted\n");
    }
}

void test_free_list_head_validity(struct test_context *ctx) {
    printf("\n---- Test: Free List Head Validity ----\n");

    struct trie *t = ctx->pt->t;

    /* Check if head points to itself (invalid state unless trie is full) */
    if (t->links[0] == 0) {
        if (t->occupied == t->capacity) {
            printf("Head points to itself: trie is full (valid)\n");
        } else {
            printf("ERROR: Head points to itself but trie not full (occupied=%zu, capacity=%zu)\n",
                   t->occupied, t->capacity);
        }
    } else {
        printf("Head points to node %zu (valid)\n", t->links[0]);
    }

    /* Verify first free node's aux points back to 0 */
    size_t first_free = t->links[0];
    if (first_free != 0) {
        size_t first_free_prev = get_aux(t, first_free);
        if (first_free_prev == 0) {
            printf("First free node's aux correctly points to head\n");
        } else {
            printf("ERROR: First free node's aux points to %zu instead of 0\n", first_free_prev);
        }
    }

    /* Mark which nodes are in free list */
    bool in_free_list[1024] = {false};
    size_t free_count = 0;
    size_t current = t->links[0];
    while (current != 0 && free_count < t->capacity) {
        in_free_list[current] = true;
        free_count++;
        current = t->links[current];
    }

    /* Check all nodes from 2 onwards */
    size_t lost_nodes = 0;
    printf("Checking for lost nodes (neither occupied nor in free list):\n");
    for (size_t i = 2; i < t->capacity; i++) {
        bool is_occupied = (t->nodes[i] != 0);
        bool is_free = in_free_list[i];

        if (!is_occupied && !is_free) {
            printf("  Node %zu is LOST (value=%d, in_free_list=%d)\n", i, t->nodes[i], is_free);
            lost_nodes++;
        } else if (is_occupied && is_free) {
            printf("  Node %zu is BOTH occupied and free! (value=%d)\n", i, t->nodes[i]);
        }
    }

    if (lost_nodes > 0) {
        printf("Found %zu lost nodes\n", lost_nodes);
    } else {
        printf("No lost nodes found\n");
    }

    size_t expected_free = (t->capacity - 2) - t->occupied;
    if (free_count == expected_free) {
        printf("Free node count matches: %zu free nodes\n", free_count);
    } else {
        printf("ERROR: Free node count mismatch! Expected %zu, got %zu (diff=%zd)\n",
               expected_free, free_count, (ssize_t)expected_free - (ssize_t)free_count);
    }
}

void test_resize_during_insertion(struct test_context *ctx) {
    printf("\n---- Test: Resize During Insertion ----\n");

    struct trie *small_trie = init_trie(8);
    if (small_trie == NULL) {
        printf("Failed to create small trie\n");
        return;
    }

    size_t initial_capacity = small_trie->capacity;
    printf("Initial capacity: %zu\n", initial_capacity);

    const char *patterns[] = {
        "a", "ab", "abc", "abcd", "abcde", "abcdef",
        "b", "bc", "bcd", "bcde"
    };

    size_t op_index;
    for (size_t i = 0; i < sizeof(patterns) / sizeof(patterns[0]); i++) {
        if (!insert_pattern(small_trie, patterns[i], &op_index, ctx->helper_trie)) {
            printf("Failed to insert pattern '%s'\n", patterns[i]);
            destroy_trie(small_trie);
            return;
        }
    }

    printf("Final capacity: %zu (resized: %s)\n", small_trie->capacity,
           small_trie->capacity > initial_capacity ? "yes" : "no");

    size_t current = small_trie->links[0];
    size_t count = 0;
    bool loop_detected = false;

    while (current != 0 && count < small_trie->capacity) {
        if (current >= small_trie->capacity) {
            printf("ERROR: Free list corrupted after resize\n");
            loop_detected = true;
            break;
        }
        current = small_trie->links[current];
        count++;
    }

    if (!loop_detected) {
        printf("Free list integrity maintained after resize\n");
    }

    size_t actual_occupied = 0;
    for (size_t i = 0; i < small_trie->capacity; i++) {
        if (small_trie->nodes[i] != 0) {
            actual_occupied++;
        }
    }

    if (actual_occupied == small_trie->occupied) {
        printf("Occupied count correct: %zu\n", small_trie->occupied);
    } else {
        printf("ERROR: Occupied mismatch! Expected %zu, got %zu\n", small_trie->occupied, actual_occupied);
    }

    destroy_trie(small_trie);
}

void test_sequential_insertion_deletion(struct test_context *ctx) {
    printf("\n---- Test: Sequential Insertion and Deletion ----\n");

    struct trie *test_trie = init_trie(256);
    if (test_trie == NULL) {
        printf("Failed to create test trie\n");
        return;
    }

    if (!put_first_level(test_trie)) {
        printf("Failed to put first level\n");
        destroy_trie(test_trie);
        return;
    }

    const char *patterns[] = {"abc", "def", "ghi", "jkl", "mno", "pqr", "stu", "vwx"};
    size_t trie_indices[8];

    for (size_t i = 0; i < 8; i++) {
        size_t op_index;
        if (!insert_pattern(test_trie, patterns[i], &op_index, ctx->helper_trie)) {
            printf("Failed to insert pattern '%s'\n", patterns[i]);
            destroy_trie(test_trie);
            return;
        }
        trie_indices[i] = traverse_trie(test_trie, patterns[i]);
        printf("Pattern '%s' at trie index %zu, occupied=%zu\n", patterns[i], trie_indices[i], test_trie->occupied);
    }

    size_t occupied_after_insert = test_trie->occupied;
    printf("Occupied after insertions: %zu\n", occupied_after_insert);

    for (size_t i = 0; i < 8; i += 2) {
        printf("Deallocating node %zu (pattern '%s'), occupied before=%zu\n", trie_indices[i], patterns[i], test_trie->occupied);
        if (!deallocate_node(test_trie, trie_indices[i])) {
            printf("Failed to deallocate node %zu\n", trie_indices[i]);
            destroy_trie(test_trie);
            return;
        }
        printf("  occupied after=%zu\n", test_trie->occupied);
    }

    size_t occupied_after_dealloc = test_trie->occupied;
    printf("Occupied after deallocations: %zu\n", occupied_after_dealloc);

    if (occupied_after_dealloc == occupied_after_insert - 4) {
        printf("Occupied count correct after 4 deallocations\n");
    } else {
        printf("ERROR: Expected %zu occupied, got %zu\n", occupied_after_insert - 4, occupied_after_dealloc);
    }

    const char *new_patterns[] = {"xyz", "uvw"};
    for (size_t i = 0; i < 2; i++) {
        printf("Inserting pattern '%s', occupied before=%zu\n", new_patterns[i], test_trie->occupied);
        size_t new_op;
        if (!insert_pattern(test_trie, new_patterns[i], &new_op, ctx->helper_trie)) {
            printf("Failed to insert new pattern '%s'\n", new_patterns[i]);
            destroy_trie(test_trie);
            return;
        }
        printf("  occupied after=%zu\n", test_trie->occupied);
    }

    size_t occupied_after_reinsert = test_trie->occupied;
    printf("Occupied after re-insertions: %zu (expected %zu)\n",
           occupied_after_reinsert, occupied_after_dealloc + 2);

    if (occupied_after_reinsert == occupied_after_dealloc + 2) {
        printf("Occupied count correct after 2 re-insertions\n");
    } else {
        printf("ERROR: Expected %zu occupied, got %zu\n", occupied_after_dealloc + 2, occupied_after_reinsert);
    }

    size_t current = test_trie->links[0];
    size_t count = 0;
    while (current != 0 && count < test_trie->capacity) {
        if (current >= test_trie->capacity) {
            printf("ERROR: Free list corrupted\n");
            destroy_trie(test_trie);
            return;
        }
        current = test_trie->links[current];
        count++;
    }

    printf("Free list intact with %zu free nodes\n", count);
    destroy_trie(test_trie);
}

void test_alternating_patterns(struct test_context *ctx) {
    printf("\n---- Test: Alternating Short and Long Patterns ----\n");

    const char *short_patterns[] = {"a", "b", "c"};
    const char *long_patterns[] = {"testing", "patterns", "alternating"};
    size_t op_index;

    for (size_t i = 0; i < 3; i++) {
        if (!insert_pattern(ctx->pt->t, short_patterns[i], &op_index, ctx->helper_trie)) {
            printf("Failed to insert short pattern '%s'\n", short_patterns[i]);
            return;
        }
        if (!insert_pattern(ctx->pt->t, long_patterns[i], &op_index, ctx->helper_trie)) {
            printf("Failed to insert long pattern '%s'\n", long_patterns[i]);
            return;
        }
    }

    size_t actual_occupied = 0;
    for (size_t i = 0; i < ctx->pt->t->capacity; i++) {
        if (ctx->pt->t->nodes[i] != 0) {
            actual_occupied++;
        }
    }

    if (actual_occupied == ctx->pt->t->occupied) {
        printf("Occupied count correct: %zu\n", ctx->pt->t->occupied);
    } else {
        printf("ERROR: Occupied mismatch! Expected %zu, got %zu\n", ctx->pt->t->occupied, actual_occupied);
    }

    printf("Successfully inserted %zu patterns\n", (size_t) 6);
}

void test_overlapping_patterns(struct test_context *ctx) {
    printf("\n---- Test: Overlapping Patterns ----\n");

    const char *patterns[] = {
        "test", "testing", "tester", "tested",
        "pat", "pattern", "patterns",
        "free", "freedom", "freeze", "freezing"
    };

    size_t op_index;
    for (size_t i = 0; i < sizeof(patterns) / sizeof(patterns[0]); i++) {
        if (!insert_pattern(ctx->pt->t, patterns[i], &op_index, ctx->helper_trie)) {
            printf("Failed to insert pattern '%s'\n", patterns[i]);
            return;
        }
    }

    printf("Inserted %zu overlapping patterns\n", sizeof(patterns) / sizeof(patterns[0]));

    size_t found = 0;
    for (size_t i = 0; i < sizeof(patterns) / sizeof(patterns[0]); i++) {
        size_t index = traverse_trie(ctx->pt->t, patterns[i]);
        if (index != 0) {
            found++;
        } else {
            printf("ERROR: Pattern '%s' not found after insertion\n", patterns[i]);
        }
    }

    printf("Found %zu/%zu patterns\n", found, sizeof(patterns) / sizeof(patterns[0]));

    size_t actual_occupied = 0;
    for (size_t i = 0; i < ctx->pt->t->capacity; i++) {
        if (ctx->pt->t->nodes[i] != 0) {
            actual_occupied++;
        }
    }

    if (actual_occupied == ctx->pt->t->occupied) {
        printf("Occupied count correct: %zu\n", ctx->pt->t->occupied);
    } else {
        printf("ERROR: Occupied mismatch! Expected %zu, got %zu\n", ctx->pt->t->occupied, actual_occupied);
    }
}

void test_repack_operations(struct test_context *ctx) {
    printf("\n---- Test: Repack Operations ----\n");

    const char *initial_patterns[] = {"abc", "def", "ghi"};
    size_t op_index;

    for (size_t i = 0; i < 3; i++) {
        if (!insert_pattern(ctx->pt->t, initial_patterns[i], &op_index, ctx->helper_trie)) {
            printf("Failed to insert initial pattern '%s'\n", initial_patterns[i]);
            return;
        }
    }

    size_t occupied_before_repack = ctx->pt->t->occupied;
    printf("Occupied before repack-triggering insertions: %zu\n", occupied_before_repack);

    const char *conflict_patterns[] = {"ab", "de", "gh", "abcdef", "ghijkl"};
    for (size_t i = 0; i < 5; i++) {
        if (!insert_pattern(ctx->pt->t, conflict_patterns[i], &op_index, ctx->helper_trie)) {
            printf("Failed to insert conflict pattern '%s'\n", conflict_patterns[i]);
            return;
        }
    }

    size_t occupied_after = ctx->pt->t->occupied;
    printf("Occupied after insertions: %zu\n", occupied_after);

    size_t current = ctx->pt->t->links[0];
    size_t free_count = 0;
    bool loop_detected = false;

    while (current != 0 && free_count < ctx->pt->t->capacity) {
        if (current >= ctx->pt->t->capacity) {
            printf("ERROR: Free list corrupted\n");
            loop_detected = true;
            break;
        }
        current = ctx->pt->t->links[current];
        free_count++;
    }

    if (!loop_detected) {
        printf("Free list integrity maintained after repack\n");
    }

    size_t found = 0;
    for (size_t i = 0; i < 3; i++) {
        if (traverse_trie(ctx->pt->t, initial_patterns[i]) != 0) {
            found++;
        }
    }
    for (size_t i = 0; i < 5; i++) {
        if (traverse_trie(ctx->pt->t, conflict_patterns[i]) != 0) {
            found++;
        }
    }

    printf("Found %zu/8 patterns after repack\n", found);

    size_t actual_occupied = 0;
    for (size_t i = 0; i < ctx->pt->t->capacity; i++) {
        if (ctx->pt->t->nodes[i] != 0) {
            actual_occupied++;
        }
    }

    if (actual_occupied == ctx->pt->t->occupied) {
        printf("Occupied count correct: %zu\n", ctx->pt->t->occupied);
    } else {
        printf("ERROR: Occupied mismatch! Expected %zu, got %zu\n", ctx->pt->t->occupied, actual_occupied);
    }
}

int main(void) {
    run_test(test_read_line);
    run_test(test_parse_header);
    run_test(test_trie);
    run_test(test_read_letters);
    run_test(test_read_translate);
    run_test(test_parse_word);
    run_test(test_hyphenate_word);
    run_test(test_patterns);
    run_test(test_free_list_integrity);
    run_test(test_stress_patterns);
    run_test(test_duplicate_patterns);
    run_test(test_empty_and_single_char_patterns);
    run_test(test_long_patterns);
    run_test(test_deallocate_and_reallocate);
    run_test(test_free_list_head_validity);
    run_test(test_resize_during_insertion);
    run_test(test_sequential_insertion_deletion);
    run_test(test_alternating_patterns);
    run_test(test_overlapping_patterns);
    run_test(test_repack_operations);

    return 0;
}

