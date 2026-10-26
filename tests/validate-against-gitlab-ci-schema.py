#!/usr/bin/env python3
"""Validate every pipeline file in this repo against GitLab's official CI JSON schema.

The schema is gitlab-org/gitlab app/assets/javascripts/editor/schema/ci.json, the one
the GitLab pipeline editor uses. Pass its local path as the first argument:

  curl -fsSL -o ci.json https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json
  tests/validate-against-gitlab-ci-schema.py ci.json [extra-file.yml ...]

Component files have two YAML documents (`spec:` header, `---`, body). The schema
describes a pipeline, so the body is validated with it; the header is checked for the
`spec: inputs:` shape, because the schema does not describe it.
Extra files (for example pipelines produced by gitlab-ci-local --preview) are
validated as plain pipelines.
"""
import json
import pathlib
import sys

import yaml
from jsonschema import Draft7Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
PIPELINE_GLOBS = [
    ".gitlab-ci.yml",
    "auto-pipeline.yml",
    "jobs/*.yml",
    "child-pipelines/*.yml",
    "dynamic/*.yml",
    "examples/*.yml",
]
COMPONENT_GLOB = "templates/*/template.yml"


class GitLabLoader(yaml.SafeLoader):
    """SafeLoader that accepts GitLab's custom `!reference [job, key]` tag."""


GitLabLoader.add_constructor("!reference", lambda loader, node: loader.construct_sequence(node))


def load_documents(path: pathlib.Path) -> list:
    return [doc for doc in yaml.load_all(path.read_text(), Loader=GitLabLoader) if doc is not None]


def schema_errors(validator: Draft7Validator, document: object) -> list[str]:
    return [
        f"{'/'.join(str(p) for p in err.absolute_path) or '<root>'}: {err.message[:200]}"
        for err in sorted(validator.iter_errors(document), key=lambda e: list(e.absolute_path))
    ]


def check_component_spec(spec_doc: object) -> list[str]:
    problems = []
    if not isinstance(spec_doc, dict) or set(spec_doc) != {"spec"}:
        return ["first document must contain only the `spec:` key"]
    inputs = spec_doc["spec"].get("inputs")
    if not isinstance(inputs, dict) or not inputs:
        return ["spec.inputs must be a non-empty mapping"]
    for name, definition in inputs.items():
        if not isinstance(definition, dict):
            problems.append(f"input {name}: must be a mapping")
            continue
        unknown = set(definition) - {"default", "description", "type", "options", "regex"}
        if unknown:
            problems.append(f"input {name}: unknown keys {sorted(unknown)}")
        if "default" not in definition:
            problems.append(f"input {name}: no default (every input of this component is optional)")
    return problems


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    validator = Draft7Validator(json.loads(pathlib.Path(sys.argv[1]).read_text()))
    failures = 0

    def report(label: str, problems: list[str]) -> None:
        nonlocal failures
        if problems:
            failures += 1
            print(f"FAIL {label}")
            for problem in problems:
                print(f"     {problem}")
        else:
            print(f"ok   {label}")

    files = [p for pattern in PIPELINE_GLOBS for p in sorted(ROOT.glob(pattern))]
    files += [pathlib.Path(a) for a in sys.argv[2:]]
    for path in files:
        docs = load_documents(path)
        report(str(path), schema_errors(validator, docs[0]) if len(docs) == 1 else [f"expected 1 YAML document, found {len(docs)}"])

    for path in sorted(ROOT.glob(COMPONENT_GLOB)):
        docs = load_documents(path)
        if len(docs) != 2:
            report(str(path), [f"expected 2 YAML documents (spec, ---, body), found {len(docs)}"])
            continue
        report(f"{path} (spec header)", check_component_spec(docs[0]))
        report(f"{path} (body)", schema_errors(validator, docs[1]))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
