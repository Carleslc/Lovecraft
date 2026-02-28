#!/usr/bin/env bash
#
# build.sh — Genera PDF, EPUB y HTML para cada relato en AI/
#
# Uso:
#   ./build.sh                               # Genera todos los relatos con la fuente por defecto
#   ./build.sh --font "Georgia"              # Genera todos con fuente personalizada
#   ./build.sh --size 12pt                   # Genera todos con tamaño de fuente personalizada
#   ./build.sh "El Pozo de Yoth"             # Genera solo un relato
#   ./build.sh --font "DejaVu Serif" --size 11pt
#   ./build.sh --font "Palatino" --size 12pt "El Pozo de Yoth"
#
# Requisitos:
#   - pandoc (https://pandoc.org/installing.html)
#   - XeLaTeX (incluido en TeX Live o MacTeX)
#
# Fuentes y tamaños por defecto:
#   - Si DejaVu Serif está instalada: DejaVu Serif 11pt (https://dejavu-fonts.github.io/)
#   - Si no: Palatino 12pt (macOS), Palatino Linotype 12pt (Windows), DejaVu Serif 11pt (Linux)

set -euo pipefail

AUTHOR="Carleslc + Opus"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_DIR="$SCRIPT_DIR/AI"
HEADER="$SCRIPT_DIR/header.tex"

# Comprobar si una fuente está disponible para XeLaTeX
font_available() {
  local tmpdir
  tmpdir=$(mktemp -d)
  printf '\\documentclass{article}\\usepackage{fontspec}\\setmainfont{%s}\\begin{document}x\\end{document}' "$1" \
    > "$tmpdir/test.tex"
  xelatex -interaction=batchmode -output-directory="$tmpdir" "$tmpdir/test.tex" >/dev/null 2>&1
  local result=$?
  rm -rf "$tmpdir"
  return $result
}

# Fuentes sans-serif y monoespaciada del sistema
case "$(uname -s)" in
  Darwin)
    SYS_SANSFONT="Helvetica Neue"
    SYS_MONOFONT="Menlo"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    SYS_SANSFONT="Segoe UI"
    SYS_MONOFONT="Consolas"
    ;;
  *)
    SYS_SANSFONT="DejaVu Sans"
    SYS_MONOFONT="DejaVu Sans Mono"
    ;;
esac

# Detectar fuente principal por defecto
if font_available "DejaVu Serif"; then
  MAINFONT="DejaVu Serif"
  FONTSIZE="11pt"
else
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      MAINFONT="Palatino Linotype"
      ;;
    *)
      MAINFONT="Palatino"
      ;;
  esac
  FONTSIZE="12pt"
fi

# Sans y mono: preferir DejaVu si está disponible, sino la del sistema
if font_available "DejaVu Sans"; then
  SANSFONT="DejaVu Sans"
else
  SANSFONT="$SYS_SANSFONT"
fi

if font_available "DejaVu Sans Mono"; then
  MONOFONT="DejaVu Sans Mono"
else
  MONOFONT="$SYS_MONOFONT"
fi

# Parsear argumentos
FILTER=""
CUSTOM_FONT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --font)
      MAINFONT="$2"
      CUSTOM_FONT=true
      shift 2
      ;;
    --size)
      # Añadir "pt" si no se especifica unidad
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        FONTSIZE="${2}pt"
      else
        FONTSIZE="$2"
      fi
      shift 2
      ;;
    *)
      FILTER="$1"
      shift
      ;;
  esac
done

# Plantilla HTML
html_template() {
  local title="$1"
  local body="$2"
  cat <<HTMLEOF
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${title}</title>
  <link rel="stylesheet" href="https://unpkg.com/github-markdown-css@5/github-markdown.css" />
  <style>
    .markdown-body {
      max-width: 720px;
      margin: 0 auto;
      padding: 2.5rem 1.5rem;
      font-family: "$MAINFONT", Palatino, Georgia, serif;
      font-size: 1.1rem;
      line-height: 1.6;
    }
    .markdown-body p {
      margin-bottom: 0.9em;
    }
    .markdown-body h1 {
      font-size: 1.8em;
      margin-bottom: 0.5em;
    }
    .markdown-body h2 {
      font-size: 1.3em;
      margin-top: 2em;
      margin-bottom: 0.8em;
    }
    .markdown-body hr {
      margin: 2em 0;
    }
    .markdown-body em {
      font-style: italic;
    }
    .back-link {
      display: inline-block;
      margin-bottom: 1.5rem;
      font-size: 0.85em;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    }
    @media (prefers-color-scheme: dark) {
      .markdown-body {
        color: #d4d4d4;
      }
      .markdown-body p {
        color: #d4d4d4;
      }
    }
  </style>
</head>
<body class="markdown-body">
<a class="back-link" href="../">← Otros relatos</a>
${body}
</body>
</html>
HTMLEOF
}

# Encontrar el markdown del relato (README.md o título.md, excluyendo Notas)
find_story_md() {
  local folder="$1"
  local story="$2"

  if [[ -f "$folder/README.md" ]]; then
    echo "$folder/README.md"
  elif [[ -f "$folder/${story}.md" ]]; then
    echo "$folder/${story}.md"
  else
    # Buscar cualquier .md que no sea Notas
    find "$folder" -maxdepth 1 -name "*.md" ! -name "*Notas.md" -print -quit
  fi
}

build_story() {
  local folder="$1"
  local story
  story="$(basename "$folder")"

  local md
  md="$(find_story_md "$folder" "$story")"

  if [[ -z "$md" || ! -f "$md" ]]; then
    echo "⚠ $story: No se encontró el markdown del relato."
    return
  fi

  local pdf="$folder/${story}.pdf"
  local epub="$folder/${story}.epub"
  local html="$folder/index.html"

  echo "━━━ $story ━━━"

  # PDF
  echo -n "  PDF...  "
  local pdf_err
  pdf_err=$(pandoc "$md" -o "$pdf" \
    --pdf-engine=xelatex \
    -V mainfont="$MAINFONT" \
    -V sansfont="$SANSFONT" \
    -V monofont="$MONOFONT" \
    -V fontsize="$FONTSIZE" \
    -V geometry:margin=2.5cm \
    -V lang=es \
    -H "$HEADER" \
    --wrap=auto 2>&1)
  if [[ $? -eq 0 ]]; then
    echo "✓"
  else
    echo "✗ (error al generar PDF)"
    echo "$pdf_err" | grep -iE "error|fatal|cannot be found" | head -3 | sed 's/^/    /'
  fi

  # EPUB
  echo -n "  EPUB... "
  if pandoc "$md" -o "$epub" \
    --metadata title="$story" \
    --metadata author="$AUTHOR" \
    --metadata lang=es \
    --wrap=auto 2>/dev/null; then
    echo "✓"
  else
    echo "✗ (error al generar EPUB)"
  fi

  # HTML
  echo -n "  HTML... "
  local body
  body="$(pandoc "$md" --wrap=auto 2>/dev/null)"
  if [[ -n "$body" ]]; then
    html_template "$story" "$body" > "$html"
    echo "✓"
  else
    echo "✗ (error al generar HTML)"
  fi
}

# Ejecutar
if [[ ! -f "$HEADER" ]]; then
  echo "Error: No se encontró header.tex en $SCRIPT_DIR" >&2
  exit 1
fi

# Verificar que la fuente está disponible si se especificó --font
if [[ "$CUSTOM_FONT" == true ]] && ! font_available "$MAINFONT"; then
  echo "Error: La fuente \"$MAINFONT\" no está instalada en este sistema." >&2
  echo "       Instálala o usa --font con otra fuente disponible." >&2
  exit 1
fi

echo "Fuente: $MAINFONT | Tamaño: $FONTSIZE"
echo

if [[ -n "$FILTER" ]]; then
  # Generar un solo relato
  target="$AI_DIR/$FILTER"
  if [[ -d "$target" ]]; then
    build_story "$target"
  else
    echo "Error: No se encontró la carpeta '$target'" >&2
    exit 1
  fi
else
  # Generar todos los relatos
  for folder in "$AI_DIR"/*/; do
    build_story "$folder"
  done
fi

echo
echo "Listo."
