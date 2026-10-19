"""CI policy regressions. No build, network, credentials or Apple TV required."""
import importlib.util
import io
import json
import os
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("ci_validation", ROOT / "Scripts/ci_validation.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class ValidationTests(unittest.TestCase):
    def test_documentation_allowlist(self):
        for path in ["TESTING.md", "Docs/NEW.md", ".agents/skills/a/SKILL.md"]:
            self.assertTrue(policy.docs_only([path]))
        for path in ["Sources/App.swift", "Docs/tool.py", "new.md", "Info.plist",
                     "requirements.lock", "Distribution/ReleaseNotes/1.md",
                     ".github/workflows/ci.yml", "build.sh"]:
            self.assertFalse(policy.docs_only(["TESTING.md", path]))
        self.assertFalse(policy.docs_only([]))

    def test_identity_changes_invalidate(self):
        inputs = {"tree": "abc", "runner": "macos-26", "image": "1"}
        for key in inputs:
            self.assertNotEqual(policy.artifact_name(inputs),
                                policy.artifact_name(dict(inputs, **{key: "different"})))

    def evidence(self):
        inputs = {"tree": "abc"}
        run = {"id": 1, "status": "completed", "conclusion": "success",
               "path": ".github/workflows/ci.yml", "event": "pull_request",
               "head_repository": {"full_name": "owner/repo"},
               "head_commit": {"tree_id": "abc"}}
        artifact = {"expired": False, "name": policy.artifact_name(inputs)}
        proof = {"inputs": inputs, "run_id": "1", "kind": "full"}
        return inputs, run, artifact, proof

    def test_only_successful_matching_full_evidence(self):
        inputs, run, artifact, proof = self.evidence()
        accepts = lambda: policy.accepted_proof(run, artifact, proof, inputs, "owner/repo", "2")
        self.assertTrue(accepts())
        for field, value in [("conclusion", "failure"), ("conclusion", "cancelled"),
                             ("status", "in_progress"), ("path", "other.yml"),
                             ("event", "workflow_dispatch"), ("id", 2),
                             ("head_commit", {"tree_id": "forged"}),
                             ("head_repository", {"full_name": "fork/repo"})]:
            with patch.dict(run, {field: value}):
                self.assertFalse(accepts(), (field, value))
        for replacement in [{"inputs": inputs, "run_id": "1", "kind": "reuse"},
                            {"inputs": {"tree": "changed"}, "run_id": "1", "kind": "full"},
                            {"inputs": inputs, "run_id": "3", "kind": "full"}]:
            self.assertFalse(policy.accepted_proof(run, artifact, replacement, inputs, "owner/repo", "2"))
        with patch.dict(artifact, {"expired": True}):
            self.assertFalse(accepts())

    def test_missing_base_and_api_failure_fall_back_to_full(self):
        with tempfile.TemporaryDirectory() as temporary:
            original = Path.cwd()
            try:
                os.chdir(temporary)
                Path("event.json").write_text("{}")
                environment = {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/tags/v1",
                               "GITHUB_EVENT_PATH": "event.json", "GITHUB_OUTPUT": "out",
                               "GITHUB_STEP_SUMMARY": "summary"}
                with patch.dict(os.environ, environment), patch.object(policy, "identity", return_value={"tree": "abc"}), \
                        patch.object(policy, "reusable", side_effect=ValueError("bad evidence")), \
                        patch.object(policy.sys, "argv", ["policy"]):
                    policy.main()
                self.assertIn("mode=full", Path("out").read_text())
            finally:
                os.chdir(original)

    def test_diff_includes_both_sides_of_a_rename_and_deletions(self):
        with patch.object(policy, "command", return_value=b"Docs/old.md\0Scripts/new.py\0") as command:
            self.assertFalse(policy.docs_only(policy.changed_paths("base")))
            self.assertIn("--no-renames", command.call_args.args)

    def test_artifact_lookup_checks_run_source_and_archive(self):
        inputs, run, artifact, proof = self.evidence()
        inputs["image"] = "released-image-1"
        artifact.update(name=policy.artifact_name(inputs), id=4,
                        size_in_bytes=1000, workflow_run={"id": 1})
        run["html_url"] = "https://github.com/owner/repo/actions/runs/1"
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as zipped:
            zipped.writestr("validation.json", json.dumps(proof))
        environment = {"GITHUB_REPOSITORY": "owner/repo", "GITHUB_RUN_ID": "2"}
        with patch.dict(os.environ, environment), patch.object(policy, "api", side_effect=[
            {"artifacts": [artifact]}, run, archive.getvalue()
        ]):
            self.assertEqual(policy.reusable(inputs), run["html_url"])
        for key, value in [("expired", True), ("size_in_bytes", policy.LIMIT + 1)]:
            with patch.dict(os.environ, environment), patch.dict(artifact, {key: value}), \
                    patch.object(policy, "api", return_value={"artifacts": [artifact]}) as api:
                self.assertIsNone(policy.reusable(inputs))
                self.assertEqual(api.call_count, 1)

    def test_documentation_and_manual_modes(self):
        for event, paths, expected in [
            ("pull_request", ["TESTING.md"], "docs"),
            ("pull_request", ["TESTING.md", "Sources/App.swift"], "full"),
            ("workflow_dispatch", ["TESTING.md"], "full"),
        ]:
            with self.subTest(event=event, paths=paths), tempfile.TemporaryDirectory() as temporary:
                original = Path.cwd()
                try:
                    os.chdir(temporary)
                    payload = {"pull_request": {"base": {"sha": "base"}}} if event == "pull_request" else {}
                    Path("event.json").write_text(json.dumps(payload))
                    environment = {"GITHUB_EVENT_NAME": event, "GITHUB_REF": "refs/pull/1/merge",
                                   "GITHUB_EVENT_PATH": "event.json", "GITHUB_OUTPUT": "out",
                                   "GITHUB_STEP_SUMMARY": "summary"}
                    with patch.dict(os.environ, environment), \
                            patch.object(policy, "changed_paths", return_value=paths), \
                            patch.object(policy, "command", return_value=b""), \
                            patch.object(policy, "identity", return_value={"tree": "abc"}), \
                            patch.object(policy, "reusable", return_value=None) as reusable, \
                            patch.object(policy.sys, "argv", ["policy"]):
                        policy.main()
                    self.assertIn(f"mode={expected}", Path("out").read_text())
                    if event == "workflow_dispatch" or expected == "docs":
                        reusable.assert_not_called()
                finally:
                    os.chdir(original)


if __name__ == "__main__":
    unittest.main()
