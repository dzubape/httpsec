#!/bin/bash

OK_COLOR='\e[1;33m'
INFO_COLOR='\e[0;36m'
ERROR_COLOR='\e[0;31m'
RESET_COLOR='\e[0m'
print_ok() { echo -e "${OK_COLOR}${1}${RESET_COLOR}" ; }
print_info() { echo -e "${INFO_COLOR}${1}${RESET_COLOR}" ; }
print_error() { echo -e "${ERROR_COLOR}${1}${RESET_COLOR}" ; }

if (( $# < 2 ))
then
    print_error "You need two params:\n\t./$(basename $0) DOMAIN_NAME ADMIN_EMAIL"
    exit -1
fi

DOMAIN_NAME=$1
ADMIN_EMAIL=$2
HTTP_CONTAINER=cert-issue-http
HTTPS_CONTAINER=cert-issue-https

ROOT_ACME=/acme-sh
WEB_ROOT_SERVER=/usr/local/apache2/htdocs
WEB_ROOT_ACME=${ROOT_ACME}/html
WEB_ROOT_LOCAL=`pwd`/web-root

print_info "Getting certificate for <${DOMAIN_NAME}>..."

## Running http-web-server ##
mkdir -p ${WEB_ROOT_LOCAL}

docker run --rm -d \
    -p 80:80 \
    --name ${HTTP_CONTAINER} \
    -v ${WEB_ROOT_LOCAL}:${WEB_ROOT_SERVER} \
    httpd:bullseye

## Building acme-client image ##
ACME_DOCKER_IMG=tmp/acme-sh

docker build -t ${ACME_DOCKER_IMG} - <<EOF
FROM debian:bullseye
WORKDIR ${ROOT_ACME}
RUN apt update && apt install -y curl && apt clean \
&& curl -O https://raw.githubusercontent.com/acmesh-official/acme.sh/7221d488e54dfc6bcb30ca562f6d6e38ec5bf6ce/acme.sh \
&& chmod +x acme.sh
EOF

## Running acme cert-issue ##
CERT_DIR_LOCAL=`pwd`/cert-storage
CERT_DIR_ACME=${WEB_ROOT_ACME}/cert
RAW_CERT_DIR_LOCAL=`pwd`/cert-raw
RAW_CERT_DIR_ACME=/root/.acme.sh
mkdir -p ${CERT_DIR_LOCAL}

## Building acme entrypoint ##
ACME_ENTRYPOINT=entrypoint-acme.sh
ACME_ENTRYPOINT_LOCAL=`pwd`/${ACME_ENTRYPOINT}
ACME_ENTRYPOINT_ACME=${ROOT_ACME}/${ACME_ENTRYPOINT}
cat <<EOF > ${ACME_ENTRYPOINT_LOCAL}
#!/bin/bash
./acme.sh --register-account -m ${ADMIN_EMAIL}
if (( \$? )); then exit -1; fi
./acme.sh --issue -d ${DOMAIN_NAME} -w ${WEB_ROOT_ACME} --force
if (( \$? )); then exit -2; fi
./acme.sh --install-cert -d ${DOMAIN_NAME} \
  --cert-file ${CERT_DIR_ACME}/server.crt \
  --key-file ${CERT_DIR_ACME}/server.key \
  --fullchain-file ${CERT_DIR_ACME}/server-ca.crt
if (( \$? )); then exit -3; fi
EOF
chmod +x ${ACME_ENTRYPOINT_LOCAL}

print_info "acme entrypoint.sh: <${ACME_ENTRYPOINT_ACME}>"

mkdir -p ${RAW_CERT_DIR_LOCAL} ${CERT_DIR_LOCAL}

docker run --rm \
    --name acme-sh \
    -v ${WEB_ROOT_LOCAL}:${WEB_ROOT_ACME} \
    -v ${CERT_DIR_LOCAL}:${CERT_DIR_ACME} \
    -v ${RAW_CERT_DIR_LOCAL}:${RAW_CERT_DIR_ACME} \
    -v ${ACME_ENTRYPOINT_LOCAL}:${ACME_ENTRYPOINT_ACME} \
    --entrypoint ${ACME_ENTRYPOINT_ACME} \
    ${ACME_DOCKER_IMG}

ISSUE_FAILED=$?

docker rm -f ${HTTP_CONTAINER}

if (( ${ISSUE_FAILED} ))
then
    print_error "Certificate issue failed. Error code: ${ISSUE_FAILED}"
    exit -1
fi

print_info "Search your certificates in ${CERT_DIR_LOCAL}"
ls ${CERT_DIR_LOCAL}

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