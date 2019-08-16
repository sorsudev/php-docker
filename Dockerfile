FROM alpine:3.10

ENV PHPIZE_DEPS \
      autoconf \
      dpkg-dev dpkg \
      file \
      g++ \
      gcc \
      libc-dev \
      make \
      pkgconf \
      re2c

RUN apk add --no-cache \
  ca-certificates \
  curl \
  tar \
  xz \
  openssl

RUN set -eux; \
  addgroup -g 82 -S www-data; \
  adduser -u 82 -D -S -G www-data www-data

ENV PHP_INI_DIR /usr/local/etc/php
RUN set -eux; \
      mkdir -p "$PHP_INI_DIR/conf.d"; \
      [ ! -d /var/www/html ]; \
        mkdir -p /var/www/html; \
        chown www-data:www-data /var/www/html; \
        chmod 777 /var/www/html

ENV PHP_EXTRA_CONFIGURE_ARGS --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --disable-cgi

# Apply stack smash protection to functions using local buffers and alloca()
# Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# Enable optimization (-O2)
# Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# Adds GNU HASH segments to generated executables (this is used if present, and is much faster than sysv hash; in this configuration, sysv hash is also generated)
# https://github.com/docker-library/php/issues/272
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"

ENV GPG_KEYS CBAF69F173A0FEA4B537F470D66C9593118BCCB6 F38252826ACD957EF380D39F2F7956BC5DA04B5D

ENV PHP_VERSION 7.3.8
ENV PHP_URL="https://www.php.net/get/php-7.3.8.tar.xz/from/this/mirror" PHP_ASC_URL="https://www.php.net/get/php-7.3.8.tar.xz.asc/from/this/mirror"
ENV PHP_SHA256="f6046b2ae625d8c04310bda0737ac660dc5563a8e04e8a46c1ee24ea414ad5a5" PHP_MD5=""

RUN set -eux; \
  \
  apk add --no-cache --virtual .fetch-deps gnupg; \
  \
  mkdir -p /usr/src; \
  cd /usr/src; \
  \
  curl -fsSL -o php.tar.xz "$PHP_URL"; \
  \
  if [ -n "$PHP_SHA256" ]; then \
  echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; \
  fi; \
  if [ -n "$PHP_MD5" ]; then \
  echo "$PHP_MD5 *php.tar.xz" | md5sum -c -; \
  fi; \
  \
  if [ -n "$PHP_ASC_URL" ]; then \
  curl -fsSL -o php.tar.xz.asc "$PHP_ASC_URL"; \
  export GNUPGHOME="$(mktemp -d)"; \
  for key in $GPG_KEYS; do \
  gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  done; \
  gpg --batch --verify php.tar.xz.asc php.tar.xz; \
  gpgconf --kill all; \
  rm -rf "$GNUPGHOME"; \
  fi; \
  \
  apk del --no-network .fetch-deps

COPY docker-php-source /usr/local/bin/

                RUN set -eux; \
                  apk add --no-cache --virtual .build-deps \
                  $PHPIZE_DEPS \
                  argon2-dev \
                  coreutils \
                  curl-dev \
                  libedit-dev \
                  libsodium-dev \
                  libxml2-dev \
                  openssl-dev \
                  sqlite-dev \
                  ; \
                  \
                  export CFLAGS="$PHP_CFLAGS" \
                  CPPFLAGS="$PHP_CPPFLAGS" \
                  LDFLAGS="$PHP_LDFLAGS" \
                  ; \
                  docker-php-source extract; \
                  cd /usr/src/php; \
                  gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
                  ./configure \
                  --build="$gnuArch" \
                  --with-config-file-path="$PHP_INI_DIR" \
                  --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
                  \
                  --enable-option-checking=fatal \
                  \
                  --with-mhash \
                  \
                  --enable-ftp \
                  --enable-mbstring \
                  --enable-mysqlnd \
                  --with-password-argon2 \
                  --with-sodium=shared \
                  \
                  --with-curl \
                  --with-libedit \
                  --with-openssl \
                  --with-zlib \
                  \
                  $(test "$gnuArch" = 's390x-linux-musl' && echo '--without-pcre-jit') \
                  \
                  ${PHP_EXTRA_CONFIGURE_ARGS:-} \
                  ; \
                  make -j "$(nproc)"; \
                  find -type f -name '*.a' -delete; \
                  make install; \
                  find /usr/local/bin /usr/local/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; \
                  make clean; \
                  \
                  cp -v php.ini-* "$PHP_INI_DIR/"; \
                  \
                  cd /; \
                  docker-php-source delete; \
                  \
                  runDeps="$( \
                  scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
                  | tr ',' '\n' \
                  | sort -u \
                  | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
                  )"; \
                  apk add --no-cache $runDeps; \
                  \
                  apk del --no-network .build-deps; \
                  \
                  pecl update-channels; \
                  rm -rf /tmp/pear ~/.pearrc; \
                  php --version

COPY docker-php-ext-* /usr/local/bin/

RUN docker-php-ext-enable sodium

WORKDIR /var/www/html

RUN set -eux; \
      cd /usr/local/etc; \
      if [ -d php-fpm.d ]; then \
        sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null; \
        cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
      else \
        mkdir php-fpm.d; \
        cp php-fpm.conf.default php-fpm.d/www.conf; \
        { \
          echo '[global]'; \
          echo 'include=etc/php-fpm.d/*.conf'; \
        } | tee php-fpm.conf; \
     fi; \
     { \
       echo '[global]'; \
       echo 'error_log = /proc/self/fd/2'; \
       echo; echo '; https://github.com/docker-library/php/pull/725#issuecomment-443540114'; echo 'log_limit = 8192'; \
       echo; \
       echo '[www]'; \
       echo '; if we send this to /proc/self/fd/1, it never appears'; \
       echo 'access.log = /proc/self/fd/2'; \
       echo; \
       echo 'clear_env = no'; \
       echo; \
       echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
       echo 'catch_workers_output = yes'; \
       echo 'decorate_workers_output = no'; \
     } | tee php-fpm.d/docker.conf; \
     { \
       echo '[global]'; \
       echo 'daemonize = no'; \
       echo; \
       echo '[www]'; \
       echo 'listen = 9000'; \
     } | tee php-fpm.d/zz-docker.conf

STOPSIGNAL SIGQUIT

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
      apk add --no-cache apache2-proxy links apache2-ssl apache2-utils tzdata $PHPIZE_DEPS $runDeps; \
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
