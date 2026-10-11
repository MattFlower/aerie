"""Fail-closed validation of a bounded, recursively verified process cohort.

This certifies the recorded known cohort, never unobserved transient processes or
instantaneous peaks. Inputs contain identities and proof fields, not environment
values or user content. The observer must retain proof and discovery failures.
"""
import math
import re


def service_fields(text):
    """Read only top-level identity fields; never return inherited environment."""
    lines = text.splitlines()
    properties = [(len(line) - len(line.lstrip()), line.strip()) for line in lines
                  if re.match(r"^\s+[^=]+ = ", line)]
    if not properties:
        return {}
    indent = min(size for size, line in properties)
    fields = {}
    for size, line in properties:
        if size != indent:
            continue
        key, value = line.split(" = ", 1)
        if key in ("domain", "type", "pid"):
            fields[key] = value
    return fields


def service_table(text):
    """Return running candidates only when the complete top-level table parses."""
    lines = text.splitlines()
    properties = [(len(line) - len(line.lstrip()), index, line.strip())
                  for index, line in enumerate(lines) if re.match(r"^\s+[^=]+ = ", line)]
    if not properties:
        return None
    indent = min(size for size, index, line in properties)
    tables = [index for size, index, line in properties
              if size == indent and line == "services = {"]
    if len(tables) != 1:
        return None
    candidates = []
    for line in lines[tables[0] + 1:]:
        size = len(line) - len(line.lstrip())
        if size == indent and line.strip() == "}":
            return candidates
        if not line.strip():
            continue
        row = re.fullmatch(r"\s*(\d+|-)\s+\S+\s+([A-Za-z0-9_.-]+)\s*", line)
        if not row or size <= indent:
            return None
        pid = 0 if row[1] == "-" else int(row[1])
        if pid:
            candidates.append({"pid": pid, "service": row[2]})
    return None


def identity(value):
    return (value.get("pid"), value.get("startTime", value.get("kernelStart")),
            value.get("bsdBirth"))


def validate_cohort(readings, roots, probes, now, *, max_probe_age=6,
                    gaps=(), historical_gaps=(), flags=None):
    issues = []
    by_id = {}
    for reading in readings:
        key = identity(reading)
        if key in by_id:
            issues.append("duplicate process identity")
        by_id[key] = reading
    duplicate = bool(issues)
    live = {key: value for key, value in by_id.items()
            if value.get("status") != "exited-confirmed"}
    if not roots:
        issues.append("no verified roots")
    root_ids = set(map(identity, roots))
    for key in root_ids:
        if key not in live or live[key].get("status") != "live":
            issues.append("root is not running and readable")
    for key, value in live.items():
        if not all(isinstance(x, int) and not isinstance(x, bool) and x > 0 for x in key):
            issues.append("unverified process start identity")
        if value.get("shared"):
            issues.append("shared ownership unresolved")
    proof_by_owner = {}
    for probe in probes:
        owner = identity(probe.get("ownerIdentity", {}))
        if owner in proof_by_owner:
            issues.append("duplicate owner proof")
        proof_by_owner[owner] = probe
    linked = set(root_ids)
    queue = list(root_ids)
    registered_owners = {}
    while queue:
        owner = queue.pop()
        probe = proof_by_owner.get(owner)
        if probe is None:
            issues.append("missing recursive owner proof")
            continue
        age = now - probe.get("observedMonotonic", float("-inf"))
        if not 0 <= age <= max_probe_age:
            issues.append("stale or future owner proof")
        if (not probe.get("identityReadable") or probe.get("returnCode") != 0
                or not probe.get("tableParsed")
                or identity(probe.get("ownerIdentityAfter", {})) != owner):
            issues.append("owner probe failed or identity changed")
        if probe.get("unverifiedCandidates"):
            issues.append("service candidate verification failed")
        for service in probe.get("verifiedServices", []):
            child = identity(service)
            if service.get("domainOwner") != owner[0] or service.get("type") != "XPCService":
                issues.append("service visibility does not establish ownership")
                continue
            owners = registered_owners.setdefault(child, set())
            owners.add(owner)
            if len(owners) > 1:
                issues.append("helper registered to multiple owners")
            if child in root_ids or child == owner:
                issues.append("cyclic ownership")
            if child not in live or live[child].get("status") != "live":
                issues.append("owned helper missing or unreadable")
            elif child not in linked:
                linked.add(child)
                queue.append(child)
    if set(live) != linked:
        issues.append("unrooted or undiscovered known members")
    if gaps or historical_gaps:
        issues.append("known affiliation or earlier-lifetime gap")
    if any((flags or {}).values()):
        issues.append("observer coverage failure")
    issues = sorted(set(issues))
    covered = not issues
    metrics = {}
    for field, label in (("footprintBytes", "physicalBytes"),
                         ("cpuPercent", "cpuPercentOneCore"),
                         ("interruptWakeupsPerSecond", "interruptWakeupsPerSecond")):
        available = [value[field] for value in readings
                     if isinstance(value.get(field), (int, float))
                     and not isinstance(value.get(field), bool)
                     and math.isfinite(value[field]) and value[field] >= 0]
        readable = bool(readings) and len(available) == len(readings)
        complete = covered and readable
        metrics[label] = {
            "completeKnownCohort": complete,
            "total": sum(available) if complete else None,
            "observedSubtotal": sum(available) if available and not duplicate else None,
        }
    return {"protocol": 2, "scope": "recorded known recursive cohort",
            "knownCohortComplete": covered, "issues": issues, "metrics": metrics,
            "limitation": "Polling does not establish unobserved transient or instantaneous peaks."}
