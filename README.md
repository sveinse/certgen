
# Certgen CA

This is a very small utiliy for generating crypto certificates to a self-signed
CA. Its a thin wrapper for the `openssl` command and is written in make for
convenience.

See https://jamielinux.com/docs/openssl-certificate-authority/index.html
for a great guide of how to use openssl to generate self signed CA.


## Changelog

### v5 update

* Refactored for newer openssl
* Changed to use .key.pem, .csr.pem, .cert.pem and so on
* Added support for subca / intermediate CA
* Added verification commands
* Synced openssl.cnf with newer openssl default
* Made usage of c= arguments more consistent. Clearer when name is used vs when
  full filename is used

