#!/bin/bash

set -euo pipefail

# Variables
NETWORK="feedback-network"
DB_NAME="feedback"
DB_HOST="postgres_db"
SERVICE_APP="test_project"
APP_ENV_FILE="/etc/$SERVICE_APP.env"
ASANA_ENV_FILE="/etc/asana.env"

system_setup() {
    # Update
    echo "Updating system"
    apt-get update

    # Install docker, perl, and postgres
    echo "Installing docker and dependencies"
    apt-get install -y docker.io perl-modules openssl
}

env_setup() {
    # Make sure docker is enabled
    systemctl enable --now docker
    
    # Create docker network for containers to talk to each other (if necessary)
    echo "Creating container network"
    if ! /usr/bin/docker network inspect "$NETWORK" >/dev/null 2>&1; then
	/usr/bin/docker network create "$NETWORK"
    fi

    # Cleanup existing containers for a clean deployment
    echo "Cleaning up old container instances"
    /usr/bin/docker rm -f "$DB_HOST" "$SERVICE_APP" >/dev/null 2>&1 || true
}

start_db() {
    echo "Starting PostgreSQL"
    /usr/bin/docker pull postgres:15
    /usr/bin/docker run -d \
		    --name "$DB_HOST" \
		    --network "$NETWORK" \
		    --log-opt max-size=10m \
		    --log-opt max-file=3 \
		    --restart always \
		    --volume "/var/lib/$DB_HOST:/var/lib/postgresql/data" \
		    --env-file "$APP_ENV_FILE" \
		    postgres:15
    
    echo "Waiting for the container to start (30s timeout)..."
    local success="false"
    for i in {1..30}; do
	if /usr/bin/docker exec "$DB_HOST" pg_isready -U postgres >/dev/null 2>&1; then
	    echo "Database is ready"
            success="true"
	    break
	fi
	# Show some progress (we want to know something is happening)
	echo -n "."
	sleep 1
    done

    if [[ "$success" == "false" ]]; then
	echo "Database failed to start after 30 seconds"
	exit 1
    fi
}

start_app() {
    local app_artifact="ghcr.io/edgardl/test_project/service_app:latest"
    echo "Pulling latest application artifact"
    /usr/bin/docker pull "$app_artifact"

    # Starting feedback app container
    echo "Starting $SERVICE_APP container"
    /usr/bin/docker run -d \
		    --name "$SERVICE_APP" \
		    --network "$NETWORK" \
		    --log-opt max-size=10m \
		    --log-opt max-file=3 \
		    --restart always \
		    -p 80:80 \
		    --env-file "$APP_ENV_FILE" \
		    "$app_artifact"
}

worker_setup() {
    local worker_artifact="ghcr.io/edgardl/test_project/reporting_worker:latest"
    echo "Pulling the worker artifact"
    /usr/bin/docker pull "$worker_artifact"

    # Schedule the 24-hour report (1:00 AM)
    local cron_cmd="0 1 * * * /usr/bin/docker run --rm --network $NETWORK --log-opt max-size=10m --log-opt max-file=3 --env-file $APP_ENV_FILE --env-file $ASANA_ENV_FILE $worker_artifact # reporting_worker_cron"

    # Add to crontab (only if it doesn't exist)
    if ! crontab -l 2>/dev/null | grep -q "reporting_worker_cron"; then
	echo "Adding crontab entry for reporting worker"
	(crontab -l 2>/dev/null ; echo "$cron_cmd") | crontab -
    fi
}

secrets_setup() {
    local project_id="test_project"
    local db_password

    # Check if the password was previously generated (We don't want to lose an existing DB)
    if [[ -f "$APP_ENV_FILE" ]]; then
        echo "Found existing environment file. Extracting current password"
        db_password=$(grep "POSTGRES_PASSWORD=" "$APP_ENV_FILE" | cut -d'=' -f2)
    else
        echo "No existing secrets found. Generating new database password"
        db_password=$(openssl rand -base64 24)
    fi
    
    # Use temporary files to avoid partial files
    local tmp_app_file=$(mktemp)
    local tmp_asana_file=$(mktemp)
    
    echo "Populating protected App environment file"
    {
	# For postgres docker image
	echo "POSTGRES_PASSWORD=$db_password"
	# For feedback app
        echo "DB_PASSWORD=$db_password"
        echo "DB_NAME=$DB_NAME"
        echo "DB_HOST=$DB_HOST"
	echo "DB_TABLE=feedback_data"
    } > "$tmp_app_file"
    mv "$tmp_app_file" "$APP_ENV_FILE"
    
    echo "Populating protected Asana environment file"
    {
	echo "ASANA_PROJECT_ID=$project_id"
        echo "ASANA_TOKEN=$ASANA_TOKEN"
    } > "$tmp_asana_file"
    mv "$tmp_asana_file" "$ASANA_ENV_FILE"
    
    for env_file in "$APP_ENV_FILE" "$ASANA_ENV_FILE"; do
	chown root:root "$env_file"
	chmod 600 "$env_file"
    done
}

main() {
    # Validate Asana token is present before doing anything
    if [[ -z "${ASANA_TOKEN:-}" ]]; then
        if [[ ! -f "$ASANA_ENV_FILE" ]]; then
            echo "Error: ASANA_TOKEN required for initial setup"
            exit 1
        fi
        echo "Using existing ASANA_TOKEN from $ASANA_ENV_FILE"
        ASANA_TOKEN=$(grep "ASANA_TOKEN=" "$ASANA_ENV_FILE" | cut -d'=' -f2)
    fi
    
    echo "Getting the system ready..."
    system_setup

    echo "Getting docker environment ready..."
    secrets_setup
    env_setup

    echo "Starting services..."
    start_db
    start_app
    worker_setup

    echo "Cleaning up old docker images..."
    /usr/bin/docker image prune -f
    
    echo "System ready!"
}

# Everything starts here
main
