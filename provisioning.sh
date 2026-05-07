#!/bin/bash

set -euo pipefail

# Variables
LOG_FILE="/var/log/provisioning.log"
NETWORK="feedback-network"
DB_NAME="feedback"
DB_HOST="postgres_db"
SERVICE_APP="test_project"
APP_ENV_FILE="/etc/$SERVICE_APP.env"
ASANA_ENV_FILE="/etc/asana.env"
VERBOSE="false"

##############################################################################
##########        This is only to make possible the review         ###########
##############################################################################
create_reviewer_user() {
    reviewer_user="reviewer"
    reviewer_password=$(openssl rand -base64 12)
    reviewer_file="/etc/reviewer"
    if ! id "$reviewer_user" >/dev/null 2>&1; then
	echo -e "\n\nCreating user \"$reviewer_user\""
	useradd -m -s /bin/bash "$reviewer_user"
	echo "$reviewer_user:$reviewer_password" | chpasswd
	usermod -aG sudo "$reviewer_user"
	echo "$reviewer_password" > "$reviewer_file"
	chown root:root "$reviewer_file"
	chmod 600 "$reviewer_file"
    elif [[ ! -f "$reviewer_file" ]]; then
	echo "$reviewer_user:$reviewer_password" | chpasswd
	echo "$reviewer_password" > "$reviewer_file"
	chown root:root "$reviewer_file"
	chmod 600 "$reviewer_file"
    fi
    echo -e "\nUSER INFORMATION:\n user: $reviewer_user\n password: Check $reviewer_file\n\n"
}
#############################################################################

# Log function
log_generic() {
    local level=$1
    local message=$2

    # Make sure log file exists
    if [[ ! -f "$LOG_FILE" ]]; then
	touch "$LOG_FILE"
    fi
    
    # Format => YYYY-MM-DD.HH:MM:SS [LEVEL] Message
    local log_entry="$(date +%F.%T) [$level] $message"
    
    # Append to log file and print to console
    echo "$log_entry" | tee -a "$LOG_FILE"
}

# Mimick Perl/Python log levels
log_info()  { log_generic "INFO"  "$1"; }
log_warn()  { log_generic "WARN"  "$1"; }
log_error() { log_generic "ERROR" "$1" >&2; }
log_debug() {
    # Only print debug messages when running on verbose mode
    if [[ "$VERBOSE" == "true" ]]; then
        log_generic "DEBUG" "$1"
    fi
}

system_setup() {
    # Update system
    log_info "Updating system"
    apt-get update

    # Install docker, perl, and postgres
    log_info "Installing docker and dependencies"
    package_list="docker.io perl-modules openssl fail2ban openssh-server"
    log_debug "Installing packages: $package_list"
    apt-get install -y $package_list
}

firewall_setup() {
    log_info "Setting up firewall rules"
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH
    log_debug "Allowing traffic on port 22 TCP (SSH)"
    ufw allow 22/tcp
    
    # Allow custom Nginx port
    log_debug "Allowing traffic on port 9999 TCP for feedback app"
    ufw allow 9999/tcp

    # Explicitly ensure 8080 is NOT reachable from outside
    log_debug "Explicitly denying traffic on port 8080 TCP for starman"
    ufw deny 8080/tcp
    
    # Enable firewall
    log_debug "Enabling firewall"
    ufw --force enable
}

sshd_setup() {
    log_info "Setting up SSHD"
    # Backup the config
    log_debug "Backing up file /etc/ssh/sshd_config as /etc/ssh/sshd_config.bak"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # Apply hardening
    log_debug "Modifying SSHD config to disallow root login"
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

    # Restart service
    log_debug "Restarting SSH service"
    systemctl restart ssh
}

start_fail2ban() {
    log_info "Starting fail2ban to monitor SSH access"

    # Default settings should be good enough for SSH (IP with 5 failed attempts is banned for 10 min)
    systemctl enable --now fail2ban
}

env_setup() {
    # Make sure docker is enabled
    log_debug "Enabling docker service"
    systemctl enable --now docker
    
    # Create docker network for containers to talk to each other (if necessary)
    log_info "Creating container network"
    if ! /usr/bin/docker network inspect "$NETWORK" >/dev/null 2>&1; then
	/usr/bin/docker network create "$NETWORK"
    fi

    # Cleanup existing containers for a clean deployment
    log_info "Cleaning up old container instances"
    /usr/bin/docker rm -f "$DB_HOST" "$SERVICE_APP" >/dev/null 2>&1 || true
}

start_db() {
    log_info "Starting PostgreSQL"
    /usr/bin/docker pull postgres:15
    
    # Gracefully stop the DB container (if already exists)
    if docker ps -a --format '{{.Names}}' | grep -q "^$DB_HOST$"; then
	log_info "Stopping existing database gracefully"
	/usr/bin/docker stop -t 30 "$DB_HOST" || true
	/usr/bin/docker rm "$DB_HOST" || true
    fi

    # Start postgres container
    /usr/bin/docker run -d \
		    --name "$DB_HOST" \
		    --network "$NETWORK" \
		    --log-opt max-size=10m \
		    --log-opt max-file=3 \
		    --restart always \
		    --volume "/var/lib/$DB_HOST:/var/lib/postgresql/data" \
		    --env-file "$APP_ENV_FILE" \
		    postgres:15
    
    log_info "Waiting for the container to start (30s timeout)..."
    local success="false"
    for i in {1..30}; do
	if /usr/bin/docker exec "$DB_HOST" pg_isready -U postgres >/dev/null 2>&1; then
	    log_info "Database is ready"
            success="true"
	    break
	fi
	# Show some progress (we want to know something is happening)
	log_info "."
	sleep 1
    done

    if [[ "$success" == "false" ]]; then
	log_error "Database failed to start after 30 seconds"
	exit 1
    fi
}

start_app() {
    local app_artifact="ghcr.io/edgardl/test_project/service_app:latest"
    log_info "Pulling latest application artifact"
    log_debug "Image: $app_artifact"
    /usr/bin/docker pull "$app_artifact"

    # Gracefully stop the service app (if already exists)
    if docker ps -a --format '{{.Names}}' | grep -q "^$SERVICE_APP$"; then
	log_info "Stopping existing service app gracefully"
	/usr/bin/docker stop "$SERVICE_APP" || true
	/usr/bin/docker rm "$SERVICE_APP" || true
    fi
    
    # Starting feedback app container
    log_info "Starting $SERVICE_APP container"
    /usr/bin/docker run -d \
		    --name "$SERVICE_APP" \
		    --network "$NETWORK" \
		    --log-opt max-size=10m \
		    --log-opt max-file=3 \
		    --restart always \
		    -p 9999:9999 \
		    --env-file "$APP_ENV_FILE" \
		    "$app_artifact"
}

worker_setup() {
    local worker_artifact="ghcr.io/edgardl/test_project/reporting_worker:latest"
    log_info "Pulling the worker artifact"
    log_debug "Image: $worker_artifact"
    /usr/bin/docker pull "$worker_artifact"

    # Schedule the 24-hour report (1:00 AM)
    local cron_cmd="0 1 * * * /usr/bin/docker run --rm --network $NETWORK --log-opt max-size=10m --log-opt max-file=3 --env-file $APP_ENV_FILE --env-file $ASANA_ENV_FILE $worker_artifact # reporting_worker_cron"

    # Add to crontab (only if it doesn't exist)
    if ! crontab -l 2>/dev/null | grep -q "reporting_worker_cron"; then
        log_info "Adding crontab entry for reporting worker"
        log_debug "Entry: $cron_cmd"
        (crontab -l 2>/dev/null || true; echo "$cron_cmd") | crontab -
    fi
}

secrets_setup() {
    local project_id="test_project"
    local db_password

    # Check if the password was previously generated (We don't want to lose an existing DB)
    if [[ -f "$APP_ENV_FILE" ]]; then
        log_info "Found existing environment file. Extracting current password"
        db_password=$(grep "POSTGRES_PASSWORD=" "$APP_ENV_FILE" | cut -d'=' -f2)
    else
        log_info "No existing secrets found. Generating new database password"
        db_password=$(openssl rand -base64 24)
    fi
    
    # Use temporary files to avoid partial files
    local tmp_app_file=$(mktemp)
    local tmp_asana_file=$(mktemp)
    
    log_info "Populating protected App environment file"
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
    
    log_info "Populating protected Asana environment file"
    {
	echo "ASANA_PROJECT_ID=$project_id"
        echo "ASANA_TOKEN=$ASANA_TOKEN"
    } > "$tmp_asana_file"
    mv "$tmp_asana_file" "$ASANA_ENV_FILE"
    
    for env_file in "$APP_ENV_FILE" "$ASANA_ENV_FILE"; do
	log_debug "Fixing permissions and ownership on $env_file"
	chown root:root "$env_file"
	chmod 600 "$env_file"
    done
}

main() {
    log_info "================ START ================"
    
    # Validate Asana token is present before doing anything
    if [[ -z "${ASANA_TOKEN:-}" ]]; then
        if [[ -f "$ASANA_ENV_FILE" ]]; then
            log_info "Using existing ASANA_TOKEN from $ASANA_ENV_FILE"
            ASANA_TOKEN=$(grep "ASANA_TOKEN=" "$ASANA_ENV_FILE" | cut -d'=' -f2)
        elif [[ -f "/etc/asana" ]]; then
            log_info "Reading ASANA_TOKEN from /etc/asana"
            ASANA_TOKEN=$(cat /etc/asana)
        else
            log_error "ASANA_TOKEN required. Pass it as a variable, or put it in /etc/asana"
	    show_help
            exit 1
        fi
    fi
    
    log_info "Getting the system ready..."
    system_setup
    firewall_setup
    sshd_setup
    start_fail2ban

    log_info "Getting docker environment ready..."
    secrets_setup
    env_setup

    log_info "Starting services..."
    start_db
    start_app
    worker_setup

    log_info "Cleaning up old docker images..."
    /usr/bin/docker image prune -f
    
    log_info "System ready!"

    # Give reviewer access to this machine
    create_reviewer_user

    log_info "Check $LOG_FILE to access the log of this execution"
    log_info "================= END ================="
}

show_help() {
    cat << EOF
Usage: ASANA_TOKEN=your_token_here ./provisioning_3.sh [options]

This script provisions the feedback system on an Ubuntu server.

Requirements:
  ASANA_TOKEN    If this is an initial setup, the token must be
                 passed as an environment variable OR stored in
                 /etc/asana file.

Options:
  -v             Enable verbose (DEBUG) mode for detailed logging.
  -h             Show this help message and exit.

Example:
  sudo ASANA_TOKEN=1/1234:abcd ./provisioning_3.sh -v
EOF
}

# Parse parameters
while getopts "vh" opt; do
  case $opt in
    h)
      show_help
      exit 0
      ;;
    v)
      VERBOSE="true"
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
done

# Shift off the options
shift $((OPTIND-1))

# Everything starts here
main
