#!/usr/bin/env bash
# Run Report #RR06, §4 (Reproduction). Every line of the report's §4 block appears below, in order and exactly as printed; each step
# then runs the commands its lines print. step1-manifest.yaml is the manifest §4 prints, byte for byte.
#   ./reproduce.sh all     steps 0 to 7, in order
# Per the report (§3), step 6(a) fails with exit code 2 and 6(b) succeeds: `set -uo pipefail` without `-e`, so the script does not
# stop on a non-zero exit.
set -uo pipefail
cd "$(dirname "$0")"

usage() { echo "usage: ./reproduce.sh all"; exit 2; }

step_0() {
# 0. Bring up a kind cluster (node k8s v1.33.4) on the test VM and install cert-manager v1.18.6
#    from the official Helm chart, with the CRDs (chart hash + image digests recorded; rollout
#    confirmed before any measurement):
#      kind create cluster --name rr06 --image kindest/node:v1.33.4@sha256:25a6018e48dfcaee478f4a59af81157a437f15e6e140bf103f85a2e7cd0cbbf2
#      helm install cert-manager https://charts.jetstack.io/charts/cert-manager-v1.18.6.tgz \
#        -n cert-manager --create-namespace --set crds.enabled=true --wait
#      for d in cert-manager cert-manager-webhook cert-manager-cainjector; do kubectl -n cert-manager rollout status "deploy/$d" --timeout=300s; done
kind create cluster --name rr06 --image kindest/node:v1.33.4@sha256:25a6018e48dfcaee478f4a59af81157a437f15e6e140bf103f85a2e7cd0cbbf2
helm install cert-manager https://charts.jetstack.io/charts/cert-manager-v1.18.6.tgz \
  -n cert-manager --create-namespace --set crds.enabled=true --wait
for d in cert-manager cert-manager-webhook cert-manager-cainjector; do kubectl -n cert-manager rollout status "deploy/$d" --timeout=300s; done
}

step_1() {
# 1. Create a SelfSigned Issuer, then a CA Certificate that re-uses one key across issuances
#    (Issuer: spec.selfSigned: {}; Certificate: spec.isCA: true, spec.privateKey.rotationPolicy: Never,
#    algorithm RSA size 2048, issuerRef -> the SelfSigned Issuer, secretName -> the CA secret).
#    Then a CA Issuer referencing that CA secret, and a leaf Certificate issued by the CA Issuer.
#      kubectl apply -f step1-manifest.yaml   # the manifest below, saved to this file
#      kubectl -n rr06 wait --for=condition=Ready certificate/rr06-ca --timeout=120s
#      kubectl -n rr06 wait --for=condition=Ready issuer/rr06-ca-issuer --timeout=120s
#      kubectl -n rr06 wait --for=condition=Ready certificate/leaf1 --timeout=120s
kubectl apply -f step1-manifest.yaml   # the manifest below, saved to this file
kubectl -n rr06 wait --for=condition=Ready certificate/rr06-ca --timeout=120s
kubectl -n rr06 wait --for=condition=Ready issuer/rr06-ca-issuer --timeout=120s
kubectl -n rr06 wait --for=condition=Ready certificate/leaf1 --timeout=120s
}

step_2() {
# 2. RECORD #1 (still on v1.18.6): the CA's Subject Key Identifier (SHA-1, 20 bytes) and public key,
#    the leaf's Authority Key Identifier (== the CA SKI above), and the CA public-key fingerprint (SPKI SHA-256).
#      kubectl -n rr06 get secret rr06-ca-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > ca-1_v1.18.6.pem
#      kubectl -n rr06 get secret leaf1-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > leaf1-1_v1.18.6.pem
#      openssl x509 -in ca-1_v1.18.6.pem -noout -subject -issuer -serial -ext subjectKeyIdentifier,authorityKeyIdentifier
#      openssl x509 -in ca-1_v1.18.6.pem -noout -pubkey | openssl pkey -pubin -outform DER | sha256sum   # CA public-key fingerprint (SPKI SHA-256)
#      openssl x509 -in ca-1_v1.18.6.pem -noout -pubkey | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null | sha1sum   # SHA-1 of the public key (the subjectPublicKey bit string)
#      openssl x509 -in ca-1_v1.18.6.pem -noout -pubkey | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null | sha256sum | cut -c1-40   # the first 20 bytes of its SHA-256
#      openssl x509 -in leaf1-1_v1.18.6.pem -noout -subject -issuer -serial -ext subjectKeyIdentifier,authorityKeyIdentifier
kubectl -n rr06 get secret rr06-ca-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > ca-1_v1.18.6.pem
kubectl -n rr06 get secret leaf1-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > leaf1-1_v1.18.6.pem
openssl x509 -in ca-1_v1.18.6.pem -noout -subject -issuer -serial -ext subjectKeyIdentifier,authorityKeyIdentifier
openssl x509 -in ca-1_v1.18.6.pem -noout -pubkey | openssl pkey -pubin -outform DER | sha256sum   # CA public-key fingerprint (SPKI SHA-256)
openssl x509 -in ca-1_v1.18.6.pem -noout -pubkey | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null | sha1sum   # SHA-1 of the public key (the subjectPublicKey bit string)
openssl x509 -in ca-1_v1.18.6.pem -noout -pubkey | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null | sha256sum | cut -c1-40   # the first 20 bytes of its SHA-256
openssl x509 -in leaf1-1_v1.18.6.pem -noout -subject -issuer -serial -ext subjectKeyIdentifier,authorityKeyIdentifier
}

step_3() {
# 3. Upgrade cert-manager IN PLACE, one minor at a time, each the latest patch, per the vendor guidance:
#    v1.18.6 -> v1.19.6 -> v1.20.4 -> v1.21.2
#      helm upgrade cert-manager https://charts.jetstack.io/charts/cert-manager-v1.19.6.tgz \
#        -n cert-manager --set crds.enabled=true --wait
#      helm upgrade cert-manager https://charts.jetstack.io/charts/cert-manager-v1.20.4.tgz \
#        -n cert-manager --set crds.enabled=true --wait
#      helm upgrade cert-manager https://charts.jetstack.io/charts/cert-manager-v1.21.2.tgz \
#        -n cert-manager --set crds.enabled=true --wait
#    (confirm rollout + version at each step; no renewal, no assertions on the transit versions.)
helm upgrade cert-manager https://charts.jetstack.io/charts/cert-manager-v1.19.6.tgz \
  -n cert-manager --set crds.enabled=true --wait
helm upgrade cert-manager https://charts.jetstack.io/charts/cert-manager-v1.20.4.tgz \
  -n cert-manager --set crds.enabled=true --wait
helm upgrade cert-manager https://charts.jetstack.io/charts/cert-manager-v1.21.2.tgz \
  -n cert-manager --set crds.enabled=true --wait
}

step_4() {
# 4. On v1.21.2, RENEW the CA Certificate with the same key (rotationPolicy: Never keeps the key):
#    trigger an in-place renewal of the CA Certificate and wait for it to complete: the revision has
#    changed and Ready is True (at most 120 one-second reads).
#      rev0=$(kubectl -n rr06 get certificate rr06-ca -o jsonpath='{.status.revision}'); echo "CA revision before: $rev0"
#      cmctl renew -n rr06 rr06-ca
#      for i in $(seq 1 120); do rev=$(kubectl -n rr06 get certificate rr06-ca -o jsonpath='{.status.revision}'); rdy=$(kubectl -n rr06 get certificate rr06-ca -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'); [ "$rev" != "$rev0" ] && [ "$rdy" = True ] && break; sleep 1; done
#      echo "CA revision after: $rev (Ready=$rdy)"
rev0=$(kubectl -n rr06 get certificate rr06-ca -o jsonpath='{.status.revision}'); echo "CA revision before: $rev0"
cmctl renew -n rr06 rr06-ca
for i in $(seq 1 120); do rev=$(kubectl -n rr06 get certificate rr06-ca -o jsonpath='{.status.revision}'); rdy=$(kubectl -n rr06 get certificate rr06-ca -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'); [ "$rev" != "$rev0" ] && [ "$rdy" = True ] && break; sleep 1; done
echo "CA revision after: $rev (Ready=$rdy)"
}

step_5() {
# 5. RECORD #2 (on v1.21.2, after the renewal): the CA's Subject Key Identifier now, compared to RECORD #1;
#    the CA public-key fingerprint, compared to RECORD #1 (expected unchanged); and the pre-renewal leaf's
#    Authority Key Identifier, compared to the renewed CA's Subject Key Identifier.
#      kubectl -n rr06 get secret rr06-ca-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > ca-2_v1.21.2_renewed.pem
#      openssl x509 -in ca-2_v1.21.2_renewed.pem -noout -subject -issuer -serial -ext subjectKeyIdentifier,authorityKeyIdentifier
#      openssl x509 -in ca-2_v1.21.2_renewed.pem -noout -pubkey | openssl pkey -pubin -outform DER | sha256sum   # CA public-key fingerprint (SPKI SHA-256)
#      openssl x509 -in ca-2_v1.21.2_renewed.pem -noout -pubkey | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null | sha1sum   # SHA-1 of the public key (the subjectPublicKey bit string)
#      openssl x509 -in ca-2_v1.21.2_renewed.pem -noout -pubkey | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null | sha256sum | cut -c1-40   # the first 20 bytes of its SHA-256
kubectl -n rr06 get secret rr06-ca-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > ca-2_v1.21.2_renewed.pem
openssl x509 -in ca-2_v1.21.2_renewed.pem -noout -subject -issuer -serial -ext subjectKeyIdentifier,authorityKeyIdentifier
openssl x509 -in ca-2_v1.21.2_renewed.pem -noout -pubkey | openssl pkey -pubin -outform DER | sha256sum   # CA public-key fingerprint (SPKI SHA-256)
openssl x509 -in ca-2_v1.21.2_renewed.pem -noout -pubkey | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null | sha1sum   # SHA-1 of the public key (the subjectPublicKey bit string)
openssl x509 -in ca-2_v1.21.2_renewed.pem -noout -pubkey | openssl rsa -pubin -RSAPublicKey_out -outform DER 2>/dev/null | sha256sum | cut -c1-40   # the first 20 bytes of its SHA-256
}

step_6() {
# 6. CLIENT VERIFICATION of the pre-renewal leaf, in two trust stores:
#    (a) the renewed CA alone;   (b) the old CA + the renewed CA, bundled.
#    Required client (path that reads AKI/SKI): openssl verify. OpenSSL's issuer test, in addition to
#    matching the issuer DN, compares the sub-fields of the subject's authorityKeyIdentifier (keyid,
#    serial, issuer) against the issuer's subjectKeyIdentifier, serial number, and issuer when present
#    (X509_check_issued(3)). Optional, recorded without a path classification: GnuTLS certtool --verify,
#    Java keytool/PKIX, Go crypto/x509 Verify. Client names, versions, and trust-store file hashes: our lab record.
#      cp ca-2_v1.21.2_renewed.pem store-a_renewed-CA-only.pem
#      cat ca-1_v1.18.6.pem ca-2_v1.21.2_renewed.pem > store-b_old-CA+renewed-CA.pem
#      openssl verify -show_chain -CAfile store-a_renewed-CA-only.pem leaf1-1_v1.18.6.pem   # (a)
#      openssl verify -show_chain -CAfile store-b_old-CA+renewed-CA.pem leaf1-1_v1.18.6.pem   # (b)
cp ca-2_v1.21.2_renewed.pem store-a_renewed-CA-only.pem
cat ca-1_v1.18.6.pem ca-2_v1.21.2_renewed.pem > store-b_old-CA+renewed-CA.pem
openssl verify -show_chain -CAfile store-a_renewed-CA-only.pem leaf1-1_v1.18.6.pem   # (a)
openssl verify -show_chain -CAfile store-b_old-CA+renewed-CA.pem leaf1-1_v1.18.6.pem   # (b)
}

step_7() {
# 7. Tear down (the test cluster only).
#      kind delete cluster --name rr06
kind delete cluster --name rr06
}

case "${1:-}" in
  all) step_0; step_1; step_2; step_3; step_4; step_5; step_6; step_7 ;;
  *) usage ;;
esac
