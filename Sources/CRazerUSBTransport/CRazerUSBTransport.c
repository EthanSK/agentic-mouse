#include "CRazerUSBTransport.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum {
    AM_RAZER_REPORT_LENGTH = 90,
    AM_RAZER_MULTIPLE_DEVICES = -2,
    AM_RAZER_INVALID_ARGUMENT = -3,
};

typedef struct {
    IOUSBDeviceInterface **device;
} AMRazerUSBContext;

static IOUSBDeviceInterface **am_razer_device_interface(io_service_t service) {
    IOCFPlugInInterface **plugin = NULL;
    IOUSBDeviceInterface **device = NULL;
    SInt32 score = 0;
    IOReturn status = IOCreatePlugInInterfaceForService(
        service,
        kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugin,
        &score
    );
    if (status != kIOReturnSuccess || plugin == NULL) {
        return NULL;
    }

    HRESULT query = (*plugin)->QueryInterface(
        plugin,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
        (LPVOID *)&device
    );
    (*plugin)->Release(plugin);
    return query == S_OK ? device : NULL;
}

int32_t am_razer_usb_open_exact(
    uint16_t vendor_id,
    uint16_t product_id,
    AMRazerUSBHandle *out_handle
) {
    if (out_handle == NULL) {
        return AM_RAZER_INVALID_ARGUMENT;
    }
    *out_handle = NULL;

    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBDeviceClassName);
    if (matching == NULL) {
        return (int32_t)kIOReturnNoMemory;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    IOReturn status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (status != kIOReturnSuccess) {
        return (int32_t)status;
    }

    IOUSBDeviceInterface **match = NULL;
    size_t match_count = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        IOUSBDeviceInterface **candidate = am_razer_device_interface(service);
        IOObjectRelease(service);
        if (candidate == NULL) {
            continue;
        }

        UInt16 candidate_vendor = 0;
        UInt16 candidate_product = 0;
        IOReturn vendor_status = (*candidate)->GetDeviceVendor(candidate, &candidate_vendor);
        IOReturn product_status = (*candidate)->GetDeviceProduct(candidate, &candidate_product);
        if (vendor_status == kIOReturnSuccess &&
            product_status == kIOReturnSuccess &&
            candidate_vendor == vendor_id &&
            candidate_product == product_id) {
            match_count += 1;
            if (match == NULL) {
                match = candidate;
            } else {
                (*candidate)->Release(candidate);
            }
        } else {
            (*candidate)->Release(candidate);
        }
    }
    IOObjectRelease(iterator);

    if (match_count == 0 || match == NULL) {
        return (int32_t)kIOReturnNotFound;
    }
    if (match_count != 1) {
        (*match)->Release(match);
        return AM_RAZER_MULTIPLE_DEVICES;
    }

    status = (*match)->USBDeviceOpen(match);
    if (status != kIOReturnSuccess) {
        (*match)->Release(match);
        return (int32_t)status;
    }

    AMRazerUSBContext *context = calloc(1, sizeof(*context));
    if (context == NULL) {
        (*match)->USBDeviceClose(match);
        (*match)->Release(match);
        return (int32_t)kIOReturnNoMemory;
    }
    context->device = match;
    *out_handle = context;
    return 0;
}

int32_t am_razer_usb_exchange(
    AMRazerUSBHandle handle,
    const uint8_t *request_bytes,
    size_t request_length,
    uint8_t *response_bytes,
    size_t response_length,
    uint32_t wait_microseconds
) {
    if (handle == NULL || request_bytes == NULL || response_bytes == NULL ||
        request_length != AM_RAZER_REPORT_LENGTH ||
        response_length != AM_RAZER_REPORT_LENGTH) {
        return AM_RAZER_INVALID_ARGUMENT;
    }

    AMRazerUSBContext *context = (AMRazerUSBContext *)handle;
    IOUSBDevRequest request;
    memset(&request, 0, sizeof(request));
    request.bmRequestType = 0x21; // Host-to-device, HID class, interface.
    request.bRequest = 0x09;      // SET_REPORT.
    request.wValue = 0x0300;      // Feature report, unnumbered report ID.
    request.wIndex = 0;
    request.wLength = AM_RAZER_REPORT_LENGTH;
    request.pData = (void *)request_bytes;

    IOReturn status = (*context->device)->DeviceRequest(context->device, &request);
    if (status != kIOReturnSuccess) {
        return (int32_t)status;
    }

    if (wait_microseconds > 0) {
        usleep(wait_microseconds);
    }

    memset(response_bytes, 0, response_length);
    memset(&request, 0, sizeof(request));
    request.bmRequestType = 0xA1; // Device-to-host, HID class, interface.
    request.bRequest = 0x01;      // GET_REPORT.
    request.wValue = 0x0300;
    request.wIndex = 0;
    request.wLength = AM_RAZER_REPORT_LENGTH;
    request.pData = response_bytes;

    status = (*context->device)->DeviceRequest(context->device, &request);
    return (int32_t)status;
}

void am_razer_usb_close(AMRazerUSBHandle handle) {
    if (handle == NULL) {
        return;
    }
    AMRazerUSBContext *context = (AMRazerUSBContext *)handle;
    if (context->device != NULL) {
        (*context->device)->USBDeviceClose(context->device);
        (*context->device)->Release(context->device);
    }
    free(context);
}
