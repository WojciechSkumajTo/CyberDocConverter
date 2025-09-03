from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import StreamingResponse, FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import io, unicodedata, re, tempfile, pathlib, posixpath
from urllib.parse import quote
from .services.convert import convert_markdown_tree

BASE_DIR = pathlib.Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
TEMPLATES_DIR = BASE_DIR / "templates"

app = FastAPI()
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

@app.get("/")
@app.get("/index.html")
def index():
  idx = TEMPLATES_DIR / "index.html"
  if not idx.is_file():
    raise HTTPException(status_code=500, detail="Brak templates/index.html")
  return FileResponse(idx)

def _content_disposition_utf8(suggested_name: str) -> dict[str, str]:
  ascii_name = unicodedata.normalize("NFKD", suggested_name).encode("ascii","ignore").decode("ascii")
  ascii_name = re.sub(r'[^A-Za-z0-9._-]+', '_', ascii_name) or "report.pdf"
  return {"Content-Disposition": f'attachment; filename="{ascii_name}"; filename*=UTF-8\'\'{quote(suggested_name, safe="")}'}

def _normalize_relpath(p: str | None) -> str | None:
  if not p:
    return None
  p = p.replace("\\", "/").lstrip("/")
  p = posixpath.normpath(p)
  if p in ("", ".", "..") or p.startswith("../"):
    return None
  return p

@app.post("/convert")
async def convert(
  files: list[UploadFile] = File(..., description="Pliki z katalogu; użyj webkitdirectory"),
  entry_md: str | None = Form(None, description="Ścieżka względna do głównego .md")
):
  with tempfile.TemporaryDirectory() as td:
    root = pathlib.Path(td)
    md_candidates: list[str] = []

    for f in files:
      rel = _normalize_relpath(f.filename)
      if not rel:
        continue
      dest = root / rel
      dest.parent.mkdir(parents=True, exist_ok=True)
      try:
        dest.resolve().relative_to(root.resolve())
      except Exception:
        raise HTTPException(status_code=400, detail="Niedozwolona ścieżka pliku.")
      dest.write_bytes(await f.read())
      if rel.lower().endswith((".md", ".markdown")):
        md_candidates.append(rel)

    if not md_candidates:
      raise HTTPException(status_code=400, detail="Brak pliku .md w przesłanym katalogu.")

    md_rel = _normalize_relpath(entry_md) or md_candidates[0]
    if md_rel not in md_candidates and not (root / md_rel).is_file():
      raise HTTPException(status_code=400, detail=f"Nie znaleziono wskazanego pliku Markdown: {md_rel}")

    try:
      pdf_bytes = convert_markdown_tree(root, md_rel, output_name_hint=pathlib.Path(md_rel).stem)
    except Exception as e:
      return JSONResponse(status_code=500, content={"detail": str(e)[:8000]})

    fname_utf8 = f"{pathlib.Path(md_rel).stem}.pdf"
    return StreamingResponse(io.BytesIO(pdf_bytes),
                             media_type="application/pdf",
                             headers=_content_disposition_utf8(fname_utf8))