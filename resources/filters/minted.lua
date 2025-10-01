-- Zamienia CodeBlock -> minted (z opcjami ze szablonu)
function CodeBlock(el)
  local lang = el.classes[1] or "text"
  local opts = el.attributes or {}

  -- przenieś atrybuty pandoca do listy opcji minted (np. linenos=false)
  local minted_opts = {}
  for k, v in pairs(opts) do
    if k ~= "caption" and k ~= "label" then
      table.insert(minted_opts, k .. "=" .. v)
    end
  end
  local optstr = table.concat(minted_opts, ",")

  local caption = opts.caption and ("\\captionof{listing}{" .. opts.caption .. "}\n") or ""
  local label   = opts.label and ("\\label{" .. opts.label .. "}\n") or ""

  -- treść kodu (bez zmian)
  local code = el.text

  local head = "\\begin{minted}" .. (#optstr>0 and "["..optstr.."]" or "") .. "{" .. lang .. "}"
  local tail = "\\end{minted}"

  return {
    pandoc.RawBlock("latex", head),
    pandoc.RawBlock("latex", code),
    pandoc.RawBlock("latex", tail),
    pandoc.RawBlock("latex", caption .. label)
  }
end
