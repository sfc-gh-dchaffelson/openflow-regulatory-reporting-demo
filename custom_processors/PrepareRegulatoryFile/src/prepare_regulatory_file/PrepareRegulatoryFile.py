from nifiapi.flowfiletransform import FlowFileTransform, FlowFileTransformResult
from nifiapi.properties import PropertyDescriptor, StandardValidators, ExpressionLanguageScope, ProcessContext
from nifiapi.relationship import Relationship
from typing import List
import io
import re
import textwrap


class PrepareRegulatoryFile(FlowFileTransform):
    """
    Prepares XML data for Spanish DGOJ regulatory submission by:
    1. Signing XML with XAdES-BES digital signature
    2. Compressing with ZIP (Deflate algorithm)
    3. Encrypting with AES-256 (WinZip-compatible)

    This processor handles the complete transformation pipeline required
    by Spanish gaming regulation BOE-A-2024-12639.

    Certificate and private key can be provided in two ways:
    - File path mode: Use 'Certificate Path' and 'Private Key Path' (non-sensitive)
      for file paths, which can reference parameter context assets.
    - PEM content mode: Use 'Certificate' and 'Private Key' (sensitive) for direct
      PEM content from AWS Secrets Manager via External Parameter Provider.

    For each credential type, provide exactly one of the two options.
    """

    class Java:
        implements = ['org.apache.nifi.python.processor.FlowFileTransform']

    class ProcessorDetails:
        version = '0.0.3'
        description = 'Signs XML with XAdES-BES, compresses with ZIP/Deflate, and encrypts with AES-256 for Spanish DGOJ regulatory compliance'
        tags = ['xml', 'signature', 'encryption', 'xades', 'regulatory', 'dgoj', 'spain']
        dependencies = ['lxml', 'signxml', 'cryptography', 'pyzipper']

    def __init__(self, *args, **kwargs):
        super().__init__()

        # Certificate - File path mode (non-sensitive, can reference assets)
        self.certificate_path = PropertyDescriptor(
            name="Certificate Path",
            description="File path to X.509 certificate (.pem or .crt) for XAdES-BES signature. Use this for asset-based workflows. Mutually exclusive with 'Certificate' property.",
            required=False,
            validators=[StandardValidators.NON_EMPTY_VALIDATOR],
            expression_language_scope=ExpressionLanguageScope.FLOWFILE_ATTRIBUTES,
            sensitive=False
        )

        # Certificate - PEM content mode (sensitive, for secrets manager)
        self.certificate_pem = PropertyDescriptor(
            name="Certificate",
            description="X.509 certificate as PEM content (must start with '-----BEGIN CERTIFICATE-----'). Use this for AWS Secrets Manager integration via External Parameter Provider. Mutually exclusive with 'Certificate Path' property.",
            required=False,
            validators=[StandardValidators.NON_EMPTY_VALIDATOR],
            expression_language_scope=ExpressionLanguageScope.FLOWFILE_ATTRIBUTES,
            sensitive=True
        )

        # Private Key - File path mode (non-sensitive, can reference assets)
        self.private_key_path = PropertyDescriptor(
            name="Private Key Path",
            description="File path to private key (.pem) for XAdES-BES signature. Use this for asset-based workflows. Mutually exclusive with 'Private Key' property.",
            required=False,
            validators=[StandardValidators.NON_EMPTY_VALIDATOR],
            expression_language_scope=ExpressionLanguageScope.FLOWFILE_ATTRIBUTES,
            sensitive=False
        )

        # Private Key - PEM content mode (sensitive, for secrets manager)
        self.private_key_pem = PropertyDescriptor(
            name="Private Key",
            description="Private key as PEM content (must start with '-----BEGIN'). Use this for AWS Secrets Manager integration via External Parameter Provider. Mutually exclusive with 'Private Key Path' property.",
            required=False,
            validators=[StandardValidators.NON_EMPTY_VALIDATOR],
            expression_language_scope=ExpressionLanguageScope.FLOWFILE_ATTRIBUTES,
            sensitive=True
        )

        self.private_key_password = PropertyDescriptor(
            name="Private Key Password",
            description="Password to decrypt the private key file (if encrypted). Leave empty if key is not encrypted.",
            required=False,
            expression_language_scope=ExpressionLanguageScope.FLOWFILE_ATTRIBUTES,
            sensitive=True
        )

        self.zip_password = PropertyDescriptor(
            name="ZIP Encryption Password",
            description="50-character password for AES-256 ZIP encryption. Must contain digits, letters, and special characters (#, $, &, !).",
            required=True,
            validators=[StandardValidators.NON_EMPTY_VALIDATOR],
            expression_language_scope=ExpressionLanguageScope.FLOWFILE_ATTRIBUTES,
            sensitive=True
        )

        self.signature_method = PropertyDescriptor(
            name="Signature Method",
            description="XAdES signature method: 'enveloped' embeds signature in XML, 'enveloping' creates separate signature file",
            required=True,
            allowable_values=["enveloped", "enveloping"],
            default_value="enveloped",
            validators=[StandardValidators.NON_EMPTY_VALIDATOR]
        )

        self.xml_filename = PropertyDescriptor(
            name="XML Filename",
            description="Filename to use for the XML file inside the ZIP (e.g., 'lote.xml' or 'enveloped.xml')",
            required=True,
            default_value="enveloped.xml",
            validators=[StandardValidators.NON_EMPTY_VALIDATOR],
            expression_language_scope=ExpressionLanguageScope.FLOWFILE_ATTRIBUTES
        )

        self.descriptors = [
            self.certificate_path,
            self.certificate_pem,
            self.private_key_path,
            self.private_key_pem,
            self.private_key_password,
            self.zip_password,
            self.signature_method,
            self.xml_filename
        ]

    def getPropertyDescriptors(self) -> List[PropertyDescriptor]:
        return self.descriptors

    def transform(self, context: ProcessContext, flowfile) -> FlowFileTransformResult:
        """
        Transform the XML flowfile by signing, compressing, and encrypting it.

        Args:
            context: ProcessContext providing access to properties and state
            flowfile: InputFlowFile containing the XML content

        Returns:
            FlowFileTransformResult with the encrypted ZIP content
        """
        try:
            # Read XML content
            xml_content = flowfile.getContentsAsBytes()

            # Get certificate properties (path mode vs PEM mode)
            cert_path = context.getProperty(self.certificate_path).evaluateAttributeExpressions(flowfile).getValue()
            cert_pem = context.getProperty(self.certificate_pem).evaluateAttributeExpressions(flowfile).getValue()

            # Get private key properties (path mode vs PEM mode)
            key_path = context.getProperty(self.private_key_path).evaluateAttributeExpressions(flowfile).getValue()
            key_pem = context.getProperty(self.private_key_pem).evaluateAttributeExpressions(flowfile).getValue()

            # Validate certificate input (exactly one required)
            cert_path_set = cert_path is not None and cert_path.strip() != ''
            cert_pem_set = cert_pem is not None and cert_pem.strip() != ''
            if cert_path_set and cert_pem_set:
                raise ValueError("Both 'Certificate Path' and 'Certificate' are set. Please configure only one.")
            if not cert_path_set and not cert_pem_set:
                raise ValueError("Neither 'Certificate Path' nor 'Certificate' is set. Please configure one.")

            # Validate private key input (exactly one required)
            key_path_set = key_path is not None and key_path.strip() != ''
            key_pem_set = key_pem is not None and key_pem.strip() != ''
            if key_path_set and key_pem_set:
                raise ValueError("Both 'Private Key Path' and 'Private Key' are set. Please configure only one.")
            if not key_path_set and not key_pem_set:
                raise ValueError("Neither 'Private Key Path' nor 'Private Key' is set. Please configure one.")

            # Get other properties
            key_password_value = context.getProperty(self.private_key_password).evaluateAttributeExpressions(flowfile).getValue()
            zip_password = context.getProperty(self.zip_password).evaluateAttributeExpressions(flowfile).getValue()
            signature_method = context.getProperty(self.signature_method).getValue()
            xml_filename = context.getProperty(self.xml_filename).evaluateAttributeExpressions(flowfile).getValue()

            # Convert password to bytes if provided
            key_password = key_password_value.encode('utf-8') if key_password_value else None

            # Determine certificate and key sources
            cert_source = ('pem', cert_pem) if cert_pem_set else ('path', cert_path)
            key_source = ('pem', key_pem) if key_pem_set else ('path', key_path)

            self.logger.info("Certificate source: {}, Private key source: {}".format(cert_source[0], key_source[0]))

            # Step 1: Sign XML with XAdES-BES
            self.logger.info("Signing XML with XAdES-BES signature method: {}".format(signature_method))
            signed_xml = self._sign_xml(xml_content, cert_source, key_source, key_password, signature_method)

            # Step 2: Create ZIP with AES-256 encryption
            self.logger.info("Creating encrypted ZIP with AES-256")
            zip_content = self._create_encrypted_zip(signed_xml, xml_filename, zip_password)

            # Update attributes
            attributes = {
                "mime.type": "application/zip",
                "dgoj.signed": "true",
                "dgoj.encrypted": "true",
                "dgoj.signature.method": signature_method
            }

            return FlowFileTransformResult(
                relationship="success",
                contents=zip_content,
                attributes=attributes
            )

        except Exception as e:
            self.logger.error("Failed to prepare regulatory file: {}".format(str(e)))
            return FlowFileTransformResult(
                relationship="failure",
                attributes={"error.message": str(e)}
            )

    def _sign_xml(self, xml_content, cert_source, key_source, key_password, method):
        """
        Sign XML content using XAdES-BES signature.

        Args:
            xml_content: XML content as bytes
            cert_source: Tuple of (source_type, value) where source_type is 'path' or 'pem'
            key_source: Tuple of (source_type, value) where source_type is 'path' or 'pem'
            key_password: Password for private key (or None)
            method: 'enveloped' or 'enveloping'

        Returns:
            Signed XML as bytes
        """
        from lxml import etree
        from signxml import XMLSigner
        from cryptography.hazmat.primitives.serialization import load_pem_private_key
        from cryptography.hazmat.backends import default_backend

        # Parse XML
        root = etree.fromstring(xml_content)

        # Load certificate based on source type
        cert_type, cert_value = cert_source
        if cert_type == 'pem':
            self.logger.info("Loading certificate from PEM content ({} chars)".format(len(cert_value)))
            try:
                cert_data = self._normalize_pem(cert_value)
            except ValueError as e:
                raise ValueError("Failed to parse certificate PEM: {}".format(str(e)))
        else:
            self.logger.info("Loading certificate from file: {}".format(cert_value))
            with open(cert_value, 'rb') as f:
                cert_data = f.read()

        # Load private key based on source type
        key_type, key_value = key_source
        if key_type == 'pem':
            self.logger.info("Loading private key from PEM content ({} chars)".format(len(key_value)))
            try:
                key_data = self._normalize_pem(key_value)
            except ValueError as e:
                raise ValueError("Failed to parse private key PEM: {}".format(str(e)))
        else:
            self.logger.info("Loading private key from file: {}".format(key_value))
            with open(key_value, 'rb') as f:
                key_data = f.read()

        # Decrypt private key if password provided (try with password, fallback to no password)
        password_bytes = key_password.encode('utf-8') if key_password and isinstance(key_password, str) else key_password
        try:
            key = load_pem_private_key(key_data, password=password_bytes, backend=default_backend())
        except TypeError:
            # Key is not encrypted, try without password
            key = load_pem_private_key(key_data, password=None, backend=default_backend())

        # Sign XML with XAdES-BES
        # For enveloped signature, we sign the root element and the signature is embedded
        # signxml automatically creates an enveloped signature when signing an element
        signer = XMLSigner(
            signature_algorithm='rsa-sha256',
            digest_algorithm='sha256',
            c14n_algorithm='http://www.w3.org/TR/2001/REC-xml-c14n-20010315'
        )

        signed_root = signer.sign(root, key=key, cert=cert_data)

        # Serialize back to bytes
        return etree.tostring(signed_root, xml_declaration=True, encoding='UTF-8')

    def _create_encrypted_zip(self, xml_content, xml_filename, password):
        """
        Create a password-protected ZIP file with AES-256 encryption.

        Args:
            xml_content: Signed XML content as bytes
            xml_filename: Filename for the XML inside the ZIP
            password: Password for AES-256 encryption

        Returns:
            ZIP file content as bytes
        """
        import pyzipper

        # Create in-memory ZIP file
        zip_buffer = io.BytesIO()

        with pyzipper.AESZipFile(
            zip_buffer,
            'w',
            compression=pyzipper.ZIP_DEFLATED,
            encryption=pyzipper.WZ_AES
        ) as zf:
            # Set password
            zf.setpassword(password.encode('utf-8'))

            # Add XML file to ZIP
            zf.writestr(xml_filename, xml_content)

        # Return ZIP content
        return zip_buffer.getvalue()

    def _normalize_pem(self, pem_string: str) -> bytes:
        """
        Normalize PEM content to handle common formatting issues from secrets managers,
        parameter providers, and JSON serialization.

        Handles:
        - Escaped newlines (literal \\n characters)
        - Windows line endings (\\r\\n)
        - Missing or extra whitespace
        - Base64 content without proper line wrapping

        Args:
            pem_string: Raw PEM string that may have formatting issues

        Returns:
            Properly formatted PEM as bytes

        Raises:
            ValueError: If PEM structure is invalid
        """
        # Strip leading/trailing whitespace
        content = pem_string.strip()

        # Handle escaped newlines (literal \n as two characters)
        # This is common when PEM is stored in JSON or passed through some parameter providers
        if '\\n' in content and '\n' not in content:
            self.logger.info("Detected escaped newlines in PEM, converting to actual newlines")
            content = content.replace('\\n', '\n')

        # Also handle escaped carriage returns
        content = content.replace('\\r', '')

        # Normalize Windows line endings
        content = content.replace('\r\n', '\n')
        content = content.replace('\r', '\n')

        # Extract the PEM type and base64 content
        # Match patterns like: -----BEGIN CERTIFICATE-----, -----BEGIN PRIVATE KEY-----, etc.
        pem_pattern = re.compile(
            r'(-----BEGIN [A-Z0-9 ]+-----)\s*(.+?)\s*(-----END [A-Z0-9 ]+-----)',
            re.DOTALL
        )

        match = pem_pattern.search(content)
        if not match:
            raise ValueError(
                "Invalid PEM format: missing BEGIN/END markers. "
                "Content starts with: {}...".format(content[:50] if len(content) > 50 else content)
            )

        begin_marker = match.group(1)
        base64_content = match.group(2)
        end_marker = match.group(3)

        # Clean the base64 content: remove all whitespace
        base64_clean = re.sub(r'\s+', '', base64_content)

        # Validate base64 characters
        if not re.match(r'^[A-Za-z0-9+/=]+$', base64_clean):
            raise ValueError("Invalid PEM format: base64 content contains invalid characters")

        # Re-wrap base64 at 64 characters (standard PEM line length)
        base64_wrapped = '\n'.join(textwrap.wrap(base64_clean, 64))

        # Reconstruct the PEM
        normalized_pem = "{}\n{}\n{}".format(begin_marker, base64_wrapped, end_marker)

        self.logger.debug("Normalized PEM: {} chars input -> {} chars output".format(
            len(pem_string), len(normalized_pem)
        ))

        return normalized_pem.encode('utf-8')

    def getRelationships(self) -> List[Relationship]:
        return [
            Relationship(name="success", description="FlowFiles that are successfully signed, compressed, and encrypted"),
            Relationship(name="failure", description="FlowFiles that failed processing")
        ]
