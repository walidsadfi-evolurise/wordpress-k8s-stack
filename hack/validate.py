#!/usr/bin/env python3
"""Strict schema validation of every manifest against the Kubernetes OpenAPI spec.

Same idea as kubeconform, without the binary: resolve each document's
apiVersion/kind to its definition via x-kubernetes-group-version-kind and
validate with additionalProperties=false injected, so a typo in a field name
fails instead of being silently ignored by the API server's pruning.

Usage: hack/validate.py path/to/swagger.json file-or-dir...
CRDs (ExternalSecret…) are skipped with a notice; kustomization.yaml and
strategic-merge patches are checked for YAML validity only.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml
import warnings

warnings.filterwarnings("ignore", category=DeprecationWarning)
from jsonschema import Draft4Validator, RefResolver  # noqa: E402

SKIP_KINDS = {"Kustomization"}


def load_spec(path: Path) -> tuple[dict, dict[tuple[str, str], str]]:
    spec = json.loads(path.read_text())
    index: dict[tuple[str, str], str] = {}
    for name, d in spec["definitions"].items():
        for gvk in d.get("x-kubernetes-group-version-kind", []):
            api = f"{gvk['group']}/{gvk['version']}" if gvk["group"] else gvk["version"]
            index[(api, gvk["kind"])] = name
    return spec, index


def strict(schema: object) -> object:
    """Recursively forbid unknown properties (except on open objects like labels/data)."""
    if isinstance(schema, dict):
        out = {k: strict(v) for k, v in schema.items()}
        if out.get("type") == "object" and "properties" in out and "additionalProperties" not in out:
            out["additionalProperties"] = False
        return out
    if isinstance(schema, list):
        return [strict(v) for v in schema]
    return schema


def main(argv: list[str]) -> int:
    spec_path, *targets = argv
    spec, index = load_spec(Path(spec_path))
    strict_defs = {k: strict(v) for k, v in spec["definitions"].items()}
    # IntOrString is declared as a string with format int-or-string; accept both like the API server does.
    strict_defs["io.k8s.apimachinery.pkg.util.intstr.IntOrString"] = {"oneOf": [{"type": "string"}, {"type": "integer"}]}
    root = {"definitions": strict_defs}
    resolver = RefResolver.from_schema(root)

    files: list[Path] = []
    for t in targets:
        p = Path(t)
        files.extend(sorted(p.rglob("*.yaml")) if p.is_dir() else [p])

    errors = 0
    checked = skipped = 0
    for f in files:
        is_patch = "patch" in f.name
        for i, doc in enumerate(yaml.safe_load_all(f.read_text())):
            if not doc:
                continue
            kind, api = doc.get("kind"), doc.get("apiVersion")
            if kind in SKIP_KINDS or is_patch:
                skipped += 1
                continue
            key = (api, kind)
            if key not in index:
                print(f"skip  {f}:{i} {api}/{kind} (not in core spec — CRD?)")
                skipped += 1
                continue
            schema = {"$ref": f"#/definitions/{index[key]}"}
            v = Draft4Validator(schema, resolver=resolver)
            errs = sorted(v.iter_errors(doc), key=lambda e: list(e.path))
            checked += 1
            for e in errs:
                errors += 1
                path = ".".join(str(x) for x in e.path) or "<root>"
                print(f"ERROR {f}:{i} {kind}/{doc.get('metadata', {}).get('name')} at {path}: {e.message}")
    print(f"validated {checked} resources, skipped {skipped}, {errors} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
