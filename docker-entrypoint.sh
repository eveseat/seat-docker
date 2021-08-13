#!/bin/bash

# The SeAT Container Entrypoint
#
# This script invokes logic depending on the specific service
# command given. The first argument to the script should be
# provided by the `command:` directive in the compose file.

set -e

if ! [[ "$1" =~ ^(web|worker|cron)$ ]]; then
    echo "Usage: $0 [service]"
    echo " Services can be web; worker; cron"
    exit 1
fi

# Wait for MySQL
while ! mysqladmin ping -h"$DB_HOST" -u"$DB_USERNAME" -p"$DB_PASSWORD" -P${DB_PORT:-3306} --silent; do
    echo "MariaDB container might not be ready yet. Sleeping..."
    sleep 3
done

# Wait for Redis
while ! redis-cli -h "$REDIS_HOST" ping; do
    echo "Redis container might not be ready yet. Sleeping..."
    sleep 3
done

# install_plugins
#
# Installs plugins defined by the SEAT_PLUGINS environment
# variable. If called with "migrate", it will also run the
# plugins migrations. Because this function will get called
# from multiple other's when starting services, we want to
# avoid migrations doing weird things, so, just the web
# service should pass this parameter.
function install_plugins() {

    echo "Processing plugins from SEAT_PLUGINS"

    plugins=$(echo -n ${SEAT_PLUGINS} | sed 's/,/ /g')
    if [ ! "$plugins" == "" ]; then

        echo "Installing plugins: ${SEAT_PLUGINS}"

        # Why are we doing it like this?
        #   ref: https://github.com/composer/composer/issues/1874

        # Require the plugins from the environment variable.
        composer require ${plugins} --no-update

        # Update the plugins.
        composer update ${plugins} --no-scripts --no-dev --no-ansi --no-progress

        # Redump the autoloader
        composer dump-autoload

        # Publish assets and migrations and run them.
        php artisan vendor:publish --force --all

        # run migrations if we got the argument
        if [ "$1" = "migrate" ]; then

            echo "Running plugin migrations"
            php artisan migrate

        fi
    fi

    echo "Completed plugins processing"
}

# register_dev_packages
#
# This function will typically get called if the callee found
# a packages/override.json file. The override.json is just 
# another composer.json, but typically with custom paths to
# local packages, fascilitating development worksflows using
# the production docker-compose setup.
function register_dev_packages() {

    echo "Looks like a development install! A composer.json override was found."
    echo "Merging composer.json and override.json..."

    # make a backup from original composer.json
    if [ ! -f "composer.json.bak" ]; then
        cp composer.json composer.json.bak
    fi

    # use JQ to merge both overrider and sourcing composer.json
    jq -s '.[0] as $composer | .[1] as $overrider | $composer | ."autoload-dev"."psr-4" = $composer."autoload-dev"."psr-4" + $overrider.autoload' composer.json.bak packages/override.json > composer.json

    echo "Registering providers manually..."

    # make a backup from original app.php
    if [ ! -f "config/app.php.bak" ]; then
        cp config/app.php config/app.php.bak
    fi

    # use PHP in order to register providers
    php -r 'require "vendor/autoload.php"; $config = require "config/app.php.bak"; $override = json_decode(file_get_contents("packages/override.json")); $config["providers"] = array_merge($config["providers"], $override->providers ?? []); file_put_contents("config/app.php", "<?php return " . var_export($config, true) . ";");'

    # Refresh composer setup
    composer update

    # Redump the autoloader
    composer dump-autoload

    # Publish assets and migrations and run them.
    php artisan vendor:publish --force --all

    # run migrations if we got the argument
    if [ "$1" = "migrate" ]; then

        echo "Running plugin migrations"
        php artisan migrate
    fi
}

# cache_and_docs_generation
#
# This function will populate the route caches
# as well as regenerate the l5 swagger docs
function cache_and_docs_generation() {

    # Clear and repopulate the config cache
    php artisan config:cache
    
    # Clear and repopulate the route cache
    php artisan route:cache
    
    # regenerate the l5-swagger docs. Done late so as to have the correct server url set
    php artisan l5-swagger:generate
}

# start_web_service
#
# this function gets the container ready to start apache.
function start_web_service() {

    echo "Starting first run routines"

    php artisan migrate
    php artisan eve:update:sde -n
    php artisan db:seed --class=Seat\\Console\\database\\seeds\\ScheduleSeeder

    echo "Completed first run routines"

    install_plugins "migrate"

    # register dev packages if setup
    test -f packages/override.json && register_dev_packages "migrate"

    echo "Dumping the autoloader"
    composer dump-autoload

    # Regenerate the caches and docs
    cache_and_docs_generation

    echo "Fixing permissions"
    find /var/www/seat -path /var/www/seat/packages -prune -o -exec chown www-data:www-data {} +

    # lets 🚀
    apache2-foreground
}

# start_worker_service
#
# this function gets the container ready to process jobs.
# it will wait for the source directory to complete composer
# installation before starting up.
function start_worker_service() {

    install_plugins

    # register dev packages if setup
    test -f packages/override.json && register_dev_packages

    # Regenerate the caches and docs
    cache_and_docs_generation

    # fix up permissions for the storage directory
    chown -R www-data:www-data storage

    php artisan horizon
}

# start_cron_service
#
# this function gets the container ready to process the cron schedule.
# it will wait for the source directory to complete composer
# installation before starting up.
function start_cron_service() {

    install_plugins

    # register dev packages if setup
    test -f packages/override.json && register_dev_packages

    # Regenerate the caches and docs
    cache_and_docs_generation

    echo "starting 'cron' loop"

    while :
    do
        php /var/www/seat/artisan schedule:run &
        sleep 60
    done
}

case $1 in
    web)
        echo "starting web service"
        start_web_service
        ;;
    worker)
        echo "starting workers via horizon"
        start_worker_service
        ;;
    cron)
        echo "starting cron service"
        start_cron_service
        ;;
esac
