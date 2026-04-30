FROM rust:latest AS pgnats-builder

RUN apt-get update && apt-get install -y \
        curl gnupg lsb-release \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
        https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y \
        postgresql-17 \
        postgresql-server-dev-17 \
        build-essential \
        pkg-config \
        libssl-dev \
        libclang-dev \
        libreadline-dev \
        zlib1g-dev \
        flex \
        bison \
        libxml2-dev \
        libxslt-dev \
        libxml2-utils \
        xsltproc \
    && rm -rf /var/lib/apt/lists/*

RUN cargo install cargo-pgrx --git https://github.com/luxms/pgrx --locked
RUN cargo pgrx init --pg17=/usr/lib/postgresql/17/bin/pg_config

WORKDIR /build
RUN git clone https://github.com/luxms/pgnats.git .
RUN cargo pgrx package --pg-config /usr/lib/postgresql/17/bin/pg_config

FROM timescale/timescaledb-ha:pg17 AS extensions-builder

USER root

RUN apt-get update && apt-get install -y \
        postgresql-server-dev-17 \
        build-essential \
        libmagic-dev \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/nmandery/pg_byteamagic.git /tmp/pg_byteamagic \
    && cd /tmp/pg_byteamagic \
    && make && make install \
    && rm -rf /tmp/pg_byteamagic

RUN git clone https://github.com/EnterpriseDB/system_stats.git /tmp/system_stats \
    && cd /tmp/system_stats \
    && PATH="/usr/lib/postgresql/17/bin:$PATH" make USE_PGXS=1 \
    && make install USE_PGXS=1 \
    && rm -rf /tmp/system_stats

RUN apt-get update && apt-get install -y \
        postgresql-17-plpgsql-check \
    && rm -rf /var/lib/apt/lists/*

FROM timescale/timescaledb-ha:pg17

USER root

COPY --from=pgnats-builder /build/target/release/pgnats-pg17/usr/lib/postgresql/17/lib/ /usr/lib/postgresql/17/lib/
COPY --from=pgnats-builder /build/target/release/pgnats-pg17/usr/share/postgresql/17/extension/ /usr/share/postgresql/17/extension/

COPY --from=extensions-builder /usr/lib/postgresql/17/lib/byteamagic.so /usr/lib/postgresql/17/lib/
COPY --from=extensions-builder /usr/share/postgresql/17/extension/byteamagic* /usr/share/postgresql/17/extension/
COPY --from=extensions-builder /usr/lib/postgresql/17/lib/system_stats.so /usr/lib/postgresql/17/lib/
COPY --from=extensions-builder /usr/share/postgresql/17/extension/system_stats* /usr/share/postgresql/17/extension/
COPY --from=extensions-builder /usr/lib/postgresql/17/lib/plpgsql_check.so /usr/lib/postgresql/17/lib/
COPY --from=extensions-builder /usr/share/postgresql/17/extension/plpgsql_check* /usr/share/postgresql/17/extension/

RUN apt-get update && apt-get install -y libmagic1 && rm -rf /var/lib/apt/lists/*

USER postgres
