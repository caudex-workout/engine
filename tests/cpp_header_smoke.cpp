#include "caudex.h"

static_assert(sizeof(caudex_buffer) >= sizeof(void *) + 2 * sizeof(size_t),
              "ABI buffer layout is incomplete");

static caudex_status use_cpp_api(caudex_runtime **runtime) {
    caudex_buffer buffer{};
    const auto status = caudex_runtime_create(runtime);
    if (status == CAUDEX_STATUS_OK) {
        caudex_buffer_free(*runtime, &buffer);
    }
    return status;
}
