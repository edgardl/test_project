FROM perl:5.34-slim

# Install only the bare essentials for Postgres and SSL
RUN apt-get update && apt-get install -y \
    libpq-dev \
    libssl-dev \
    pkg-config \
    gcc \
    make \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Perl modules
RUN cpanm --notest \
    DBD::Pg \
    JSON::MaybeXS \
    Net::SSLeay \
    IO::Socket::SSL \
    Mozilla::CA

WORKDIR /app
COPY scripts/report_to_asana.pl .

# No EXPOSE needed as it's not a server
CMD ["perl", "report_to_asana.pl"]
