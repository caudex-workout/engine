#include "caudex.h"

static caudex_status use_c_api(caudex_runtime **runtime) {
    uint32_t version = caudex_abi_version();
    if (version != CAUDEX_ABI_VERSION) {
        return CAUDEX_STATUS_UNSUPPORTED_VERSION;
    }
    return caudex_runtime_create(runtime);
}
