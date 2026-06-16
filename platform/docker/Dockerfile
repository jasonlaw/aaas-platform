FROM nousresearch/hermes-agent:latest

# Install as root
USER root

RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir \
    "mnemosyne-memory[embeddings]" \
    mnemosyne-hermes && \
    chown -R hermes:hermes /opt/hermes/.venv

# Switch back to hermes user (required by official image)
USER hermes
