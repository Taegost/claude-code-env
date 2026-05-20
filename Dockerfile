FROM node:20-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        tmux \
        git \
        curl \
        ca-certificates \
        gosu \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code and Codeburn globally (accessible to all users)
RUN npm install -g @anthropic-ai/claude-code codeburn

# Install Caveman pinned to 2026-05-17 release.
# Claude Code binary is on PATH at this point, so Caveman detects and installs
# agent-specific hooks alongside the base hook files.
# --non-interactive: skips TTY prompt, installs all detected agents.
RUN curl -fsSL -o /tmp/caveman-install.sh \
        https://raw.githubusercontent.com/juliusbrussee/caveman/18e45320a0b1aecc959a807f8568ee44b3aaa055/install.sh \
    && echo '8ddef49c15f089c26affed3c31d97142c683e1d37a1499ae557281ca09c2712c  /tmp/caveman-install.sh' | sha256sum -c - \
    && bash /tmp/caveman-install.sh --non-interactive \
    && rm /tmp/caveman-install.sh

# Seed defaults before runtime volume mounts can override /root/.claude.
# Marker file: /root/.claude/.caveman-active
RUN mkdir -p /opt/claude-defaults \
    && cp -r /root/.claude/. /opt/claude-defaults/ \
    && chown -R root:root /opt/claude-defaults \
    && chmod -R u+rX,go-rwx /opt/claude-defaults

COPY scripts/docker-entrypoint.sh /scripts/docker-entrypoint.sh
RUN chmod +x /scripts/docker-entrypoint.sh

ENTRYPOINT ["/scripts/docker-entrypoint.sh"]
