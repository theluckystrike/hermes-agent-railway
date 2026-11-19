# Official Hermes Agent image, pinned by release tag and multi-arch index digest.
# .github/workflows/bump.yml rewrites this line when Nous Research ships a release.
FROM nousresearch/hermes-agent:v0.23.2@sha256:d6746a084e9341baada483e3d6210444d3c1aeb7c130f0915150065fb2851459

# The only addition to the official image is the Railway start script (mode 0755 in git).
# ENTRYPOINT stays untouched, so s6-overlay still bootstraps /opt/data as root
# and supervises the gateway.
COPY railway/start.sh /opt/railway/start.sh

# Hermes state lives in /opt/data (HERMES_HOME). Railway mounts the template volume there.
EXPOSE 8642
CMD ["/opt/railway/start.sh"]
