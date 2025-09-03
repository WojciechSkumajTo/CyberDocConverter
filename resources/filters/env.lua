local unpack = table.unpack or unpack

local M = {
  critical = {open='\\begin{severitybox}[KRYTYCZNY]{red}',              close='\\end{severitybox}'},
  high     = {open='\\begin{severitybox}[WYSOKI]{orange}',              close='\\end{severitybox}'},
  medium   = {open='\\begin{severitybox}[ŚREDNI]{yellow!60!orange}',    close='\\end{severitybox}'},
  low      = {open='\\begin{severitybox}[NISKI]{green!60!black}',       close='\\end{severitybox}'},
  info     = {open='\\begin{severitybox}[INFORMACYJNY]{cyan!60!black}', close='\\end{severitybox}'},
}

function Div(el)
  if not FORMAT:match('latex') then return nil end
  for _, cls in ipairs(el.classes) do
    local cfg = M[cls]
    if cfg then
      local out = {
        pandoc.RawBlock('latex','\\clearpage'),  -- ZAWSZE nowa strona przed blokiem
        pandoc.RawBlock('latex', cfg.open),
      }
      for i = 1, #el.content do out[#out+1] = el.content[i] end
      out[#out+1] = pandoc.RawBlock('latex', cfg.close)
      return out
    end
  end
  return nil
end

function HorizontalRule()
  return pandoc.RawBlock('latex', '\\noindent\\rule{\\linewidth}{0.4pt}')
end
