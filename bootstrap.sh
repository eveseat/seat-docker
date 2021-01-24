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

read -p "Are you sure you want to continue? [Y/n] " -n 1 -r
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

echo    # (optional) move to a new line
echo "Grabbing docker-compose and .env file"
curl -L https://raw.githubusercontent.com/eveseat/seat-docker/master/docker-compose.yml \
    -o $SEAT_DOCKER_INSTALL/docker-compose.yml
curl -L https://raw.githubusercontent.com/eveseat/seat-docker/master/.env \
    -o $SEAT_DOCKER_INSTALL/.env

echo "Generating a random database password and writing it to the .env file."
sed -i -- 's/DB_PASSWORD=i_should_be_changed/DB_PASSWORD='$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c22 ; echo '')'/g' .env
echo "Generating an application key and writing it to the .env file."
sed -i -- 's/APP_KEY=insecure/APP_KEY='$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c32 ; echo '')'/g' .env

echo    # (optional) move to a new line
echo "Setup the domain"
while true; do
  while [ -z "$TRAEFIK_DOMAIN" ]
  do
    read -p "SeAT root domain (eg: example.com): " TRAEFIK_DOMAIN
  done

  while [ -z "$SEAT_SUBDOMAIN" ]
  do
    read -p "SeAT subdomain (eg: seat): " SEAT_SUBDOMAIN
  done

  read -p "SeAT will be served over https://${SEAT_SUBDOMAIN}.${TRAEFIK_DOMAIN} - is that correct ? [Y/n]" -n 1 -r
  echo    # (optional) move to a new line
  case $REPLY in
    [yY]|"") sed -i -- 's/TRAEFIK_DOMAIN=seat.local/TRAEFIK_DOMAIN='"${TRAEFIK_DOMAIN}"'/g' .env
      sed -i -- 's/SEAT_SUBDOMAIN=seat/SEAT_SUBDOMAIN='"${SEAT_SUBDOMAIN}"'/g' .env
      break ;;
    *) TRAEFIK_DOMAIN=''
       SEAT_SUBDOMAIN=''
       echo "No changes have been applied. Please provide the root domain and sub-domain on which SeAT will be served"
  esac
done

echo "Enabling SSL entrypoint"
echo "Please provide a valid e-mail address for Let's Encrypt account creation (this service will handle your SSL certificates) - leave empty to not use SSL"
read -p "e-mail: " ACME_EMAIL
if [ -n "$ACME_EMAIL" ]; then
  sed -i -- 's/TRAEFIK_ACME_EMAIL=you@domain.com/TRAEFIK_ACME_EMAIL='"${ACME_EMAIL}"'/g' .env
  sed -i -- 's/      #- "traefik.http.routers.seat-web.tls.certResolver=primary"/      - "traefik.http.routers.seat-web.tls.certResolver=primary"/g' docker-compose.yml
else
  echo "No e-mail address has been provided, SSL will not be available"
  echo "SeAT will be reachable on http://${SEAT_SUBDOMAIN}.${TRAEFIK_DOMAIN} only"
fi

echo "Preparing an acme.json file for Traefik and Let's Encrypt"
mkdir acme
touch acme/acme.json
chmod 600 acme/acme.json

echo    # (optional) move to a new line
echo "Setup EVE Online Application"
echo "Please go to https://developers.eveonline.com/applications/create in order to create a new application"

if [ -n "$ACME_EMAIL" ]; then
  echo "You must use https://${SEAT_SUBDOMAIN}.${TRAEFIK_DOMAIN}/auth/eve/callback as callback"
else
  echo "You must use http://${SEAT_SUBDOMAIN}.${TRAEFIK_DOMAIN}/auth/eve/callback as callback"
fi

while [ -z "$CLIENT_ID" ]
do
  read -p "Client ID: " CLIENT_ID
done

while [ -z "$CLIENT_SECRET" ]
do
  read -p "Secret Key: " CLIENT_SECRET
done

sed -i -- 's/EVE_CLIENT_ID=null/EVE_CLIENT_ID='"${CLIENT_ID}"'/g' .env
sed -i -- 's/EVE_CLIENT_SECRET=null/EVE_CLIENT_SECRET='"${CLIENT_SECRET}"'/g' .env

echo    # (optional) move to a new line
echo "Starting docker stack. This will download the images too. Please wait..."
docker-compose up -d

echo    # (optional) move to a new line
echo "Done! The containers are now initialising. To check what is happening, run 'docker-compose logs --tail 5 -f' in ${SEAT_DOCKER_INSTALL}"
