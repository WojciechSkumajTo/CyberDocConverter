FROM pandoc/latex:3.7.0.2-ubuntu

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
  PIP_DISABLE_PIP_VERSION_CHECK=1 \
  PIP_NO_CACHE_DIR=1 \
  REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
  PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
  PANDOC_PDF_ENGINE=xelatex \
  LANG=C.UTF-8 \
  LC_ALL=C.UTF-8

# Python + certy + fonty + Pygments (dla minted)
RUN apt-get update && apt-get install -y --no-install-recommends \
  python3 python3-venv python3-pip python3-pygments ca-certificates \
  fonts-texgyre fonts-dejavu fonts-lmodern fontconfig \
  && update-ca-certificates && fc-cache -f \
  && rm -rf /var/lib/apt/lists/*

# TeX Live: instalacja pakietów z retry
RUN REPO="https://mirror.ctan.org/systems/texlive/tlnet" \
  && tlmgr option repository "$REPO" \
  && PKGS="\
  koma-script minted babel-polish pgf pgfplots csquotes \
  xcolor float geometry setspace amsmath amsfonts \
  tcolorbox mdframed fvextra upquote siunitx makecell tocloft titling \
  zref needspace placeins adjustbox xurl enumitem booktabs longtable \
  caption hyperref bookmark background pagecolor afterpage pdfcol \
  " \
  && for i in 1 2 3 4 5; do \
  tlmgr install --no-persistent-downloads $PKGS && break || sleep 5; \
  done \
  && mktexlsr \
  && which kpsewhich \
  && kpsewhich -var-value=TEXMFROOT \
  && tlmgr --version \
  && kpsewhich scrartcl.cls \
  && kpsewhich minted.sty \
  && kpsewhich pagecolor.sty \
  && kpsewhich afterpage.sty \
  && kpsewhich background.sty \
  && kpsewhich pdfcol.sty \
  && kpsewhich enumitem.sty


# VENDOR pliki TeX + szablony do TEXMFLOCAL
RUN install -d /tmp/tex/latex/local /tmp/tex/generic/tikz /tmp/templates
COPY resources/tex/tikzfill.sty                      /tmp/tex/latex/local/
COPY resources/tex/footnotebackref.sty               /tmp/tex/latex/local/
COPY resources/tex/lineno.sty                        /tmp/tex/latex/local/
COPY resources/tex/tikzfill-common.sty               /tmp/tex/latex/local/
COPY resources/tex/tikzfill.image.sty                /tmp/tex/latex/local/
COPY resources/tex/tikzlibraryfill.image.code.tex    /tmp/tex/generic/tikz/
COPY resources/tex/tikzlibraryfill.hexagon.code.tex  /tmp/tex/generic/tikz/
COPY resources/tex/tikzlibraryfill.rhombus.code.tex  /tmp/tex/generic/tikz/
COPY resources/templates/vuln_legend.tex /tmp/templates/
COPY resources/templates/vuln_stats.tex  /tmp/templates/

RUN TEXMFLOCAL="$(kpsewhich -var-value=TEXMFLOCAL)" \
  && install -d "$TEXMFLOCAL/tex/latex/local" "$TEXMFLOCAL/tex/generic/tikz" "$TEXMFLOCAL/tex/templates" \
  && mv /tmp/tex/latex/local/* "$TEXMFLOCAL/tex/latex/local/" \
  && mv /tmp/tex/generic/tikz/* "$TEXMFLOCAL/tex/generic/tikz/" \
  && mv /tmp/templates/* "$TEXMFLOCAL/tex/templates/" \
  && mktexlsr \
  && kpsewhich tikzfill.sty \
  && kpsewhich tikzlibraryfill.image.code.tex \
  && kpsewhich templates/vuln_legend.tex \
  && kpsewhich templates/vuln_stats.tex

# Aplikacja
WORKDIR /srv
COPY requirements.txt /srv/requirements.txt
RUN python3 -m venv /srv/.venv \
  && /srv/.venv/bin/pip install --upgrade pip \
  && /srv/.venv/bin/pip install -r /srv/requirements.txt

# Użytkownik nieuprzywilejowany + lokalny cache TeX
RUN useradd -m -U -s /bin/bash appuser
ENV PATH="/srv/.venv/bin:${PATH}" \
  UVICORN_WORKERS=2 \
  PYTHONDONTWRITEBYTECODE=1 \
  PYTHONUNBUFFERED=1 \
  HOME=/home/appuser \
  TEXMFVAR=/srv/.texlive-var
RUN install -d -o appuser -g appuser /srv/.texlive-var

COPY --chown=appuser:appuser app /srv/app
COPY --chown=appuser:appuser resources /srv/resources
COPY --chown=appuser:appuser assets /srv/assets

USER appuser

EXPOSE 8000
ENTRYPOINT []
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8000","--timeout-keep-alive","5","--no-server-header"]
