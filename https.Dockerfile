# syntax=docker/dockerfile:1.4

ARG DOMAIN_NAME=kukuyok.online
ARG INSTALL_CERT_DIR=/web/$DOMAIN_NAME/cert


FROM ubuntu:22.04 AS apache-http
SHELL ["/bin/bash", "-c"]
RUN apt update && apt install -y apache2 apache2-utils && apt clean 
EXPOSE 80
EXPOSE 443
CMD ["apache2ctl", "-D", "FOREGROUND"]


## certificate issue ##
FROM ubuntu:22.04 AS cert-issue

ARG DOMAIN_NAME

RUN apt update && apt install -y curl nano && apt clean

WORKDIR "/root"
RUN curl -sOL "https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh" && chmod +x ./acme.sh


## certificate install ##
FROM apache-http AS apache-https

ARG INSTALL_CERT_DIR
ARG DOMAIN_NAME
ARG DOCUMENT_ROOT=/web/${DOMAIN_NAME}/html

# RUN SSL_CONFIG_FILE=/etc/apache2/sites-available/${DOMAIN_NAME}-ssl.conf \
#   && cp /etc/apache2/sites-available/default-ssl.conf ${SSL_CONFIG_FILE} \
#   && SET_VAL() { sed -r -i "s|(#*)?$1\s+\S+|$1 $2|g" ${SSL_CONFIG_FILE} ; } \
#   && SET_VAL SSLCertificateFile ${INSTALL_CERT_DIR}/server.crt \
#   && SET_VAL SSLCertificateKeyFile ${INSTALL_CERT_DIR}/server.key \
#   && SET_VAL SSLCertificateChainFile ${INSTALL_CERT_DIR}/server-ca.crt \
#   && SET_VAL DocumentRoot ${DOCUMENT_ROOT} \
#   && sed -r -i "s|VirtualHost\s+_default_\:443|VirtualHost *:443|g" ${SSL_CONFIG_FILE} \
#   && cat ${SSL_CONFIG_FILE}

ARG SSL_CONFIG_FILE=/etc/apache2/sites-available/${DOMAIN_NAME}-ssl.conf

COPY <<EOF ${SSL_CONFIG_FILE}
<IfModule mod_ssl.c>
	<VirtualHost *:443>
		DocumentRoot /web/${DOMAIN_NAME}/html

        <Directory />
            Require all granted
        </Directory>

		ErrorLog \${APACHE_LOG_DIR}/error.log
		CustomLog \${APACHE_LOG_DIR}/access.log combined

		SSLEngine on
		SSLCertificateFile /web/${DOMAIN_NAME}/cert/server.crt
		SSLCertificateKeyFile /web/${DOMAIN_NAME}/cert/server.key
		SSLCertificateChainFile /web/${DOMAIN_NAME}/cert/server-ca.crt
	</VirtualHost>
</IfModule>
EOF

RUN a2enmod ssl
RUN touch /etc/apache2/sites-available/${DOMAIN_NAME}-ssl.conf && a2ensite ${DOMAIN_NAME}-ssl
