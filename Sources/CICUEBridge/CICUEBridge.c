#include "include/CICUEBridge.h"

#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* ---------------------------------------------------------------------------
 * Compile-time ABI guards.
 *
 * These assertions pin this shim's local declarations to the audited iCUE SDK
 * protocol 18 layouts on 64-bit Apple platforms. They catch accidental local
 * declaration drift. They cannot inspect a dynamically loaded vendor binary;
 * Swift performs a fail-closed runtime framework-version allowlist before this
 * shim is allowed to dlopen it.
 * ------------------------------------------------------------------------ */

#define SC_STATIC_ASSERT(cond, name) typedef char sc_static_assert_##name[(cond) ? 1 : -1]

SC_STATIC_ASSERT(sizeof(sc_icue_version) == 12, version_size);
SC_STATIC_ASSERT(sizeof(sc_icue_session_details) == 36, session_details_size);
SC_STATIC_ASSERT(sizeof(sc_icue_session_state_changed) == 40, session_state_changed_size);
SC_STATIC_ASSERT(offsetof(sc_icue_device_info, id) == 4, device_info_id_offset);
SC_STATIC_ASSERT(offsetof(sc_icue_device_info, serial) == 132, device_info_serial_offset);
SC_STATIC_ASSERT(offsetof(sc_icue_device_info, model) == 260, device_info_model_offset);
SC_STATIC_ASSERT(offsetof(sc_icue_device_info, led_count) == 388, device_info_led_count_offset);
SC_STATIC_ASSERT(offsetof(sc_icue_device_info, channel_count) == 392, device_info_channel_offset);
SC_STATIC_ASSERT(sizeof(sc_icue_device_info) == 396, device_info_size);
SC_STATIC_ASSERT(sizeof(sc_icue_led_color) == 8, led_color_size);
SC_STATIC_ASSERT(offsetof(sc_icue_led_color, r) == 4, led_color_r_offset);
SC_STATIC_ASSERT(sizeof(sc_icue_led_position) == 24, led_position_size);
SC_STATIC_ASSERT(offsetof(sc_icue_led_position, cx) == 8, led_position_cx_offset);
SC_STATIC_ASSERT(offsetof(sc_icue_key_event, key_id) == 128, key_event_key_id_offset);
SC_STATIC_ASSERT(sizeof(sc_icue_event) == 16, event_size);
SC_STATIC_ASSERT(offsetof(sc_icue_event, data) == 8, event_data_offset);
SC_STATIC_ASSERT(sizeof(sc_icue_property) == 24, property_size);
SC_STATIC_ASSERT(offsetof(sc_icue_property, value) == 8, property_value_offset);
SC_STATIC_ASSERT(offsetof(sc_icue_key_event_configuration, is_intercepted) == 4, key_config_offset);
SC_STATIC_ASSERT(sizeof(sc_icue_key_event_configuration) == 8, key_config_size);

/* ---------------------------------------------------------------------------
 * Dynamically resolved SDK entry points
 * ------------------------------------------------------------------------ */

typedef int32_t (*fn_connect)(sc_icue_session_state_changed_handler, void *);
typedef int32_t (*fn_disconnect)(void);
typedef int32_t (*fn_get_session_details)(sc_icue_session_details *);
typedef int32_t (*fn_get_devices)(const sc_icue_device_filter *, int32_t, sc_icue_device_info *, int32_t *);
typedef int32_t (*fn_get_device_info)(const char *, sc_icue_device_info *);
typedef int32_t (*fn_get_led_positions)(const char *, int32_t, sc_icue_led_position *, int32_t *);
typedef int32_t (*fn_get_led_colors)(const char *, int32_t, sc_icue_led_color *);
typedef int32_t (*fn_set_led_colors)(const char *, int32_t, const sc_icue_led_color *);
typedef int32_t (*fn_set_led_colors_buffer)(const char *, int32_t, const sc_icue_led_color *);
typedef int32_t (*fn_flush_async)(sc_icue_async_callback, void *);
typedef int32_t (*fn_set_layer_priority)(uint32_t);
typedef int32_t (*fn_get_device_property_info)(const char *, int32_t, uint32_t, int32_t *, uint32_t *);
typedef int32_t (*fn_read_device_property)(const char *, int32_t, uint32_t, sc_icue_property *);
typedef int32_t (*fn_free_property)(sc_icue_property *);
typedef int32_t (*fn_subscribe)(sc_icue_event_handler, void *);
typedef int32_t (*fn_unsubscribe)(void);
typedef int32_t (*fn_request_control)(const char *, int32_t);
typedef int32_t (*fn_release_control)(const char *);
typedef int32_t (*fn_configure_key_event)(const char *, const sc_icue_key_event_configuration *);

typedef struct {
    void *handle;
    fn_connect connect;
    fn_disconnect disconnect;
    fn_get_session_details get_session_details;
    fn_get_devices get_devices;
    fn_get_device_info get_device_info;
    fn_get_led_positions get_led_positions;
    fn_get_led_colors get_led_colors;
    fn_set_led_colors set_led_colors;
    fn_set_led_colors_buffer set_led_colors_buffer;
    fn_flush_async flush_async;
    fn_set_layer_priority set_layer_priority;
    fn_get_device_property_info get_device_property_info;
    fn_read_device_property read_device_property;
    fn_free_property free_property;
    fn_subscribe subscribe;
    fn_unsubscribe unsubscribe;
    fn_request_control request_control;
    fn_release_control release_control;
    fn_configure_key_event configure_key_event;
} sc_icue_library;

static sc_icue_library g_lib;
static char g_last_error[512];

static void sc_set_error(const char *message) {
    if (message == NULL) {
        g_last_error[0] = '\0';
        return;
    }
    strncpy(g_last_error, message, sizeof(g_last_error) - 1);
    g_last_error[sizeof(g_last_error) - 1] = '\0';
}

const char *sc_icue_last_error(void) {
    return g_last_error;
}

int sc_icue_is_loaded(void) {
    return g_lib.handle != NULL;
}

void sc_icue_unload(void) {
    if (g_lib.handle != NULL) {
        dlclose(g_lib.handle);
    }
    memset(&g_lib, 0, sizeof(g_lib));
}

/* Resolve a symbol; records an error and returns NULL when missing. */
static void *sc_required(void *handle, const char *name, int *ok) {
    void *symbol = dlsym(handle, name);
    if (symbol == NULL) {
        char buffer[256];
        snprintf(buffer, sizeof(buffer), "missing symbol: %s", name);
        sc_set_error(buffer);
        *ok = 0;
    }
    return symbol;
}

int sc_icue_load(const char *const *candidate_paths,
                 int candidate_count,
                 char *out_resolved_path,
                 int out_resolved_path_size) {
    if (g_lib.handle != NULL) {
        return 1;
    }
    if (candidate_paths == NULL || candidate_count <= 0) {
        sc_set_error("no candidate paths supplied");
        return 0;
    }

    sc_set_error(NULL);

    for (int i = 0; i < candidate_count; i++) {
        const char *path = candidate_paths[i];
        if (path == NULL || path[0] == '\0') {
            continue;
        }

        /* RTLD_LOCAL keeps the vendor library's symbols out of the global
         * namespace so it cannot shadow anything in this process. */
        void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (handle == NULL) {
            sc_set_error(dlerror());
            continue;
        }

        sc_icue_library candidate;
        memset(&candidate, 0, sizeof(candidate));
        candidate.handle = handle;

        int ok = 1;
        candidate.connect = (fn_connect)sc_required(handle, "CorsairConnect", &ok);
        candidate.disconnect = (fn_disconnect)sc_required(handle, "CorsairDisconnect", &ok);
        candidate.get_session_details =
            (fn_get_session_details)sc_required(handle, "CorsairGetSessionDetails", &ok);
        candidate.get_devices = (fn_get_devices)sc_required(handle, "CorsairGetDevices", &ok);
        candidate.get_device_info = (fn_get_device_info)sc_required(handle, "CorsairGetDeviceInfo", &ok);
        candidate.get_led_positions =
            (fn_get_led_positions)sc_required(handle, "CorsairGetLedPositions", &ok);
        candidate.set_led_colors = (fn_set_led_colors)sc_required(handle, "CorsairSetLedColors", &ok);
        candidate.set_led_colors_buffer =
            (fn_set_led_colors_buffer)sc_required(handle, "CorsairSetLedColorsBuffer", &ok);
        candidate.flush_async =
            (fn_flush_async)sc_required(handle, "CorsairSetLedColorsFlushBufferAsync", &ok);
        candidate.set_layer_priority =
            (fn_set_layer_priority)sc_required(handle, "CorsairSetLayerPriority", &ok);
        candidate.subscribe = (fn_subscribe)sc_required(handle, "CorsairSubscribeForEvents", &ok);
        candidate.unsubscribe = (fn_unsubscribe)sc_required(handle, "CorsairUnsubscribeFromEvents", &ok);
        candidate.request_control = (fn_request_control)sc_required(handle, "CorsairRequestControl", &ok);
        candidate.release_control = (fn_release_control)sc_required(handle, "CorsairReleaseControl", &ok);
        candidate.configure_key_event =
            (fn_configure_key_event)sc_required(handle, "CorsairConfigureKeyEvent", &ok);

        /* Optional symbols: absence degrades a feature, it does not fail load. */
        candidate.get_led_colors = (fn_get_led_colors)dlsym(handle, "CorsairGetLedColors");
        candidate.get_device_property_info =
            (fn_get_device_property_info)dlsym(handle, "CorsairGetDevicePropertyInfo");
        candidate.read_device_property =
            (fn_read_device_property)dlsym(handle, "CorsairReadDeviceProperty");
        candidate.free_property = (fn_free_property)dlsym(handle, "CorsairFreeProperty");

        if (!ok) {
            dlclose(handle);
            continue;
        }

        g_lib = candidate;
        sc_set_error(NULL);
        if (out_resolved_path != NULL && out_resolved_path_size > 0) {
            strncpy(out_resolved_path, path, (size_t)out_resolved_path_size - 1);
            out_resolved_path[out_resolved_path_size - 1] = '\0';
        }
        return 1;
    }

    if (g_last_error[0] == '\0') {
        sc_set_error("no candidate path could be opened");
    }
    return 0;
}

/* ---------------------------------------------------------------------------
 * Forwarding wrappers. Every one is null-safe so that a partially available
 * SDK never crashes the companion; it just reports an error code.
 * ------------------------------------------------------------------------ */

#define SC_REQUIRE(fnptr)                          \
    do {                                           \
        if (g_lib.handle == NULL) {                \
            return SC_ICUE_LIBRARY_NOT_LOADED;     \
        }                                          \
        if ((fnptr) == NULL) {                     \
            return SC_ICUE_SYMBOL_MISSING;         \
        }                                          \
    } while (0)

int32_t sc_icue_connect(sc_icue_session_state_changed_handler handler, void *context) {
    SC_REQUIRE(g_lib.connect);
    return g_lib.connect(handler, context);
}

int32_t sc_icue_disconnect(void) {
    SC_REQUIRE(g_lib.disconnect);
    return g_lib.disconnect();
}

int32_t sc_icue_get_session_details(sc_icue_session_details *out_details) {
    SC_REQUIRE(g_lib.get_session_details);
    return g_lib.get_session_details(out_details);
}

int32_t sc_icue_get_devices(const sc_icue_device_filter *filter,
                            int32_t size_max,
                            sc_icue_device_info *out_devices,
                            int32_t *out_size) {
    SC_REQUIRE(g_lib.get_devices);
    return g_lib.get_devices(filter, size_max, out_devices, out_size);
}

int32_t sc_icue_get_device_info(const char *device_id, sc_icue_device_info *out_info) {
    SC_REQUIRE(g_lib.get_device_info);
    return g_lib.get_device_info(device_id, out_info);
}

int32_t sc_icue_get_led_positions(const char *device_id,
                                  int32_t size_max,
                                  sc_icue_led_position *out_positions,
                                  int32_t *out_size) {
    SC_REQUIRE(g_lib.get_led_positions);
    return g_lib.get_led_positions(device_id, size_max, out_positions, out_size);
}

int32_t sc_icue_get_led_colors(const char *device_id, int32_t size, sc_icue_led_color *colors) {
    SC_REQUIRE(g_lib.get_led_colors);
    return g_lib.get_led_colors(device_id, size, colors);
}

int32_t sc_icue_set_led_colors(const char *device_id, int32_t size, const sc_icue_led_color *colors) {
    SC_REQUIRE(g_lib.set_led_colors);
    return g_lib.set_led_colors(device_id, size, colors);
}

int32_t sc_icue_set_led_colors_buffer(const char *device_id,
                                      int32_t size,
                                      const sc_icue_led_color *colors) {
    SC_REQUIRE(g_lib.set_led_colors_buffer);
    return g_lib.set_led_colors_buffer(device_id, size, colors);
}

int32_t sc_icue_set_led_colors_flush_async(sc_icue_async_callback callback, void *context) {
    SC_REQUIRE(g_lib.flush_async);
    return g_lib.flush_async(callback, context);
}

int32_t sc_icue_set_layer_priority(uint32_t priority) {
    SC_REQUIRE(g_lib.set_layer_priority);
    return g_lib.set_layer_priority(priority);
}

int32_t sc_icue_get_device_property_info(const char *device_id,
                                         int32_t property_id,
                                         uint32_t index,
                                         int32_t *out_data_type,
                                         uint32_t *out_flags) {
    SC_REQUIRE(g_lib.get_device_property_info);
    return g_lib.get_device_property_info(device_id, property_id, index, out_data_type, out_flags);
}

int32_t sc_icue_read_device_property(const char *device_id,
                                     int32_t property_id,
                                     uint32_t index,
                                     sc_icue_property *out_property) {
    SC_REQUIRE(g_lib.read_device_property);
    return g_lib.read_device_property(device_id, property_id, index, out_property);
}

int32_t sc_icue_free_property(sc_icue_property *property) {
    SC_REQUIRE(g_lib.free_property);
    return g_lib.free_property(property);
}

sc_icue_property sc_icue_make_empty_property(void) {
    sc_icue_property property;
    memset(&property, 0, sizeof(property));
    return property;
}

int32_t sc_icue_subscribe_for_events(sc_icue_event_handler handler, void *context) {
    SC_REQUIRE(g_lib.subscribe);
    return g_lib.subscribe(handler, context);
}

int32_t sc_icue_unsubscribe_from_events(void) {
    SC_REQUIRE(g_lib.unsubscribe);
    return g_lib.unsubscribe();
}

int32_t sc_icue_request_key_control(const char *device_id, int32_t access_level) {
    SC_REQUIRE(g_lib.request_control);

    /* A NULL device id means "every Corsair device" in the SDK. This project
     * targets exactly one mouse, so refuse rather than pass it through. */
    if (device_id == NULL || device_id[0] == '\0') {
        return SC_ICUE_INVALID_ARGUMENTS;
    }

    /* Hard gate: the two lighting-bearing access levels are unreachable. */
    if (access_level != SC_ICUE_ACCESS_SHARED &&
        access_level != SC_ICUE_ACCESS_EXCLUSIVE_KEY_EVENTS) {
        return SC_ICUE_ACCESS_LEVEL_FORBIDDEN;
    }

    return g_lib.request_control(device_id, access_level);
}

int32_t sc_icue_release_control(const char *device_id) {
    SC_REQUIRE(g_lib.release_control);
    if (device_id == NULL || device_id[0] == '\0') {
        return SC_ICUE_INVALID_ARGUMENTS;
    }
    return g_lib.release_control(device_id);
}

int32_t sc_icue_configure_key_event(const char *device_id,
                                    const sc_icue_key_event_configuration *config) {
    SC_REQUIRE(g_lib.configure_key_event);
    if (device_id == NULL || device_id[0] == '\0' || config == NULL) {
        return SC_ICUE_INVALID_ARGUMENTS;
    }
    return g_lib.configure_key_event(device_id, config);
}
