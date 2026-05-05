# syntax=docker/dockerfile:1.6
# Public read-only Doom Emacs viewer served via ttyd.
# The container is the security boundary; the elisp lockdowns in
# config.el are belt-and-suspenders, not the cage.

FROM debian:bookworm-slim AS builder

ARG DOOM_BRANCH=v3.0
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git emacs-nox ripgrep fd-find \
  && rm -rf /var/lib/apt/lists/*

ENV EMACSDIR=/opt/doom-emacs
ENV DOOMDIR=/opt/doom-config
ENV HOME=/tmp/doom-build

RUN git clone --depth 1 --branch ${DOOM_BRANCH} \
      https://github.com/doomemacs/doomemacs.git ${EMACSDIR}

RUN mkdir -p ${DOOMDIR}
COPY init.el config.el packages.el ${DOOMDIR}/

RUN mkdir -p ${HOME} && \
    ${EMACSDIR}/bin/doom sync -u --force

# ---------------------------------------------------------------------

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates ttyd emacs-nox ripgrep fd-find tini curl \
  && rm -rf /var/lib/apt/lists/* \
  && useradd -m -u 1000 -s /bin/sh browse

COPY --from=builder /opt/doom-emacs /opt/doom-emacs
COPY --from=builder /opt/doom-config /opt/doom-config

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0555 /usr/local/bin/entrypoint.sh

USER browse
WORKDIR /home/browse

ENV HOME=/home/browse

EXPOSE 7681

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
