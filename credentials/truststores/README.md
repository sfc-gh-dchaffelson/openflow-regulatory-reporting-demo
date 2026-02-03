# Regulatory Authority Truststores

This directory is for CA certificates and truststores used to connect to European gambling regulatory authority websites.

## Overview

The SPCS OpenFlow runtime uses a default Java truststore that may not include CA certificates for European government websites. You must generate a custom truststore with the necessary certificates.

**Note:** Certificate files are not included in this repository. Follow the generation instructions below to create them.

## Files to Generate

| File | Purpose |
|------|---------|
| `regulatory_truststore.jks` | Combined JKS truststore for OpenFlow SSL Context Service |
| `regulatory_ca_bundle.pem` | Combined PEM bundle (all CA certificates) |

## Regulatory Domains Covered

| Country | Domain | CA Chain |
|---------|--------|----------|
| Spain | boe.es | FNMT-RCM |
| Denmark | spillemyndigheden.dk | Let's Encrypt |
| Italy | adm.gov.it | Let's Encrypt |
| France | anj.fr | Gandi -> USERTrust |
| Portugal | srij.turismodeportugal.pt | Sectigo -> USERTrust |
| Netherlands | kansspelautoriteit.nl | Sectigo |
| Malta | mga.org.mt | Google -> GlobalSign |
| Gibraltar | gibraltar.gov.gi | DigiCert |

## Usage in OpenFlow

### Option 1: Upload as Asset

Upload the truststore to your parameter context as an asset:

```bash
nipyapi --profile <profile> parameters upload_asset \
  --context_name "Fetch Regulatory References" \
  --asset_path credentials/truststores/regulatory_truststore.jks
```

### Option 2: Configure SSL Context Service

1. Create or edit an SSL Context Service in your flow
2. Set Truststore Filename to the asset path:
   ```
   /nifi/configuration_resources/assets/<context-id>/regulatory_truststore.jks
   ```
3. Set Truststore Password: `changeit`
4. Set Truststore Type: `JKS`

### Option 3: Use with InvokeHTTP

Configure the InvokeHTTP processor to use the SSL Context Service.

## Truststore Password

The JKS truststore uses the default password: `changeit`

## Generating the Truststore

Generate certificates for each regulatory domain you need to connect to:

```bash
cd credentials/truststores

# Extract certificate chain from a domain
extract_chain() {
  local domain=$1
  local alias=$2
  echo | openssl s_client -connect ${domain}:443 -servername ${domain} -showcerts 2>/dev/null | \
    awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > ${alias}_chain.pem
}

# Extract chains for required domains
extract_chain boe.es spain_boe
extract_chain spillemyndigheden.dk denmark_spille
extract_chain adm.gov.it italy_adm
extract_chain anj.fr france_anj
extract_chain srij.turismodeportugal.pt portugal_srij
extract_chain kansspelautoriteit.nl netherlands_ksa
extract_chain mga.org.mt malta_mga
extract_chain gibraltar.gov.gi gibraltar_gov

# Combine into PEM bundle
cat *_chain.pem > regulatory_ca_bundle.pem

# Create JKS truststore (import each chain)
for pem in *_chain.pem; do
  alias=$(basename $pem _chain.pem)
  keytool -importcert -noprompt -alias ${alias} -file ${pem} \
    -keystore regulatory_truststore.jks -storepass changeit 2>/dev/null || true
done
```

## Verifying the Truststore

Check the certificates in your truststore:

```bash
keytool -list -v -keystore regulatory_truststore.jks -storepass changeit | grep -A2 "Alias name"
```

## Security Notes

- This truststore is for **demo purposes** connecting to public government websites
- The `changeit` password is a Java default - use a secure password in production
- Truststore files are excluded from version control via `.gitignore`
- Regenerate certificates periodically as intermediate certificates may expire
