# Official Hermes Agent image, pinned by release tag and multi-arch index digest.
# .github/workflows/bump.yml rewrites this line when Nous Research ships a release.
FROM nousresearch/hermes-agent:v0.23.1@sha256:276d44685c65c0cb2a25f190b63c65c8906f9dc76486fb1c05ae71b5826bda08

# The only addition to the official image is the Railway start script (mode 0755 in git).
# ENTRYPOINT stays untouched, so s6-overlay still bootstraps /opt/data as root
# and supervises the gateway.
COPY railway/start.sh /opt/railway/start.sh

# Hermes state lives in /opt/data (HERMES_HOME). Railway mounts the template volume there.
EXPOSE 8642
CMD ["/opt/railway/start.sh"]
