FROM nousresearch/hermes-agent:latest

USER root

RUN pip3 install fastembed --break-system-packages

RUN mkdir -p /opt/hermes/plugins && \
    git clone https://github.com/AxDSan/mnemosyne /opt/hermes/plugins/mnemosyne && \
    chown -R hermes:hermes /opt/hermes/plugins

USER hermes
