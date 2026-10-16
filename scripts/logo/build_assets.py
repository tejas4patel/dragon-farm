"""Build every dragonfarm image from one minimal mark: a dragon's head in profile.

Writes, next to this script:
  mark.svg     the mark alone, transparent (site hero, posts)
  head.svg     the mark on a rounded navy tile (favicon, app navbar)
  dragon.svg   the hex sticker source (518 x 600)
  dragon.html  the hex sticker page, rendered to PNG by render.js
  social.html  the 1280 x 640 social card page
and prints the R code for brand_mark() in R/app.R.
"""
import io, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
CORAL, AMBER, NAVY, TILE = "#FF6B35", "#FFB547", "#0B1020", "#151E3A"

# The mark, in a 100 x 100 box: a dragon's head in profile with two horns,
# spikes down the neck, an open jaw, an eye, and a nostril.
MARK = (
    '<path d="M42 38 L10 12 L32 44 Z" fill="%s"/>' % AMBER
    + '<path d="M54 34 L36 6 L46 36 Z" fill="%s"/>' % AMBER
    + '<path d="M30 56 L6 54 L26 70 Z" fill="%s"/>' % AMBER
    + '<path d="M28 72 L4 74 L28 86 Z" fill="%s"/>' % AMBER
    + '<path d="M26 94 C16 72 18 52 30 40 C38 32 48 28 58 30 L86 40 C93 42 94 49 88 51 L66 56 L70 61 C64 66 56 66 50 64 C46 74 48 84 54 94 Z" fill="%s"/>' % CORAL
    + '<circle cx="57" cy="40" r="4.2" fill="%s"/>' % NAVY
    + '<circle cx="86" cy="44" r="1.8" fill="%s"/>' % NAVY
)


def mark_svg(attrs='viewBox="2 4 96 92"'):
    return '<svg xmlns="http://www.w3.org/2000/svg" %s role="img" aria-label="The dragonfarm dragon">%s</svg>' % (attrs, MARK)


def head_svg(size=64, extra=""):
    return ('<svg xmlns="http://www.w3.org/2000/svg"%s viewBox="0 0 100 100" width="%d" height="%d">'
            '<rect width="100" height="100" rx="22" fill="%s"/><g transform="translate(9,8) scale(0.84)">%s</g></svg>') % (extra, size, size, TILE, MARK)


HEX = """<svg xmlns="http://www.w3.org/2000/svg" width="518" height="600" viewBox="0 0 518 600">
  <defs>
    <linearGradient id="edge" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="%(amber)s"/><stop offset="1" stop-color="%(coral)s"/>
    </linearGradient>
  </defs>
  <polygon points="259,2 509,146 509,454 259,598 9,454 9,146" fill="url(#edge)"/>
  <polygon points="259,14 499,152 499,448 259,586 19,448 19,152" fill="%(navy)s"/>
  <g transform="translate(151,116) scale(2.2)">%(mark)s</g>
  <text x="259" y="430" text-anchor="middle" font-family="Space Grotesk" font-weight="700" font-size="60" fill="#F1F5FF" letter-spacing="-1">dragonfarm</text>
  <text x="259" y="478" text-anchor="middle" font-family="Space Grotesk" font-weight="600" font-size="18" fill="%(amber)s" letter-spacing="3.2">RAISE YOUR OWN DRAGON</text>
</svg>
""" % {"amber": AMBER, "coral": CORAL, "navy": NAVY, "mark": MARK}

FONT = '@font-face { font-family: "Space Grotesk"; src: url("space-grotesk.woff2") format("woff2"); font-weight: 300 700; }'


def write(name, text):
    io.open(os.path.join(HERE, name), "w", encoding="utf-8", newline="\n").write(text)


write("mark.svg", mark_svg() + "\n")
write("head.svg", head_svg() + "\n")
write("dragon.svg", HEX)
write("dragon.html", "<!doctype html><html><head><meta charset=\"utf-8\"><style>%s html, body { margin: 0; background: transparent; } svg { display: block; }</style></head><body>%s</body></html>" % (FONT, HEX))

social = """<!doctype html><html><head><meta charset="utf-8"><style>
%s
html, body { margin: 0; width: 1280px; height: 640px; overflow: hidden; }
body { font-family: "Space Grotesk", sans-serif; color: #fff; position: relative;
  background: radial-gradient(620px 420px at 1000px 300px, rgba(255,122,61,0.22), transparent 70%%),
              radial-gradient(560px 420px at 60px 120px, rgba(47,111,143,0.40), transparent 70%%), #0B1020; }
.brand { position: absolute; left: 80px; top: 62px; display: flex; align-items: center; gap: 14px; font-size: 30px; font-weight: 700; }
.brand svg { width: 46px; height: 46px; }
h1 { position: absolute; left: 80px; top: 150px; margin: 0; font-size: 92px; line-height: 0.98; letter-spacing: -2px; font-weight: 700; }
h1 em { font-style: normal; background: linear-gradient(90deg, #FFB547, #FF6B35); -webkit-background-clip: text; background-clip: text; color: transparent; }
p { position: absolute; left: 82px; top: 372px; width: 640px; margin: 0; font-size: 28px; line-height: 1.4; color: #C5CFE4; }
.foot { position: absolute; left: 82px; right: 80px; bottom: 54px; display: flex; justify-content: space-between; font: 500 26px "Consolas", monospace; }
.foot .url { color: #9AA7C2; } .foot .cmd { color: #FFD9A0; }
.mark { position: absolute; right: 90px; top: 110px; width: 380px; }
</style></head><body>
<div class="brand">%s<span>dragonfarm</span></div>
<h1>Raise your<br>own <em>dragon.</em></h1>
<p>Fine-tune your own model on your documents. From R, on your own laptop, with RAG built in.</p>
<div class="mark">%s</div>
<div class="foot"><span class="url">dragonfarm.dev</span><span class="cmd">install.packages("dragonfarm")</span></div>
</body></html>""" % (FONT, head_svg(46), mark_svg())
write("social.html", social)

r_svg = head_svg(26, ' class="df-logo" aria-hidden="true"').replace('xmlns="http://www.w3.org/2000/svg" ', "")
print(r_svg)
