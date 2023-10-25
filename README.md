# Certgen CA

This is a very small command-line utiliy for generating crypto certificates to
a self-signed CA. Its a thin wrapper for the `openssl` command and is written
in make.

The motivation for this tools is to provide a simple CA setup for my own
personal use.

## Setup

Before it can be used `make` must be installed. Then edit
the default [`openssl.cnf`](openssl.cnf) and edit the section
[req_distinguished_name] to fit your needs:

```sh
$ nano openssl.cnf       # Edit section [req_distinguished_name]
```

The top part of [`Makefile`](Makefile) can also be edited to configure
the default key sizes and certificate lengths:

```sh
$ nano Makefile          # Edit BITS and DAYS default
```

## Usage

Generally the operations are done simpy by calling `make`. Quick guide:

```sh
$ make                   # Will list all command options

$ make ca ca=rootca      # Generate root CA named "rootca"

$ make cert n=me t=user  # Generate a user certificate named "me"

$ make p12 n=me k=1      # Make p12 keybag with the "me" cert including
                         # its key and certificate chain.

$ make info              # List all certificates

$ make cert-info n=me    # Show info about certificate "me"
```

## Create root CA 

First step is to create a new self-signed root CA:

```sh
$ make ca ca=rootca      # The ca name "rootca" is arbitrary
```
It will create a key for the CA. It will then ask
interactively for the subject DN of the certificate. Which of these
fields are required and what defaults are controlled in the
`[req_distinguished_name]` section of [`openssl.cnf`](openssl.cnf):

```
Country Name (2 letter code) [AU]:
State or Province Name (full name) [Some-State]:
Locality Name (eg, city) []:
Organization Name (eg, company) [Internet Widgits Pty Ltd]:
Organizational Unit Name (eg, section) []:
Common Name (e.g. server FQDN or YOUR name) []:
Email Address []:
```

It will then create a self-signed certificate and its info will be printed:

```
**** Cert info for rootca.cert.pem:
        Issuer: C = AU, ST = Some-State, O = Internet Widgits Pty Ltd
        Validity
            Not Before: Oct 22 21:27:01 2023 GMT
            Not After : Oct 19 21:27:01 2033 GMT
        Subject: C = AU, ST = Some-State, O = Internet Widgits Pty Ltd
```

The files will be stored in `data/` by default. The newly created self
signed certificate can now be copied from `data/rootca.cert.pem`.


## Create signed certificates

This tool supports 3 types of certificates:

  * **CA** - A certificate which is able to further sign certificates
  * **Server** - A certificate which is able to identify typical server services
  * **User** - A certificate to identify users

The `t=<type>` option can be used to select which type certificate to generate
and sign. Omitting `t=` defaults to a user certificate.

To generate and sign a new certificate run:

```sh
$ make cert n=myself t=user   # Generates user certificate "myself"
```

This will sign the certificate in the root CA. The `t=<type>` option controls
which type of certificate is wanted.

It will interactively ask for the subject DN of the certificate. Which of these
fields are required and what defaults are controlled in the
`[req_distinguished_name]` section of [`openssl.cnf`](openssl.cnf).

When done it will print the certificate request and ask for the certificate to
be signed.


## Recursive certificates

The special `t=ca` options allows to make recursive certificate. Or more
precisely, it makes intermediary CA certificates that can in turn sign other
certificates.

`make cert t=intermediate_ca n=inter` will generate new intermediate CA
certificates named "inter". This intermediary CA certificate can be used when
generating new certificates:

```sh
$ make cert n=subcert t=user ca=inter   # New cert "subcert" signed by "inter"
```


## Revocation

To revoke a certificate use

```sh
$ make revoke n=mycert    # Revoke
```

The certificate must be revoked in the CA which signed the certificate. If the
default top-level CA didn't sign the certificate, `ca=otherca` must be used.

Revocated certificates will be moved to `data/obsolete`


## Links

See https://jamielinux.com/docs/openssl-certificate-authority/index.html
for a great guide of how to use openssl to generate self signed CA.


## Changelog

### v6 update

* Refactored the make structure
* Moved all cert data into data/
* Updated with latest openssl config
* Removed obsolete Netscape cert ext (ns*)
* Support for recursive sub CA
* Better help and messages during use

### v5 update

* Refactored for newer openssl
* Changed to use .key.pem, .csr.pem, .cert.pem and so on
* Added support for subca / intermediate CA
* Added verification commands
* Synced openssl.cnf with newer openssl default
* Made usage of c= arguments more consistent. Clearer when name is used vs when
  full filename is used

