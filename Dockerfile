FROM pandoc/latex:3.7.0.2-ubuntu

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    PANDOC_PDF_ENGINE=xelatex

# Python + certy + fonty systemowe dla XeLaTeX
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip ca-certificates \
      fonts-texgyre fonts-dejavu fonts-lmodern fontconfig \
 && update-ca-certificates \
 && fc-cache -f \
 && rm -rf /var/lib/apt/lists/*

# TeX Live + potrzebne paczki
RUN set -eux; \
  tlmgr option repository https://sunsite.icm.edu.pl/pub/CTAN/systems/texlive/tlnet; \
  tlmgr update --self --no-persistent-downloads; \
  tlmgr install --no-persistent-downloads \
    latexmk koma-script xcolor float geometry setspace \
    amsmath amsfonts hyperref bookmark caption \
    mdframed tcolorbox fvextra upquote listings \
    pgf pgfplots csquotes \
    fontspec tex-gyre dejavu \
    titlesec sectsty enumitem wrapfig \
    background pagecolor draftwatermark \
    footmisc footnotebackref \
    babel-polish colortbl pdfcol \
    siunitx l3kernel l3packages l3backend \
    makecell tocloft titling zref needspace \
    placeins adjustbox; \
  mktexlsr

# === VENDOR: tylko niezbędne pliki TeX ===
RUN install -d /tmp/tex/latex/local /tmp/tex/generic/tikz /tmp/templates
# pakiet + biblioteki tikz
COPY resources/tex/tikzfill.sty                      /tmp/tex/latex/local/
COPY resources/tex/tikzfill-common.sty               /tmp/tex/latex/local/
COPY resources/tex/tikzfill.image.sty                /tmp/tex/latex/local/
COPY resources/tex/tikzlibraryfill.image.code.tex    /tmp/tex/generic/tikz/
COPY resources/tex/tikzlibraryfill.hexagon.code.tex  /tmp/tex/generic/tikz/
COPY resources/tex/tikzlibraryfill.rhombus.code.tex  /tmp/tex/generic/tikz/
# pliki treści używane przez \input{templates/...}
COPY resources/templates/vuln_legend.tex /tmp/templates/
COPY resources/templates/vuln_stats.tex  /tmp/templates/

# instalacja do właściwego TEXMFLOCAL + weryfikacja
RUN set -eux; \
  TEXMFLOCAL="$(kpsewhich -var-value=TEXMFLOCAL)"; \
  install -d "$TEXMFLOCAL/tex/latex/local" "$TEXMFLOCAL/tex/generic/tikz" "$TEXMFLOCAL/tex/templates"; \
  mv /tmp/tex/latex/local/* "$TEXMFLOCAL/tex/latex/local/"; \
  mv /tmp/tex/generic/tikz/* "$TEXMFLOCAL/tex/generic/tikz/"; \
  mv /tmp/templates/* "$TEXMFLOCAL/tex/templates/"; \
  mktexlsr; \
  kpsewhich tikzfill.sty; \
  kpsewhich tikzlibraryfill.image.code.tex; \
  kpsewhich templates/vuln_legend.tex; \
  kpsewhich templates/vuln_stats.tex

# Aplikacja
WORKDIR /srv

COPY requirements.txt /srv/requirements.txt
RUN python3 -m venv /srv/.venv && /srv/.venv/bin/pip install -r /srv/requirements.txt

# Użytkownik bez uprawnień + lokalny cache TeX
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
