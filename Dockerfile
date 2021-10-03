FROM php:7.4-apache-bullseye

# OS Packages
RUN export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    zip unzip mariadb-client redis-tools jq \
    libzip-dev libpq-dev libpng-dev libjpeg-dev libgmp-dev libbz2-dev libfreetype6-dev libicu-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# PHP Extentions
RUN pecl install redis && \
    docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg && \
    docker-php-ext-install zip pdo pdo_mysql gd bz2 gmp intl pcntl opcache && \
    docker-php-ext-enable redis

# Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin \
    --filename=composer && hash -r
ENV COMPOSER_MEMORY_LIMIT -1

# Install SeAT
RUN cd /var/www && \
    composer create-project eveseat/seat --stability beta --no-scripts --no-dev --no-ansi --no-progress && \
    composer clear-cache --no-ansi && \
    # Fix up the source permissions to be owned by www-data
    chown -R www-data:www-data /var/www/seat && \
    cd /var/www/seat && \
    # Setup the default configuration file
    php -r "file_exists('.env') || copy('.env.example', '.env');" && \
    # Publish assets and generate API documentation
    php artisan vendor:publish --force --all && \
    php artisan l5-swagger:generate

# Expose only the public directory to Apache
RUN rmdir /var/www/html && \
    ln -s /var/www/seat/public /var/www/html
RUN a2enmod rewrite
EXPOSE 80

WORKDIR /var/www/seat

COPY version /var/www/seat/storage/version
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
