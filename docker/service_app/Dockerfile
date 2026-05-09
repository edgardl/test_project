FROM perl:5.34-slim

# Install Nginx, Runit, and Postgres dependencies
RUN apt-get update && apt-get install -y \
    nginx \
    runit \
    libpq-dev \
    gcc \
    make \
    && rm -rf /var/lib/apt/lists/*

# Add user with no login shell or home
RUN adduser --system --group --no-create-home appuser

# Install Perl dependencies                                                                                                                                                                                                                 
RUN cpanm --notest \
    Plack \
    Plack::Middleware::Session \
    Starman \
    DBI \
    DBD::Pg \
    DBIx::Connector \
    JSON::MaybeXS \
    Log::Any \
    Log::Any::Adapter

# Copy tests and scripts to a temp area for validation
COPY unit_tests/ /tmp/unit_tests/
COPY scripts/ /tmp/scripts/

# Run tests from the renamed directory
RUN prove -lr /tmp/unit_tests/

# Nginx Config
RUN rm -f /etc/nginx/nginx.conf /etc/nginx/sites-enabled/default
COPY configs/nginx-app.conf /etc/nginx/nginx.conf

# Create all Nginx directories
RUN mkdir -p /etc/nginx/ssl /var/cache/nginx /var/run /var/log/nginx /var/lib/nginx

# Generate self-signed SSL Certificate
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Nginx can run its worker processes and logs without root
RUN chown -R www-data:www-data /var/cache/nginx /var/run /var/log/nginx /var/lib/nginx /etc/nginx/ssl
RUN chmod 600 /etc/nginx/ssl/nginx.key

# App Setup
# Copy script into the path runit and starman expect
RUN mkdir -p /etc/runit/runsvdir/default/starman/scripts
COPY scripts/feedback_app.psgi /service_app/scripts/
RUN chown -R appuser:appuser /service_app

# For PSGI (starman) logs
RUN mkdir -p /var/log/service_app
RUN chown appuser:appuser /var/log/service_app

# Setup Runit Services
# Copy service scripts into the runit directory
COPY services /etc/service/
RUN chmod +x /etc/service/nginx/run && chmod +x /etc/service/starman/run

EXPOSE 9999

# Use runsvdir to manage the /etc/service directory
CMD ["runsvdir", "-P", "/etc/service"]
