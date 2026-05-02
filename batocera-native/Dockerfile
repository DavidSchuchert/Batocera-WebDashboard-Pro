FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir flask

COPY server.py .
COPY public/ public/

# Fake Batocera-Filesystem für Tests
RUN mkdir -p /userdata/roms/snes /userdata/roms/nes /userdata/roms/gba \
             /userdata/roms/snes/images /userdata/roms/nes/images \
             /userdata/system/logs

RUN touch /userdata/roms/snes/SuperMarioWorld.sfc \
          /userdata/roms/snes/DonkeyKongCountry.sfc \
          /userdata/roms/nes/SuperMarioBros.nes \
          /userdata/roms/nes/Contra.nes \
          /userdata/roms/gba/PokemonFireRed.gba

COPY testdata/roms/snes/gamelist.xml /userdata/roms/snes/gamelist.xml
COPY testdata/roms/nes/gamelist.xml  /userdata/roms/nes/gamelist.xml

RUN echo "global.language=de_DE\nsnes.shaders=scan-lines\n" \
    > /userdata/system/batocera.conf

RUN echo "[INFO] EmulationStation started\n[INFO] Loading theme\n[INFO] Ready" \
    > /userdata/system/logs/emulationstation.log

RUN echo '#!/bin/bash\necho "batocera-linux 40 (20240101)"' > /usr/bin/batocera-version && \
    chmod +x /usr/bin/batocera-version && \
    echo '#!/bin/bash\necho "ok"' > /usr/bin/batocera-settings-set && \
    chmod +x /usr/bin/batocera-settings-set && \
    echo '#!/bin/bash\nsync' > /usr/bin/batocera-save-overlay && \
    chmod +x /usr/bin/batocera-save-overlay

EXPOSE 8080
CMD ["python", "server.py"]
