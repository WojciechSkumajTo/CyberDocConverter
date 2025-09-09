-- resources/filters/env.lua

local path = require 'pandoc.path'

-- === Bezpieczeństwo: helpery ścieżek ===
local function norm_dir(p)
  p = path.normalize(p)
  if p:sub(-1) ~= "/" then p = p .. "/" end
  return p
end

local function is_within(base, p)
  -- true tylko gdy p leży w drzewie base
  base = norm_dir(base)
  p = path.normalize(p)
  return p:sub(1, #base) == base
end

local function file_exists(p)
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
end

-- === Konfiguracja filtra ===
local MAX_H = '0.65\\textheight'

local M = {
  critical = {open='\\begin{severitybox}[KRYTYCZNY]{Crit}',  close='\\end{severitybox}'},
  high     = {open='\\begin{severitybox}[WYSOKI]{High}',     close='\\end{severitybox}'},
  medium   = {open='\\begin{severitybox}[ŚREDNI]{Med}',      close='\\end{severitybox}'},
  low      = {open='\\begin{severitybox}[NISKI]{Low}',       close='\\end{severitybox}'},
  info     = {open='\\begin{severitybox}[INFORMACYJNY]{Info}', close='\\end{severitybox}'},
}

local function latex_escape(s)
  if not s or s == '' then return '' end
  local map = { ['\\']='\\textbackslash{}',['{']='\\{',['}']='\\}',
                ['%']='\\%', ['#']='\\#',['&']='\\&',
                ['_']='\\_', ['^']='\\^{}',['~']='\\textasciitilde{}' }
  return (s:gsub('[\\%%{}#&_^~]', map))
end

local function width_spec(attr)
  if not attr or not attr.attributes then return '\\linewidth' end
  local w = attr.attributes['width']
  if not w or w == '' then return '\\linewidth' end
  local p = w:match('^(%d+)%%$')
  return p and (tostring(tonumber(p)/100) .. '\\linewidth') or w
end

local function caption_text(inlines)
  return latex_escape(pandoc.utils.stringify(inlines or {}))
end

-- === Resolucja ścieżek obrazów z blokadą wyjścia poza projekt ===
local function resolve_image(src)
  if not src or src == '' then return src end
  -- Zostaw URL-e w spokoju; TeX i tak ich nie wczyta jako grafik.
  if src:match("^%a+://") then return src end

  local inputdir = os.getenv("INPUT_DIR") or "."
  local project  = os.getenv("PROJECT_ROOT") or inputdir
  project = path.normalize(project)

  -- 1) próba względem katalogu .md
  local p1 = path.normalize(path.join({inputdir, src}))
  if file_exists(p1) and is_within(project, p1) then
    return path.make_relative(p1, inputdir)
  end

  -- 2) próba „od root projektu”
  --    Uwaga: blokujemy wszystko spoza PROJECT_ROOT.
  local p2
  if src:sub(1,1) == "/" then
    -- absoluty dozwolone tylko, jeśli wewnątrz projektu
    p2 = path.normalize(src)
  else
    p2 = path.normalize(path.join({project, src}))
  end
  if file_exists(p2) and is_within(project, p2) then
    return path.make_relative(p2, inputdir)
  end

  -- 3) odrzuć ścieżki poza projektem: zostaw oryginał, TeX wywali błąd
  return src
end

-- === Render obrazka jako blok z kontrolą rozmiaru ===
local function blocks_image(img)
  local src    = resolve_image(img.src)
  local width  = width_spec(img.attr)
  local cap    = caption_text(img.caption)
  local hascap = cap ~= ''
  local CAP_SPACE = hascap and '1.2\\baselineskip' or '0.5\\baselineskip'

  local t = {}
  t[#t+1] = pandoc.RawBlock('latex',
    '\\makeatletter\\@ifundefined{pandocImgBox}{\\newsavebox{\\pandocImgBox}}{}\\makeatother')
  t[#t+1] = pandoc.RawBlock('latex',
    '\\sbox{\\pandocImgBox}{\\adjustbox{max width='..width..',max totalheight='..MAX_H..',keepaspectratio}{' ..
    '\\includegraphics{\\detokenize{'..src..'}}}}')
  t[#t+1] = pandoc.RawBlock('latex',
    '\\needspace{\\dimexpr\\ht\\pandocImgBox+\\dp\\pandocImgBox+'..CAP_SPACE..'\\relax}')
  t[#t+1] = pandoc.RawBlock('latex','\\noindent\\begin{minipage}{\\linewidth}\\centering')
  t[#t+1] = pandoc.RawBlock('latex','\\usebox{\\pandocImgBox}')
  if hascap then
    t[#t+1] = pandoc.RawBlock('latex','\\par\\vspace{0.25\\baselineskip}{\\small\\itshape '..cap..'}')
  end
  t[#t+1] = pandoc.RawBlock('latex','\\end{minipage}\\par')
  return t
end

-- === Ramki i hooki ===
function Div(el)
  if not FORMAT:match('latex') then return nil end
  for _, cls in ipairs(el.classes) do
    local cfg = M[cls]
    if cfg then
      local out = {}
      out[#out+1] = pandoc.RawBlock('latex','\\FloatBarrier')
      out[#out+1] = pandoc.RawBlock('latex','\\clearpage')
      out[#out+1] = pandoc.RawBlock('latex', cfg.open)
      for i = 1, #el.content do out[#out+1] = el.content[i] end
      out[#out+1] = pandoc.RawBlock('latex', cfg.close)
      return out
    end
  end
  return nil
end

local function handle_para_like(el)
  if #el.content == 1 and el.content[1].t == 'Image' then
    return blocks_image(el.content[1])
  end
  return nil
end

function Para(el)  return handle_para_like(el) end
function Plain(el) return handle_para_like(el) end

-- Pojedyncze obrazy w tekście: tylko przepisz src z kontrolą ścieżki
function Image(el)
  el.src = resolve_image(el.src)
  return el
end

function HorizontalRule()
  return pandoc.RawBlock('latex','\\noindent\\rule{\\linewidth}{0.4pt}')
end

return { { Div=Div, Para=Para, Plain=Plain, Image=Image, HorizontalRule=HorizontalRule } }
