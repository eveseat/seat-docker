#!/bin/bash

# This script attempts to bootstrap an environment, ready to
# use as a docker installation for SeAT.

# 2018 - 2020 @leonjza

SEAT_DOCKER_INSTALL=/opt/seat-docker

set -e

# Running as root?
if (( $EUID != 0 )); then

    echo "Please run as root"
    exit
fi

# Have curl?
if ! [ -x "$(command -v curl)" ]; then

    echo "curl is not installed."
    exit 1
fi

# Have docker?
if ! [ -x "$(command -v docker)" ]; then

    echo "Docker is not installed. Installing..."

    sh <(curl -fsSL get.docker.com)

    echo "Docker installed"
fi

# Have docker-compose?
if ! [ -x "$(command -v docker-compose)" ]; then

    echo "docker-compose is not installed. Installing..."

    curl -L https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    echo "docker-compose installed"
fi

# Make sure /opt/seat-docker exists
echo "Ensuring $SEAT_DOCKER_INSTALL is available..."
mkdir -p $SEAT_DOCKER_INSTALL
cd $SEAT_DOCKER_INSTALL

echo "Grabbing docker-compose and .env file"
curl -L https://raw.githubusercontent.com/eveseat/scripts/master/docker-compose/docker-compose.yml -o $SEAT_DOCKER_INSTALL/docker-compose.yml
curl -L https://raw.githubusercontent.com/eveseat/scripts/master/docker-compose/.env -o $SEAT_DOCKER_INSTALL/.env
curl -L https://raw.githubusercontent.com/eveseat/scripts/master/docker-compose/my.cnf -o $SEAT_DOCKER_INSTALL/my.cnf

echo "Generating a random database password and writing it to the .env file."
sed -i -- 's/DB_PASSWORD=i_should_be_changed/DB_PASSWORD='$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c22 ; echo '')'/g' .env
echo "Generating an application key and writing it to the .env file."
sed -i -- 's/APP_KEY=insecure/APP_KEY='$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c32 ; echo '')'/g' .env

echo "Starting docker stack. This will download the images too. Please wait..."
docker-compose up -d

echo "Images downloaded. The containers are now iniliatising. To check what is happening, run 'docker-compose logs --tail 5 -f' in /opt/seat-docker"

echo "Done!"

