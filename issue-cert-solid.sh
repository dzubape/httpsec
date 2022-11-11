#!/bin/bash

if (( $# < 2 ))
then
    echo -e "You need two params:\n\t./$(basename $0) DOMAIN_NAME ADMIN_EMAIL"
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

echo "Getting certificate for <${DOMAIN_NAME}>..."

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

echo "acme entrypoint.sh: <${ACME_ENTRYPOINT_ACME}>"

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
    echo "Certificate issue failed. Error code: ${ISSUE_FAILED}"
    exit -1
fi

echo "Search your certificates in ${CERT_DIR_LOCAL}"
ls ${CERT_DIR_LOCAL}

UNCOMMENT_DIR() {

    KEY=$1
    INPUT=
    if (( $# > 1 )); then INPUT="-i $2"; fi
    sed -r "s|(#+\s*)+(\b${KEY}\b.*)|\2|g" ${INPUT}
}


## try use cert ##
SAMPLE_CONF=httpd-ssl.conf
docker run --rm httpd:bullseye cat /usr/local/apache2/conf/httpd.conf | \
UNCOMMENT_DIR "LoadModule .*mod_socache_shmcb.so" | \
UNCOMMENT_DIR "LoadModule .*mod_ssl.so" | \
UNCOMMENT_DIR "Include .*httpd-ssl.conf" > ${SAMPLE_CONF}

HTTPS_CHECK_IMG=tmp/cert-issue-check
docker build -t ${HTTPS_CHECK_IMG} - <<EOF
FROM httpd:bullseye

RUN UNCOMMENT_DIR() { KEY=$1 ; sed -r "s|(#+\s*)+(\b${KEY}\b.*)|\2|g" ; } \
    && CONF=/usr/local/apache2/conf/httpd.conf \
    && cat ${CONF} \
    | UNCOMMENT_DIR "LoadModule .*mod_socache_shmcb.so" \
    | UNCOMMENT_DIR "LoadModule .*mod_ssl.so" \
    | UNCOMMENT_DIR "Include .*httpd-ssl.conf" \
    > ${CONF} \
    && CONF=/usr/local/apache2/conf/extra/httpd-ssl.conf \
    && cat ${CONF} \
    | UNCOMMENT_DIR "SSLCertificateChainFile .*server-ca.crt" \
    > ${CONF}
EOF

docker run --rm -d \
    --name ${HTTPS_CONTAINER} \
    -p 80:80 \
    -p 443:443 \
    -v `pwd`/${SAMPLE_CONF}:/usr/local/apache2/httpd.conf \
    -v ${CERT_DIR_LOCAL}/server.crt:/usr/local/apache2/conf/server.crt \
    -v ${CERT_DIR_LOCAL}/server.key:/usr/local/apache2/conf/server.key \
    -v ${CERT_DIR_LOCAL}/server-ca.crt:/usr/local/apache2/conf/server-ca.crt \
    ${HTTPS_CHECK_IMG}
