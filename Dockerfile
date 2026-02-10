FROM openclaw:local

USER root

# Install rclone (Proton Drive sync)
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates bash openssl jq \
    && curl -fsSL https://rclone.org/install.sh | bash \
    && rm -rf /var/lib/apt/lists/*

# Install Proton Pass CLI
ENV PROTON_PASS_CLI_INSTALL_DIR=/usr/local/bin
RUN curl -fsSL https://proton.me/download/pass-cli/install.sh | bash

# Copy our config and scripts
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY setup-telegram.sh /usr/local/bin/setup-telegram.sh
COPY secrets.env /opt/openclaw-proton/secrets.env
COPY openclaw.json.template /opt/openclaw-proton/openclaw.json.template
COPY rclone-exclude.txt /opt/openclaw-proton/rclone-exclude.txt
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/setup-telegram.sh \
    && chown -R node:node /opt/openclaw-proton \
    && mkdir -p /home/node/.openclaw \
    && chown node:node /home/node/.openclaw

USER node

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
