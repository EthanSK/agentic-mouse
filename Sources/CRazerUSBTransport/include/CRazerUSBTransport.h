#ifndef C_RAZER_USB_TRANSPORT_H
#define C_RAZER_USB_TRANSPORT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *AMRazerUSBHandle;

/// Counts USB devices matching `vendor_id` and `product_id` without opening
/// the device or touching any input interface.
int32_t am_razer_usb_count_exact(
    uint16_t vendor_id,
    uint16_t product_id,
    uint32_t *out_count
);

/// Opens exactly one USB device matching `vendor_id` and `product_id`.
/// Returns zero on success, -2 when more than one exact device is present,
/// or an IOKit status value on transport failure.
int32_t am_razer_usb_open_exact(
    uint16_t vendor_id,
    uint16_t product_id,
    AMRazerUSBHandle *out_handle
);

/// Sends one HID class SET_REPORT to interface zero, waits, then performs the
/// matching GET_REPORT. Both buffers must be exactly 90 bytes.
int32_t am_razer_usb_exchange(
    AMRazerUSBHandle handle,
    const uint8_t *request_bytes,
    size_t request_length,
    uint8_t *response_bytes,
    size_t response_length,
    uint32_t wait_microseconds
);

void am_razer_usb_close(AMRazerUSBHandle handle);

#ifdef __cplusplus
}
#endif

#endif
