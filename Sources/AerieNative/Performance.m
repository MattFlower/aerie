#include "AerieNative.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

// Resolve the required private ABI before subscribing. An unavailable optional merge ABI
// retains separate subscriptions; no source, interval or privilege changes are made.
struct AeriePerformance {
    void *library;
    CFTypeRef subscriptions[3], merged_subscription;
    CFMutableDictionaryRef channels[3], merged_channels;
    AerieClockIdentity catalog[128];
    int catalog_count, status[3];
    CFMutableDictionaryRef (*copy_channels)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
    CFTypeRef (*subscribe)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
    int (*merge)(CFMutableDictionaryRef, CFDictionaryRef, CFTypeRef);
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
int aerie_clock_catalog_valid(const AerieClockIdentity *catalog, int count) {
    if (!catalog || count <= 0 || count > 128) return 0;
    for (int i = 0; i < count; i++) {
        if (catalog[i].kind < 0 || catalog[i].kind > 2) return 0;
        for (int j = 0; j < i; j++) {
            if (catalog[i].driver_id == catalog[j].driver_id &&
                catalog[i].channel_id == catalog[j].channel_id) return 0;
        }
    }
    return 1;
}
int aerie_clock_catalog_kind(const AerieClockIdentity *catalog, int count,
                             uint64_t driver, uint64_t channel) {
    if (!catalog || count <= 0 || count > 128) return -1;
    int found = -1;
    for (int i = 0; i < count; i++) {
        if (catalog[i].driver_id != driver || catalog[i].channel_id != channel) continue;
        if (found != -1 || catalog[i].kind < 0 || catalog[i].kind > 2) return -1;
        found = catalog[i].kind;
    }
    return found;
}
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
    if (reader->merged_subscription) CFRelease(reader->merged_subscription);
    if (reader->merged_channels) CFRelease(reader->merged_channels);
    if (reader->library) dlclose(reader->library);
    free(reader);
}
int aerie_performance_subscription_count(AeriePerformance *reader) {
    if (!reader) return 0;
    if (reader->merged_subscription) return 1;
    int count = 0;
    for (int i = 0; i < 3; i++) if (reader->subscriptions[i] && reader->channels[i]) count++;
    return count;
}
static int catalog_covers(AeriePerformance *reader, CFDictionaryRef channels) {
    __block int valid = 1;
    __block struct { unsigned char seen[128]; } coverage = {0};
    reader->iterate(channels, ^int(CFDictionaryRef channel) {
        uint64_t driver = reader->driver_id(channel), id = reader->channel_id(channel);
        int found = -1;
        for (int i = 0; i < reader->catalog_count; i++) {
            if (reader->catalog[i].driver_id == driver && reader->catalog[i].channel_id == id) {
                found = i; break;
            }
        }
        if (found == -1 || coverage.seen[found]) { valid = 0; return 1; }
        coverage.seen[found] = 1; return 0;
    });
    for (int i = 0; i < reader->catalog_count; i++) if (!coverage.seen[i]) valid = 0;
    return valid;
}
static int try_merge(AeriePerformance *reader, CFMutableDictionaryRef desired[3]) {
    if (!reader->merge) return 0;
    reader->catalog_count = 0;
    __block int valid = 1;
    for (int kind = 0; kind < 3; kind++) {
        if (!desired[kind]) continue;
        reader->iterate(desired[kind], ^int(CFDictionaryRef channel) {
            if (reader->catalog_count >= 128) { valid = 0; return 1; }
            reader->catalog[reader->catalog_count++] = (AerieClockIdentity){
                kind, reader->driver_id(channel), reader->channel_id(channel)};
            return 0;
        });
    }
    if (!valid || !aerie_clock_catalog_valid(reader->catalog, reader->catalog_count)) return 0;
    CFMutableDictionaryRef merged = NULL;
    for (int kind = 0; kind < 3; kind++) {
        if (!desired[kind]) continue;
        if (!merged) merged = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, desired[kind]);
        else if (reader->merge(merged, desired[kind], NULL) != 0) { valid = 0; break; }
        if (!merged) { valid = 0; break; }
    }
    CFTypeRef subscription = NULL;
    CFMutableDictionaryRef subscribed = NULL;
    if (valid && merged) subscription = reader->subscribe(NULL, merged, &subscribed, 0, NULL);
    if (merged) CFRelease(merged);
    if (!subscription || !subscribed || !catalog_covers(reader, subscribed)) {
        if (subscription) CFRelease(subscription);
        if (subscribed) CFRelease(subscribed);
        return 0;
    }
    reader->merged_subscription = subscription; reader->merged_channels = subscribed;
    return 1;
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
    // Apple's published callers use an iteration-result integer and a null third argument.
    reader->merge = dlsym(reader->library, "IOReportMergeChannels");
    CFStringRef groups[3] = {CFSTR("CPU Stats"), CFSTR("CPU Stats"), CFSTR("GPU Stats")};
    CFStringRef subgroups[3] = {CFSTR("CPU Complex Performance States"), CFSTR("CPU Core Performance States"), CFSTR("GPU Performance States")};
    CFMutableDictionaryRef desired[3] = {NULL, NULL, NULL};
    for (int i = 0; i < 3; i++) {
        desired[i] = reader->copy_channels(groups[i], subgroups[i], 0, 0, 0);
        if (!desired[i]) reader->status[i] = 2;
    }
    int merged = try_merge(reader, desired);
    if (!merged) {
        for (int i = 0; i < 3; i++) {
            if (!desired[i]) continue;
            reader->subscriptions[i] = reader->subscribe(NULL, desired[i], &reader->channels[i], 0, NULL);
            if (!reader->subscriptions[i] || !reader->channels[i]) reader->status[i] = 3;
        }
    }
    for (int i = 0; i < 3; i++) if (desired[i]) CFRelease(desired[i]);
    return reader;
}
static int copy_channel(AeriePerformance *reader, CFDictionaryRef channel,
                         int kind, AerieClockChannel *record) {
    uint32_t states = reader->state_count(channel);
    if (!states) return 0;
    if (states > 64) return -1;
    memset(record, 0, sizeof(*record));
    record->kind = kind; record->state_count = (int)states;
    record->driver_id = reader->driver_id(channel); record->channel_id = reader->channel_id(channel);
    copy_text(reader->channel_name(channel), record->name, sizeof(record->name));
    copy_text(reader->unit(channel), record->unit, sizeof(record->unit));
    for (uint32_t i = 0; i < states; i++) {
        copy_text(reader->state_name(channel, i), record->states[i].name, sizeof(record->states[i].name));
        record->states[i].ticks = reader->residency(channel, i);
    }
    return 1;
}
int aerie_performance_read(AeriePerformance *reader, AerieClockChannel *out, int capacity, int status[3]) {
    if (!status) return 0;
    for (int i = 0; i < 3; i++) status[i] = reader ? reader->status[i] : 1;
    if (!reader || !out || capacity <= 0 || capacity > 128) return 0;
    __block int count = 0;
    if (reader->merged_subscription) {
        CFDictionaryRef sample = reader->samples(reader->merged_subscription, reader->merged_channels, NULL);
        if (!sample) { for (int i = 0; i < 3; i++) if (!status[i]) status[i] = 4; return 0; }
        __block struct { int by_kind[3]; unsigned char seen[128]; } coverage = {0};
        reader->iterate(sample, ^int(CFDictionaryRef channel) {
            int kind = aerie_clock_catalog_kind(reader->catalog, reader->catalog_count,
                reader->driver_id(channel), reader->channel_id(channel));
            if (kind < 0) { for (int i = 0; i < 3; i++) if (!status[i]) status[i] = 4; return 0; }
            for (int i = 0; i < reader->catalog_count; i++) {
                if (reader->catalog[i].driver_id == reader->driver_id(channel) &&
                    reader->catalog[i].channel_id == reader->channel_id(channel)) {
                    if (coverage.seen[i]) { status[kind] = 4; return 0; }
                    coverage.seen[i] = 1; break;
                }
            }
            if (count >= capacity) { for (int i = 0; i < 3; i++) if (!status[i]) status[i] = 5; return 1; }
            int copied = copy_channel(reader, channel, kind, &out[count]);
            if (copied < 0) status[kind] = 5;
            if (copied > 0) { count++; coverage.by_kind[kind]++; }
            return 0;
        });
        CFRelease(sample);
        for (int i = 0; i < reader->catalog_count; i++)
            if (!coverage.seen[i] && !status[reader->catalog[i].kind]) status[reader->catalog[i].kind] = 4;
        for (int i = 0; i < 3; i++) if (!status[i] && !coverage.by_kind[i]) status[i] = 2;
        return count;
    }
    for (int kind = 0; kind < 3; kind++) {
        if (reader->status[kind]) continue;
        CFDictionaryRef sample = reader->samples(reader->subscriptions[kind], reader->channels[kind], NULL);
        if (!sample) { status[kind] = 4; continue; }
        int before = count;
        reader->iterate(sample, ^int(CFDictionaryRef channel) {
            if (count >= capacity) { status[kind] = 5; return 1; }
            int copied = copy_channel(reader, channel, kind, &out[count]);
            if (copied < 0) status[kind] = 5;
            if (copied > 0) count++;
            return 0;
        });
        CFRelease(sample);
        if (count == before && status[kind] == 0) status[kind] = 2;
    }
    return count;
}
