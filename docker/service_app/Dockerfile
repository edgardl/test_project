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
    Starman \
    DBI \
    DBD::Pg \
    JSON::MaybeXS \
    Log::Any \
    Log::Any::Adapter

# Nginx Config
RUN rm /etc/nginx/nginx.conf /etc/nginx/sites-enabled/default
COPY configs/nginx-app.conf /etc/nginx/nginx.conf
RUN mkdir -p /var/cache/nginx /var/run && \
    chown -R www-data:www-data /var/cache/nginx /var/run

# Nginx can run its worker processes and logs without root
RUN chown -R www-data:www-data /var/lib/nginx /var/log/nginx

# App Setup
# Copy script into the path runit and starman expect
RUN mkdir -p /etc/runit/runsvdir/default/starman/scripts
COPY scripts/feedback_app.psgi /etc/runit/runsvdir/default/starman/scripts/
RUN chown -R appuser:appuser /etc/runit/runsvdir/default/starman/scripts

# Setup Runit Services
# Copy service scripts into the runit directory
COPY services /etc/service/
RUN chmod +x /etc/service/nginx/run && chmod +x /etc/service/starman/run

EXPOSE 80

# Use runsvdir to manage the /etc/service directory
CMD ["runsvdir", "-P", "/etc/service"]
