-- Ulepszone podpisy (Figure N: …, pogrubiony label, zwykły tekst)
-- Bezpieczeństwo ścieżek: blokada wyjścia poza PROJECT_ROOT

local path = require 'pandoc.path'

-- === Bezpieczeństwo ścieżek ===
local function norm_dir(p) p = path.normalize(p); if p:sub(-1)~="/" then p=p.."/" end; return p end
local function is_within(base,p) base=norm_dir(base); p=path.normalize(p); return p:sub(1,#base)==base end
local function file_exists(p) local f=io.open(p,"rb"); if f then f:close(); return true end; return false end

-- === Pomocnicze ===
local MAX_H = '0.65\\textheight'

local function has_class(attr, name)
  if not attr or not attr.classes then return false end
  for _, c in ipairs(attr.classes) do if c==name then return true end end
  return false
end

local function latex_escape(s)
  if not s or s=='' then return '' end
  local m={['\\']='\\textbackslash{}',['{']='\\{',['}']='\\}',['%']='\\%', ['#']='\\#',['&']='\\&',
           ['_']='\\_', ['^']='\\^{}',['~']='\\textasciitilde{}'}
  return (s:gsub('[\\%%{}#&_^~]', m))
end

local function width_spec(attr)
  if not attr or not attr.attributes then return '\\linewidth' end
  local w=attr.attributes['width']; if not w or w=='' then return '\\linewidth' end
  local p=w:match('^(%d+)%%$'); return p and (tostring(tonumber(p)/100)..'\\linewidth') or w
end

local function caption_text(inlines) return latex_escape(pandoc.utils.stringify(inlines or {})) end

-- === Resolucja ścieżek obrazów z blokadą wyjścia poza projekt ===
local function resolve_image(src)
  if not src or src=='' then return src end
  if src:match("^%a+://") then return src end -- URL zostaw
  local inputdir = os.getenv("INPUT_DIR") or "."
  local project  = path.normalize(os.getenv("PROJECT_ROOT") or inputdir)

  local p1 = path.normalize(path.join({inputdir, src}))
  if file_exists(p1) and is_within(project, p1) then return path.make_relative(p1, inputdir) end

  local p2 = (src:sub(1,1)=="/") and path.normalize(src) or path.normalize(path.join({project, src}))
  if file_exists(p2) and is_within(project, p2) then return path.make_relative(p2, inputdir) end

  return src -- poza projektem: zostaw, TeX zgłosi błąd
end

-- === Globalna konfiguracja stylu podpisów ===
local function inject_caption_setup(meta)
  local tex = [[
\usepackage{caption}
\captionsetup{
  labelfont=bf,
  textfont=normalfont,
  format=plain,
  justification=raggedright,
  singlelinecheck=false,
  skip=6pt
}
]]
  local hi = meta['header-includes'] or pandoc.MetaList{}
  if hi.t ~= 'MetaList' then hi = pandoc.MetaList{hi} end
  table.insert(hi, pandoc.MetaBlocks{ pandoc.RawBlock('latex', tex) })
  meta['header-includes'] = hi
  return meta
end

-- === Budowa bloku obrazka z podpisem ===
local function blocks_image(img)
  local src    = resolve_image(img.src)
  local width  = width_spec(img.attr)

  -- atrybuty: caption / shortcaption / source / label; alt jako fallback
  local cap_attr   = img.attr.attributes and img.attr.attributes["caption"]
  local short_attr = img.attr.attributes and img.attr.attributes["shortcaption"]
  local source_attr= img.attr.attributes and img.attr.attributes["source"]
  local label      = img.attr.attributes and img.attr.attributes["label"]
  if (not label or label=='') and img.attr and img.attr.identifier and img.attr.identifier~='' then
    label = img.attr.identifier
  end

  local cap_base = cap_attr or caption_text(img.caption)
  local cap_full = latex_escape(cap_base)
  if source_attr and source_attr~='' then
    cap_full = cap_full .. "\\\\{\\footnotesize \\textit{Źródło:} " .. latex_escape(source_attr) .. "}"
  end
  local cap_short = short_attr and latex_escape(short_attr) or nil
  local hascap = cap_full ~= ''
  local numbered = hascap and not has_class(img.attr, "nonumber") -- domyślnie numeruj

  local t = {}
  t[#t+1] = pandoc.RawBlock('latex','\\makeatletter\\@ifundefined{pandocImgBox}{\\newsavebox{\\pandocImgBox}}{}\\makeatother')
  t[#t+1] = pandoc.RawBlock('latex',
    '\\sbox{\\pandocImgBox}{\\adjustbox{max width='..width..',max totalheight='..MAX_H..',keepaspectratio}{' ..
    '\\includegraphics{\\detokenize{'..src..'}}}}')
  t[#t+1] = pandoc.RawBlock('latex','\\needspace{\\dimexpr\\ht\\pandocImgBox+\\dp\\pandocImgBox+1.2\\baselineskip\\relax}')
  t[#t+1] = pandoc.RawBlock('latex','\\noindent\\begin{minipage}{\\linewidth}\\centering')
  t[#t+1] = pandoc.RawBlock('latex','\\usebox{\\pandocImgBox}')

  if hascap then
    if numbered then
      local captex = cap_short and ('\\captionof{figure}['..cap_short..']{'..cap_full..'}')
                               or  ('\\captionof{figure}{'..cap_full..'}')
      t[#t+1] = pandoc.RawBlock('latex','\\par\\vspace{0.25\\baselineskip}'..captex)
      if label and label~='' then
        t[#t+1] = pandoc.RawBlock('latex','\\label{'..latex_escape(label)..'}')
      end
    else
      t[#t+1] = pandoc.RawBlock('latex','\\par\\vspace{0.25\\baselineskip}{'..cap_full..'}')
    end
  end

  t[#t+1] = pandoc.RawBlock('latex','\\end{minipage}\\par')
  return t
end

-- === Ramki dla sekcji podatności (bez zmian funkcjonalnych) ===
local Boxes = {
  critical = {open='\\begin{severitybox}[KRYTYCZNY]{Crit}',  close='\\end{severitybox}'},
  high     = {open='\\begin{severitybox}[WYSOKI]{High}',     close='\\end{severitybox}'},
  medium   = {open='\\begin{severitybox}[ŚREDNI]{Med}',      close='\\end{severitybox}'},
  low      = {open='\\begin{severitybox}[NISKI]{Low}',       close='\\end{severitybox}'},
  info     = {open='\\begin{severitybox}[INFORMACYJNY]{Info}', close='\\end{severitybox}'},
}

function Div(el)
  if not FORMAT:match('latex') then return nil end
  for _, cls in ipairs(el.classes) do
    local cfg = Boxes[cls]
    if cfg then
      local out = {}
      out[#out+1] = pandoc.RawBlock('latex','\\FloatBarrier')
      out[#out+1] = pandoc.RawBlock('latex','\\clearpage')
      out[#out+1] = pandoc.RawBlock('latex', cfg.open)
      for i=1,#el.content do out[#out+1]=el.content[i] end
      out[#out+1] = pandoc.RawBlock('latex', cfg.close)
      return out
    end
  end
  return nil
end

local function handle_para_like(el)
  if #el.content==1 and el.content[1].t=='Image' then return blocks_image(el.content[1]) end
  return nil
end
function Para(el)  return handle_para_like(el) end
function Plain(el) return handle_para_like(el) end

-- Obrazy inline: tylko popraw ścieżkę
function Image(el) el.src = resolve_image(el.src); return el end

function HorizontalRule() return pandoc.RawBlock('latex','\\noindent\\rule{\\linewidth}{0.4pt}') end

return {
  { Meta = inject_caption_setup },
  { Div=Div, Para=Para, Plain=Plain, Image=Image, HorizontalRule=HorizontalRule }
}
