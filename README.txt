
Tools for creating crypto certificates:


make ca
     To create a self-signed CA. Creates:
        - solidasca.key        CA private key
        - solidasca.crt        CA public certificate
        - solidasca.crl        CA revocation list
        - solidasca.db.certs   All CA signed certificates
        - solidasca.db.index   
        - solidasca.db.serial  Next available certificate serial number

make SERVER=<server> server
     To create a server certificate. Creates:
        - <server>.key         Server private key
        - <server>.crt         Server public certificate

make <user>.crt
     Create a user certificate. Creates:
        - <user>.key           User private key
        - <user>.crt           User public certificate

make CERTINC="<list_of_certs_to_add>" <user>.p12
     Create a p12 keybag. Creates:
        - <user>.p12           A bag of certificates and the user's private key

make CERT=<filename> info
     Print info about the selected certificate

make distclean
     Start everything from scratch. Use with caution!!


Apache
------

Apache requires the following files to work:
    - $(CA).crl
    - $(SERVER).crt
    - $(SERVER).key
    - The certificates of all authorized clients:
         make CERTINC="$(CA) $(SERVER) <list_of_all_clients>" CERT=apache_access.crt joincert
