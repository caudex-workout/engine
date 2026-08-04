#ifndef CAUDEX_H
#define CAUDEX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CAUDEX_ABI_VERSION 2u

typedef struct caudex_runtime caudex_runtime;

typedef enum caudex_status {
    CAUDEX_STATUS_OK = 0,
    CAUDEX_STATUS_INVALID_ARGUMENT = 1,
    CAUDEX_STATUS_OUT_OF_MEMORY = 2,
    CAUDEX_STATUS_INVALID_REQUEST = 3,
    CAUDEX_STATUS_UNSUPPORTED_VERSION = 4,
    CAUDEX_STATUS_UNSUPPORTED_METHODOLOGY = 5,
    CAUDEX_STATUS_OUTPUT_LIMIT_REACHED = 6,
    CAUDEX_STATUS_INSUFFICIENT_OUTPUT = 7,
    CAUDEX_STATUS_INTERNAL_ERROR = 255
} caudex_status;

uint32_t caudex_abi_version(void);

caudex_status caudex_runtime_create(caudex_runtime **out_runtime);

void caudex_runtime_destroy(caudex_runtime *runtime);

caudex_status caudex_runtime_execute(
    caudex_runtime *runtime,
    const uint8_t *request_data,
    size_t request_len,
    uint8_t *output_data,
    size_t output_capacity,
    size_t *out_required);

#ifdef __cplusplus
}
#endif

#endif
