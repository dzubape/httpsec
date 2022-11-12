#!/bin/bash

if (( $# < 2 ))
then
    echo -e "You need two params:\n\t./$(basename $0) DOMAIN_NAME ADMIN_EMAIL"
    exit -1
fi

DOMAIN_NAME=$1
ADMIN_EMAIL=$2

CERT_DIR_LOCAL=`pwd`/cert-storage/${DOMAIN_NAME}
HTTPS_CONTAINER=cert-issue-https

################################################

HTTPS_CHECK_IMG=tmp/cert-issue-check
docker build -t ${HTTPS_CHECK_IMG} - <<EOF
FROM httpd:bullseye

# SHELL ["/bin/bash", "-c"]

ARG CONF=/usr/local/apache2/conf/httpd.conf
ARG CONF_SSL=/usr/local/apache2/conf/extra/httpd-ssl.conf

RUN echo \${CONF}

RUN UNCOMMENT_DIR() { KEY=\$1 ; sed -r "s|(#+\s*)+(\b\${KEY}\b.*)|\2|g" ; } \
    && cat \${CONF} \
    | UNCOMMENT_DIR "LoadModule .*/mod_socache_shmcb.so" \
    | UNCOMMENT_DIR "LoadModule .*/mod_ssl.so" \
    | UNCOMMENT_DIR "Include .*/httpd-ssl.conf" \
    | UNCOMMENT_DIR "Include .*/httpd-mpm.conf" \
    > \${CONF}.x && mv \${CONF}.x \${CONF} \
    && cat \${CONF_SSL} \
    | UNCOMMENT_DIR "SSLCertificateChainFile .*server-ca.crt" \
    > \${CONF_SSL}.x && mv \${CONF_SSL}.x \${CONF_SSL} \
    && echo ">Configs have been configured<"
EOF

if (( $? )) ; then echo "Build ${HTTPS_CHECK_IMG} failed :(" ; fi

docker run --rm \
    --name ${HTTPS_CONTAINER} \
    -p 80:80 \
    -p 443:443 \
    -v ${CERT_DIR_LOCAL}/server.crt:/usr/local/apache2/conf/server.crt \
    -v ${CERT_DIR_LOCAL}/server.key:/usr/local/apache2/conf/server.key \
    -v ${CERT_DIR_LOCAL}/server-ca.crt:/usr/local/apache2/conf/server-ca.crt \
    ${HTTPS_CHECK_IMG}
