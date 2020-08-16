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
while ! mysqladmin ping -hmariadb -u$MYSQL_USER -p$MYSQL_PASSWORD --silent; do
    echo "MariaDB container might not be ready yet... sleeping..."
    sleep 3
done

# Wait for Redis
while ! redis-cli -h redis ping; do
    echo "Redis container might not be ready yet... sleeping..."
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

    plugins=`echo -n ${SEAT_PLUGINS} | sed 's/,/ /g'`
    if [ ! "$plugins" == "" ]; then

        echo "Installing plugins: ${SEAT_PLUGINS}"

        # Why are we doing it like this?
        #   ref: https://github.com/composer/composer/issues/1874

        # Require the plugins from the environment variable.
        composer require ${plugins} --no-update

        # Update the plugins.
        composer update ${plugins} --no-scripts --no-dev --no-ansi --no-progress

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

# start_web_service
#
# this function gets the container ready to start apache.
function start_web_service() {

    echo "Starting first run routines"

    php -r "file_exists('.env') || copy('.env.example', '.env');"
    php artisan migrate
    php artisan eve:update:sde -n
    php artisan db:seed --class=Seat\\Console\\database\\seeds\\ScheduleSeeder

    echo "Completed first run routines"

    install_plugins "migrate"

    echo "Dumping the autoloader"
    composer dump-autoload

    echo "Fixing permissions"
    chown -R www-data:www-data /var/www/seat

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
