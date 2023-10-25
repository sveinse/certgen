# Certgen v6 - A simple certificate generator
# (C) 2004-2023 Svein Seldal
# Licensed under MIT, see LICENSE
#

###########################
#
#  DEFAULTS
#  Change to your needs
#
###########################

# Default keysize
CA_BITS ?= 8192
SERVER_BITS ?= 4096
KEY_BITS ?= 2048

# Default certificate lifetimes
CA_DAYS ?= 3650
SERVER_DAYS ?= 730
DAYS ?= 365

# Uncomment this to encrypt keys by default
# KEY_OPT ?= -aes256

# Directories for data and obsolete certificates
DIR ?= data
OBSOLETE = obsolete

###########################

# Default configuration
CONFIG ?= openssl.cnf
CONF = -config $(CONFIG)

# For debug output
PS4=>>>  
export PS4

# Running make in subdirs
SUBMAKE = CONFIG=../openssl.cnf DIR=. $(MAKE) -f ../Makefile -s

# Command for running openssl in a subshell with logging
define openssl
	(set -ex; openssl $1)
endef

# Include dependency files if they exist
-include $(DIR)/.depend
export CA = $(ca)


all:
	@echo
	@echo "Seldal CA build system v6 2023-10-22"
	@echo "===================================="
	@echo
	@echo "Data dir: $(DIR)"
	@echo "Root CA : $(if $(ca),$(ca),<unset>)"
	@echo
	@echo "Create certificates:"
	@echo "    make ca ca=<name>                   Make root CA"
	@echo "    make cert n=<name> [t=user|server|ca] [ca=<parent>]"
	@echo "                                        Make certificate, t=type"
	@echo "    make p12 n=<name> [k=1] [ca=<name>]"
	@echo "                                        Generate p12 keybag w/cert and CA"
	@echo "                                        k=1 will include the cert key"
	@echo
	@echo "Update and modify certificates:"
	@echo "    make update-crl [ca=<name>]         Update revocation list"
	@echo "    make revoke n=<name> [ca=<name>]    Revoke a certificate"
	@echo "    make obsolete n=<name>              Move a certificate to $(OBSOLETE)"
	@echo
	@echo "View certificates:"
	@echo "    make ls                             List all certificates"
	@echo "    make ca-info [ca=<name>]            View CA info"
	@echo "    make ca-db-info [ca=<name>]         View CA database"
	@echo "    make crl-info [ca=<name>]           View CA revolcation list"
	@echo "    make info n=<name>                  Certificate info"
	@echo "    make key-info n=<name>              Key info"
	@echo "    make p12-info n=<name>              Get P12 info"
	@echo "    make verify n=<name> [ca=<name>]    Verify certificate"
	@echo
	@echo "Cleanup:  (dangerzone)"
	@echo "    make distclean                      Remove all certificates"
	@echo


###########################
#
#  Main user targets
#
###########################

ca:
	@test $${ca:?"usage: make $@ ca=<name>"}
	@test -e "$(DIR)/$(ca).cert.pem" && \
	    echo "CA $(ca) already exists" && exit 1 || true
	@test "$(root_ca)" && \
	    echo "Root CA $(root_ca) already exists" && exit 1 || true

	@echo
	@echo "**** Create new Root CA certificate $(ca)"

	@mkdir -p $(DIR)
	@( set -e; cd $(DIR); \
	  \
	  # Setup dependencies \
	  if [ ! -e .depend ]; then \
	    echo "root_ca = $(ca)" >.depend; \
	    echo "ca ?= \$$(root_ca)" >>.depend; \
	  fi; \
	  \
	  # Make the key \
	  $(SUBMAKE) KEY_EXT="$(CA_BITS)" $(ca).key.pem \
	  \
	  # Make a signing request (which is the certificate) \
	  $(SUBMAKE) CSR_EXT="-extensions v3_ca -reqexts v3_req_ca -x509 -days $(CA_DAYS)" $(ca).csr.pem; \
	  \
	  # CSR is the certificate when self signed \
	  mv $(ca).csr.pem $(ca).cert.pem; \
	  ln -s $(ca).cert.pem $(ca).chain.cert.pem; \
	  \
	  # Create the remaining CA DB files \
	  $(SUBMAKE) \
	    $(ca).db.certs \
	    $(ca).db.serial \
	    $(ca).db.index \
	    $(ca).db.index.attr \
	    $(ca).crlnumber \
	    $(ca).crl.pem; \
	  \
	  $(SUBMAKE) info n=$(ca); \
	  \
	  printf "\n**** Root CA $(ca) successfully created\n"; \
	)


cert:
	@test $${n:?"usage: make $@ n=<name> [t=user|server|ca] [ca=<parent>]"}
	@test -e "$(DIR)/$(n).cert.pem" && \
	    echo "Certificate $(n) already exists" && exit 1 || true
	@test ! -e "$(DIR)/$(ca).cert.pem" && \
	    echo "CA $(ca) does not exist" && exit 1 || true

	@echo
	@echo "**** Create new certificate $(n)"

	@( set -e; cd $(DIR); \
	  \
	  t="$(if $(t),$(t),user)"; \
	  case "$$t" in \
	    ca) \
	      key_ext="$(CA_BITS)"; \
	      csr_ext="-reqexts v3_req_intermediate_ca"; \
	      crt_ext="-extensions v3_intermediate_ca -days $(CA_DAYS)"; \
	      ;; \
	    server) \
	      key_ext="$(SERVER_BITS)"; \
	      csr_ext="-reqexts v3_req_server -days $(SERVER_DAYS)"; \
	      crt_ext="-extensions v3_server -days $(SERVER_DAYS)"; \
	      ;; \
	    user) \
	      key_ext="$(KEY_BITS)"; \
	      csr_ext="-reqexts v3_req_user -days $(DAYS)"; \
	      crt_ext="-extensions v3_user -days $(DAYS)"; \
	      ;; \
	    *) \
	      echo "Unknown type $(t)"; \
	      exit 1; \
	      ;; \
	  esac; \
	  \
	  # Make the key \
	  $(SUBMAKE) KEY_EXT="$$key_ext" $(n).key.pem; \
	  \
	  # Create a signing request for our CA \
	  $(SUBMAKE) CSR_EXT="$$csr_ext" $(n).csr.pem; \
	  \
	  # Sign the request \
	  $(SUBMAKE) CRT_EXT="$$crt_ext" $(n).cert.pem; \
	  \
	  # Compile the cert chain \
	  $(SUBMAKE) $(n).chain.cert.pem; \
	  \
	  if [ "$$t" = "ca" ]; then \
	    # Create the remaining CA DB files \
	    $(SUBMAKE) \
	      $(n).db.certs \
	      $(n).db.serial \
	      $(n).db.index \
	      $(n).db.index.attr; \
	  fi; \
	  \
	  $(SUBMAKE) ca-db-info; \
	  \
	  printf "\n**** $${t} certificate $(n) signed by $(ca) successfully created\n"; \
	)


p12:
	@test $${n:?"usage: make $@ n=<name> [k=1] [p12=<p12>] [inc=<inc>]"}
	@$(SUBMAKE) -C "$(DIR)" cert-exists

	@echo
	@echo "**** Create a PKCS12 keybag for $(n)"
	@echo

	@( set -e; cd $(DIR); \
	  in="$(n).cert.pem"; \
	  out="$(n).p12"; \
	  NAME="`openssl x509 -noout -text -in $$in | grep "Subject:" | sed -e 's/^\s\+Subject:\s//'`"; \
	  if [ "$(k)" ]; then \
	    printf "Adding certificate and keys from $$in:\n     $$NAME\n"; \
	    echo -n "openssl pkcs12 -export -in $$in -inkey $(n).key.pem -name \"$$NAME\" -out $$out -certfile tmp.cert.pem " >tmp.cert.sh; \
	  else \
	    printf "Adding certificate $$in:\n    $$NAME\n"; \
	    echo -n "openssl pkcs12 -export -in $$in -nokeys -name \"$$NAME\" -out $$out -certfile tmp.cert.pem " >tmp.cert.sh; \
	  fi; \
	  echo >tmp.cert.pem; \
	  for cert in $(ca).chain.cert.pem $(INC); do \
	    CERTNAME="`openssl x509 -noout -text -in $$cert |grep "Subject:" | sed -e 's/^\s\+Subject:\s//'`"; \
	    cat $$cert >>tmp.cert.pem; \
	    printf "Adding certificate(s) from $$cert:\n    $$CERTNAME"; \
	    echo -n "-caname \"$$CERTNAME\" " >>tmp.cert.sh; \
	  done; \
	  echo >>tmp.cert.sh; \
	  printf "\n\n"; cat tmp.cert.sh; \
	  echo; \
	  . ./tmp.cert.sh; \
	  rm tmp.cert.sh tmp.cert.pem; \
	  \
	  printf "\n**** Successful P12 export to $$out\n"; \
	)


update-crl:
	@$(SUBMAKE) -C "$(DIR)" $(ca).crl.pem
	@$(SUBMAKE) -C "$(DIR)" ca-info


revoke:
	@test $${n:?"usage: make $@ n=<name>"}
	@$(SUBMAKE) -C "$(DIR)" cert-exists

	@$(SUBMAKE) -C "$(DIR)" _revoke
	@$(SUBMAKE) -C "$(DIR)" $(ca).crl.pem
	@$(SUBMAKE) -C "$(DIR)" obsolete
	@$(SUBMAKE) -C "$(DIR)" ca-info


obsolete:
	@test $${n:?"usage: make $@ n=<name>"}

	@echo 
	@echo "**** Obsoleting certs $(n)"

	@( set -e; \
	  if [ ! -e "$(DIR)/$(n).key.pem" ]; then \
	    echo "No key/certificate with name $(n)"; \
	    exit 1; \
	  fi; \
	  b="$(DIR)/$(OBSOLETE)"; \
	  mkdir -p "$$b"; \
	  for v in 01 02 03 04 05 06 07 08 09 10; do \
	    if [ -e $$b/$(n).$$v.key.pem ]; then continue; fi ; \
	    for f in "$(DIR)/$(n)."* ; do \
	      d="$$b/$(n).$$v$${f##*/$(n)}"; \
	      mv -v $$f $$d ; \
	    done ; \
	    break ; \
	  done ; \
	)


info:
	@test $${n:?"usage: make $@ n=<name>"}
	@echo 
	@echo "**** Cert info for $(n).cert.pem:"
	@echo
	openssl x509 -text -noout -certopt no_header,no_serial,no_pubkey,no_sigdump,no_signame,no_version -in $(DIR)/$(n).cert.pem


key-info:
	@test $${n:?"usage: make $@ n=<name>"}
	openssl rsa -text -noout -in $(DIR)/$(n).key.pem


ca-db-info: ca-exists
	@echo 
	@echo "**** CA db for $(ca):"
	@echo
	@cat $(DIR)/$(ca).db.index


ca-info: ca-exists
	@$(SUBMAKE) -C "$(DIR)" info n=$(ca)
	@$(SUBMAKE) -C "$(DIR)" ca-db-info n=$(ca)


crl-info: ca-exists
	openssl crl -text -noout -in $(DIR)/$(ca).crl.pem


ls:
	@echo
	@echo "**** Certificates:"
	@echo
	@( set -e; cd "$(DIR)"; \
	  for f in *.cert.pem; do \
	    case "$$f" in \
	      *.chain.cert.pem) continue;; \
	      *) ;; \
	    esac; \
	    echo "$(DIR)/$$f"; \
	    openssl x509 -text -noout -certopt no_header,no_serial,no_pubkey,no_sigdump,no_signame,no_version,no_extensions -in $$f; \
	    echo; \
	  done; \
	)


verify:
	@test $${n:?"usage: make $@ n=<name>"}
	openssl verify -show_chain -CAfile $(DIR)/$(ca).chain.cert.pem $(DIR)/$(n).cert.pem


p12-info:
	@test $${n:?"usage: make $@ n=<name>"}
	openssl pkcs12 -in $(DIR)/$(n).p12 -info -nokeys


distclean:
	@test $${force:?"It wipes everything, use 'make $@ force=1'"}
	-rm -rf $(DIR)

###########################
#
#  Helpers
#
###########################

cert-exists: ca-exists
	@test ! -e "$(DIR)/$(n).cert.pem" && \
	    echo "Certificate $(n) does not exist" && exit 1 || true

ca-exists:
	@test ! -e "$(DIR)/$(ca).cert.pem" && \
	    echo "CA $(ca) does not exist" && exit 1 || true


###########################
#
#  Operations
#
###########################

# Generate a private key
.PRECIOUS: %.key.pem
%.key.pem:
	@echo
	@echo "**** Generate private key $@"
	@echo
	@$(call openssl, genrsa $(KEY_OPT) -out "$@" $(KEY_EXT))

# Generate a signing request
.PRECIOUS: %.csr.pem
%.csr.pem: %.key.pem
	@echo
	@echo "**** Create a signing request $@"
	@echo
	@$(call openssl, req $(CONF) $(CSR_EXT) -new -text -key $< -out $@)

# Generate a certificate
.PRECIOUS: %.cert.pem
%.cert.pem: %.csr.pem
	@echo
	@echo "**** Sign certificate $@ by $(ca)"
	@echo
	@$(call openssl, ca $(CONF) $(CRT_EXT) -md sha512 -out $@ -infiles $<)
	$(SUBMAKE) -C "$(DIR)" $(ca).crl.pem

# Create a CA revoke-file
.PHONY: $(ca).crl.pem
$(ca).crl.pem: $(ca).key.pem $(ca).cert.pem $(ca).db.index $(ca).db.index.attr $(ca).crlnumber
	@echo
	@echo "**** Update CA revoke file $@ for $(ca)"
	@echo
	@$(call openssl, ca $(CONF) -gencrl -out $@)

%.chain.cert.pem: %.cert.pem
	@cat $(ca).chain.cert.pem $< >$@

# Create certification databases (to CA)
%.db.certs:
	mkdir -p $@

%.db.serial:
	if [ ! -f $@ ]; then echo '01' >$@; fi

%.db.index:
	touch $@

%.db.index.attr:
	if [ ! -f $@ ]; then echo "unique_subject = no" >$@; fi

%.crlnumber:
	if [ ! -f $@ ]; then echo '1000' >$@; fi

.PHONY: _revoke
_revoke: $(ca).cert.pem
	@echo
	@echo "**** Revoking certificate $(n) from $(ca)"
	@echo
	@$(call openssl, ca $(CONF) -revoke $(n).cert.pem)


###########################
#
#  Old functions
#
###########################

verify-csr:
	@test $${c:?"usage: make $@ c=<csr>"}
	openssl req -noout -verify -in $(c)

verify-key:
	@test $${k:?"usage: make $@ k=<key>"}
	openssl rsa -noout -check -in $(k)

rempwd:
	@test $${in:?"usage: make $@ in=<in_key> out=<out_key>"}
	@test $${out:?"usage: make $@ in=<in_key> out=<out_key>"}
	openssl rsa -in $(in) -out $(out)
