/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.example.nifi.processors.dgoj;

import eu.europa.esig.dss.enumerations.DigestAlgorithm;
import eu.europa.esig.dss.enumerations.SignatureAlgorithm;
import eu.europa.esig.dss.enumerations.SignatureLevel;
import eu.europa.esig.dss.enumerations.SignaturePackaging;
import eu.europa.esig.dss.model.DSSDocument;
import eu.europa.esig.dss.model.InMemoryDocument;
import eu.europa.esig.dss.model.SignatureValue;
import eu.europa.esig.dss.model.ToBeSigned;
import eu.europa.esig.dss.model.x509.CertificateToken;
import eu.europa.esig.dss.xades.XAdESSignatureParameters;
import eu.europa.esig.dss.xades.signature.XAdESService;
import eu.europa.esig.dss.validation.CommonCertificateVerifier;
import net.lingala.zip4j.io.outputstream.ZipOutputStream;
import net.lingala.zip4j.model.ZipParameters;
import net.lingala.zip4j.model.enums.AesKeyStrength;
import net.lingala.zip4j.model.enums.CompressionMethod;
import net.lingala.zip4j.model.enums.EncryptionMethod;
import org.bouncycastle.asn1.pkcs.PrivateKeyInfo;
import org.bouncycastle.asn1.pkcs.RSAPrivateKey;
import org.bouncycastle.openssl.PEMKeyPair;
import org.bouncycastle.openssl.PEMParser;
import org.bouncycastle.openssl.jcajce.JcaPEMKeyConverter;
import org.bouncycastle.openssl.jcajce.JceOpenSSLPKCS8DecryptorProviderBuilder;
import org.bouncycastle.operator.InputDecryptorProvider;
import org.bouncycastle.pkcs.PKCS8EncryptedPrivateKeyInfo;
import org.apache.nifi.annotation.behavior.InputRequirement;
import org.apache.nifi.annotation.behavior.SideEffectFree;
import org.apache.nifi.annotation.behavior.SupportsBatching;
import org.apache.nifi.annotation.behavior.WritesAttribute;
import org.apache.nifi.annotation.behavior.WritesAttributes;
import org.apache.nifi.annotation.documentation.CapabilityDescription;
import org.apache.nifi.annotation.documentation.Tags;
import org.apache.nifi.components.AllowableValue;
import org.apache.nifi.components.PropertyDescriptor;
import org.apache.nifi.expression.ExpressionLanguageScope;
import org.apache.nifi.flowfile.FlowFile;
import org.apache.nifi.processor.AbstractProcessor;
import org.apache.nifi.processor.ProcessContext;
import org.apache.nifi.processor.ProcessSession;
import org.apache.nifi.processor.Relationship;
import org.apache.nifi.processor.exception.ProcessException;
import org.apache.nifi.processor.util.StandardValidators;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.Base64;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * NiFi processor for Spanish DGOJ regulatory compliance.
 *
 * Performs:
 * 1. XAdES-BES 1.3.2 digital signature (RSA-SHA256)
 * 2. ZIP compression (Deflate)
 * 3. AES-256 encryption (WinZip-compatible)
 */
@Tags({"xml", "signature", "encryption", "xades", "regulatory", "dgoj", "spain", "xades-bes", "aes"})
@CapabilityDescription("Signs XML with XAdES-BES, compresses with ZIP/Deflate, and encrypts with AES-256 " +
        "for Spanish DGOJ regulatory compliance (BOE-A-2024-12639).")
@SupportsBatching
@SideEffectFree
@InputRequirement(InputRequirement.Requirement.INPUT_REQUIRED)
@WritesAttributes({
        @WritesAttribute(attribute = "mime.type", description = "Set to application/zip after successful encryption"),
        @WritesAttribute(attribute = "dgoj.signed", description = "Set to true after successful XAdES-BES signature"),
        @WritesAttribute(attribute = "dgoj.encrypted", description = "Set to true after successful AES-256 encryption"),
        @WritesAttribute(attribute = "dgoj.signature.method", description = "The signature packaging method used (enveloped or enveloping)")
})
public class DgojXadesProcessor extends AbstractProcessor {

    // Constants
    private static final int BUFFER_SIZE = 8192;
    private static final String PEM_HEADER_PREFIX = "-----BEGIN";

    // Allowable values for signature method
    public static final AllowableValue ENVELOPED = new AllowableValue(
            "enveloped", "Enveloped", "Signature is embedded within the XML document");
    public static final AllowableValue ENVELOPING = new AllowableValue(
            "enveloping", "Enveloping", "XML is wrapped inside the signature");

    // Property Descriptors - Dual input mode: file path OR PEM content for each credential

    // Certificate - File path mode (non-sensitive, can reference assets)
    public static final PropertyDescriptor CERTIFICATE_PATH = new PropertyDescriptor.Builder()
            .name("Certificate Path")
            .displayName("Certificate Path")
            .description("File path to X.509 certificate (.pem or .crt) for XAdES-BES signature. " +
                    "Use this for asset-based workflows. Mutually exclusive with 'Certificate' property.")
            .required(false)
            .sensitive(false)
            .addValidator(StandardValidators.NON_EMPTY_VALIDATOR)
            .expressionLanguageSupported(ExpressionLanguageScope.FLOWFILE_ATTRIBUTES)
            .build();

    // Certificate - PEM content mode (sensitive, for secrets manager)
    public static final PropertyDescriptor CERTIFICATE = new PropertyDescriptor.Builder()
            .name("Certificate")
            .displayName("Certificate")
            .description("X.509 certificate as PEM content (must start with '-----BEGIN CERTIFICATE-----'). " +
                    "Use this for AWS Secrets Manager integration via External Parameter Provider. " +
                    "Mutually exclusive with 'Certificate Path' property.")
            .required(false)
            .sensitive(true)
            .addValidator(StandardValidators.NON_EMPTY_VALIDATOR)
            .expressionLanguageSupported(ExpressionLanguageScope.FLOWFILE_ATTRIBUTES)
            .build();

    // Private Key - File path mode (non-sensitive, can reference assets)
    public static final PropertyDescriptor PRIVATE_KEY_PATH = new PropertyDescriptor.Builder()
            .name("Private Key Path")
            .displayName("Private Key Path")
            .description("File path to private key (.pem) for XAdES-BES signature. " +
                    "Use this for asset-based workflows. Mutually exclusive with 'Private Key' property.")
            .required(false)
            .sensitive(false)
            .addValidator(StandardValidators.NON_EMPTY_VALIDATOR)
            .expressionLanguageSupported(ExpressionLanguageScope.FLOWFILE_ATTRIBUTES)
            .build();

    // Private Key - PEM content mode (sensitive, for secrets manager)
    public static final PropertyDescriptor PRIVATE_KEY = new PropertyDescriptor.Builder()
            .name("Private Key")
            .displayName("Private Key")
            .description("Private key as PEM content (must start with '-----BEGIN'). " +
                    "Use this for AWS Secrets Manager integration via External Parameter Provider. " +
                    "Mutually exclusive with 'Private Key Path' property.")
            .required(false)
            .sensitive(true)
            .addValidator(StandardValidators.NON_EMPTY_VALIDATOR)
            .expressionLanguageSupported(ExpressionLanguageScope.FLOWFILE_ATTRIBUTES)
            .build();

    public static final PropertyDescriptor PRIVATE_KEY_PASSWORD = new PropertyDescriptor.Builder()
            .name("Private Key Password")
            .displayName("Private Key Password")
            .description("Password to decrypt the private key file (if encrypted). Leave empty if key is not encrypted.")
            .required(false)
            .sensitive(true)
            .addValidator(StandardValidators.NON_BLANK_VALIDATOR)
            .expressionLanguageSupported(ExpressionLanguageScope.FLOWFILE_ATTRIBUTES)
            .build();

    public static final PropertyDescriptor ZIP_PASSWORD = new PropertyDescriptor.Builder()
            .name("ZIP Encryption Password")
            .displayName("ZIP Encryption Password")
            .description("50-character password for AES-256 ZIP encryption. " +
                    "Must contain digits, letters, and special characters (#, $, &, !).")
            .required(true)
            .sensitive(true)
            .addValidator(StandardValidators.NON_EMPTY_VALIDATOR)
            .expressionLanguageSupported(ExpressionLanguageScope.FLOWFILE_ATTRIBUTES)
            .build();

    public static final PropertyDescriptor SIGNATURE_METHOD = new PropertyDescriptor.Builder()
            .name("Signature Method")
            .displayName("Signature Method")
            .description("XAdES signature method: 'enveloped' embeds signature in XML, " +
                    "'enveloping' creates separate signature file")
            .required(true)
            .allowableValues(ENVELOPED, ENVELOPING)
            .defaultValue(ENVELOPED.getValue())
            .build();

    public static final PropertyDescriptor XML_FILENAME = new PropertyDescriptor.Builder()
            .name("XML Filename")
            .displayName("XML Filename")
            .description("Filename to use for the XML file inside the ZIP (e.g., 'lote.xml' or 'enveloped.xml')")
            .required(true)
            .defaultValue("enveloped.xml")
            .addValidator(StandardValidators.NON_EMPTY_VALIDATOR)
            .expressionLanguageSupported(ExpressionLanguageScope.FLOWFILE_ATTRIBUTES)
            .build();

    // Relationships
    public static final Relationship REL_SUCCESS = new Relationship.Builder()
            .name("success")
            .description("FlowFiles that are successfully signed, compressed, and encrypted")
            .build();

    public static final Relationship REL_FAILURE = new Relationship.Builder()
            .name("failure")
            .description("FlowFiles that failed processing")
            .build();

    private static final List<PropertyDescriptor> PROPERTY_DESCRIPTORS = List.of(
            CERTIFICATE_PATH,
            CERTIFICATE,
            PRIVATE_KEY_PATH,
            PRIVATE_KEY,
            PRIVATE_KEY_PASSWORD,
            ZIP_PASSWORD,
            SIGNATURE_METHOD,
            XML_FILENAME
    );

    private static final Set<Relationship> RELATIONSHIPS = Set.of(REL_SUCCESS, REL_FAILURE);

    @Override
    public Set<Relationship> getRelationships() {
        return RELATIONSHIPS;
    }

    @Override
    public List<PropertyDescriptor> getSupportedPropertyDescriptors() {
        return PROPERTY_DESCRIPTORS;
    }

    @Override
    public void onTrigger(ProcessContext context, ProcessSession session) throws ProcessException {
        FlowFile flowFile = session.get();
        if (flowFile == null) {
            return;
        }

        try {
            // Read XML content from FlowFile
            byte[] xmlContent = readFlowFileContent(session, flowFile);

            // Get property values - dual input mode: path OR PEM content
            String certPath = context.getProperty(CERTIFICATE_PATH)
                    .evaluateAttributeExpressions(flowFile).getValue();
            String certPem = context.getProperty(CERTIFICATE)
                    .evaluateAttributeExpressions(flowFile).getValue();
            String keyPath = context.getProperty(PRIVATE_KEY_PATH)
                    .evaluateAttributeExpressions(flowFile).getValue();
            String keyPem = context.getProperty(PRIVATE_KEY)
                    .evaluateAttributeExpressions(flowFile).getValue();
            String keyPassword = context.getProperty(PRIVATE_KEY_PASSWORD)
                    .evaluateAttributeExpressions(flowFile).getValue();
            String zipPassword = context.getProperty(ZIP_PASSWORD)
                    .evaluateAttributeExpressions(flowFile).getValue();
            String signatureMethod = context.getProperty(SIGNATURE_METHOD).getValue();
            String xmlFilename = context.getProperty(XML_FILENAME)
                    .evaluateAttributeExpressions(flowFile).getValue();

            // Resolve certificate: prefer path if set, otherwise use PEM content
            String certValue = resolveDualInput(certPath, certPem, "Certificate");
            // Resolve private key: prefer path if set, otherwise use PEM content
            String keyValue = resolveDualInput(keyPath, keyPem, "Private Key");

            // Step 1: Sign XML with XAdES-BES
            getLogger().debug("Signing XML with XAdES-BES signature method: {}", signatureMethod);
            byte[] signedXml = signXml(xmlContent, certValue, keyValue, keyPassword, signatureMethod);

            // Step 2: Create ZIP with AES-256 encryption
            getLogger().debug("Creating encrypted ZIP with AES-256");
            byte[] zipContent = createEncryptedZip(signedXml, xmlFilename, zipPassword);

            // Write result to FlowFile
            flowFile = session.write(flowFile, out -> out.write(zipContent));

            // Update attributes
            flowFile = session.putAttribute(flowFile, "mime.type", "application/zip");
            flowFile = session.putAttribute(flowFile, "dgoj.signed", "true");
            flowFile = session.putAttribute(flowFile, "dgoj.encrypted", "true");
            flowFile = session.putAttribute(flowFile, "dgoj.signature.method", signatureMethod);

            session.transfer(flowFile, REL_SUCCESS);

        } catch (Exception e) {
            getLogger().error("Failed to prepare regulatory file: {}", e.getMessage(), e);
            flowFile = session.putAttribute(flowFile, "error.message", e.getMessage());
            session.transfer(flowFile, REL_FAILURE);
        }
    }

    /**
     * Resolve dual input mode: returns path if set, otherwise PEM content.
     * Throws if neither is provided.
     */
    private String resolveDualInput(String pathValue, String pemValue, String propertyName) {
        boolean hasPath = pathValue != null && !pathValue.trim().isEmpty();
        boolean hasPem = pemValue != null && !pemValue.trim().isEmpty();

        if (hasPath && hasPem) {
            getLogger().warn("{} Path and {} (PEM) both provided; using {} Path",
                    propertyName, propertyName, propertyName);
            return pathValue;
        } else if (hasPath) {
            return pathValue;
        } else if (hasPem) {
            return pemValue;
        } else {
            throw new IllegalArgumentException(
                    "Either '" + propertyName + " Path' or '" + propertyName + "' must be provided");
        }
    }

    /**
     * Read FlowFile content into byte array.
     */
    private byte[] readFlowFileContent(ProcessSession session, FlowFile flowFile) {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        session.read(flowFile, in -> {
            byte[] buffer = new byte[BUFFER_SIZE];
            int bytesRead;
            while ((bytesRead = in.read(buffer)) != -1) {
                baos.write(buffer, 0, bytesRead);
            }
        });
        return baos.toByteArray();
    }

    /**
     * Sign XML content using XAdES-BES signature.
     */
    private byte[] signXml(byte[] xmlContent, String certValue, String keyValue,
                           String keyPassword, String method) throws Exception {

        // Load certificate and private key
        X509Certificate certificate = loadCertificate(certValue);
        PrivateKey privateKey = loadPrivateKey(keyValue, keyPassword);

        // Create signature parameters
        XAdESSignatureParameters parameters = new XAdESSignatureParameters();
        parameters.setSignatureLevel(SignatureLevel.XAdES_BASELINE_B);
        parameters.setSignaturePackaging(
                "enveloped".equals(method) ? SignaturePackaging.ENVELOPED : SignaturePackaging.ENVELOPING
        );
        parameters.setDigestAlgorithm(DigestAlgorithm.SHA256);

        // Set signing certificate
        CertificateToken certToken = new CertificateToken(certificate);
        parameters.setSigningCertificate(certToken);

        // Create the XAdES service
        CommonCertificateVerifier certificateVerifier = new CommonCertificateVerifier();
        XAdESService service = new XAdESService(certificateVerifier);

        // Create document to sign
        DSSDocument documentToSign = new InMemoryDocument(xmlContent, "document.xml");

        // Get data to sign
        ToBeSigned dataToSign = service.getDataToSign(documentToSign, parameters);

        // Sign the data using RSA-SHA256 (per BOE specification)
        SignatureValue signatureValue = signData(dataToSign, privateKey);

        // Create signed document
        DSSDocument signedDocument = service.signDocument(documentToSign, parameters, signatureValue);

        // Return signed XML as bytes
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        signedDocument.writeTo(baos);
        return baos.toByteArray();
    }

    /**
     * Sign data using private key with RSA-SHA256 algorithm (per BOE specification).
     */
    private SignatureValue signData(ToBeSigned dataToSign, PrivateKey privateKey) throws Exception {
        java.security.Signature sig = java.security.Signature.getInstance("SHA256withRSA");
        sig.initSign(privateKey);
        sig.update(dataToSign.getBytes());
        byte[] signatureBytes = sig.sign();

        SignatureValue signatureValue = new SignatureValue();
        signatureValue.setAlgorithm(SignatureAlgorithm.RSA_SHA256);
        signatureValue.setValue(signatureBytes);
        return signatureValue;
    }

    /**
     * Create password-protected ZIP file with AES-256 encryption.
     */
    private byte[] createEncryptedZip(byte[] xmlContent, String xmlFilename, String password) throws IOException {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();

        ZipParameters zipParams = new ZipParameters();
        zipParams.setCompressionMethod(CompressionMethod.DEFLATE);
        zipParams.setEncryptFiles(true);
        zipParams.setEncryptionMethod(EncryptionMethod.AES);
        zipParams.setAesKeyStrength(AesKeyStrength.KEY_STRENGTH_256);
        zipParams.setFileNameInZip(xmlFilename);

        try (ZipOutputStream zos = new ZipOutputStream(baos, password.toCharArray())) {
            zos.putNextEntry(zipParams);
            zos.write(xmlContent);
            zos.closeEntry();
        }

        return baos.toByteArray();
    }

    /**
     * Load X.509 certificate from file path or PEM content.
     */
    private X509Certificate loadCertificate(String certValue) throws Exception {
        byte[] certBytes;

        if (isPemContent(certValue)) {
            getLogger().debug("Loading certificate from PEM content");
            certBytes = normalizePem(certValue);
        } else {
            getLogger().debug("Loading certificate from file: {}", certValue);
            certBytes = Files.readAllBytes(Paths.get(certValue));
        }

        // Parse the PEM to extract DER bytes
        String pemString = new String(certBytes, StandardCharsets.UTF_8);
        byte[] derBytes = extractDerFromPem(pemString, "CERTIFICATE");

        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        return (X509Certificate) cf.generateCertificate(new ByteArrayInputStream(derBytes));
    }

    /**
     * Load private key from file path or PEM content.
     */
    private PrivateKey loadPrivateKey(String keyValue, String password) throws Exception {
        byte[] keyBytes;

        if (isPemContent(keyValue)) {
            getLogger().debug("Loading private key from PEM content");
            keyBytes = normalizePem(keyValue);
        } else {
            getLogger().debug("Loading private key from file: {}", keyValue);
            keyBytes = Files.readAllBytes(Paths.get(keyValue));
        }

        String pemString = new String(keyBytes, StandardCharsets.UTF_8);

        // Check if it's encrypted (ENCRYPTED PRIVATE KEY)
        if (pemString.contains("ENCRYPTED PRIVATE KEY")) {
            return loadEncryptedPrivateKey(pemString, password);
        }

        // Try PKCS#8 format first - use Bouncy Castle to auto-detect algorithm
        if (pemString.contains("PRIVATE KEY") && !pemString.contains("RSA PRIVATE KEY")) {
            try (java.io.StringReader reader = new java.io.StringReader(pemString);
                 PEMParser parser = new PEMParser(reader)) {
                Object pemObject = parser.readObject();
                if (pemObject instanceof PrivateKeyInfo) {
                    JcaPEMKeyConverter converter = new JcaPEMKeyConverter();
                    return converter.getPrivateKey((PrivateKeyInfo) pemObject);
                }
            }
        }

        // Try RSA PRIVATE KEY (PKCS#1) format - use Bouncy Castle PEM parser
        if (pemString.contains("RSA PRIVATE KEY")) {
            return loadPkcs1PrivateKey(pemString);
        }

        throw new IllegalArgumentException("Unsupported private key format");
    }

    /**
     * Load PKCS#1 RSA private key using Bouncy Castle PEM parser.
     */
    private PrivateKey loadPkcs1PrivateKey(String pemString) throws Exception {
        try (java.io.StringReader reader = new java.io.StringReader(pemString);
             PEMParser parser = new PEMParser(reader)) {

            Object pemObject = parser.readObject();
            JcaPEMKeyConverter converter = new JcaPEMKeyConverter();

            if (pemObject instanceof RSAPrivateKey) {
                // PKCS#1 RSAPrivateKey structure - convert to Java key spec
                RSAPrivateKey rsaKey = (RSAPrivateKey) pemObject;
                java.security.spec.RSAPrivateCrtKeySpec keySpec = new java.security.spec.RSAPrivateCrtKeySpec(
                        rsaKey.getModulus(),
                        rsaKey.getPublicExponent(),
                        rsaKey.getPrivateExponent(),
                        rsaKey.getPrime1(),
                        rsaKey.getPrime2(),
                        rsaKey.getExponent1(),
                        rsaKey.getExponent2(),
                        rsaKey.getCoefficient()
                );
                return KeyFactory.getInstance("RSA").generatePrivate(keySpec);
            } else if (pemObject instanceof PrivateKeyInfo) {
                return converter.getPrivateKey((PrivateKeyInfo) pemObject);
            } else if (pemObject instanceof PEMKeyPair) {
                PEMKeyPair keyPair = (PEMKeyPair) pemObject;
                return converter.getPrivateKey(keyPair.getPrivateKeyInfo());
            } else {
                throw new IllegalArgumentException("Unsupported PEM object type: " +
                        (pemObject != null ? pemObject.getClass().getName() : "null"));
            }
        }
    }

    /**
     * Load encrypted private key using password.
     */
    private PrivateKey loadEncryptedPrivateKey(String pemString, String password) throws Exception {
        if (password == null || password.isEmpty()) {
            throw new IllegalArgumentException("Password required for encrypted private key");
        }

        try (java.io.StringReader reader = new java.io.StringReader(pemString);
             PEMParser parser = new PEMParser(reader)) {

            Object pemObject = parser.readObject();

            if (pemObject instanceof PKCS8EncryptedPrivateKeyInfo) {
                PKCS8EncryptedPrivateKeyInfo encryptedInfo = (PKCS8EncryptedPrivateKeyInfo) pemObject;

                InputDecryptorProvider decryptorProvider =
                        new JceOpenSSLPKCS8DecryptorProviderBuilder().build(password.toCharArray());

                PrivateKeyInfo privateKeyInfo = encryptedInfo.decryptPrivateKeyInfo(decryptorProvider);

                return new JcaPEMKeyConverter().getPrivateKey(privateKeyInfo);
            } else {
                throw new IllegalArgumentException("Not an encrypted private key");
            }
        }
    }

    /**
     * Extract DER bytes from PEM content.
     */
    private byte[] extractDerFromPem(String pem, String type) {
        Pattern pattern = Pattern.compile(
                "-----BEGIN " + type + "-----\\s*(.+?)\\s*-----END " + type + "-----",
                Pattern.DOTALL
        );
        Matcher matcher = pattern.matcher(pem);
        if (!matcher.find()) {
            throw new IllegalArgumentException("Invalid PEM format: missing BEGIN/END " + type + " markers");
        }

        String base64 = matcher.group(1).replaceAll("\\s+", "");
        return Base64.getDecoder().decode(base64);
    }

    /**
     * Normalize PEM content to handle formatting issues from secrets managers.
     */
    private byte[] normalizePem(String pemString) {
        String content = pemString.strip();

        // Handle escaped newlines (literal \n as two characters)
        if (content.contains("\\n") && !content.contains("\n")) {
            getLogger().debug("Detected escaped newlines in PEM, converting to actual newlines");
            content = content.replace("\\n", "\n");
        }

        // Handle escaped carriage returns
        content = content.replace("\\r", "");

        // Normalize Windows line endings
        content = content.replace("\r\n", "\n");
        content = content.replace("\r", "\n");

        // Validate PEM structure
        if (!content.contains(PEM_HEADER_PREFIX)) {
            throw new IllegalArgumentException(
                    "Invalid PEM format: missing BEGIN marker. Content starts with: " +
                            (content.length() > 50 ? content.substring(0, 50) + "..." : content)
            );
        }

        return content.getBytes(StandardCharsets.UTF_8);
    }

    /**
     * Check if a value appears to be PEM content rather than a file path.
     * PEM content starts with "-----BEGIN" (possibly after whitespace).
     */
    private boolean isPemContent(String value) {
        if (value == null || value.isEmpty()) {
            return false;
        }
        String trimmed = value.stripLeading();
        return trimmed.startsWith(PEM_HEADER_PREFIX);
    }
}
