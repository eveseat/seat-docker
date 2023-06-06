FROM php:8.2-apache-bullseye

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

# User and Group
RUN groupadd -r -g 200 seat && useradd --no-log-init -r -g seat -u 200 seat

# Install SeAT
RUN cd /var/www && \
    composer create-project eveseat/seat:5.0.x-dev --stability dev --no-scripts --no-dev --no-ansi --no-progress && \
    composer clear-cache --no-ansi && \
    # Fix up the source permissions to be owned by www-data
    chown -R seat:seat /var/www/seat && \
    cd /var/www/seat && \
    # Setup the default configuration file
    php -r "file_exists('.env') || copy('.env.example', '.env');"

# Expose only the public directory to Apache
RUN rmdir /var/www/html && \
    ln -s /var/www/seat/public /var/www/html
RUN a2enmod rewrite

# Changing default Apache port to allow rootless container exploitation
#
# If the Listen specified in the configuration file is default of 80 (or any other port below 1024),
# then it is necessary to have root privileges in order to start apache, so that it can bind to this privileged port.
# Once the server has started and performed a few preliminary activities such as opening its log files, it will launch
# several child processes which do the work of listening for and answering requests from clients. The main httpd process
# continues to run as the root user, but the child processes run as a less privileged user.

RUN sed -i 's/80/8080/g' /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf

WORKDIR /var/www/seat

COPY version /var/www/seat/storage/version
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

USER seat
EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]
