FROM ubuntu:noble

WORKDIR /root/
ENV HOME /root

ENV DEBIAN_FRONTEND noninteractive
ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

ENV WINEPREFIX /root/.wine
ENV DISPLAY :0

ENV IQFEED_INSTALLER_BIN="iqfeed_client_6_2_0_25.exe"
ENV IQFEED_LOG_LEVEL 0xB222

ENV WINEDEBUG -all

# Step 1: Manually fetch and install the missing GPG key.
# This ADD command pulls the key directly from the URL without needing apt/wget.
ADD https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x871920D1991BC93C /tmp/ubuntu-key.asc

# Now properly install the key and clean up. gpg is available in the base image.
RUN gpg --dearmor -o /usr/share/keyrings/ubuntu-archive-keyring-2024.gpg /tmp/ubuntu-key.asc && \
    rm /tmp/ubuntu-key.asc

# Step 2: With the key fixed, perform the update and upgrade. No workarounds needed.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get upgrade -yq

# Step 2: Install system and python dependencies in a single layer to optimize image size
RUN apt-get install -yq --no-install-recommends \
        software-properties-common \
        apt-utils \
        supervisor \
        xvfb \
        wget \
        tar \
        gpg-agent \
        bbe \
        netcat-openbsd \
        net-tools \
        git \
        python3 \
        python3-setuptools \
        python3-numpy \
        python3-pip \
        python3-tz \
        python3-psycopg2 \
        python3-dateutil \
        python3-sqlalchemy \
        python3-pandas && \
    # Cleaning up in the same layer where packages were installed
    apt-get autoremove -y --purge && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Step 3: Install WineHQ
RUN mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources && \
    apt-get update && \
    apt-get install -yq --no-install-recommends winehq-stable winbind winetricks cabextract && \
    wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
    chmod +x winetricks && mv winetricks /usr/local/bin && \
    # Cleaning up
    apt-get autoremove -y --purge && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Init wine instance
RUN \
    winecfg && wineserver --wait
# Download iqfeed client
RUN \
    wget -nv http://www.iqfeed.net/$IQFEED_INSTALLER_BIN -O /root/$IQFEED_INSTALLER_BIN
# Install iqfeed client
RUN \
    xvfb-run -s -noreset -a wine64 /root/$IQFEED_INSTALLER_BIN /S && wineserver --wait
RUN \
    wine64 reg add HKEY_CURRENT_USER\\\Software\\\DTN\\\IQFeed\\\Startup /t REG_DWORD /v LogLevel /d $IQFEED_LOG_LEVEL /f && wineserver --wait
RUN \
    # Add pyiqfeed 
    git clone https://github.com/jaikumarm/pyiqfeed.git && \
    cd pyiqfeed && \
    python3 setup.py install && \
    cd .. && rm -rf pyiqfeed && \
    # 'hack' to allow the client to listen on other interfaces
    bbe -e 's/127.0.0.1/000.0.0.0/g' "/root/.wine/drive_c/Program Files/DTN/IQFeed/iqconnect.exe" > "/root/.wine/drive_c/Program Files/DTN/IQFeed/iqconnect_patched.exe" && \
    rm -rf /root/.wine/.cache

ADD launch_iqfeed.py /root/launch_iqfeed.py
ADD pyiqfeed_admin_conn.py /root/pyiqfeed_admin_conn.py
ADD is_iqfeed_running.py /root/is_iqfeed_running.py
ADD iqfeed_startup.sh /root/iqfeed_startup.sh
RUN chmod +x /root/iqfeed_startup.sh && mkdir -p /root/DTN/IQFeed

ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 5009 9100 9200 9300 9400 
EXPOSE 5900 8080

CMD ["/usr/bin/supervisord"]
