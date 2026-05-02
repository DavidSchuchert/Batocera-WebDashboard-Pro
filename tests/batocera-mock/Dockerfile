FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    bash \
    procps \
    && rm -rf /var/lib/apt/lists/*

# SSH setup
RUN mkdir /var/run/sshd && \
    echo 'root:linux' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Fake Batocera filesystem
RUN mkdir -p /userdata/roms/snes/images \
             /userdata/roms/nes/images \
             /userdata/roms/gba/images \
             /userdata/roms/psx/images \
             /userdata/roms/n64/images \
             /userdata/system/logs \
             /userdata/system \
             /sys/class/thermal/thermal_zone0

# Fake ROMs
RUN touch /userdata/roms/snes/SuperMarioWorld.sfc \
          /userdata/roms/snes/DonkeyKongCountry.sfc \
          /userdata/roms/snes/Zelda.sfc \
          /userdata/roms/nes/SuperMarioBros.nes \
          /userdata/roms/nes/Contra.nes \
          /userdata/roms/nes/Castlevania.nes \
          /userdata/roms/gba/PokemonFireRed.gba \
          /userdata/roms/gba/MetroidFusion.gba \
          /userdata/roms/n64/MarioKart64.z64 \
          /userdata/roms/psx/FinalFantasy7.chd

# Fake gamelists
COPY roms/snes/gamelist.xml /userdata/roms/snes/gamelist.xml
COPY roms/nes/gamelist.xml /userdata/roms/nes/gamelist.xml

# Fake batocera version + commands
RUN echo "batocera-linux 40 (20240101)" > /usr/share/batocera/batocera.version 2>/dev/null || \
    (mkdir -p /usr/share/batocera && echo "batocera-linux 40 (20240101)" > /usr/share/batocera/batocera.version)

RUN echo '#!/bin/bash\ncat /usr/share/batocera/batocera.version' > /usr/bin/batocera-version && \
    chmod +x /usr/bin/batocera-version

RUN echo '#!/bin/bash\necho "ok"' > /usr/bin/batocera-settings-set && \
    chmod +x /usr/bin/batocera-settings-set

RUN echo '#!/bin/bash\nsync' > /usr/bin/batocera-save-overlay && \
    chmod +x /usr/bin/batocera-save-overlay

RUN echo '#!/bin/bash\necho "volume set"' > /usr/bin/batocera-audio && \
    chmod +x /usr/bin/batocera-audio

# Fake batocera.conf
RUN echo "global.language=de_DE\nglobal.videomode=auto\nsnes.shaders=scan-lines\n" \
    > /userdata/system/batocera.conf

# Fake thermal (55°C = 55000)
RUN echo "55000" > /sys/class/thermal/thermal_zone0/temp

# Fake ES log
RUN echo "[INFO] EmulationStation started\n[INFO] Loading theme\n[INFO] Ready" \
    > /userdata/system/logs/emulationstation.log

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
