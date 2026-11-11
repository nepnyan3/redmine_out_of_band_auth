FROM redmine:7.0.3@sha256:eff65d7d651d8b07784cbaf37aec5aa74c1ccea3b834e8157e7043c003bdbf70
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY database.yml config/database.yml
COPY Gemfile.lock Gemfile.lock
RUN --mount=type=secret,id=ca \
    if [ -f /run/secrets/ca ]; then export BUNDLE_SSL_CA_CERT=/run/secrets/ca SSL_CERT_FILE=/run/secrets/ca; fi; \
    bundle config unset without && BUNDLE_FROZEN=true bundle install --jobs 4
RUN chown -R 1000:1000 /usr/src/redmine
USER 1000:1000
ENTRYPOINT []
