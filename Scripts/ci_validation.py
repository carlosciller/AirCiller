"""Select CI work and reuse only successful, identical full-check evidence.

Uses GitHub's read-only API through gh. Missing or invalid evidence means a full
check, never acceptance. No media, device access, secrets or app artifacts.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import zipfile

DOC_FILES = frozenset({
    "AGENTS.md", "README.md", "CHANGELOG.md", "CONTRIBUTING.md",
    "TESTING.md", "DISTRIBUTION.md", "ROADMAP.md", "SECURITY.md",
    "CODE_OF_CONDUCT.md",
    "ARCHITECTURE.md", "COMPATIBILITY.md", "PRIVACY.md",
})
LIMIT = 65536


def command(*args):
    return subprocess.check_output(args, timeout=30)


def docs_only(paths):
    # Explicit prose locations only. New scripts, assets, release notes,
    # renames to code and unknown paths require the full gate.
    return bool(paths) and all(
        path in DOC_FILES or (
            path.endswith(".md") and path.startswith(("Docs/", ".agents/"))
        ) for path in paths
    )


def changed_paths(base):
    return command("git", "diff", "--no-renames", "--name-only", "-z",
                   base, "HEAD").decode().strip("\0").split("\0")


def identity():
    return {
        "schema": 1,
        "tree": command("git", "rev-parse", "HEAD^{tree}").decode().strip(),
        "runner": os.environ["CI_RUNNER"],
        "image": os.environ.get("ImageVersion", "unknown"),
        "os": command("sw_vers").decode().strip(),
        "xcode": command("xcodebuild", "-version").decode().strip(),
        "swift": command("xcrun", "swiftc", "--version").decode().strip(),
        "python": sys.version,
        "node": command("node", "--version").decode().strip(),
        "architecture": command("uname", "-m").decode().strip(),
    }


def artifact_name(inputs):
    digest = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
    return "full-check-" + digest


def api(path, binary=False):
    data = command("gh", "api", path)
    return data if binary else json.loads(data)


def accepted_proof(run, artifact, proof, inputs, repository, current_run):
    return (
        str(run.get("id")) != str(current_run)
        and run.get("status") == "completed"
        and run.get("conclusion") == "success"
        and run.get("path") == ".github/workflows/ci.yml"
        and run.get("event") in {"push", "pull_request"}
        and run.get("head_repository", {}).get("full_name") == repository
        and run.get("head_commit", {}).get("tree_id") == inputs["tree"]
        and not artifact.get("expired", True)
        and artifact.get("name") == artifact_name(inputs)
        and proof == {"inputs": inputs, "run_id": str(run["id"]), "kind": "full"}
    )


def reusable(inputs):
    if inputs.get("image") in {None, "unknown", ""}:
        return None
    repository = os.environ["GITHUB_REPOSITORY"]
    name = artifact_name(inputs)
    artifacts = api(f"repos/{repository}/actions/artifacts?name={name}&per_page=5")
    for artifact in artifacts["artifacts"]:
        if artifact.get("expired", True) or not 0 < artifact.get("size_in_bytes", 0) <= LIMIT:
            continue
        run_id = artifact["workflow_run"]["id"]
        run = api(f"repos/{repository}/actions/runs/{run_id}")
        if run.get("conclusion") != "success" or run.get("status") != "completed":
            continue
        archive = api(f"repos/{repository}/actions/artifacts/{artifact['id']}/zip", True)
        if len(archive) > LIMIT:
            continue
        with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
            if zipped.namelist() != ["validation.json"]:
                continue
            if zipped.getinfo("validation.json").file_size > LIMIT:
                continue
            proof = json.loads(zipped.read("validation.json"))
        if accepted_proof(run, artifact, proof, inputs, repository, os.environ["GITHUB_RUN_ID"]):
            return run["html_url"]
    return None


def output(name, value):
    with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
        stream.write(f"{name}={value}\n")


def main():
    if sys.argv[1:] == ["record"]:
        inputs = json.loads(Path(".build/ci-inputs.json").read_text())
        proof = {"inputs": inputs, "run_id": os.environ["GITHUB_RUN_ID"], "kind": "full"}
        Path(".build/validation.json").write_text(json.dumps(proof, sort_keys=True))
        return
    event = os.environ["GITHUB_EVENT_NAME"]
    payload = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    base = payload.get("pull_request", {}).get("base", {}).get("sha")
    if event == "push" and os.environ["GITHUB_REF"] == "refs/heads/main":
        base = payload.get("before")
    mode, reason = "full", "No matching successful evidence; run the full local suite."
    # Tags and manual diagnostics always need full or identical full evidence.
    try:
        if base and docs_only(changed_paths(base)):
            command("git", "diff", "--check", base, "HEAD")
            mode, reason = "docs", "Only allowlisted documentation changed."
    except (subprocess.SubprocessError, UnicodeError):
        pass
    if mode != "docs":
        inputs = identity()
        Path(".build").mkdir(exist_ok=True)
        Path(".build/ci-inputs.json").write_text(json.dumps(inputs, sort_keys=True))
        output("artifact", artifact_name(inputs))
        if event != "workflow_dispatch":
            try:
                previous = reusable(inputs)
                if previous:
                    mode, reason = "reuse", f"Identical full-check inputs: {previous}"
            except (subprocess.SubprocessError, ValueError, KeyError, TypeError, AttributeError,
                    zipfile.BadZipFile, OSError):
                reason = "Evidence unavailable or invalid; run the full local suite."
    output("mode", mode)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
        stream.write(f"## Validation selection\n\nMode: **{mode}**\n\n{reason}\n")
    print(f"Validation: {mode}. {reason}")


if __name__ == "__main__":
    main()
