# Certgen v8 - A simple certificate generator
# (C) 2004-2023 Svein Seldal
# Licensed under MIT, see LICENSE
#

###########################
#
#  DEFAULTS
#  Change to your needs
#
###########################

# Selectable certificate types
CERT_TYPES = intermediate_ca server user

# Default keysizes for the various certificate types
ca_bits ?= 8192
intermediate_ca_bits ?= 8192
server_bits ?= 4096
user_bits ?= 2048

# Default certificate lifetimes
ca_days ?= 3650
intermediate_ca_days ?= 3650
server_days ?= 730
user_days ?= 365

# Uncomment this to encrypt keys by default
# KEY_OPT ?= -aes256

# Directories for data and obsolete certificates
DIR ?= data
OBSOLETE = obsolete

# Default configuration (must be in the same directory as this Makefile)
CONFIG ?= openssl.cnf

###########################
# Include dependency files if it exist
-include $(DIR)/config
export CA = $(ca)

# Provide default config
config ?= $(CONFIG)
conf := -config $(if $(subconfig),$(subconfig),$(config))

# Logging
define calog
	echo "$(shell date -R): $(1)" >>"$(DIR)/cmdlog.txt"
endef
define shalog
	$(call calog, "$$(sha256sum $(1) | cut -d' ' -f1) $(1)")
endef

# Command for running openssl in a subshell with logging
define openssl
	$(call calog, "CMD: openssl $(1)")
	(set -ex; openssl $1)
endef
define addcert
	grep -x "$(1)" "$(DIR)/certs" || echo "$(1)" >>"$(DIR)/certs"
endef

# Running make in subdirs
SUBMAKE = subconfig=../$(config) DIR=. $(MAKE) -f ../Makefile -s

# Make quirks
empty :=
space := $(empty) $(empty)
comma := $(empty),$(empty)

# For debug output
PS4:=>>>$(space)$(space)
export PS4

# Set default value for "make cert"
t ?= user

# Certificate type alternatives, separated by |
cert_types ?= $(CERT_TYPES)
cert_alt = $(subst $(space),|,$(cert_types))

# Certificate view options
certopt_v = no_header,no_serial,no_pubkey,no_sigdump,no_signame,no_version$(if $(q),$(comma)no_extensions,)
certopt_vq = no_header,no_serial,no_pubkey,no_sigdump,no_signame,no_version$(if $(v),,$(comma)no_extensions)$(if $(q),$(comma)no_validity$(comma)no_issuer,)

all:
	@echo
	@echo "Seldal CA build system v9 2024-12-19"
	@echo "===================================="
	@echo
	@echo "Data dir: $(DIR)"
	@echo "Root CA : $(if $(ca),$(ca),<unset>)"
	@echo
	@echo "Create certificates:"
	@echo "    make ca ca=<name> [config=<file>]   Make root CA. Setting custom"
	@echo "                                        openssl config is optional"
	@echo
	@echo "    make cert n=<name> [t=$(cert_alt)] [ca=<parent>]"
	@echo "                                        Make certificate, t=type"
	@echo
	@echo "    make p12 n=<name> [k=1] [ca=<name>]"
	@echo "                                        Generate p12 cert bundle with"
	@echo "                                        certificate and CA chain."
	@echo "                                        k=1 will include the cert key"
	@echo
	@echo "Available cert types:"
	@$(foreach ct,ca $(cert_types), \
	  printf "    %-16s bits=$($(ct)_bits)  days=$($(ct)_days)\n" "$(ct)"; \
	)
	@echo
	@echo "Update and modify certificates:"
	@echo "    make update-crl [ca=<name>]         Update revocation list"
	@echo "    make revoke n=<name> [ca=<name>]    Revoke a certificate"
	@echo "    make obsolete n=<name>              Move a certificate to $(OBSOLETE)"
	@echo
	@echo "Export certificates:"
	@echo "    make rsync d=<dest> [keys=1]        Rsync certs to <dest>"
	@echo
	@echo "View certificates:"
	@echo "    make info [v=1] [q=1]               List all certificates [verbose, quiet]"
	@echo "    make settings                       List configuration"
	@echo "    make type-info t=<name>             View certificate type info"
	@echo "    make ca-info [ca=<name>]            View CA info"
	@echo "    make ca-db-info [ca=<name>]         View CA database"
	@echo "    make crl-info [ca=<name>]           View CA revolcation list"
	@echo "    make cert-info n=<name> [q=1]       Certificate info [quiet]"
	@echo "    make csr-info n=<name>              Certificate Signing Request (CSR) info"
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

.PHONY: setup
setup:
	@mkdir -p $(DIR)
	@( set -e; cd $(DIR); \
	  \
	  if [ ! -e "config" ]; then \
	    # Setup dependencies \
	    s=config; \
	    echo "root_ca = $(ca)" >$$s; \
	    echo "ca ?= \$$(root_ca)" >>$$s; \
	    echo "config ?= $(config)" >>$$s; \
	    echo "" >>$$s; \
	    echo "cert_types := $(cert_types)" >>$$s; \
	    echo "" >>$$s; \
	    $(foreach ct,ca $(cert_types), \
	      echo "$(ct)_bits := $($(ct)_bits)" >>$$s; \
	      echo "$(ct)_days := $($(ct)_days)" >>$$s; \
	    ) \
	    printf "\n**** Setup new CA config in $(DIR)/config\n"; \
	  fi; \
	)


.PHONY: ca
ca:
	@test $${ca:?"usage: make $@ ca=<name>"}
	@test -e "$(DIR)/$(ca).cert.pem" && \
	    echo "CA $(ca) already exists" && exit 1 || true
	@test "$(root_ca)" && \
	    echo "Root CA $(root_ca) already exists" && exit 1 || true

	@$(MAKE) -s setup ca=$(ca)
	@$(call calog, "--- Create new Root CA certificate ca='$(ca)' config='$(config)'")

	@echo
	@echo "**** Create new Root CA certificate $(ca)"

	@( set -e; cd $(DIR); \
	  \
	  # Make the key \
	  $(SUBMAKE) KEY_EXT="$(ca_bits)" $(ca).key.pem \
	  \
	  # Make a signing request (which is the certificate) \
	  $(SUBMAKE) CSR_EXT="-extensions v3_ca -reqexts v3_req_ca -x509 -days $(ca_days)" $(ca).csr.pem; \
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


.PHONY: key
key:
	@test $${n:?"usage: make $@ n=<name> [t=$(cert_alt)] [ca=<parent>]"}
	@test -e "$(DIR)/$(n).key.pem" && \
	    echo "Key $(n) already exists" && exit 1 || true
	@test ! -e "$(DIR)/$(ca).cert.pem" && \
	    echo "CA $(ca) does not exist" && exit 1 || true

	@$(call calog, "--- Create new key n='$(n)' t='$(t)' ca='$(ca)'")
	@echo
	@echo "**** Create new key $(n)"

	@( set -e; cd $(DIR); \
	  \
	  case "$(t)" in \
	    $(cert_alt)) \
	      key_ext="$($(t)_bits)"; \
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
	  printf "\n**** $(t) key $(n) successfully created\n"; \
	)


.PHONY: cert
cert:
	@test $${n:?"usage: make $@ n=<name> [t=$(cert_alt)] [ca=<parent>]"}
	@test -e "$(DIR)/$(n).cert.pem" && \
	    echo "Certificate $(n) already exists" && exit 1 || true
	@test ! -e "$(DIR)/$(ca).cert.pem" && \
	    echo "CA $(ca) does not exist" && exit 1 || true

	@echo
	@echo "**** Create new certificate '$(n)' of type '$(t)' on CA '$(ca)'"

	@$(MAKE) -s cert-info n=$(ca) q=1
	@$(MAKE) -s type-info t=$(t)

	@$(call calog, "--- Create new certificate n='$(n)' t='$(t)' ca='$(ca)'")

	@( set -e; cd $(DIR); \
	  \
	  case "$(t)" in \
	    $(cert_alt)) \
	      key_ext="$($(t)_bits)"; \
	      csr_ext="-reqexts v3_req_$(t)"; \
	      crt_ext="-extensions v3_$(t) -days $($(t)_days)"; \
	      ;; \
	    *) \
	      echo "Unknown type $(t)"; \
	      exit 1; \
	      ;; \
	  esac; \
	  \
	  # Make the key (if no signing request already exists) \
	  if [ ! -e "$(n).csr.pem" ]; then \
	    $(SUBMAKE) KEY_EXT="$$key_ext" $(n).key.pem; \
	  fi; \
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
	  if [ "$(findstring ca,$(t))" ]; then \
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
	  printf "\n**** $(t) certificate $(n) signed by $(ca) successfully created\n"; \
	)


.PHONY: p12
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


.PHONY: update-crl
update-crl:
	@$(SUBMAKE) -C "$(DIR)" $(ca).crl.pem
	@$(SUBMAKE) -C "$(DIR)" ca-info


.PHONY: revoke
revoke:
	@test $${n:?"usage: make $@ n=<name>"}
	@$(SUBMAKE) -C "$(DIR)" cert-exists

	@$(SUBMAKE) -C "$(DIR)" _revoke
	@$(SUBMAKE) -C "$(DIR)" $(ca).crl.pem
	@$(SUBMAKE) -C "$(DIR)" obsolete
	@$(SUBMAKE) -C "$(DIR)" ca-info


.PHONY: obsolete
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


.PHONY: cert-info
cert-info:
	@test $${n:?"usage: make $@ n=<name> [q=1]"}
	@echo 
	@echo "**** Cert info for $(n).cert.pem"
	@openssl x509 -text -noout -certopt $(certopt_v) -in $(DIR)/$(n).cert.pem


.PHONY: csr-info
csr-info:
	@test $${n:?"usage: make $@ n=<name>"}
	@openssl req -text -noout -reqopt no_sigdump,no_pubkey -in $(DIR)/$(n).csr.pem


.PHONY: type-info
type-info:
	@test $${t:?"usage: make $@ t=<name>"}
	@echo
	@echo "**** Certificate type info for $(t)"
	@echo
	@echo "    Type: $(t)"
	@echo "    Bits: $($(t)_bits)"
	@echo "    Days: $($(t)_days)"
	@echo
	@grep -Pzo '(?s)\[\s*v3_req_$(t)\s*\].*?\n\n' $(CONFIG)
	@grep -Pzo '(?s)\[\s*v3_$(t)\s*\].*?\n\n' $(CONFIG)


.PHONY: key-info
key-info:
	@test $${n:?"usage: make $@ n=<name>"}
	openssl rsa -text -noout -in $(DIR)/$(n).key.pem


.PHONY: ca-db-info
ca-db-info: ca-exists
	@echo 
	@echo "**** CA db for $(ca):"
	@echo
	@cat $(DIR)/$(ca).db.index


.PHONY: ca-info
ca-info: ca-exists
	@$(SUBMAKE) -C "$(DIR)" info n=$(ca)
	@$(SUBMAKE) -C "$(DIR)" ca-db-info n=$(ca)


crl-info: ca-exists
	openssl crl -text -noout -in $(DIR)/$(ca).crl.pem


.PHONY: info ls
info ls:
	@echo
	@echo "**** Certificates:"
	@echo
	@( set -e; cd "$(DIR)"; \
	  while read n; do \
	    if [ -e "$$n.cert.pem" ]; then \
	      f="$$n.cert.pem"; \
	      echo "$(DIR)/$$f"; \
	      openssl x509 -text -noout -certopt $(certopt_vq) -in $$f; \
	      echo; \
	    elif [ -e "$$n.key.pem" ]; then \
	      f="$$n.key.pem"; \
	      echo "$(DIR)/$$f"; \
	      echo -n "        "; \
	      openssl rsa -text -noout -in $$f | head -1; \
	      echo; \
	    fi; \
	  done <certs; \
	)


.PHONY: settings
.PRECIOUS: settings
settings:
	@echo
	@echo "**** Settings:"
	@echo
	@cat $(DIR)/config


.PHONY: verify
verify:
	@test $${n:?"usage: make $@ n=<name>"}
	openssl verify -show_chain -CAfile $(DIR)/$(ca).chain.cert.pem $(DIR)/$(n).cert.pem


.PHONY: p12-info
p12-info:
	@test $${n:?"usage: make $@ n=<name>"}
	openssl pkcs12 -in $(DIR)/$(n).p12 -info -nokeys


.PHONY: rsync
rsync:
	@test $${d:?"usage: make $@ d=<dest> [keys=1]"}
	@( set -e; \
	  if [ "$(keys)" ]; then \
	    opts=--include="*.key.pem"; \
	  else \
	    opts=; \
	  fi; \
	  set -x; \
	  rsync -av --include="*.cert.pem" $$opts --exclude="*" $(DIR)/ $(d)/; \
	)

.PHONY: distclean
distclean:
	@test $${force:?"It wipes everything, use 'make $@ force=1'"}
	-rm -rf $(DIR)


###########################
#
#  Helpers
#
###########################

.PHONY: cert-exists
cert-exists: ca-exists
	@test ! -e "$(DIR)/$(n).cert.pem" && \
	    echo "Certificate $(n) does not exist" && exit 1 || true

.PHONY: ca-exists
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
	@$(call calog, "Private key: $@")
	@echo
	@echo "**** Generate private key $@"
	@echo
	@$(call openssl, genrsa $(KEY_OPT) -out "$@" $(KEY_EXT) $(key_ext))
	@$(call addcert,"$(@:%.key.pem=%)")
	@$(call shalog, "$@")

# Generate a signing request
.PRECIOUS: %.csr.pem
%.csr.pem: %.key.pem
	@$(call calog, "Signing request: $@ from $<")
	@echo
	@echo "**** Create a signing request $@"
	@echo
	@$(call openssl, req $(conf) $(CSR_EXT) $(csr_ext) -new -text -key $< -out $@)
	@$(call addcert,"$(@:%.csr.pem=%)")
	@$(call shalog, "$@")

# Generate a certificate
.PRECIOUS: %.cert.pem
%.cert.pem: %.csr.pem
	@$(call calog, "Sign certificate: $@ from $< by '$(ca)'")
	@echo
	@echo "**** Sign certificate $@ by $(ca)"
	@echo
	@echo "Signing CA:"
	@$(call openssl, x509 -text -noout -certopt $(certopt_vq) -in $(ca).cert.pem)
	@echo
	@$(call openssl, ca $(conf) $(CRT_EXT) $(crt_ext) -out $@ -infiles $<)
	@$(call addcert,"$(@:%.cert.pem=%)")
	$(SUBMAKE) -C "$(DIR)" $(ca).crl.pem
	@$(call shalog, "$@")

# Create a CA revoke-file
.PHONY: $(ca).crl.pem
$(ca).crl.pem: $(ca).key.pem $(ca).cert.pem $(ca).db.index $(ca).db.index.attr $(ca).crlnumber
	@$(call calog, "Certificate revoke list: $@ from $< by '$(ca)'")
	@echo
	@echo "**** Update CA revoke file $@ for $(ca)"
	@echo
	@$(call openssl, ca $(conf) -gencrl -out $@)
	@$(call shalog, "$@")

%.chain.cert.pem: %.cert.pem
	@cat $< $(ca).chain.cert.pem >$@

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
	@$(call openssl, ca $(conf) -revoke $(n).cert.pem)


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
