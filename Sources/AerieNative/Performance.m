#include "AerieNative.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

// IOReport is a private system ABI; resolve the entire required interface before subscribing.
// Symbols may disappear. Failure remains explicit and never invokes an elevated fallback.
struct AeriePerformance {
    void *library;
    CFTypeRef subscriptions[3];
    CFMutableDictionaryRef channels[3];
    int status[3];
    CFMutableDictionaryRef (*copy_channels)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
    CFTypeRef (*subscribe)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
    CFDictionaryRef (*samples)(CFTypeRef, CFMutableDictionaryRef, CFTypeRef);
    void (*iterate)(CFDictionaryRef, int (^)(CFDictionaryRef));
    uint32_t (*state_count)(CFDictionaryRef);
    uint64_t (*residency)(CFDictionaryRef, uint32_t);
    CFStringRef (*state_name)(CFDictionaryRef, uint32_t);
    CFStringRef (*channel_name)(CFDictionaryRef);
    CFStringRef (*unit)(CFDictionaryRef);
    uint64_t (*driver_id)(CFDictionaryRef);
    uint64_t (*channel_id)(CFDictionaryRef);
};
static void copy_text(CFStringRef text, char *out, size_t size) {
    out[0] = 0;
    if (!text || CFGetTypeID(text) != CFStringGetTypeID() ||
        !CFStringGetCString(text, out, size, kCFStringEncodingUTF8)) out[0] = 0;
}
void aerie_performance_close(AeriePerformance *reader) {
    if (!reader) return;
    for (int i = 0; i < 3; i++) {
        if (reader->subscriptions[i]) CFRelease(reader->subscriptions[i]);
        if (reader->channels[i]) CFRelease(reader->channels[i]);
    }
    if (reader->library) dlclose(reader->library);
    free(reader);
}
AeriePerformance *aerie_performance_create(void) {
    AeriePerformance *reader = calloc(1, sizeof(*reader));
    if (!reader) return NULL;
    reader->library = dlopen("/usr/lib/libIOReport.dylib", RTLD_LOCAL | RTLD_NOW);
    if (!reader->library) { aerie_performance_close(reader); return NULL; }
#define LOAD(member, name) reader->member = dlsym(reader->library, name); if (!reader->member) { aerie_performance_close(reader); return NULL; }
    LOAD(copy_channels, "IOReportCopyChannelsInGroup")
    LOAD(subscribe, "IOReportCreateSubscription")
    LOAD(samples, "IOReportCreateSamples")
    LOAD(iterate, "IOReportIterate")
    LOAD(state_count, "IOReportStateGetCount")
    LOAD(residency, "IOReportStateGetResidency")
    LOAD(state_name, "IOReportStateGetNameForIndex")
    LOAD(channel_name, "IOReportChannelGetChannelName")
    LOAD(unit, "IOReportChannelGetUnitLabel")
    LOAD(driver_id, "IOReportChannelGetDriverID")
    LOAD(channel_id, "IOReportChannelGetChannelID")
#undef LOAD
    CFStringRef groups[3] = {CFSTR("CPU Stats"), CFSTR("CPU Stats"), CFSTR("GPU Stats")};
    CFStringRef subgroups[3] = {CFSTR("CPU Complex Performance States"), CFSTR("CPU Core Performance States"), CFSTR("GPU Performance States")};
    for (int i = 0; i < 3; i++) {
        CFMutableDictionaryRef desired = reader->copy_channels(groups[i], subgroups[i], 0, 0, 0);
        if (!desired) { reader->status[i] = 2; continue; }
        reader->subscriptions[i] = reader->subscribe(NULL, desired, &reader->channels[i], 0, NULL);
        CFRelease(desired);
        if (!reader->subscriptions[i] || !reader->channels[i]) reader->status[i] = 3;
    }
    return reader;
}
int aerie_performance_read(AeriePerformance *reader, AerieClockChannel *out, int capacity, int status[3]) {
    if (!status) return 0;
    for (int i = 0; i < 3; i++) status[i] = reader ? reader->status[i] : 1;
    if (!reader || !out || capacity <= 0 || capacity > 128) return 0;
    __block int count = 0;
    for (int kind = 0; kind < 3; kind++) {
        if (reader->status[kind]) continue;
        CFDictionaryRef sample = reader->samples(reader->subscriptions[kind], reader->channels[kind], NULL);
        if (!sample) { status[kind] = 4; continue; }
        int before = count;
        reader->iterate(sample, ^int(CFDictionaryRef channel) {
            if (count >= capacity) { status[kind] = 5; return 1; }
            uint32_t states = reader->state_count(channel);
            if (!states) return 0;
            if (states > 64) { status[kind] = 5; return 0; }
            AerieClockChannel *record = &out[count]; memset(record, 0, sizeof(*record));
            record->kind = kind; record->state_count = (int)states;
            record->driver_id = reader->driver_id(channel); record->channel_id = reader->channel_id(channel);
            copy_text(reader->channel_name(channel), record->name, sizeof(record->name));
            copy_text(reader->unit(channel), record->unit, sizeof(record->unit));
            for (uint32_t i = 0; i < states; i++) {
                copy_text(reader->state_name(channel, i), record->states[i].name, sizeof(record->states[i].name));
                record->states[i].ticks = reader->residency(channel, i);
            }
            count++; return 0;
        });
        CFRelease(sample);
        if (count == before && status[kind] == 0) status[kind] = 2;
    }
    return count;
}
