FROM php:7.3-fpm-alpine

# install the PHP extensions we need
# postgresql-dev is needed for https://bugs.alpinelinux.org/issues/3642
RUN set -eux; \
      \
      apk add --no-cache --virtual .build-deps \
      coreutils \
      freetype-dev \
      libjpeg-turbo-dev \
      libpng-dev \
      libzip-dev \
      postgresql-dev \
      ; \
      \
      docker-php-ext-configure gd \
      --with-freetype-dir=/usr/include \
      --with-jpeg-dir=/usr/include \
      --with-png-dir=/usr/include \
      ; \
      \
      docker-php-ext-install -j "$(nproc)" \
      gd \
      opcache \
      pdo \
      pdo_mysql \
      pdo_pgsql \
      zip \
      ; \
      \
      runDeps="$( \
      scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
      | tr ',' '\n' \
      | sort -u \
      | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
      )"; \
      apk add --no-cache apache2-proxy links apache2-ssl apache2-utils vim tzdata $PHPIZE_DEPS $runDeps; \
      apk del .build-deps

RUN cp /usr/share/zoneinfo/Mexico/General /etc/localtime

RUN pecl install xdebug
RUN docker-php-ext-enable xdebug
RUN echo "error_reporting = E_ALL" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
RUN echo "display_startup_errors = On" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
RUN echo "display_errors = On" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
RUN echo "xdebug.remote_enable=1" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
RUN echo "xdebug.remote_connect_back=1" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
RUN echo "xdebug.idekey=\"PHPSTORM\"" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini
RUN echo "xdebug.remote_port=9001" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
  echo 'opcache.memory_consumption=128'; \
  echo 'opcache.interned_strings_buffer=8'; \
  echo 'opcache.max_accelerated_files=4000'; \
  echo 'opcache.revalidate_freq=60'; \
  echo 'opcache.fast_shutdown=1'; \
} > /usr/local/etc/php/conf.d/opcache-recommended.ini
RUN  rm -rf /etc/init.d/*; \
     addgroup -g 1000 -S site; \
     adduser -G site -u 1000 -s /bin/sh -D site

WORKDIR /var/www

COPY httpd.conf /etc/apache2/httpd.conf
COPY www.conf /usr/local/etc/php-fpm.d/www.conf
COPY run.sh /run.sh
COPY index.php /var/www/localhost/htdocs
RUN rm /var/www/localhost/htdocs/index.html
RUN chmod -R 755 /run.sh

EXPOSE 80

CMD ["/run.sh"]
