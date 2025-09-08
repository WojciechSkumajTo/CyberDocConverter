local MAX_H = '0.65\\textheight'   -- limit wysokości po skalowaniu

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

local function blocks_image(img)
  local src    = img.src
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

function HorizontalRule()
  return pandoc.RawBlock('latex','\\noindent\\rule{\\linewidth}{0.4pt}')
end

return { { Div=Div, Para=Para, Plain=Plain, HorizontalRule=HorizontalRule } }