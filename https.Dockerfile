# syntax=docker/dockerfile:1.4

ARG DOMAIN_NAME=kukuyok.online
ARG INSTALL_CERT_DIR=/web/$DOMAIN_NAME/cert


FROM ubuntu:22.04 AS apache-http
SHELL ["/bin/bash", "-c"]
RUN apt update && apt install -y apache2 apache2-utils && apt clean 
EXPOSE 80
EXPOSE 443
CMD ["timeout", "80", "apache2ctl", "-D", "FOREGROUND"]


## certificate issue ##
FROM ubuntu:22.04 AS cert-issue

ARG DOMAIN_NAME

RUN apt update && apt install -y curl nano && apt clean

WORKDIR "/root"
RUN curl -sOL "https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh" && chmod +x ./acme.sh


## certificate check ##
FROM apache-http AS apache-https

ARG DOMAIN_NAME

ARG SSL_CONFIG_FILE=/etc/apache2/sites-available/${DOMAIN_NAME}-ssl.conf

COPY default-ssl.conf ${SSL_CONFIG_FILE}
RUN sed -i "s|\${DOMAIN_NAME}|${DOMAIN_NAME}|g" ${SSL_CONFIG_FILE} && cat ${SSL_CONFIG_FILE}
RUN a2enmod ssl
RUN touch ${SSL_CONFIG_FILE} && a2ensite ${DOMAIN_NAME}-ssl

CMD ["apache2ctl", "-D", "FOREGROUND"]
