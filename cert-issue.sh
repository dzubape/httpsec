#!/bin/bash

./acme.sh --register-account -m kukuyok@gmail.com

INSTALL_CERT_DIR=/root/cert
WEB_PROXY_DIR=/root/htdocs
DOMAIN_NAME=$1

./acme.sh --issue -d ${DOMAIN_NAME} -w ${WEB_PROXY_DIR} --force

if (( $? != 0 ))
then
  echo "Certificate issue failure.."
  exit -1
fi

./acme.sh --install-cert -d ${DOMAIN_NAME} \
  --cert-file ${INSTALL_CERT_DIR}/server.crt \
  --key-file ${INSTALL_CERT_DIR}/server.key \
  --fullchain-file ${INSTALL_CERT_DIR}/server-ca.crt