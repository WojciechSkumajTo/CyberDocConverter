import os, re, shutil, subprocess, pathlib
from typing import Optional

APP_ROOT = pathlib.Path(__file__).resolve().parents[1]
RES = APP_ROOT.parent / "resources"
ASSETS = APP_ROOT.parent / "assets"

PANDOC_FROM = "markdown+autolink_bare_uris+raw_tex+link_attributes-implicit_figures"
PDF_ENGINE = os.getenv("PANDOC_PDF_ENGINE", "xelatex")
PANDOC_TIMEOUT_SEC = 180

def build_cmd(inp: pathlib.Path, out_pdf: pathlib.Path, workdir: pathlib.Path,
              meta_override: Optional[dict[str, str]] = None) -> list[str]:
    rpaths = [p for p in [
        inp.parent, workdir,
        workdir / "assets" / "images", workdir / "assets" / "branding",
        ASSETS if ASSETS.exists() else None,
        ASSETS / "images" if (ASSETS / "images").exists() else None,
        ASSETS / "branding" if (ASSETS / "branding").exists() else None
    ] if p]
    resource_path_arg = os.pathsep.join(str(p) for p in rpaths)

    cmd = [
        "pandoc", str(inp),
        "--from", PANDOC_FROM,
        "--pdf-engine", PDF_ENGINE,
        "--pdf-engine-opt=-shell-escape",   # minted
        "--toc", "--number-sections",
        "--resource-path", resource_path_arg,
        "--output", str(out_pdf),
    ]

    meta_file   = RES / "meta.yaml"
    template    = RES / "templates" / "eisvogel.tex"
    lua_filter  = RES / "filters"  / "env.lua"
    minted_flt  = RES / "filters"  / "minted.lua"  # konwersja CodeBlock -> minted

    if meta_file.exists(): cmd += ["--metadata-file", str(meta_file)]
    if template.exists():  cmd += ["--template", str(template)]
    if lua_filter.exists():cmd += ["--lua-filter", str(lua_filter)]
    if minted_flt.exists():cmd += ["--lua-filter", str(minted_flt)]

    for k, v in (meta_override or {}).items(): cmd += ["--metadata", f"{k}={v}"]

    cmd += ["-V", "minted"]   # odblokuj zmienne minted w szablonie
    return cmd

def _safe_stem(name: str) -> str:
    stem = pathlib.Path(name).stem or "report"
    return re.sub(r"[^A-Za-z0-9._-]+", "_", stem) or "report"

def convert_markdown_tree(workdir: pathlib.Path, md_relpath: str,
                          output_name_hint: Optional[str] = None,
                          meta: Optional[dict[str, str]] = None) -> bytes:
    workdir = workdir.resolve()
    inp = (workdir / md_relpath).resolve()
    try: inp.relative_to(workdir)
    except ValueError: raise PermissionError("md_relpath poza katalogiem roboczym")
    if not inp.is_file(): raise FileNotFoundError(f"Nie znaleziono pliku Markdown: {md_relpath}")

    if ASSETS.exists(): shutil.copytree(ASSETS, workdir / "assets", dirs_exist_ok=True)

    out = workdir / (_safe_stem(output_name_hint or inp.name) + ".pdf")
    cmd = build_cmd(inp, out, workdir=workdir, meta_override=meta)

    env = os.environ.copy()
    env["TEXMFVAR"] = str(workdir / ".texlive-var")
    env["TEXINPUTS"] = f"{RES.as_posix()}//:{workdir.as_posix()}//::"
    env["openin_any"] = "r"
    env["PROJECT_ROOT"] = workdir.as_posix()
    env["INPUT_DIR"] = inp.parent.as_posix()

    try:
        subprocess.run(cmd, cwd=inp.parent, check=True,
                       capture_output=True, timeout=PANDOC_TIMEOUT_SEC, env=env)
    except subprocess.CalledProcessError as e:
        log = (e.stderr or b"").decode(errors="ignore") + "\n" + (e.stdout or b"").decode(errors="ignore")
        raise RuntimeError(f"Pandoc/LaTeX error:\n{log[:8000]}")
    except subprocess.TimeoutExpired:
        raise TimeoutError(f"Pandoc przekroczył limit {PANDOC_TIMEOUT_SEC}s")

    return out.read_bytes()
