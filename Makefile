#
# Site/web certificate generator
# $Id$
#
#
# TODO:
#	- Possibility to make several p12 targets with different names
#       - Automatic .np.key files?
#

#
# include dependency files if they exist
#
-include .depend

# Default keysize
KEY_BITS ?= 4096
CA_BITS ?= 8192

# Default certificate lifetimes
CA_DAYS ?= 3650
SERVER_DAYS ?= 730
DAYS ?= 365

# Default configuration
CONFIG ?= ./openssl.cnf
CONF = -config $(CONFIG)

# Default name of CA
CA ?= seldalca
export CA

# Default values
CSR_EXT ?= -reqexts v3_req_user
CRT_EXT ?= -extensions v3_user -days $(DAYS)

# Standard include (used in P12)
STDINC ?=


all:
	@echo
	@echo "Seldal CA build system v4 2019-05-29"
	@echo
	@echo "  make ca ca=<name>                       Self-signed CA certificate"
	@echo "  make server c=<name>                    Server certificates"
	@echo "  make user c=<name>                      User certificates"
	@echo
	@echo "  make revoke c=<cert>                    Revoke a certificate"
	@echo "  make update-crl                         Update the revocation list"
	@echo "  make crl-info                           View revocation list"
	@echo "  make ca-info                            View certifactes"
	@echo
	@echo "  make rempwd in=<in_key> out=<out_key>   Remove password from key"
	@echo "  make p12 c=<name> [k=<key>] [p12=<out>] [inc=<include>]"
	@echo "                                          Compile pkcs12 keybag (CA included)"
	@echo
	@echo "  make info c=<cert>                      Certificate info"
	@echo "  make key-info k=<key>                   Key info"
	@echo "  make p12-info p12=<p12>                 View pkcs12 info"
	@echo
	@echo "  make <file>.key                         Make a private key"
	@echo "  make <file>.csr                         Create a signing request"
	@echo "  make <file>.crt                         Create a certificate"



#
# The main targets
#
ca:
	@test $${ca:?"usage: make $@ ca=<name>"}
	echo "CA = $(ca)" >.depend

	# Make the key (add this for pwd: KEY_EXT="-des3" )
	$(MAKE) KEY_BITS=$(CA_BITS) $(ca).key

	# Create a cert for our CA
	if [ ! -f $(ca).crt ]; then \
	    $(MAKE) CSR_EXT="-extensions v3_ca -reqexts v3_req_ca -x509" DAYS=$(CA_DAYS) $(ca).csr; \
	    mv $(ca).csr $(ca).crt; \
	fi

	# Create the remaining CA files
	$(MAKE) $(ca).db.certs $(ca).db.serial $(ca).db.index $(ca).db.index.attr $(ca).crlnumber $(ca).crl


user:
	@test $${c:?"usage: make $@ c=<name>"}

	# Make it all in one (using defaults)
	$(MAKE) $(c).crt


server:
	@test $${c:?"usage: make $@ c=<name>"}

	# Make the key
	$(MAKE) $(c).key

	# Create a signing request for our CA
	$(MAKE) CSR_EXT="-reqexts v3_req_server" DAYS=$(SERVER_DAYS) $(c).csr

	# Sign the request
	$(MAKE) CRT_EXT="-extensions v3_server -days $(SERVER_DAYS)" $(c).crt


p12:
	@test $${c:?"usage: make $@ c=<name> [k=<key>] [p12=<p12>] [inc=<inc>]"}

	# Make the conversion
	# $(MAKE) IN=$(c).crt OUT=$${out:-$(c)}.p12 INC=$${inc:-$(STDINC)} p12_maker
	$(MAKE) IN=$(c).crt OUT=$${p12:-$(c)}.p12 INC=$(inc) KEY=$(k) p12_maker


update-crl:
	$(MAKE) $(CA).crl
	$(MAKE) ca-info


revoke:
	@test $${c:?"usage: make $@ c=<name>"}
	openssl ca $(CONF) -revoke $(c).crt
	$(MAKE) update-crl
	set -x; \
	  for v in 01 02 03 04 05 06 07 08 09 10; do \
	    if [ -e revoked/$(c).crt.$$v ]; then continue; fi ; \
	    for f in $(c).* ; do \
	      mv $$f revoked/$$f.$$v ; \
	    done ; \
	    break ; \
	  done ;


# Generate a private key
%.key:
	@echo
	@echo "**** Generate private key, $@"
	@echo
	openssl genrsa $(KEY_EXT) $(KEY_BITS) >$@

# Generate a signing request
%.csr: %.key
	@echo
	@echo "**** Create a signing request, $@"
	@echo
	openssl req $(CONF) $(CSR_EXT) -text -new -days $(DAYS) -key $< -out $@

# Generate a certificate
%.crt: %.csr
	@echo
	@echo "**** Create a user certificate, $@"
	@echo
	openssl ca $(CONF) $(CRT_EXT) -md sha512 -out $@ -infiles $<
	$(MAKE) update-crl

# Create a CA revoke-file
$(CA).crl: $(CA).key $(CA).crt $(CA).db.index $(CA).crlnumber
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


#
# Create a PKCS12 keybag
#
p12_maker:
	@echo
	@echo "**** Create a PKCS12 keybag $(OUT) from $(IN)"
	@echo "**** Including certificates CA + '$(INC)' + KEY $(KEY)"
	@echo
	NAME="`openssl x509 -noout -text -in $(IN) |grep "Subject:" | sed -e 's/^\s\+Subject:\s//'`"; \
	echo; echo; \
	if [ "$(KEY)" ]; then \
		echo "Adding certificate + keys for $(IN): '$$NAME'"; \
		echo -n "openssl pkcs12 -export -in $(IN) -inkey $(KEY) -name \"$$NAME\" -out $(OUT) -certfile /tmp/tmp.crt ">/tmp/tmp.crt.sh; \
	else \
		echo "Adding certificate w/o keys for $(IN): '$$NAME'"; \
		echo -n "openssl pkcs12 -export -in $(IN) -nokeys -name \"$$NAME\" -out $(OUT) -certfile /tmp/tmp.crt ">/tmp/tmp.crt.sh; \
	fi; \
	echo >/tmp/tmp.crt; \
	for cert in $(CA).crt $(INC); do \
		CERTNAME="`openssl x509 -noout -text -in $$cert |grep "Subject:" | sed -e 's/^\s\+Subject:\s//'`"; \
		cat $$cert >>/tmp/tmp.crt; \
		echo "Adding $$cert: '$$CERTNAME'"; \
		echo -n "-caname \"$$CERTNAME\" " >>/tmp/tmp.crt.sh; \
	done; \
	echo >>/tmp/tmp.crt.sh; \
	echo; cat /tmp/tmp.crt.sh; \
	. /tmp/tmp.crt.sh;
	rm /tmp/tmp.crt.sh /tmp/tmp.crt



###########################
#
#  Misc extra functions
#
###########################
info:
	@test $${c:?"usage: make $@ c=<cert>"}
	openssl x509 -text -noout -in $(c)

ca-info:
	cat $(CA).db.index

key-info:
	@test $${k:?"usage: make $@ k=<key>"}
	openssl rsa -text -noout -in $(k)

crl-info:
	-openssl crl -text -noout -in $(CA).crl

p12-info:
	@test $${p12:?"usage: make $@ p12=<p12>"}
	openssl pkcs12 -in $(p12) -info -noout

rempwd:
	@test $${in:?"usage: make $@ in=<in_key> out=<out_key>"}
	@test $${out:?"usage: make $@ in=<in_key> out=<out_key>"}
	openssl rsa -in $(in) -out $(out)



#
# Clean up unused files
#
clean:
	rm -rf *~

distclean:
	@test $${force:?"usage: make $@ force=1"}
	-rm -rf *~ *.key *.crt *.crl *.crlnumber* *.csr *.db.* *.p12 .depend

.PHONY: %.p12 $(CA).crl
.PRECIOUS: %.key %.crt
