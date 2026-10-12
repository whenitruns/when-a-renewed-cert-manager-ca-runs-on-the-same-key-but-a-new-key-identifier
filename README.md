# When a Renewed cert-manager CA Runs on the Same Key but a New Key Identifier — reproduction

When It Runs — Run Report #RR06 · Testing what infrastructure actually does.

Run Report: https://whenitruns.substack.com/p/when-a-renewed-cert-manager-ca-runs

This repository holds the reproduction from the report above: the step-1 manifest printed in its §4 (Reproduction), byte for byte, and the commands its §4 prints, run in order. Nothing here adds versions, configurations, or findings beyond the report.

## Setup pinned in the report

- cert-manager v1.18.6 to issue, installed from the official Helm chart `cert-manager-v1.18.6.tgz` from charts.jetstack.io with one non-default value, `crds.enabled=true`, so the chart installs the CRDs (chart default `false`). The 1.18 line is EOL (vendor-listed 2026-03-10); v1.18.6 is its latest patch — use a disposable test cluster.
- The controller is then upgraded in place to v1.19.6 → v1.20.4 → v1.21.2 — one minor at a time, each the minor's latest patch, with the same chart value; the renewal is measured on v1.21.2.
- A single-node `kind` cluster on a Linux test VM (GNU coreutils), node image `kindest/node:v1.33.4` (digest-pinned); `kubectl` within ±1 minor of the node.
- The renewal was triggered on v1.21.2 with `cmctl renew` (cmctl v2.6.1); the client was OpenSSL 3.0.13 (`openssl verify -show_chain -CAfile <store> <leaf>`).
- Verified on: 2026-09-24 (lab measurement, v1.18.6 → v1.21.2; desk sources re-confirmed 2026-09-14; the `go.mod` lines, PR #8480 and the latest release re-checked 2026-09-24) — re-verification against the then-current release happens at publication.

## Not scripted here

The report describes these without printing a command for them, so they are not scripted:

- a separate rollout and version check after each upgrade in step 3 — the printed `helm upgrade` lines wait (`--wait`);
- the comparisons in steps 2 and 5 — the Subject Key Identifier before and after the renewal, the pre-renewal leaf's Authority Key Identifier against the renewed CA's Subject Key Identifier, and the public-key fingerprint before and after;
- the optional clients named in step 6 (GnuTLS `certtool --verify`, Java keytool/PKIX, Go `crypto/x509` `Verify`) — the report ran `openssl verify` only.

## Files

| File | From the report |
|---|---|
| `step1-manifest.yaml` | §4 — the manifest for step 1, byte for byte |
| `reproduce.sh` | §4 — every line of its block, with the commands it prints, in order |

## Run order

On a disposable test host set up as pinned above (Docker, `kind`, `kubectl`, `helm`, `cmctl` and `openssl`), from a clone of this repository:

1. `./reproduce.sh all` — steps 0 to 7: create the `kind` cluster `rr06` and install cert-manager v1.18.6 with the CRDs, confirming the rollout; apply `step1-manifest.yaml` (the SelfSigned `Issuer`, the CA `Certificate`, the CA `Issuer`, the leaf `Certificate`) and wait for them to be Ready; RECORD #1, still on v1.18.6, with the SHA-1 and the truncated SHA-256 of the CA public key; upgrade in place to v1.19.6, v1.20.4 and v1.21.2; renew the CA with the same key and wait until its revision has changed and `Ready` is `True`; RECORD #2, with the same two hashes; the two trust stores and client verification of the pre-renewal leaf in each; remove the cluster.

## Expected observation

From the report (§3):

> CA Subject Key Identifier before (v1.18.6): `42b062a23924df0a7492534af9e3d64925be0106` (20 bytes) — equal to the SHA-1 of the CA's public key (the subjectPublicKey bit string), which we computed from the certificate itself.

> CA Subject Key Identifier after the renewal (v1.21.2): `9de807cf05452aca93f19f6f1ca515f1ceba4809` (20 bytes) — equal to the first 20 bytes of the SHA-256 of that same public key (the truncated SHA-256 form), and different from the value above.

> the pre-renewal leaf's Authority Key Identifier vs. the renewed CA's Subject Key Identifier: the leaf issued on v1.18.6 carries AKI `42b062a23924df0a7492534af9e3d64925be0106` — the old CA SKI — which does **not** match the renewed CA's SKI `9de807cf05452aca93f19f6f1ca515f1ceba4809`. The leaf itself carries no SKI.

> (a) Renewed CA alone: `error 20 at 0 depth lookup: unable to get local issuer certificate`, exit code 2. (b) Old CA + renewed CA bundled: `OK` (chain depth 1 `CN = rr06-ca`), exit code 0.

The report's own limits (§6):

> **Client behavior is not exhaustive.** We report only the clients and trust-store configurations we measured (the client-verification step). Whether a given library, language runtime, or middlebox builds the path by DN, by key identifier, or by trying alternates is a per-client question; "TLS verification breaks" is not a general claim of this report.

> **Out of measured scope:** other trust-store shapes, other key algorithms, and intermediate-CA topologies are not covered. The transit versions (v1.19.6, v1.20.4) and the first affected version (v1.19.0) are not measured for renewal behavior — v1.19.0 is read from `go.mod` only; the renewal is measured on v1.21.2.

---

The team behind When It Runs maintains its own test environments and re-verifies findings when new releases change things; that is what the "Verified on" date means.

Licensed under the Apache License 2.0 — see `LICENSE`.
