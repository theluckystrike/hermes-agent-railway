# Official Hermes Agent image, pinned by release tag and multi-arch index digest.
# .github/workflows/bump.yml rewrites this line when Nous Research ships a release.
FROM nousresearch/hermes-agent:v0.22.4@sha256:7a69201726bc64db2072a1371557137c23312d29705cda2b8ea2a0214a50a4cf

# The only addition to the official image is the Railway start script (mode 0755 in git).
# ENTRYPOINT stays untouched, so s6-overlay still bootstraps /opt/data as root
# and supervises the gateway.
COPY railway/start.sh /opt/railway/start.sh

# Hermes state lives in /opt/data (HERMES_HOME). Railway mounts the template volume there.
EXPOSE 8642
CMD ["/opt/railway/start.sh"]
