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
    int active;
} AerieInterface;
typedef struct {
    int pid, ppid, valid, error;
    char name[128];
    uint64_t footprint, resident, cpu_ns, wakeups, disk_read, disk_write, start_time;
} AerieProcess;
typedef struct { char key[5], type[5]; double value; } AerieSensor;
typedef struct { uint32_t key, type, size; } AerieSensorSource;
int aerie_cpu(uint64_t *ticks, int capacity);
AerieMemory aerie_memory(void);
int aerie_interfaces(AerieInterface *interfaces, int capacity);
void aerie_interfaces_invalidate(void);
int aerie_processes(AerieProcess *processes, int capacity);
AerieProcess aerie_process(int pid);
int aerie_smc_open(void);
int aerie_smc_keys(char *keys, int capacity);
int aerie_smc_read(const char *key, AerieSensor *sensor);
int aerie_smc_source(const char *key, AerieSensorSource *source);
int aerie_smc_value(AerieSensorSource source, double *value);
void aerie_smc_close(void);
#endif
