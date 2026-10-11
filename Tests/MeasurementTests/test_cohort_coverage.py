import copy
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "scripts"))
from cohort_coverage import service_fields, service_table, validate_cohort


class CohortCoverageTests(unittest.TestCase):
    def setUp(self):
        # A synthetic app, four direct services, and four nested services.
        self.readings = [{"pid": pid, "startTime": pid * 100,
                          "bsdBirth": pid * 1000, "status": "live",
                          "footprintBytes": 1024, "cpuPercent": 1,
                          "interruptWakeupsPerSecond": 2, "shared": False}
                         for pid in range(10, 19)]
        self.roots = [self.readings[0]]
        children = {10: [11, 12, 14, 18], 12: [13], 14: [15, 16, 17]}
        self.probes = []
        for value in self.readings:
            owner = {key: value[key] for key in ("pid", "startTime", "bsdBirth")}
            self.probes.append({"ownerIdentity": owner, "ownerIdentityAfter": owner.copy(),
                                "identityReadable": True, "returnCode": 0,
                                "tableParsed": True, "observedMonotonic": 100,
                                "verifiedServices": [
                                    {**self.readings[pid - 10], "domainOwner": value["pid"],
                                     "type": "XPCService", "service": "com.example.Synthetic"}
                                    for pid in children.get(value["pid"], [])]})

    def check(self, **changes):
        arguments = dict(readings=self.readings, roots=self.roots, probes=self.probes, now=101)
        arguments.update(changes)
        return validate_cohort(**arguments)

    def assert_incomplete(self, result):
        self.assertFalse(result["knownCohortComplete"])
        for metric in result["metrics"].values():
            self.assertFalse(metric["completeKnownCohort"])
            self.assertIsNone(metric["total"])

    def test_all_nine_distinct_recursive_members_are_counted_once(self):
        result = self.check()
        self.assertTrue(result["knownCohortComplete"])
        self.assertEqual(result["metrics"]["physicalBytes"]["total"], 9 * 1024)

    def test_root_only_and_direct_only_discovery_cannot_claim_completeness(self):
        self.assert_incomplete(self.check(probes=self.probes[:1]))
        self.assert_incomplete(self.check(probes=[p for p in self.probes
                                                 if p["ownerIdentity"]["pid"] in (10, 11, 12, 14, 18)]))

    def test_missing_nested_reading_is_never_zero(self):
        result = self.check(readings=self.readings[:-2] + self.readings[-1:])
        self.assert_incomplete(result)
        self.assertEqual(result["metrics"]["physicalBytes"]["observedSubtotal"], 8 * 1024)

    def test_duplicate_identity_cannot_double_the_sum(self):
        result = self.check(readings=self.readings + [self.readings[0]])
        self.assert_incomplete(result)
        self.assertIsNone(result["metrics"]["physicalBytes"]["observedSubtotal"])

    def test_namespace_visibility_in_another_owner_domain_is_not_affiliation(self):
        self.probes[0]["verifiedServices"][0]["domainOwner"] = 999
        self.assert_incomplete(self.check())

    def test_pid_reuse_and_bsd_identity_changes_invalidate_proof(self):
        self.probes[0]["ownerIdentityAfter"]["startTime"] += 1
        self.assert_incomplete(self.check())
        self.setUp()
        self.probes[0]["ownerIdentityAfter"]["bsdBirth"] += 1
        self.assert_incomplete(self.check())

    def test_unreadable_shared_and_ambiguous_ownership_are_incomplete(self):
        self.readings[2]["status"] = "unreadable"
        self.assert_incomplete(self.check())
        self.setUp()
        self.readings[2]["shared"] = True
        self.assert_incomplete(self.check())
        self.setUp()
        service = copy.deepcopy(self.probes[0]["verifiedServices"][0])
        service["domainOwner"] = 12
        self.probes[2]["verifiedServices"].append(service)
        self.assert_incomplete(self.check())

    def test_missing_or_old_proof_and_candidate_read_failure_are_incomplete(self):
        self.assert_incomplete(self.check(probes=[]))
        self.assert_incomplete(self.check(now=107))
        self.assert_incomplete(self.check(now=99))
        self.probes[0]["unverifiedCandidates"] = ["com.example.Unreadable"]
        self.assert_incomplete(self.check())

    def test_discovery_gaps_capacity_drops_and_earlier_lifetimes_are_incomplete(self):
        self.assert_incomplete(self.check(gaps=[17]))
        self.assert_incomplete(self.check(historical_gaps=[17]))
        for flag in ("ownerLimit", "enumerationAtCapacity", "logQueueDrops", "logStreamExited"):
            self.assert_incomplete(self.check(flags={flag: True}))

    def test_metric_failure_and_first_rate_baseline_withhold_only_affected_totals(self):
        self.readings[3]["cpuPercent"] = None
        result = self.check()
        self.assertTrue(result["knownCohortComplete"])
        self.assertEqual(result["metrics"]["physicalBytes"]["total"], 9 * 1024)
        self.assertIsNone(result["metrics"]["cpuPercentOneCore"]["total"])
        self.readings[3]["footprintBytes"] = None
        self.assertIsNone(self.check()["metrics"]["physicalBytes"]["total"])

    def test_terminated_root_cannot_become_a_zero_memory_idle_pass(self):
        self.readings[0]["status"] = "exited-confirmed"
        self.readings[0]["footprintBytes"] = 0
        self.assert_incomplete(self.check())

    def test_legacy_probe_without_process_identity_is_not_upgraded(self):
        for probe in self.probes:
            probe.pop("ownerIdentity")
            probe.pop("ownerIdentityAfter")
        self.assert_incomplete(self.check())

    def test_nonfinite_negative_and_boolean_metrics_are_not_complete(self):
        for value in (float("nan"), float("inf"), -1, True):
            self.readings[0]["footprintBytes"] = value
            self.assertIsNone(self.check()["metrics"]["physicalBytes"]["total"])

    def test_nested_environment_cannot_supply_identity_or_escape_parser(self):
        text = """pid/10/com.example.Synthetic = {
\tactive count = 1
\ttype = XPCService
\tdomain = pid/10 [fixture]
\tpid = 11
\tenvironment = {
\t\ttype = unrelated
\t\tdomain = pid/999
\t\tpid = 999
\t\tFixtureValue = synthetic
\t}
}"""
        self.assertEqual(service_fields(text), {"type": "XPCService",
                                               "domain": "pid/10 [fixture]", "pid": "11"})
        self.assertNotIn("FixtureValue", str(service_fields(text)))
        self.assertEqual(service_fields("""service = {
\tenvironment = {
\t\ttype = XPCService
\t\tdomain = pid/999
\t\tpid = 999
\t}
}"""), {})

    def test_service_table_requires_complete_top_level_structure(self):
        text = "pid/10 = {\n\tservices = {\n\t\t11 0 com.example.Child\n\t\t0 - com.example.Stopped\n\t}\n}"
        self.assertEqual(service_table(text), [{"pid": 11, "service": "com.example.Child"}])
        self.assertEqual(service_table("pid/10 = {\n\tservices = {\n\t}\n}"), [])
        self.assertIsNone(service_table(text.replace("11 0", "unexpected row 11 0")))
        self.assertIsNone(service_table(text.replace("\n\t}\n}", "")))
        self.assertIsNone(service_table("pid/10 = {\n\tenvironment = {\n\t\tservices = {\n\t\t\t11 0 com.example.Child\n\t\t}\n\t}\n}"))


if __name__ == "__main__":
    unittest.main()
