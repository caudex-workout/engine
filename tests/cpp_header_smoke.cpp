#include "caudex.h"

static_assert(CAUDEX_ABI_VERSION == 2u, "unexpected ABI version");

static caudex_status use_cpp_api(caudex_runtime **runtime) {
    return caudex_runtime_create(runtime);
}
