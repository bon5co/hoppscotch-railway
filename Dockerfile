# Hoppscotch wrapper for Railway.
# The wrapper does the jobs a template cannot publish as variables: it points the web app, the API and the
# WebSocket at the deploy's own domain, moves Caddy onto Railway's PORT, applies the migrations, lets the backend
# fill its settings table once (it stops itself after that on purpose), closes the open onboarding endpoint and
# seeds an administrator with an access token and an infra token taken from the template variables.
# upstream: hoppscotch/hoppscotch
FROM hoppscotch/hoppscotch:2026.10.1@sha256:09a50aa1831ff1e39dfe73bf672e2bca45e1e73514d656e9be6a91f561071a53

COPY seed.js /tmp/hoppscotch-seed.js
COPY boot.sh /usr/local/bin/railway-boot.sh
RUN chmod +x /usr/local/bin/railway-boot.sh

ENTRYPOINT ["/usr/local/bin/railway-boot.sh"]
