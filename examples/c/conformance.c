#include "caudex.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char fingerprint_prefix[] = "\"resultFingerprint\":\"";
static const char methodology_marker[] =
    "\"id\":\"caudex.double-progression\"";

static int load_file(
    const char *path,
    uint8_t **out_data,
    size_t *out_len
) {
    FILE *file = fopen(path, "rb");
    long length;
    uint8_t *data;

    if (file == NULL) {
        return 0;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return 0;
    }
    length = ftell(file);
    if (length < 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return 0;
    }
    data = (uint8_t *)malloc((size_t)length);
    if (data == NULL && length != 0) {
        fclose(file);
        return 0;
    }
    if (fread(data, 1, (size_t)length, file) != (size_t)length) {
        free(data);
        fclose(file);
        return 0;
    }
    fclose(file);
    *out_data = data;
    *out_len = (size_t)length;
    return 1;
}

static const uint8_t *find_bytes(
    const uint8_t *haystack,
    size_t haystack_len,
    const char *needle
) {
    const size_t needle_len = strlen(needle);
    size_t index;

    if (needle_len > haystack_len) {
        return NULL;
    }
    for (index = 0; index <= haystack_len - needle_len; ++index) {
        if (memcmp(haystack + index, needle, needle_len) == 0) {
            return haystack + index;
        }
    }
    return NULL;
}

static int extract_fingerprint(
    const caudex_buffer *result,
    char out_fingerprint[65]
) {
    const uint8_t *start = find_bytes(
        result->data,
        result->len,
        fingerprint_prefix
    );
    const size_t prefix_len = sizeof(fingerprint_prefix) - 1;

    if (start == NULL) {
        return 0;
    }
    start += prefix_len;
    if ((size_t)(result->data + result->len - start) < 65 ||
        start[64] != '"') {
        return 0;
    }
    memcpy(out_fingerprint, start, 64);
    out_fingerprint[64] = '\0';
    return 1;
}

int main(int argc, char **argv) {
    uint8_t *request = NULL;
    size_t request_len = 0;
    caudex_runtime *runtime = NULL;
    caudex_buffer first = {0};
    caudex_buffer second = {0};
    char first_fingerprint[65];
    char second_fingerprint[65];
    caudex_status status;
    int exit_code = 1;

    if (argc != 2) {
        fprintf(stderr, "usage: %s REQUEST.json\n", argv[0]);
        return 2;
    }
    if (caudex_abi_version() != CAUDEX_ABI_VERSION) {
        fprintf(stderr, "unexpected Caudex ABI version\n");
        return 1;
    }
    if (!load_file(argv[1], &request, &request_len)) {
        fprintf(stderr, "could not read request fixture\n");
        return 1;
    }
    status = caudex_runtime_create(&runtime);
    if (status != CAUDEX_STATUS_OK) {
        fprintf(stderr, "runtime creation failed: %d\n", (int)status);
        goto cleanup;
    }
    status = caudex_runtime_execute(
        runtime,
        request,
        request_len,
        &first
    );
    if (status != CAUDEX_STATUS_OK) {
        fprintf(stderr, "first execution failed: %d\n", (int)status);
        goto cleanup;
    }
    status = caudex_runtime_execute(
        runtime,
        request,
        request_len,
        &second
    );
    if (status != CAUDEX_STATUS_OK) {
        fprintf(stderr, "second execution failed: %d\n", (int)status);
        goto cleanup;
    }
    if (find_bytes(first.data, first.len, methodology_marker) == NULL ||
        find_bytes(second.data, second.len, methodology_marker) == NULL) {
        fprintf(stderr, "resolved methodology missing from result\n");
        goto cleanup;
    }
    if (!extract_fingerprint(&first, first_fingerprint) ||
        !extract_fingerprint(&second, second_fingerprint)) {
        fprintf(stderr, "result fingerprint missing or malformed\n");
        goto cleanup;
    }
    if (strcmp(first_fingerprint, second_fingerprint) != 0) {
        fprintf(stderr, "repeated request produced a different fingerprint\n");
        goto cleanup;
    }

    printf("caudex C conformance fingerprint: %s\n", first_fingerprint);
    exit_code = 0;

cleanup:
    caudex_buffer_free(runtime, &second);
    caudex_buffer_free(runtime, &first);
    caudex_runtime_destroy(runtime);
    free(request);
    return exit_code;
}
