#include "AerieNative.h"
#include <mach/mach.h>
#include <mach/host_info.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <sys/proc_info.h>
#include <libproc.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_mib.h>
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
int aerie_interface_counters(const void *data, size_t size, AerieInterfaceCounter *out, int capacity) {
    if (!data || !out || capacity <= 0 || size > 16 * 1024 * 1024) return -1;
    const unsigned char *bytes = data; size_t offset = 0; int count = 0;
    // All route messages share only length, version and type. Address messages
    // are shorter than if_msghdr and must be skipped without ending enumeration.
    while (offset < size) {
        if (size - offset < 4) return -1;
        uint16_t length; memcpy(&length, bytes + offset, sizeof(length));
        uint8_t version = bytes[offset + 2], type = bytes[offset + 3];
        if (length < 4 || length > size - offset || version != RTM_VERSION) return -1;
        if (type == RTM_IFINFO2) {
            if (length < sizeof(struct if_msghdr2)) return -1;
            struct if_msghdr2 m; memcpy(&m, bytes + offset, sizeof(m));
            if (!(m.ifm_flags & IFF_LOOPBACK)) {
                if (count >= capacity) return -1;
                AerieInterfaceCounter *item = &out[count++]; memset(item, 0, sizeof(*item));
                item->index = m.ifm_index; item->counter_bits = 32;
                item->received = m.ifm_data.ifi_ibytes; item->sent = m.ifm_data.ifi_obytes;
                item->packets_in = m.ifm_data.ifi_ipackets; item->packets_out = m.ifm_data.ifi_opackets;
                item->errors_in = m.ifm_data.ifi_ierrors; item->errors_out = m.ifm_data.ifi_oerrors;
                item->active = (m.ifm_flags & IFF_UP) && (m.ifm_flags & IFF_RUNNING);
            }
        }
        offset += length;
    }
    return count;
}
int aerie_mib_interface_counters(const void *data, size_t size, AerieInterfaceCounter *out, int capacity) {
    if (!data || !out || capacity <= 0 || size > 16 * 1024 * 1024 || size % sizeof(struct ifmibdata)) return -1;
    const unsigned char *bytes = data; int count = 0;
    for (size_t offset = 0; offset < size; offset += sizeof(struct ifmibdata)) {
        struct ifmibdata m; memcpy(&m, bytes + offset, sizeof(m));
        if (!memchr(m.ifmd_name, 0, sizeof(m.ifmd_name))) return -1;
        if (!m.ifmd_name[0] || (m.ifmd_flags & IFF_LOOPBACK)) continue;
        if (count >= capacity) return -1;
        AerieInterfaceCounter *item = &out[count++]; memset(item, 0, sizeof(*item));
        strlcpy(item->name, m.ifmd_name, sizeof(item->name)); item->counter_bits = 64;
        item->received = m.ifmd_data.ifi_ibytes; item->sent = m.ifmd_data.ifi_obytes;
        item->packets_in = m.ifmd_data.ifi_ipackets; item->packets_out = m.ifmd_data.ifi_opackets;
        item->errors_in = m.ifmd_data.ifi_ierrors; item->errors_out = m.ifmd_data.ifi_oerrors;
        item->active = (m.ifmd_flags & IFF_UP) && (m.ifmd_flags & IFF_RUNNING);
    }
    return count;
}
static int read_interface_counters(AerieInterfaceCounter *records, int capacity) {
    // The public interface MIB preserves cumulative 64-bit counters. Route
    // snapshots can be OS-rounded/truncated for ordinary applications.
    int mib[] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFALLDATA, 0, IFDATA_GENERAL};
    size_t size = 0; int decoded = -1;
    if (sysctl(mib, 6, NULL, &size, NULL, 0) == 0 && size && size <= 16 * 1024 * 1024) {
        void *data = malloc(size);
        if (data && sysctl(mib, 6, data, &size, NULL, 0) == 0) decoded = aerie_mib_interface_counters(data, size, records, capacity);
        free(data);
    }
    if (decoded >= 0) return decoded;
    int route[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0}; size = 0;
    if (sysctl(route, 6, NULL, &size, NULL, 0) != 0 || !size || size > 16 * 1024 * 1024) return -1;
    void *data = malloc(size); if (!data) return -1;
    if (sysctl(route, 6, data, &size, NULL, 0) == 0) decoded = aerie_interface_counters(data, size, records, capacity);
    free(data); return decoded;
}
int aerie_interfaces(AerieInterface *out, int capacity) {
    if (!out || capacity <= 0) return -1;
    if (!interface_inventory_at || monotonic_ns() - interface_inventory_at >= 30000000000ULL) refresh_interface_inventory();
    AerieInterfaceCounter records[256]; int decoded = read_interface_counters(records, 256);
    if (decoded < 0 || decoded > capacity) return -1;
    int count = 0;
    for (int r = 0; r < decoded; r++) {
        AerieInterfaceCounter *record = &records[r]; int match = -1;
        for (int attempt = 0; attempt < 2 && match < 0; attempt++) {
            for (int i = 0; i < interface_inventory_count; i++) {
                if (record->name[0] ? strcmp(interface_inventory[i].value.name, record->name) == 0 : interface_inventory[i].index == record->index) { match = i; break; }
            }
            if (match < 0) refresh_interface_inventory();
        }
        if (match < 0) return -1;
        AerieInterface *item = &out[count++]; *item = interface_inventory[match].value;
        item->received = record->received; item->sent = record->sent;
        item->packets_in = record->packets_in; item->packets_out = record->packets_out;
        item->errors_in = record->errors_in; item->errors_out = record->errors_out;
        item->active = record->active; item->counter_bits = record->counter_bits;
    }
    return count;
}

uint64_t aerie_process_birth(int pid) {
    struct proc_bsdinfo bsd = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) return 0;
    return (uint64_t)bsd.pbi_start_tvsec * 1000000 + bsd.pbi_start_tvusec;
}

AerieProcess aerie_process(int pid) {
    AerieProcess out = {0}; out.pid = pid;
    struct proc_bsdinfo bsd = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) == sizeof(bsd)) out.ppid = bsd.pbi_ppid;
    proc_name(pid, out.name, sizeof(out.name));
    struct rusage_info_v4 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) { out.error = errno; return out; }
    out.footprint = usage.ri_phys_footprint; out.resident = usage.ri_resident_size;
    out.lifetime_peak_footprint = usage.ri_lifetime_max_phys_footprint;
    // rusage CPU time uses Mach absolute units, which differ from nanoseconds on arm64.
    mach_timebase_info_data_t timebase; mach_timebase_info(&timebase);
    uint64_t absolute = usage.ri_user_time + usage.ri_system_time;
    out.cpu_ns = (uint64_t)((long double)absolute * timebase.numer / timebase.denom);
    out.wakeups = usage.ri_interrupt_wkups; out.disk_read = usage.ri_diskio_bytesread;
    out.disk_write = usage.ri_diskio_byteswritten; out.start_time = usage.ri_proc_start_abstime;
    out.valid = 1; return out;
}

int aerie_process_path(int pid, uint64_t expected_start, char *buffer, int capacity) {
    if (pid <= 0 || expected_start == 0 || !buffer || capacity != PROC_PIDPATHINFO_MAXSIZE) return 0;
    memset(buffer, 0, (size_t)capacity);
    int length = proc_pidpath(pid, buffer, (uint32_t)capacity);
    if (length <= 0 || length >= capacity || !buffer[0]) { buffer[0] = 0; return 0; }
    AerieProcess current = aerie_process(pid);
    if (!current.valid || current.start_time != expected_start) { buffer[0] = 0; return 0; }
    buffer[capacity - 1] = 0;
    return length;
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

// An app-owned temporary terminal lets the OS logger flush each CSV update.
#include <util.h>
#include <termios.h>
#include <fcntl.h>

#include <sys/wait.h>
#include <signal.h>
// forkpty establishes the child's isolated controlling terminal before exec.
// Only async-signal-safe operations run in the child; no Cocoa code is entered.
int aerie_network_spawn(const char *executable, const char *argument, int seconds, int *master, int *pid) {
    if (!master || !pid || !executable || seconds < 1 || seconds > 60) return EINVAL;
    *master = *pid = -1;
    char interval[16]; snprintf(interval, sizeof(interval), "%d", seconds);
    char *logger_args[] = {(char *)executable, "-P", "-L", "0", "-n", "-x", "-s", interval, "-J", "bytes_in,bytes_out", NULL};
    char *fixture_args[] = {(char *)executable, (char *)argument, NULL};
    char *environment[] = {"PATH=/usr/bin:/bin", "LC_ALL=C", NULL};
    pid_t child = forkpty(master, NULL, NULL, NULL);
    if (child < 0) return errno;
    if (child == 0) {
        sigset_t mask; sigemptyset(&mask); sigprocmask(SIG_SETMASK, &mask, NULL);
        signal(SIGHUP, SIG_DFL); signal(SIGTERM, SIG_DFL); signal(SIGPIPE, SIG_DFL);
        int null = open("/dev/null", O_WRONLY);
        if (null >= 0) { dup2(null, STDERR_FILENO); if (null != STDERR_FILENO) close(null); }
        execve(executable, argument ? fixture_args : logger_args, environment);
        _exit(127);
    }
    if (fcntl(*master, F_SETFL, O_NONBLOCK) < 0 || fcntl(*master, F_SETFD, FD_CLOEXEC) < 0) {
        int error = errno; close(*master); kill(child, SIGKILL); waitpid(child, NULL, 0); *master = -1; return error;
    }
    *pid = child; return 0;
}
