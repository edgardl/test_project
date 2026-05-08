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
    HTTP::Tiny \
    JSON::MaybeXS \
    Net::SSLeay \
    IO::Socket::SSL \
    Test::More \
    Mozilla::CA \
    Log::Any \
    Log::Any::Adapter

# Simple unit tests
COPY unit_tests/ /tmp/unit_tests/
COPY scripts/ /tmp/scripts/

# Run prove to validate the reporting logic
RUN prove -lr /tmp/unit_tests/

# Copy script to a standard execution path
COPY scripts/report_to_asana.pl /usr/local/bin/report_to_asana.pl
RUN chmod +x /usr/local/bin/report_to_asana.pl

# Set the default command to run the script
ENTRYPOINT ["perl", "/usr/local/bin/report_to_asana.pl"]
