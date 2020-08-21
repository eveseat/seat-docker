#!/bin/bash

# This script attempts to bootstrap an environment, ready to
# use as a docker installation for SeAT.

# 2018 - 2020 @leonjza

set -e

SEAT_DOCKER_INSTALL=/opt/seat-docker

echo "SeAT Docker Bootstrap"
echo
echo "This script will install docker, docker-compose, download"
echo "all of the nessesary container and finally start up a fresh"
echo "SeAT installation."
echo
echo "Everything will live in $SEAT_DOCKER_INSTALL"

read -p "Are you sure you want to continue? [y/n] " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Please type \"y\" to continue"
    exit 1
fi

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
curl -L https://raw.githubusercontent.com/eveseat/seat-docker/master/docker-compose.yml \
    -o $SEAT_DOCKER_INSTALL/docker-compose.yml
curl -L https://raw.githubusercontent.com/eveseat/seat-docker/master/.env \
    -o $SEAT_DOCKER_INSTALL/.env

echo "Generating a random database password and writing it to the .env file."
sed -i -- 's/DB_PASSWORD=i_should_be_changed/DB_PASSWORD='$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c22 ; echo '')'/g' .env
echo "Generating an application key and writing it to the .env file."
sed -i -- 's/APP_KEY=insecure/APP_KEY='$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c32 ; echo '')'/g' .env

echo "Preparing an acme.json file for Traefik and Let's Encrypt"
mkdir acme
touch acme/acme.json
chmod 600 acme/acme.json

echo "Starting docker stack. This will download the images too. Please wait..."
docker-compose up -d

echo "Done! The containers are now iniliatising. To check what is happening, run 'docker-compose logs --tail 5 -f' in /opt/seat-docker"

