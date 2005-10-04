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
KEY_BITS ?= 2048

# Default certificate lifetimes
CA_DAYS ?= 1100
SERVER_DAYS ?= 365
DAYS ?= 365

# Default configuration
CONFIG ?= ./openssl.cnf
CONF = -config $(CONFIG)

# Default name of CA
CA ?= seldalca
export CA


all:
	@echo
	@echo "  o Self-signed CA certificate"
	@echo "        make ca ca=<name>"
	@echo "  o Server certificates"
	@echo "        make server server=<name>"
	@echo "  o User certificates"
	@echo "        make user user=<name>"
	@echo
	@echo "  o Compile pkcs12 keybag (CA cert is already included)"
	@echo "        make inc=<certs_to_include> <user>.p12"
	@echo "  o Revoke a certificate"
	@echo "        make revoke cert=<cert>"
	@echo "  o Update the revocation list"
	@echo "        make update-crl"
	@echo
	@echo "  o Key info"
	@echo "        make key-info key=<key>"
	@echo "  o Certificate info"
	@echo "        make info cert=<cert>"
	@echo "  o Remove password from key"
	@echo "       make rempwd in=<in_key> out=<out_key>"
	@echo "  o View crl (certificate revocation list)"
	@echo "       make crl-info crl=<crl>"
	@echo "  o View pkcs12 info"
	@echo "       make p12-info p12=<p12>"


#
# The main targets
#
ca:
	@test $${ca:?"usage: make $@ ca=<name>"}
	echo "CA = $(ca)" >.depend

	# Make the key (add this for pwd: KEY_EXT="-des3" )
	make $(ca).key 

	# Create a cert for our CA
	if [ ! -f $(ca).crt ]; then \
	    make CSR_EXT="-extensions ca_cert -reqexts v3_req_ca -x509" DAYS=$(CA_DAYS) $(ca).csr; \
	    mv $(ca).csr $(ca).crt; \
	fi

	# Create the remaining CA files
	make $(ca).db.certs $(ca).db.serial $(ca).db.index $(ca).crl


user:
	@test $${user:?"usage: make $@ user=<name>"}

	# Make it all in one (using defaults)
	make $(user).crt


server:
	@test $${server:?"usage: make $@ server=<name>"}

	# Make the key
	make $(server).key 

	# Create a signing request for our CA
	make CSR_EXT="-reqexts v3_req_server" DAYS=$(SERVER_DAYS) $(server).csr

	# Sign the request
	make CRT_EXT="-extensions server_cert" $(server).crt


update-crl:
	make $(CA).crl
	-cat $(CA).db.index


revoke:
	@test $${cert:?"usage: make $@ cert=<name>"}
	openssl ca $(CONF) -revoke $(cert)
	make update-crl


# Generate a private key
%.key:
	@echo
	@echo "**** Generate $@ private key"
	@echo
	openssl genrsa $(KEY_EXT) $(KEY_BITS) >$@

# Generate a signing request
%.csr: %.key
	@echo
	@echo "**** Create a user signing request, $@"
	@echo
	openssl req $(CONF) $(CSR_EXT) -new -days $(DAYS) -key $< -out $@

# Generate a certificate
%.crt: %.csr
	@echo
	@echo "**** Create a user certificate, $@"
	@echo
	openssl ca $(CONF) $(CRT_EXT) -out $@ -infiles $<
	make update-crl

# Create a CA revoke-file
$(CA).crl: $(CA).key $(CA).crt $(CA).db.index
	@echo
	@echo "**** Create CA revoke file, $@"
	@echo
	openssl ca $(CONF) -gencrl -out $@

# Create certification databases (to CA)
%.db.certs:
	if [ ! -d $@ ]; then mkdir $@; fi

%.db.serial:
	if [ ! -f $@ ]; then echo '01' >$@; fi

%.db.index:
	if [ ! -f $@ ]; then touch $@; fi


#
# Create a PKCS12 keybag
#
%.p12: %.crt force
	@echo
	@echo "**** Create a PKCS12 keybag, $@"
	@echo "**** Including certificates CA + '$(inc)'"
	@echo
	NAME="`openssl x509 -noout -text -in $< |grep "Subject:" | sed -e 's/.*CN=//' | sed -e 's/\/.*//'`"; \
	echo; echo "Certificate for '$$NAME'"; \
	echo -n "openssl pkcs12 -export -in $< -inkey $(basename $<).key -name \"$$NAME\" -out $@ -certfile .tmp.crt ">.tmp.sh; \
	echo >.tmp.crt; \
	for cert in $(CA).crt $(inc); do \
		CERTNAME="`openssl x509 -noout -text -in $$cert |grep "Subject:" | sed -e 's/.*CN=//' | sed -e 's/\/.*//'`"; \
		cat $$cert >>.tmp.crt; \
		echo "Adding '$$CERTNAME'"; \
		echo -n "-caname \"$$CERTNAME\" " >>.tmp.sh; \
	done; \
	echo >>.tmp.sh; \
	echo; cat .tmp.sh; \
	. .tmp.sh; \
	rm .tmp.sh .tmp.crt



###########################
#
#  Misc extra functions
#
###########################
info:
	@test $${cert:?"usage: make $@ cert=<cert>"}
	openssl x509 -text -noout -in $(cert)

key-info:
	@test $${key:?"usage: make $@ key=<cert>"}
	openssl rsa -text -noout -in $(key)

crl-info:
	@test $${crl:?"usage: make $@ crl=<crl>"}
	-openssl crl -text -noout -in $(CA).crl

p12-info:
	@test $${p12:?"usage: make $@ p12=<p12>"}
	openssl pkcs12 -in $(p12) -info -nokeys

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
	-rm -rf *~ *.key *.crt *.crl *.csr *.db.* *.p12 .depend

force:

.PRECIOUS: %.key %.crt
