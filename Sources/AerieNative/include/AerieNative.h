#ifndef AERIE_NATIVE_H
#define AERIE_NATIVE_H
#include <stdint.h>
#include <stddef.h>
typedef struct {
    uint64_t total, free, active, inactive, speculative, wired, compressed, purgeable;
    uint64_t internal, external, pageins, pageouts, swapins, swapouts, swap_used, swap_total;
    int pressure, valid;
} AerieMemory;
typedef struct {
    char name[32], addresses[512];
    uint64_t received, sent, packets_in, packets_out, errors_in, errors_out;
    int active, counter_bits;
} AerieInterface;
typedef struct {
    unsigned index;
    char name[32];
    uint64_t received, sent, packets_in, packets_out, errors_in, errors_out;
    int active, counter_bits;
} AerieInterfaceCounter;
typedef struct {
    int pid, ppid, valid, error;
    char name[128];
    uint64_t footprint, resident, cpu_ns, wakeups, disk_read, disk_write, start_time, lifetime_peak_footprint;
} AerieProcess;
typedef struct { char key[5], type[5]; double value; } AerieSensor;
typedef struct { uint32_t key, type, size; } AerieSensorSource;
int aerie_cpu(uint64_t *ticks, int capacity);
AerieMemory aerie_memory(void);
int aerie_interfaces(AerieInterface *interfaces, int capacity);
// Decode a bounded native route snapshot; -1 denotes malformed input.
int aerie_interface_counters(const void *data, size_t size, AerieInterfaceCounter *out, int capacity);
int aerie_mib_interface_counters(const void *data, size_t size, AerieInterfaceCounter *out, int capacity);
void aerie_interfaces_invalidate(void);
int aerie_processes(AerieProcess *processes, int capacity);
AerieProcess aerie_process(int pid);
// Independent BSD birth identity, available even when resource accounting is denied.
uint64_t aerie_process_birth(int pid);
// Advises the current process allocator to release unused pages; never affects live allocations.
uint64_t aerie_release_unused_memory(uint64_t goal);
// Read-only executable path; reject a reused or unreadable resource identity.
int aerie_process_path(int pid, uint64_t expected_start, char *buffer, int capacity);
int aerie_smc_open(void);
int aerie_smc_keys(char *keys, int capacity);
int aerie_smc_read(const char *key, AerieSensor *sensor);
int aerie_smc_source(const char *key, AerieSensorSource *source);
// Pure bounded decoder for already-read payloads; no IOKit calls or unit/role inference.
int aerie_smc_decode(uint32_t type, const uint8_t *bytes, uint32_t size, double *value);
int aerie_smc_value(AerieSensorSource source, double *value);
void aerie_smc_close(void);
int aerie_network_spawn(const char *executable, const char *argument, int seconds, int *master, int *pid);
// Opaque, read-only platform clock-state subscriptions. No privileged helper or timer.
typedef struct AeriePerformance AeriePerformance;
typedef struct { int kind; uint64_t driver_id, channel_id; } AerieClockIdentity;
// Pure catalog checks: collision/unknown identities never acquire an inferred group.
int aerie_clock_catalog_valid(const AerieClockIdentity *catalog, int count);
int aerie_clock_catalog_kind(const AerieClockIdentity *catalog, int count, uint64_t driver, uint64_t channel);
typedef struct { char name[32]; uint64_t ticks; } AerieClockState;
typedef struct {
    int kind, state_count;
    uint64_t driver_id, channel_id;
    char name[64], unit[32];
    AerieClockState states[64];
} AerieClockChannel;
AeriePerformance *aerie_performance_create(void);
int aerie_performance_subscription_count(AeriePerformance *reader);
// kind: 0 CPU complexes, 1 CPU cores, 2 GPU. status: 0 readable, 1 library/symbol unavailable,
// 2 channel unavailable, 3 subscription unavailable, 4 sample unavailable, 5 bounded truncation.
int aerie_performance_read(AeriePerformance *reader, AerieClockChannel *out, int capacity, int status[3]);
void aerie_performance_close(AeriePerformance *reader);
#endif
