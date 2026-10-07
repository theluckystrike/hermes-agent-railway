# Official Hermes Agent image, pinned by release tag and multi-arch index digest.
# .github/workflows/bump.yml rewrites this line when Nous Research ships a release.
FROM nousresearch/hermes-agent:v2026.9.21@sha256:6bece0644e29a347e5ae17db43c36938c86f171c6f5e0cef18aa2075d331f3a3

# The only addition to the official image is the Railway start script.
# ENTRYPOINT stays untouched, so s6-overlay still bootstraps /opt/data as root
# and supervises the gateway.
COPY --chmod=0755 railway/start.sh /opt/railway/start.sh

# Hermes state lives in /opt/data (HERMES_HOME). Railway mounts the template volume there.
EXPOSE 8642
CMD ["/opt/railway/start.sh"]
