FROM pandoc/latex:3.7.0.2-ubuntu

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# Python
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# TeX: tylko wymagane pakiety
RUN tlmgr update --self && tlmgr install \
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
 && mktexlsr

# === VENDOR: pliki TeX ===
RUN install -d /opt/texlive/texmf-local/tex/latex/local \
              /opt/texlive/texmf-local/tex/generic/tikz
COPY resources/tex/tikzfill.sty                                /opt/texlive/texmf-local/tex/latex/local/
COPY resources/tex/tikzfill-common.sty                         /opt/texlive/texmf-local/tex/latex/local/
COPY resources/tex/tikzfill.image.sty                          /opt/texlive/texmf-local/tex/latex/local/
COPY resources/tex/tikzlibraryfill.image.code.tex              /opt/texlive/texmf-local/tex/generic/tikz/
COPY resources/tex/tikzlibraryfill.hexagon.code.tex            /opt/texlive/texmf-local/tex/generic/tikz/
COPY resources/tex/tikzlibraryfill.rhombus.code.tex            /opt/texlive/texmf-local/tex/generic/tikz/
RUN mktexlsr && \
    kpsewhich tikzfill.sty && kpsewhich tikzfill-common.sty && kpsewhich tikzfill.image.sty && \
    kpsewhich tikzlibraryfill.image.code.tex && kpsewhich tikzlibraryfill.hexagon.code.tex && \
    kpsewhich tikzlibraryfill.rhombus.code.tex

# Aplikacja
WORKDIR /srv

COPY requirements.txt /srv/requirements.txt
RUN python3 -m venv /srv/.venv && /srv/.venv/bin/pip install -r /srv/requirements.txt

# Użytkownik bez uprawnień
RUN useradd -m -U -s /bin/bash appuser
# TEXMFVAR aby cache był zapisywalny i nie w HOME roota
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
