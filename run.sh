#!/bin/sh
chown -R site:site /var/www/localhost/htdocs;
exec /usr/sbin/httpd -D FOREGROUND -f /etc/apache2/httpd.conf &
exec php-fpm -F
