
FROM makeproject

# Clone ixwebsocket
RUN git clone https://github.com/machinezone/IXWebSocket.git /ixwebsocket

WORKDIR /ixwebsocket

# Build ixwebsocket
RUN mkdir -p build && cd build && \
    cmake .. -DUSE_TLS=ON && \
    make -j$(nproc) && \
    make install
