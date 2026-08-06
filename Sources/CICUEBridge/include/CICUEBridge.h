/*
 * CICUEBridge — a thin, runtime-loaded shim for the Corsair iCUE SDK.
 *
 * Why a shim exists at all
 * -----------------------
 * The iCUE SDK is proprietary vendor material distributed under an EULA. This
 * repository therefore contains **no** Corsair headers and **no** Corsair
 * binaries. Instead, the small subset of the SDK's C ABI that this project
 * needs is re-declared below and resolved with dlopen()/dlsym() at runtime.
 *
 * Consequences (all deliberate):
 *   - The project builds and its tests run on a machine with no iCUE, no SDK
 *     disk image and no Corsair hardware attached.
 *   - A missing/incompatible SDK degrades to "lighting unavailable" instead of
 *     a link error or a crash.
 *   - Struct layouts here MUST stay ABI-compatible with iCUE SDK protocol 18
 *     (SDK 4.0.x). Layout assertions are compiled into CICUEBridge.c.
 *
 * Scope: session lifecycle, device enumeration, LED discovery, *shared-layer*
 * LED writes, layer priority, device property reads, macro-key event
 * subscription, and the three key-control entry points needed to make
 * multi-tap mode modal.
 *
 * A note on access levels, because it is easy to get wrong:
 *
 *   CAL_SHARED (0)                       — the default. Lighting is shared.
 *   CAL_EXCLUSIVE_LIGHTING_CONTROL (1)   — BANNED in this project.
 *   CAL_EXCLUSIVE_KEY_EVENTS_LISTENING (2) — input only; "exclusive key
 *                                          events, but shared lightings".
 *   CAL_EXCLUSIVE_BOTH (3)               — BANNED (contains lighting).
 *
 * Level 2 is what multi-tap mode holds, transactionally, for exactly as long
 * as the mode is active, scoped to one device id. It does not touch lighting.
 * `sc_icue_request_key_control` refuses levels 1 and 3 outright so the ban on
 * exclusive lighting cannot be violated even by a caller mistake.
 */

#ifndef CICUE_BRIDGE_H
#define CICUE_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---------------------------------------------------------------------------
 * Constants mirrored from the SDK
 * ------------------------------------------------------------------------ */

#define SC_ICUE_STRING_SIZE_S 64
#define SC_ICUE_STRING_SIZE_M 128
#define SC_ICUE_DEVICE_COUNT_MAX 64
#define SC_ICUE_DEVICE_LEDCOUNT_MAX 512
#define SC_ICUE_LAYER_PRIORITY_MAX 255

/* CorsairError */
typedef enum {
    SC_ICUE_SUCCESS = 0,
    SC_ICUE_NOT_CONNECTED = 1,
    SC_ICUE_NO_CONTROL = 2,
    SC_ICUE_INCOMPATIBLE_PROTOCOL = 3,
    SC_ICUE_INVALID_ARGUMENTS = 4,
    SC_ICUE_INVALID_OPERATION = 5,
    SC_ICUE_DEVICE_NOT_FOUND = 6,
    SC_ICUE_NOT_ALLOWED = 7,
    /* Bridge-local codes, outside the SDK's range. */
    SC_ICUE_LIBRARY_NOT_LOADED = 1000,
    SC_ICUE_SYMBOL_MISSING = 1001
} sc_icue_error;

/* CorsairSessionState */
typedef enum {
    SC_ICUE_SESSION_INVALID = 0,
    SC_ICUE_SESSION_CLOSED = 1,
    SC_ICUE_SESSION_CONNECTING = 2,
    SC_ICUE_SESSION_TIMEOUT = 3,
    SC_ICUE_SESSION_CONNECTION_REFUSED = 4,
    SC_ICUE_SESSION_CONNECTION_LOST = 5,
    SC_ICUE_SESSION_CONNECTED = 6
} sc_icue_session_state;

/* CorsairDeviceType bit mask */
#define SC_ICUE_DEVICE_TYPE_MOUSE 0x0002

/* CorsairEventId */
typedef enum {
    SC_ICUE_EVENT_INVALID = 0,
    SC_ICUE_EVENT_DEVICE_CONNECTION_STATUS_CHANGED = 1,
    SC_ICUE_EVENT_KEY = 2
} sc_icue_event_id;

/* CorsairDevicePropertyId (only the members this project reads) */
typedef enum {
    SC_ICUE_PROPERTY_PROPERTY_ARRAY = 1,
    SC_ICUE_PROPERTY_MACRO_KEY_ARRAY = 8,
    SC_ICUE_PROPERTY_BATTERY_LEVEL = 9
} sc_icue_property_id;

/* CorsairDataType */
typedef enum {
    SC_ICUE_DATA_BOOLEAN = 0,
    SC_ICUE_DATA_INT32 = 1,
    SC_ICUE_DATA_FLOAT64 = 2,
    SC_ICUE_DATA_STRING = 3,
    SC_ICUE_DATA_BOOLEAN_ARRAY = 16,
    SC_ICUE_DATA_INT32_ARRAY = 17,
    SC_ICUE_DATA_FLOAT64_ARRAY = 18,
    SC_ICUE_DATA_STRING_ARRAY = 19
} sc_icue_data_type;

/* CorsairLedGroup — the LED luid high half. */
#define SC_ICUE_LED_GROUP_MOUSE 4

/*
 * CorsairAccessLevel. Only SHARED and EXCLUSIVE_KEY_EVENTS_LISTENING are
 * reachable through this bridge; see the header comment.
 */
typedef enum {
    SC_ICUE_ACCESS_SHARED = 0,
    SC_ICUE_ACCESS_EXCLUSIVE_LIGHTING = 1,             /* rejected by the bridge */
    SC_ICUE_ACCESS_EXCLUSIVE_KEY_EVENTS = 2,
    SC_ICUE_ACCESS_EXCLUSIVE_LIGHTING_AND_KEYS = 3     /* rejected by the bridge */
} sc_icue_access_level;

/* Bridge-local refusal code for a banned access level. */
#define SC_ICUE_ACCESS_LEVEL_FORBIDDEN 1002

/* ---------------------------------------------------------------------------
 * ABI-compatible structures
 * ------------------------------------------------------------------------ */

typedef struct {
    int32_t major;
    int32_t minor;
    int32_t patch;
} sc_icue_version;

typedef struct {
    sc_icue_version client_version;
    sc_icue_version server_version;
    sc_icue_version server_host_version;
} sc_icue_session_details;

typedef struct {
    int32_t state; /* sc_icue_session_state */
    sc_icue_session_details details;
} sc_icue_session_state_changed;

typedef struct {
    int32_t type; /* CorsairDeviceType */
    char id[SC_ICUE_STRING_SIZE_M];
    char serial[SC_ICUE_STRING_SIZE_M];
    char model[SC_ICUE_STRING_SIZE_M];
    int32_t led_count;
    int32_t channel_count;
} sc_icue_device_info;

typedef struct {
    int32_t device_type_mask;
} sc_icue_device_filter;

typedef struct {
    uint32_t id; /* CorsairLedLuid */
    double cx;
    double cy;
} sc_icue_led_position;

typedef struct {
    uint32_t id; /* CorsairLedLuid */
    unsigned char r;
    unsigned char g;
    unsigned char b;
    unsigned char a;
} sc_icue_led_color;

typedef struct {
    char device_id[SC_ICUE_STRING_SIZE_M];
    bool is_connected;
} sc_icue_device_connection_status_changed_event;

typedef struct {
    char device_id[SC_ICUE_STRING_SIZE_M];
    int32_t key_id; /* CorsairMacroKeyId, 1...20 */
    bool is_pressed;
} sc_icue_key_event;

/* CorsairKeyEventConfiguration */
typedef struct {
    int32_t key_id;       /* CorsairMacroKeyId */
    bool is_intercepted;  /* true: deliver only to the exclusive client */
} sc_icue_key_event_configuration;

typedef struct {
    int32_t id; /* sc_icue_event_id */
    union {
        const sc_icue_device_connection_status_changed_event *device_connection;
        const sc_icue_key_event *key;
    } data;
} sc_icue_event;

typedef struct {
    void *items;
    uint32_t count;
} sc_icue_array;

typedef union {
    bool boolean;
    int32_t int32;
    double float64;
    char *string;
    sc_icue_array array;
} sc_icue_data_value;

typedef struct {
    int32_t type; /* sc_icue_data_type */
    sc_icue_data_value value;
} sc_icue_property;

/* ---------------------------------------------------------------------------
 * Callbacks
 * ------------------------------------------------------------------------ */

typedef void (*sc_icue_session_state_changed_handler)(void *context,
                                                     const sc_icue_session_state_changed *event);
typedef void (*sc_icue_event_handler)(void *context, const sc_icue_event *event);
typedef void (*sc_icue_async_callback)(void *context, int32_t error);

/* ---------------------------------------------------------------------------
 * Library lifecycle
 * ------------------------------------------------------------------------ */

/*
 * Try each candidate path in order until one dlopen()s and exports the core
 * symbols. Returns 1 on success and copies the winning path into
 * `out_resolved_path` (if non-NULL); returns 0 on failure. The most recent
 * dlerror() text is available from sc_icue_last_error().
 */
int sc_icue_load(const char *const *candidate_paths,
                 int candidate_count,
                 char *out_resolved_path,
                 int out_resolved_path_size);

int sc_icue_is_loaded(void);
const char *sc_icue_last_error(void);
void sc_icue_unload(void);

/* ---------------------------------------------------------------------------
 * Session
 * ------------------------------------------------------------------------ */

int32_t sc_icue_connect(sc_icue_session_state_changed_handler handler, void *context);
int32_t sc_icue_disconnect(void);
int32_t sc_icue_get_session_details(sc_icue_session_details *out_details);

/* ---------------------------------------------------------------------------
 * Devices and LEDs
 * ------------------------------------------------------------------------ */

int32_t sc_icue_get_devices(const sc_icue_device_filter *filter,
                            int32_t size_max,
                            sc_icue_device_info *out_devices,
                            int32_t *out_size);
int32_t sc_icue_get_device_info(const char *device_id, sc_icue_device_info *out_info);
int32_t sc_icue_get_led_positions(const char *device_id,
                                  int32_t size_max,
                                  sc_icue_led_position *out_positions,
                                  int32_t *out_size);
int32_t sc_icue_get_led_colors(const char *device_id, int32_t size, sc_icue_led_color *colors);

/* Shared-layer writes only. */
int32_t sc_icue_set_led_colors(const char *device_id, int32_t size, const sc_icue_led_color *colors);
int32_t sc_icue_set_led_colors_buffer(const char *device_id, int32_t size, const sc_icue_led_color *colors);
int32_t sc_icue_set_led_colors_flush_async(sc_icue_async_callback callback, void *context);
int32_t sc_icue_set_layer_priority(uint32_t priority);

/* ---------------------------------------------------------------------------
 * Properties and events
 * ------------------------------------------------------------------------ */

int32_t sc_icue_get_device_property_info(const char *device_id,
                                         int32_t property_id,
                                         uint32_t index,
                                         int32_t *out_data_type,
                                         uint32_t *out_flags);
int32_t sc_icue_read_device_property(const char *device_id,
                                     int32_t property_id,
                                     uint32_t index,
                                     sc_icue_property *out_property);
int32_t sc_icue_free_property(sc_icue_property *property);

/*
 * A zeroed property value. Swift's importer does not reliably synthesise a
 * default initialiser for a struct containing a C union, so the zero value is
 * produced here where the layout is unambiguous.
 */
sc_icue_property sc_icue_make_empty_property(void);

int32_t sc_icue_subscribe_for_events(sc_icue_event_handler handler, void *context);
int32_t sc_icue_unsubscribe_from_events(void);

/* ---------------------------------------------------------------------------
 * Key control (input only — never lighting)
 * ------------------------------------------------------------------------ */

/*
 * Requests an access level for one device id.
 *
 * `device_id` must be non-NULL: passing NULL to the SDK would request control
 * for *all* devices, which this project forbids, so the bridge rejects it.
 *
 * `access_level` must be SC_ICUE_ACCESS_SHARED or
 * SC_ICUE_ACCESS_EXCLUSIVE_KEY_EVENTS. Anything else returns
 * SC_ICUE_ACCESS_LEVEL_FORBIDDEN without calling the SDK.
 */
int32_t sc_icue_request_key_control(const char *device_id, int32_t access_level);

/* Releases whatever control was requested, returning the device to shared. */
int32_t sc_icue_release_control(const char *device_id);

/*
 * Marks one macro key as intercepted (delivered only to this exclusive client)
 * or not. Requires an exclusive key-events access level to take effect.
 */
int32_t sc_icue_configure_key_event(const char *device_id,
                                    const sc_icue_key_event_configuration *config);

#ifdef __cplusplus
}
#endif

#endif /* CICUE_BRIDGE_H */
