#!/bin/bash

set -e

CERT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$CERT_DIR"

echo "Generating TeamX local certificates..."

# Generate Root CA private key
openssl genrsa -out rootCA.key 4096

# Generate Root CA certificate
openssl req -x509 -new -nodes \
  -key rootCA.key \
  -sha256 \
  -days 3650 \
  -out rootCA.pem \
  -config ca.cnf

# Generate server private key
openssl genrsa -out server.key 2048

# Generate server certificate signing request
openssl req -new \
  -key server.key \
  -out server.csr \
  -config leaf.cnf

# Sign the server certificate with the Root CA
openssl x509 -req \
  -in server.csr \
  -CA rootCA.pem \
  -CAkey rootCA.key \
  -CAcreateserial \
  -out server.crt \
  -days 825 \
  -sha256 \
  -extfile leaf.cnf \
  -extensions req_ext

echo
echo "Certificate generation completed."
echo
echo "Generated files:"
echo "  rootCA.pem"
echo "  server.crt"
echo
echo "Private keys and temporary certificate files should NOT be committed."