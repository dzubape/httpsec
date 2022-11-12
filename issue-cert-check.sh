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
WEB_ROOT_SERVER=/usr/local/apache2/htdocs
WEB_ROOT_LOCAL=`pwd`/web-root

################################################

OK_COLOR='\e[1;33m'
INFO_COLOR='\e[0;36m'
ERROR_COLOR='\e[0;31m'
RESET_COLOR='\e[0m'
print_ok() { echo -e "${OK_COLOR}${1}${RESET_COLOR}" ; }
print_info() { echo -e "${INFO_COLOR}${1}${RESET_COLOR}" ; }
print_error() { echo -e "${ERROR_COLOR}${1}${RESET_COLOR}" ; }

HTTPS_CHECK_IMG=tmp/cert-issue-check
docker build -t ${HTTPS_CHECK_IMG} - <<EOF
FROM httpd:bullseye

# SHELL ["/bin/bash", "-c"]

ARG APACHE_ROOT=/usr/local/apache2
ARG CONF=\${APACHE_ROOT}/conf/httpd.conf
ARG CONF_SSL=\${APACHE_ROOT}/conf/extra/httpd-ssl.conf

RUN uncomment() { KEY=\$1 ; sed -r "s|(#+\s*)+(\b\${KEY}\b.*)|\2|g" ; } \
    && cat \${CONF} \
    | uncomment "LoadModule .*/mod_socache_shmcb.so" \
    | uncomment "LoadModule .*/mod_ssl.so" \
    | uncomment "Include .*/httpd-ssl.conf" \
    > \${CONF}.x && mv \${CONF}.x \${CONF} \
    && cat \${CONF_SSL} \
    | uncomment "SSLCertificateChainFile .*server-ca.crt" \
    > \${CONF_SSL}.x && mv \${CONF_SSL}.x \${CONF_SSL} \
    && echo ">Configs have been configured<"

# RUN echo -n ${CHECK_CONTENT} > ${WEB_ROOT_SERVER}/${CHECK_FILENAME}
EOF

if (( $? ))
then
    print_error "Build ${HTTPS_CHECK_IMG} failed :("
    exit -1
fi

CHECK_FILE=$(openssl rand -base64 32)
CHECK_CONTENT=$(openssl rand -base64 32)
echo -n ${CHECK_CONTENT} > ${WEB_ROOT_LOCAL}/secret.check

docker run --rm \
    -d \
    --name ${HTTPS_CONTAINER} \
    -p 80:80 \
    -p 443:443 \
    -v ${CERT_DIR_LOCAL}/server.crt:/usr/local/apache2/conf/server.crt \
    -v ${CERT_DIR_LOCAL}/server.key:/usr/local/apache2/conf/server.key \
    -v ${CERT_DIR_LOCAL}/server-ca.crt:/usr/local/apache2/conf/server-ca.crt \
    -v ${WEB_ROOT_LOCAL}/secret.check:${WEB_ROOT_SERVER}/${CHECK_FILE} \
    ${HTTPS_CHECK_IMG}

shutdown_https() { docker rm -f ${HTTPS_CONTAINER} ; }

if (( $? ))
then
    print_error "Check image run failed.."
    exit -1
fi

sleep 1
CHECK_RESPONSE=$(curl -s "https://${DOMAIN_NAME}/${CHECK_FILE}")

if (( $? ))
then
    print_error "Check request failed"
    shutdown_https
    exit -1
fi

echo -n "Check response: "
print_info ${CHECK_RESPONSE}

if [ "${CHECK_CONTENT}" != "${CHECK_RESPONSE}" ]
then
    print_error "Request over HTTPS failed. Response contains shit"
    shutdown_https
    exit -1
fi

print_ok "SSL is on and works enough"

docker rm -f ${HTTPS_CONTAINER}

if (( $? ))
then
    print_error "Test container cannot be removed properly. Solve this trouble mannually"
    shutdown_https
    exit -1
fi

print_info "Test container has been removed. See you"