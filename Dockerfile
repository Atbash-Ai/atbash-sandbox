# Atbash CLI sandbox — isolated test environment
# Build:  docker build -t atbash-sandbox .
# Run:    docker run -it --rm atbash-sandbox

FROM node:22-alpine

# Non-root user (reviewer requirement)
RUN adduser -D -h /home/atbash atbash

# Install CLI globally
RUN npm install -g @atbash/cli@latest

# Switch to non-root user
USER atbash
WORKDIR /home/atbash

# Create config directory with secure permissions
RUN mkdir -p /home/atbash/.config/atbash && chmod 700 /home/atbash/.config/atbash

# Copy test suite and entrypoint
COPY --chown=atbash:atbash test-suite.sh /home/atbash/test-suite.sh
COPY --chown=atbash:atbash entrypoint.sh /home/atbash/entrypoint.sh
RUN chmod +x /home/atbash/test-suite.sh /home/atbash/entrypoint.sh

ENTRYPOINT ["/home/atbash/entrypoint.sh"]
CMD ["sh"]
