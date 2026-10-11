#include "AerieNative.h"
#include <mach/mach.h>
#include <mach/host_info.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <sys/proc_info.h>
#include <libproc.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/route.h>
#include <net/if_dl.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <time.h>
#include <IOKit/IOKitLib.h>
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <mach/mach_time.h>

int aerie_cpu(uint64_t *ticks, int capacity) {
    natural_t cores = 0; processor_info_array_t info = NULL; mach_msg_type_number_t count = 0;
    mach_port_t host = mach_host_self();
    kern_return_t result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (result != KERN_SUCCESS) return 0;
    int n = (int)cores < capacity ? (int)cores : capacity;
    for (int i = 0; i < n * CPU_STATE_MAX; i++) ticks[i] = (uint32_t)info[i];
    vm_deallocate(mach_task_self(), (vm_address_t)info, count * sizeof(integer_t));
    return n;
}

AerieMemory aerie_memory(void) {
    AerieMemory out = {0}; vm_statistics64_data_t stats = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT; mach_port_t host = mach_host_self();
    kern_return_t result = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&stats, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (result != KERN_SUCCESS) return out;
    size_t size = sizeof(out.total); sysctlbyname("hw.memsize", &out.total, &size, NULL, 0);
    uint64_t page = vm_kernel_page_size;
    out.free = stats.free_count * page; out.active = stats.active_count * page;
    out.inactive = stats.inactive_count * page; out.speculative = stats.speculative_count * page;
    out.wired = stats.wire_count * page; out.compressed = stats.compressor_page_count * page;
    out.purgeable = stats.purgeable_count * page; out.internal = stats.internal_page_count * page;
    out.external = stats.external_page_count * page;
    out.pageins = stats.pageins * page; out.pageouts = stats.pageouts * page;
    out.swapins = stats.swapins * page; out.swapouts = stats.swapouts * page;
    struct xsw_usage swap = {0}; size = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0) {
        out.swap_used = swap.xsu_used; out.swap_total = swap.xsu_total;
    }
    size = sizeof(out.pressure);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &out.pressure, &size, NULL, 0) != 0) out.pressure = -1;
    out.valid = 1; return out;
}

// Names/addresses are inventory; throughput counters are read on every sample.
static struct { unsigned index; AerieInterface value; } interface_inventory[256];
static int interface_inventory_count = 0;
static uint64_t interface_inventory_at = 0;
void aerie_interfaces_invalidate(void) { interface_inventory_at = 0; }
static uint64_t monotonic_ns(void) { return clock_gettime_nsec_np(CLOCK_MONOTONIC); }
static void refresh_interface_inventory(void) {
    struct ifaddrs *addresses = NULL;
    if (getifaddrs(&addresses) != 0) return;
    interface_inventory_count = 0;
    for (struct ifaddrs *a = addresses; a; a = a->ifa_next) {
        if (!a->ifa_addr || a->ifa_addr->sa_family != AF_LINK || interface_inventory_count >= 256) continue;
        struct sockaddr_dl *link = (struct sockaddr_dl *)a->ifa_addr;
        int i = interface_inventory_count++;
        memset(&interface_inventory[i], 0, sizeof(interface_inventory[i]));
        interface_inventory[i].index = link->sdl_index;
        strlcpy(interface_inventory[i].value.name, a->ifa_name, sizeof(interface_inventory[i].value.name));
    }
    for (struct ifaddrs *a = addresses; a; a = a->ifa_next) {
        if (!a->ifa_addr) continue;
        int family = a->ifa_addr->sa_family;
        if (family != AF_INET && family != AF_INET6) continue;
        char address[INET6_ADDRSTRLEN + 24] = {0};
        const void *bytes = family == AF_INET ? (const void *)&((struct sockaddr_in *)a->ifa_addr)->sin_addr
                                            : (const void *)&((struct sockaddr_in6 *)a->ifa_addr)->sin6_addr;
        if (!inet_ntop(family, bytes, address, sizeof(address))) continue;
        if (family == AF_INET6) {
            unsigned scope = ((struct sockaddr_in6 *)a->ifa_addr)->sin6_scope_id;
            if (scope) { char suffix[24]; snprintf(suffix, sizeof(suffix), "%%%u", scope); strlcat(address, suffix, sizeof(address)); }
        }
        for (int i = 0; i < interface_inventory_count; i++) if (strcmp(interface_inventory[i].value.name, a->ifa_name) == 0) {
            char *target = interface_inventory[i].value.addresses;
            if (target[0]) strlcat(target, ", ", sizeof(interface_inventory[i].value.addresses));
            strlcat(target, address, sizeof(interface_inventory[i].value.addresses));
            break;
        }
    }
    freeifaddrs(addresses); interface_inventory_at = monotonic_ns();
}
int aerie_interfaces(AerieInterface *out, int capacity) {
    if (!out || capacity <= 0) return 0;
    if (!interface_inventory_at || monotonic_ns() - interface_inventory_at >= 30000000000ULL) refresh_interface_inventory();
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0}; size_t size = 0;
    if (sysctl(mib, 6, NULL, &size, NULL, 0) != 0 || size > 16 * 1024 * 1024) return 0;
    char *data = malloc(size); if (!data) return 0;
    if (sysctl(mib, 6, data, &size, NULL, 0) != 0) { free(data); return 0; }
    int count = 0;
    for (char *cursor = data; cursor + sizeof(struct if_msghdr) <= data + size && count < capacity;) {
        struct if_msghdr *msg = (struct if_msghdr *)cursor;
        if (msg->ifm_msglen < sizeof(*msg) || cursor + msg->ifm_msglen > data + size) break;
        if (msg->ifm_type == RTM_IFINFO2 && msg->ifm_msglen >= sizeof(struct if_msghdr2)) {
            struct if_msghdr2 *m = (struct if_msghdr2 *)cursor;
            if (!(m->ifm_flags & IFF_LOOPBACK)) {
                int match = -1;
                for (int i = 0; i < interface_inventory_count; i++) if (interface_inventory[i].index == m->ifm_index) { match = i; break; }
                if (match < 0) {
                    refresh_interface_inventory();
                    for (int i = 0; i < interface_inventory_count; i++) if (interface_inventory[i].index == m->ifm_index) { match = i; break; }
                }
                if (match >= 0) {
                    AerieInterface *item = &out[count++]; *item = interface_inventory[match].value;
                    item->received = m->ifm_data.ifi_ibytes; item->sent = m->ifm_data.ifi_obytes;
                    item->packets_in = m->ifm_data.ifi_ipackets; item->packets_out = m->ifm_data.ifi_opackets;
                    item->errors_in = m->ifm_data.ifi_ierrors; item->errors_out = m->ifm_data.ifi_oerrors;
                    item->active = (m->ifm_flags & IFF_UP) && (m->ifm_flags & IFF_RUNNING);
                }
            }
        }
        cursor += msg->ifm_msglen;
    }
    free(data); return count;
}

AerieProcess aerie_process(int pid) {
    AerieProcess out = {0}; out.pid = pid;
    struct proc_bsdinfo bsd = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) == sizeof(bsd)) out.ppid = bsd.pbi_ppid;
    proc_name(pid, out.name, sizeof(out.name));
    struct rusage_info_v4 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) { out.error = errno; return out; }
    out.footprint = usage.ri_phys_footprint; out.resident = usage.ri_resident_size;
    // rusage CPU time uses Mach absolute units, which differ from nanoseconds on arm64.
    mach_timebase_info_data_t timebase; mach_timebase_info(&timebase);
    uint64_t absolute = usage.ri_user_time + usage.ri_system_time;
    out.cpu_ns = (uint64_t)((long double)absolute * timebase.numer / timebase.denom);
    out.wakeups = usage.ri_interrupt_wkups; out.disk_read = usage.ri_diskio_bytesread;
    out.disk_write = usage.ri_diskio_byteswritten; out.start_time = usage.ri_proc_start_abstime;
    out.valid = 1; return out;
}

int aerie_processes(AerieProcess *out, int capacity) {
    int size = proc_listallpids(NULL, 0);
    if (size <= 0 || size > 100000) return 0;
    int *pids = calloc(size + 64, sizeof(int)); if (!pids) return 0;
    int n = proc_listallpids(pids, (size + 64) * sizeof(int));
    int count = 0;
    for (int i = 0; i < n && count < capacity; i++) if (pids[i] > 0) out[count++] = aerie_process(pids[i]);
    free(pids); return count;
}

// Read-only SMC transport. Firmware keys are capabilities, not a stable OS API.
typedef struct { uint16_t version; uint16_t length; uint32_t cpu; uint32_t gpu; uint32_t memory; } SMCLimit;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCKeyInfo;
typedef struct {
    uint32_t key; uint8_t version[6]; SMCLimit limit; SMCKeyInfo info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} SMCData;
_Static_assert(sizeof(SMCData) == 80, "Unexpected SMC transport layout");
_Static_assert(offsetof(SMCData, bytes) == 48, "Unexpected SMC payload offset");
static io_connect_t smc = IO_OBJECT_NULL;
static struct { uint32_t key; SMCKeyInfo info; } smc_info_cache[4096];
static int smc_info_count = 0;
static uint32_t fourcc(const char *text) {
    return (uint32_t)(uint8_t)text[0] << 24 | (uint32_t)(uint8_t)text[1] << 16 |
           (uint32_t)(uint8_t)text[2] << 8 | (uint8_t)text[3];
}
static void unfourcc(uint32_t value, char *text) {
    for (int i = 0; i < 4; i++) text[i] = (char)(value >> (24 - 8 * i)); text[4] = 0;
}
static int smc_call(SMCData *in, SMCData *out) {
    if (!smc) return -1;
    size_t size = sizeof(*out); memset(out, 0, sizeof(*out));
    kern_return_t r = IOConnectCallStructMethod(smc, 2, in, sizeof(*in), out, &size);
    return r == KERN_SUCCESS && size == sizeof(*out) && out->result == 0 ? 0 : -1;
}
int aerie_smc_open(void) {
    if (smc) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t r = IOServiceOpen(service, mach_task_self(), 0, &smc); IOObjectRelease(service);
    return r == KERN_SUCCESS ? 0 : (int)r;
}
void aerie_smc_close(void) { if (smc) IOServiceClose(smc); smc = IO_OBJECT_NULL; smc_info_count = 0; }
int aerie_smc_source(const char *key, AerieSensorSource *source) {
    if (!key || strlen(key) != 4 || !source) return -1;
    SMCData in = {0}, out = {0}; in.key = fourcc(key); in.command = 9;
    int cached = 0;
    for (int i = 0; i < smc_info_count; i++) if (smc_info_cache[i].key == in.key) {
        in.info = smc_info_cache[i].info; cached = 1; break;
    }
    if (!cached) {
        if (smc_call(&in, &out) != 0 || out.info.size > 32 || !out.info.size) return -1;
        in.info = out.info;
        if (smc_info_count < 4096) {
            smc_info_cache[smc_info_count].key = in.key;
            smc_info_cache[smc_info_count++].info = in.info;
        }
    }
    source->key = in.key; source->type = in.info.type; source->size = in.info.size; return 0;
}
int aerie_smc_value(AerieSensorSource source, double *value) {
    if (!value || !source.size || source.size > 32) return -1;
    SMCData in = {0}, out = {0}; in.key = source.key; in.info.size = source.size; in.info.type = source.type; in.command = 5;
    if (smc_call(&in, &out) != 0) return -1;
    char type[5]; unfourcc(source.type, type);
    if (source.type == fourcc("sp78")) *value = (int16_t)((out.bytes[0] << 8) | out.bytes[1]) / 256.0;
    else if (source.type == fourcc("fpe2")) *value = ((out.bytes[0] << 8) | out.bytes[1]) / 4.0;
    else if (source.type == fourcc("flt ")) { float f; memcpy(&f, out.bytes, sizeof(f)); *value = f; }
    else if ((type[0] == 'f' || type[0] == 's') && type[1] == 'p' && source.size == 2) {
        char c = type[3]; int fractional = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1;
        if (fractional < 0) return -1;
        uint16_t raw = (out.bytes[0] << 8) | out.bytes[1];
        *value = (type[0] == 's' ? (int16_t)raw : (int)raw) / (double)(1U << fractional);
    } else if (source.type == fourcc("ui8 ")) *value = out.bytes[0];
    else if (source.type == fourcc("ui16")) *value = (out.bytes[0] << 8) | out.bytes[1];
    else if (source.type == fourcc("ui32")) *value = fourcc((const char *)out.bytes);
    else return -1;
    return 0;
}
int aerie_smc_read(const char *key, AerieSensor *sensor) {
    if (!sensor) return -1;
    AerieSensorSource source;
    if (aerie_smc_source(key, &source) != 0) return -1;
    memset(sensor, 0, sizeof(*sensor)); memcpy(sensor->key, key, 4); unfourcc(source.type, sensor->type);
    return aerie_smc_value(source, &sensor->value);
}

int aerie_smc_keys(char *keys, int capacity) {
    AerieSensor n = {0}; if (aerie_smc_read("#KEY", &n) != 0) return 0;
    int total = (int)n.value; if (total < 0 || total > 20000) return 0;
    int count = 0;
    for (int i = 0; i < total && count < capacity; i++) {
        SMCData in = {0}, out = {0}; in.command = 8; in.index = i;
        if (smc_call(&in, &out) == 0) unfourcc(out.key, keys + count++ * 5);
    }
    return count;
}
