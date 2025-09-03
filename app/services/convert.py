import subprocess, shutil, os, pathlib, re

APP_ROOT = pathlib.Path(__file__).resolve().parents[1]  # /srv/app
RES = APP_ROOT.parent / "resources"  # /srv/resources
ASSETS = APP_ROOT.parent / "assets"  # /srv/assets

PANDOC_FROM = "markdown+raw_tex+link_attributes+implicit_figures"
PDF_ENGINE = "lualatex"

def build_cmd(inp: pathlib.Path, out_pdf: pathlib.Path, workdir: pathlib.Path,
              meta_override: dict[str, str] | None = None):
  rpaths = [inp.parent, workdir,
            workdir / "assets" / "images",
            workdir / "assets" / "branding"]
  if ASSETS.exists():
    rpaths += [ASSETS, ASSETS / "images", ASSETS / "branding"]
  rpaths = [p for p in rpaths if p.exists()]
  resource_path_arg = os.pathsep.join(str(p) for p in rpaths)

  cmd = [
    "pandoc", str(inp),
    "--from", PANDOC_FROM,
    "--pdf-engine", PDF_ENGINE,
    "--listings",
    "--toc", "--number-sections",
    "--resource-path", resource_path_arg,
    "--output", str(out_pdf),
  ]
  meta_file = RES / "meta.yaml"
  template = RES / "templates" / "eisvogel.tex"
  lua_filter = RES / "filters" / "env.lua"
  if meta_file.exists():
    cmd += ["--metadata-file", str(meta_file)]
  if template.exists():
    cmd += ["--template", str(template)]
  if lua_filter.exists():
    cmd += ["--lua-filter", str(lua_filter)]
  for k, v in (meta_override or {}).items():
    cmd += ["--metadata", f"{k}={v}"]
  return cmd

def _safe_stem(name: str) -> str:
  stem = pathlib.Path(name).stem or "report"
  return re.sub(r'[^A-Za-z0-9._-]+', '_', stem) or "report"

def convert_markdown_tree(workdir: pathlib.Path, md_relpath: str,
                          output_name_hint: str | None = None,
                          meta: dict[str, str] | None = None) -> bytes:
  inp = (workdir / md_relpath).resolve()
  if not inp.is_file():
    raise FileNotFoundError(f"Nie znaleziono pliku Markdown: {md_relpath}")

  if ASSETS.exists():
    shutil.copytree(ASSETS, workdir / "assets", dirs_exist_ok=True)

  out = workdir / (_safe_stem(output_name_hint or inp.name) + ".pdf")
  cmd = build_cmd(inp, out, workdir=workdir, meta_override=meta)
  try:
    subprocess.run(cmd, cwd=workdir, check=True, capture_output=True)
  except subprocess.CalledProcessError as e:
    log = (e.stderr or b"").decode(errors="ignore") + "\n" + (e.stdout or b"").decode(errors="ignore")
    raise RuntimeError(f"Pandoc/LaTeX error:\n{log[:8000]}")
  return out.read_bytes()