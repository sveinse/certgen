#
# Simple CA tool
#

# Include dependency files if they exist
-include .depend

# Default keysize
CA_BITS ?= 8192
SERVER_BITS ?= 4096
KEY_BITS ?= 2048

# Default certificate lifetimes
CA_DAYS ?= 3650
SERVER_DAYS ?= 730
DAYS ?= 365

# Uncomment this to encrypt keys by default
#KEY_EXT ?= -aes256

# Default configuration
CONFIG ?= ./openssl.cnf
CONF = -config $(CONFIG)

# Default name of CA
CA ?= ca
export CA

# Default values
CSR_EXT ?= -reqexts v3_req_user
CRT_EXT ?= -extensions v3_user -days $(DAYS)

# Standard include (used in P12)
STDINC ?=


all:
	@echo
	@echo "Seldal CA build system v5 2021-07-20"
	@echo
	@echo "  make ca ca=<name>                       Self-signed CA certificate"
	@echo "  make subca ca=<name>                    Make a sub intermediary CA"
	@echo "  make server n=<name>                    Server certificates"
	@echo "  make user n=<name>                      User certificates"
	@echo
	@echo "  make revoke c=<cert>                    Revoke a certificate"
	@echo "  make update-crl                         Update the revocation list"
	@echo "  make crl-info                           View revocation list"
	@echo "  make ca-info                            View certifactes"
	@echo
	@echo "  make rempwd in=<in_key> out=<out_key>   Remove password from key"
	@echo "  make p12 c=<cert> [k=<key>] [p12=<out>] [inc=<cert>]"
	@echo "                                          Compile pkcs12 keybag (CA included)"
	@echo
	@echo "  make info c=<cert>                      Certificate info"
	@echo "  make verify c=<cert>                    Verify certificate"
	@echo "  make verify-csr c=<csr>                 Verify CSR"
	@echo "  make verify-key k=<key>                 Verify key"
	@echo "  make key-info k=<key>                   Key info"
	@echo "  make p12-info p12=<p12>                 View pkcs12 info"
	@echo
	@echo "  make <file>.key.pem                     Make a private key"
	@echo "  make <file>.csr.pem                     Create a signing request"
	@echo "  make <file>.cert.pem                    Create a certificate"



#
# The main targets
#
ca:
	@test $${ca:?"usage: make $@ ca=<name>"}
	echo "CA = $(ca)" >.depend
	echo "THIS = $(THIS)" >>.depend

	# Make the key (add this for pwd: KEY_EXT="-aes256" )
	$(MAKE) KEY_BITS=$(CA_BITS) $(ca).key.pem

	# Sign or self sign the CA certificate
	set -ex; if [ ! -f $(ca).cert.pem ]; then \
	    if [ "$(PARENTCA)" ]; then \
	        # Make a signing request \
	        $(MAKE) CSR_EXT= DAYS= $(ca).csr.pem; \
	        \
	        # Sign this certificate request in the parent CA \
	        $(MAKE) -C .. CRT_EXT="-extensions v3_intermediate_ca -days $(CA_DAYS)" $(THIS)/$(ca).cert.pem; \
	        \
	        # Compile CA chain \
	        cat $(ca).cert.pem ../$(PARENTCA).chain.cert.pem > $(ca).chain.cert.pem; \
	    else \
	        # Create a self signed certificate \
	        $(MAKE) CSR_EXT="-extensions v3_ca -reqexts v3_req_ca -x509" DAYS=$(CA_DAYS) $(ca).csr.pem; \
	        \
	        mv $(ca).csr.pem $(ca).cert.pem; \
	        ln -s $(ca).cert.pem $(ca).chain.cert.pem; \
	    fi; \
	fi;

	# Create the remaining CA DB files
	$(MAKE) $(ca).db.certs $(ca).db.serial $(ca).db.index $(ca).db.index.attr $(ca).crlnumber $(ca).crl.pem


subca:
	@test $${ca:?"usage: make $@ ca=<name>"}

	mkdir -p $(ca)
	-ln -s ../Makefile $(ca)/Makefile
	-ln -s ../openssl.cnf $(ca)/openssl.cnf
	echo "$(ca)" >>.subca

	# Create sub CA
	$(MAKE) -C $(ca) ca THIS=$(ca) PARENTCA=$(CA) c=$(ca)


server:
	@test $${n:?"usage: make $@ n=<name>"}

	# Make the key
	$(MAKE) KEY_BITS=$(SERVER_BITS) $(n).key.pem

	# Create a signing request for our CA
	$(MAKE) CSR_EXT="-reqexts v3_req_server" DAYS=$(SERVER_DAYS) $(n).csr.pem

	# Sign the request
	$(MAKE) CRT_EXT="-extensions v3_server -days $(SERVER_DAYS)" $(n).cert.pem


user:
	@test $${n:?"usage: make $@ n=<name>"}

	# Make it all in one (using defaults)
	$(MAKE) $(n).cert.pem


p12:
	@test $${c:?"usage: make $@ c=<cert> [k=<key>] [p12=<p12>] [inc=<inc>]"}

	# Make the conversion
	$(MAKE) IN=$(c) OUT=$(if $(p12),$(p12),$(subst .pem,.p12,$(c))) INC=$(inc) KEY=$(k) _p12


_p12:
	@echo
	@echo "**** Create a PKCS12 keybag $(OUT) from $(IN)"
	@echo "**** Including certificates CA + '$(INC)' + KEY $(KEY)"
	@echo
	NAME="`openssl x509 -noout -text -in $(IN) |grep "Subject:" | sed -e 's/^\s\+Subject:\s//'`"; \
	echo; echo; \
	if [ "$(KEY)" ]; then \
		echo "Adding certificate + keys for $(IN): '$$NAME'"; \
		echo -n "openssl pkcs12 -export -in $(IN) -inkey $(KEY) -name \"$$NAME\" -out $(OUT) -certfile tmp.cert.pem ">tmp.cert.sh; \
	else \
		echo "Adding certificate w/o keys for $(IN): '$$NAME'"; \
		echo -n "openssl pkcs12 -export -in $(IN) -nokeys -name \"$$NAME\" -out $(OUT) -certfile tmp.cert.pem " > tmp.cert.sh; \
	fi; \
	echo >tmp.cert.pem; \
	for cert in $(CA).chain.cert.pem $(INC); do \
		CERTNAME="`openssl x509 -noout -text -in $$cert |grep "Subject:" | sed -e 's/^\s\+Subject:\s//'`"; \
		cat $$cert >>tmp.cert.pem; \
		echo "Adding $$cert: '$$CERTNAME'"; \
		echo -n "-caname \"$$CERTNAME\" " >>tmp.cert.sh; \
	done; \
	echo >>tmp.cert.sh; \
	echo; cat tmp.cert.sh; \
	. ./tmp.cert.sh;
	rm tmp.cert.sh tmp.cert.pem


update-crl:
	$(MAKE) $(CA).crl.pem
	$(MAKE) ca-info


revoke:
	@test $${c:?"usage: make $@ c=<cert>"}
	openssl ca $(CONF) -revoke $(c)
	$(MAKE) update-crl
	set -x; \
	  mkdir -p revoked; \
	  for v in 01 02 03 04 05 06 07 08 09 10; do \
	    if [ -e revoked/$(c).$$v ]; then continue; fi ; \
	    for f in $(subst .cert.pem,,$(c)).* ; do \
	      mv $$f revoked/$$f.$$v ; \
	    done ; \
	    break ; \
	  done ;


# Generate a private key
%.key.pem:
	@echo
	@echo "**** Generate private key, $@"
	@echo
	openssl genrsa $(KEY_EXT) $(KEY_BITS) >$@

# Generate a signing request
%.csr.pem: %.key.pem
	@echo
	@echo "**** Create a signing request, $@"
	@echo
	openssl req $(CONF) $(CSR_EXT) -text -new $(if $(DAYS),-days $(DAYS)) -key $< -out $@

# Generate a certificate
%.cert.pem: %.csr.pem
	@echo
	@echo "**** Create a user certificate, $@"
	@echo
	openssl ca $(CONF) $(CRT_EXT) -md sha512 -out $@ -infiles $<
	$(MAKE) update-crl

# Create a CA revoke-file
$(CA).crl.pem: $(CA).key.pem $(CA).cert.pem $(CA).db.index $(CA).crlnumber
	@echo
	@echo "**** Create CA revoke file, $@"
	@echo
	openssl ca $(CONF) -gencrl -out $@

# Create certification databases (to CA)
%.db.certs:
	mkdir -p $@

%.db.serial:
	if [ ! -f $@ ]; then echo '01' >$@; fi

%.db.index:
	touch $@ $@.attr

%.crlnumber:
	if [ ! -f $@ ]; then echo '01' >$@; fi



###########################
#
#  Misc extra functions
#
###########################
info:
	@test $${c:?"usage: make $@ c=<cert>"}
	openssl x509 -text -noout -in $(c)

verify:
	@test $${c:?"usage: make $@ c=<cert>"}
	openssl verify -CAfile $(CA).chain.cert.pem $(c)

verify-csr:
	@test $${c:?"usage: make $@ c=<csr>"}
	openssl req -noout -verify -in $(c)

verify-key:
	@test $${k:?"usage: make $@ k=<key>"}
	openssl rsa -noout -check -in $(k)

ca-info:
	cat $(CA).db.index

key-info:
	@test $${k:?"usage: make $@ k=<key>"}
	openssl rsa -text -noout -in $(k)

crl-info:
	openssl crl -text -noout -in $(CA).crl.pem

p12-info:
	@test $${c:?"usage: make $@ c=<p12>"}
	openssl pkcs12 -in $(c) -info -noout

rempwd:
	@test $${in:?"usage: make $@ in=<in_key> out=<out_key>"}
	@test $${out:?"usage: make $@ in=<in_key> out=<out_key>"}
	openssl rsa -in $(in) -out $(out)



#
# Clean up unused files
#
distclean:
	@test $${force:?"Since it wipes everything, use 'make $@ force=1' to do it"}
	@if [ -e .subca ]; then set -x; rm -rf $$(cat .subca); fi
	-rm -rf *~ *.pem *.crlnumber* *.db.* *.p12 .depend revoked .subca

.PHONY: %.p12 $(CA).crl.pem
.PRECIOUS: %.key.pem %.cert.pem
