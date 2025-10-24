# Credentials Directory

This directory stores security credentials generated during setup. All files in this directory are excluded from version control.

## Required Files

After completing [02_CREDENTIALS_SETUP.md](../setup/02_CREDENTIALS_SETUP.md), this directory should contain:

- `dgoj_demo_cert.pem` - DGOJ signing certificate (public)
- `dgoj_demo_key.pem` - DGOJ private key (password-protected)
- `sftp_key` - SSH private key for SFTP authentication
- `sftp_key.pub` - SSH public key for SFTP authentication
- `passwords.txt` - Demo passwords for ZIP encryption and private key

## Security

**NEVER commit these files to version control.** They are excluded via `.gitignore`.

For production deployments, use enterprise secrets management and Hardware Security Modules (HSM).
