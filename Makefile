#
# Site/web certificate generator
# $Id$
#

CA_DAYS     = 1100		# Active days of the CA certificate
SERVER_DAYS = 365		# Active days of the server
USER_DAYS   = 365		# Active days of the user

ifeq "$(CONF)" ""
	CONF = "./openssl.cnf"
endif
ifeq "$(CA)" ""
	CA = seldalca
	export CA
endif
ifeq "$(SERVER)" "" 
	SERVER = server
endif
ifeq "$(CERTINC)" ""
	CERTINC = $(SERVER)
endif
ifeq "$(CERT)" ""
	CERT = temp.crt
endif
ifeq "$(KEY_BITS)" ""
	KEY_BITS = 2048
endif


all:
	@echo
	@echo "This makefile allows you to create:"
	@echo "  o Self-signed CA certificate"
	@echo "        make ca"
	@echo "  o Server certificates"
	@echo "        make SERVER=<server> server"
	@echo "  o User certificates"
	@echo "        make <user>.crt"
	@echo
	@echo "Other functions:"
	@echo "  o Compile p12 keybag (CA cert is already included)"
	@echo "        make CERTINC=<certs_to_include> <user>.p12"
	@echo "  o Information about a certificate"
	@echo "        make CERT=<file.crt> info"
	@echo "  o Join certificates"
	@echo "       make CERTINC=<certs_to_include> CERT=<certfile> joincert"
	@echo "  o Remove password from key"
	@echo "       make IN=<in_key> OUT=<out_key> rempwd"



#################################
#
#  Basic certificate functions
#
#################################

#
# Generate a private key
#
%.key:
	@echo
	@echo "**** Generate $@ private key"
	@echo
	openssl genrsa -des3 $(KEY_BITS) >$@

#
# Generate a client signing request
#
%.csr: %.key
	@echo
	@echo "**** Create a user signing request, $@"
	@echo
	openssl req -config $(CONF) -new -days $(USER_DAYS) -key $< -out $@

#
# Generate a client certificate
#
%.crt: %.csr
	@echo
	@echo "**** Create a user certificate, $@"
	@echo
	openssl ca -config $(CONF) -out $@ -infiles $<

#
# Create a self-signed CA certificate
#
$(CA).crt: $(CA).key
	@echo
	@echo "**** Create a self-signed CA certificate"
	@echo
	openssl req -config $(CONF) -extensions v3_ca -reqexts v3_req_ca -new -x509 -days $(CA_DAYS) -key $< -out $@

#
# Create a CA revoke-file
#
$(CA).crl: $(CA).key $(CA).crt $(CA).db.index
	@echo
	@echo "**** Create CA revoke file, $@"
	@echo
	openssl ca -config $(CONF) -gencrl -out $@

#
# Create server signing request
#
$(SERVER).csr: $(SERVER).key
	@echo
	@echo "**** Create server signing request, $@"
	@echo
	openssl req -config $(CONF) -reqexts v3_req_server -new -days $(SERVER_DAYS) -key $< -out $@

#
# Create a server certificate
#
$(SERVER).crt: $(SERVER).csr
	@echo
	@echo "**** Create a server certificate, $@"
	@echo
	openssl ca -config $(CONF) -extensions server_cert -out $@ -infiles $<

#
# Create certification databases (to CA)
#
%.db.certs:
	if [ ! -d $@ ]; then \
		mkdir $@; \
	fi

%.db.serial:
	if [ ! -f $@ ]; then \
		echo '01' >$@; \
	fi

%.db.index:
	if [ ! -f $@ ]; then \
		cp /dev/null $@; \
	fi

#
# The CA targets
#
ca: $(CA)
$(CA): $(CA).key $(CA).crt $(CA).db.certs $(CA).db.serial $(CA).db.index


#
# The server targets
#
server: $(SERVER).key $(SERVER).crt



###########################
#
#  Misc extra functions
#
###########################

#
# Create a PKCS12 keybag
#   make CERTINC=<list_of_certificates> <user>.p12
#
%.p12: %.crt $(addsuffix .crt,$(CERTINC))
	@echo
	@echo "**** Create a PKCS12 keybag, $@"
	@echo "**** Including certificates '$(CERTINC)'"
	@echo
	make CERTINC="$(CA) $(CERTINC)" CERT=temp joincert
	NAME="`openssl x509 -noout -text -in $< |grep "Subject:" | sed -e 's/.*CN=//' | sed -e 's/\/.*//'`"; \
	CANAME="`openssl x509 -noout -text -in $(CA).crt |grep "Subject:" | sed -e 's/.*CN=//' | sed -e 's/\/.*//'`"; \
	openssl pkcs12 -export -in $< -inkey $(basename $<).key -certfile temp.crt -name "$$NAME" -caname "$$CANAME" -out $@
	rm temp.crt

#
# Join certificates
#   make CERTINC=<list_of_certificates> CERT=<dst_cert> joincert
#
joincert: $(addsuffix .crt,$(CERTINC))
	@echo
	@echo "**** Joining certificates '$(CERTINC)' into '$(CERT).crt'"
	@echo
	cat $(addsuffix .crt,$(CERTINC)) >$(CERT).crt

#
# Show the contents of a certificate
#   make CERT=<filename> info
#
info:
	openssl x509 -text -noout -in $(CERT)

#
# Make a private key passwordless
#   make IN=<filename> OUT=<filename> rempwd
#
rempwd:
	openssl rsa -in $(IN) -out $(OUT)


#
# Clean up unused files
#
clean:
	rm -rf *~

distclean:
	@echo "*** Are you certain?  If you are, use 'make distclean_i_am_sure'"

distclean_i_am_sure:
	rm -rf *~ *.key *.crt *.crl *.csr *.db.* *.p12

.PRECIOUS: %.key %.csr %.crt
