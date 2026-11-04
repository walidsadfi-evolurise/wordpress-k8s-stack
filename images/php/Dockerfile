# WordPress code + PHP-FPM, built once per release. No code is written at runtime:
# plugins and themes are added here (composer/wp-cli) and shipped as an image.
ARG WORDPRESS_TAG=6-php8.3-fpm-alpine
FROM wordpress:${WORDPRESS_TAG}

RUN set -eux; \
    apk add --no-cache --virtual .build-deps $PHPIZE_DEPS; \
    pecl install redis; \
    docker-php-ext-enable redis; \
    apk del .build-deps; \
    apk add --no-cache fcgi mariadb-client less; \
    wget -qO /usr/local/bin/php-fpm-healthcheck \
      https://raw.githubusercontent.com/renatomefi/php-fpm-healthcheck/v0.5.0/php-fpm-healthcheck; \
    chmod +x /usr/local/bin/php-fpm-healthcheck; \
    curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; \
    chmod +x /usr/local/bin/wp

# The official image copies WordPress into /var/www/html at *runtime* when the
# directory is empty. On Kubernetes we want the code in the image, so do it now.
RUN set -eux; \
    cp -a /usr/src/wordpress/. /var/www/html/; \
    rm -f /var/www/html/wp-config-sample.php; \
    chown -R www-data:www-data /var/www/html

COPY wp-config.php /var/www/html/wp-config.php
COPY --chown=www-data:www-data mu-plugins/ /var/www/html/wp-content/mu-plugins/

# Plugins and themes pinned per release (add your own below). Object cache drop-in is mandatory.
RUN set -eux; cd /var/www/html; \
    wp --allow-root core version; \
    wp --allow-root plugin install redis-cache --version=2.5.4 --path=/var/www/html --skip-plugins --skip-themes 2>/dev/null || \
      (curl -fsSL -o /tmp/rc.zip https://downloads.wordpress.org/plugin/redis-cache.2.5.4.zip && \
       unzip -q /tmp/rc.zip -d /var/www/html/wp-content/plugins/ && rm /tmp/rc.zip); \
    cp /var/www/html/wp-content/plugins/redis-cache/includes/object-cache.php /var/www/html/wp-content/object-cache.php; \
    chown -R www-data:www-data /var/www/html/wp-content

USER www-data
WORKDIR /var/www/html
# Runtime config (ini, pool) is mounted from the php-config ConfigMap.
CMD ["php-fpm"]
