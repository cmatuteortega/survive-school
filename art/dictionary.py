# The GRAMMAR boss's body (`Sprites.DICTIONARY` in src/sprites.lua): a fat
# dictionary lying on the page, modelled and traced by art/raytrace.py like the
# whistle, the metronome and the stamp -- red boards, a rounded spine with raised
# bands across it, a block of pages between with the thumb index cut into its
# fore-edge, and a title panel on the cover.
#
# It is the stamp's method (several poses, every one a ring of headings, all cut
# to one box with the pivot at the same pixel -- raytrace.share), because a book
# does more than turn:
#
#   shut     closed, lying flat: at rest, and landing
#   ajar     the front board lifted off the pages, hinged at the spine -- a book
#            that bites. The tell, and what it hops with
#   open     lying open on its back, both leaves flat and the pages rising out of
#            the gutter -- the clap's set-up, the riffle and the definition
#
# The front of the model is the fore-edge, the side that opens, so a book facing
# you is a mouth facing you. The open book is built about its spine rather than
# about the closed one's middle, because the spine is where the game puts the
# middle of the clap (src/dictionary.lua): swapping shut for open moves the
# picture half a book, which happens on a landing, where the eye does not look
# for it. An open book is the same either way round, so that ring is baked at
# half a turn and repeated (src/sprites.lua builds the sixteen); shut and ajar
# have a spine on one side and are baked in full. Forty pictures on disk.
#
#   python3 art/dictionary.py              -- print the views
#   python3 art/dictionary.py --bake       -- write them between the BAKE:dictionary
#                                             markers in src/sprites.lua
#   python3 art/dictionary.py --preview f  -- every pose and view on the GRAMMAR
#                                             page, as a PNG

import math, sys
from raytrace import Rig, length, sd_box, share

S = 0.92
PITCH = 34

# --- the model: front (the fore-edge) along -x, y up off the page, z from the
# tail to the head of the book. Half-sizes along x and z.
W = 13.5                           # half the boards, fore-edge to spine
Z = 16.5                           # half the boards, tail to head
T = 13.0                           # how thick it is shut: a dictionary is fat
BOARD = 1.2                        # one board's thickness
INSET = 0.9                        # how far the boards stand out past the pages
SPINE_R = T/2

def sd_cyl_z(p, cx, cy, r, h):
    # A cylinder along z, `h` long either side of the middle.
    x, y, z = p
    dx = math.hypot(x-cx, y-cy)-r
    dz = abs(z)-h
    return min(max(dx, dz), 0)+length((max(dx, 0), max(dz, 0), 0))

def sd_board(p, y0):
    return sd_box(p, (0, y0+BOARD/2, 0), (W, BOARD/2, Z), 0.45)

def sd_pages(p, y0, y1):
    return sd_box(p, (-INSET/2, (y0+y1)/2, 0), (W-INSET/2-1.2, (y1-y0)/2, Z-INSET), 0.3)

def sd_spine(p):
    # The back: half a cylinder round the pages, standing out past the boards.
    x, y, z = p
    sx = W-SPINE_R+1.4
    d = sd_cyl_z(p, sx, T/2, SPINE_R, Z-0.1)
    return max(d, sx-0.2-x)

# The upper board turned up by `lift` about the hinge, where it meets the spine.
HINGE = (W-2.0, T-BOARD/2)

def lifted(p, lift):
    x, y, z = p
    hx, hy = HINGE
    dx, dy = x-hx, y-hy
    c, s = math.cos(lift), math.sin(lift)
    # Turning the board up (front up) is turning the point the other way.
    return (hx+dx*c-dy*s, hy+dx*s+dy*c, z)

def shut_model(p, lift=0.0):
    q = lifted(p, lift) if lift else p
    top = sd_board(q, T-BOARD)
    parts = [(sd_board(p, 0), 'cover'), (sd_spine(p), 'cover'),
             (sd_pages(p, BOARD, T-BOARD), 'pages')]
    # Its inside is paper -- the endpaper -- so a lifted board shows a white mouth.
    if lift and q[1] < T-BOARD*0.55:
        parts.append((top, 'endpaper'))
    else:
        parts.append((top, 'cover'))
    return min(parts, key=lambda a: a[0])

LIFT = math.radians(62)

def ajar_model(p):
    return shut_model(p, LIFT)

# --- open: on its back about the spine at x = 0, each leaf a board and half the
# pages, the pages lying low at the gutter, rising to a crest and easing down
# to the fore-edge.
LEAF = 2*W-0.6                     # the open boards, gutter to fore-edge
GUTTER = 0.8

def page_top(u):
    crest = 0.28
    if u < crest: return BOARD+1.4+3.6*math.sin(math.pi/2*u/crest)
    return BOARD+5.0-1.3*(u-crest)/(1-crest)

def sd_leaf(p, side):
    x, y, z = p
    ax = x*side
    x0, x1 = GUTTER, LEAF-INSET
    u = min(1, max(0, (ax-x0)/(x1-x0)))
    top = page_top(u)
    # The block's sides, a box in x and z, and its top the curve: slope at
    # most a half, so a distance off the top of it is near enough the height
    # over it times 0.85.
    dx = max(x0-ax, ax-x1)
    dz = abs(z)-(Z-INSET)
    side_d = length((max(dx, 0), max(dz, 0), 0))+min(max(dx, dz), 0)
    return max(side_d, (y-top)*0.85, BOARD-y)

def open_model(p):
    x, y, z = p
    board = sd_box(p, (0, BOARD/2, 0), (LEAF, BOARD/2, Z), 0.45)
    pages = min(sd_leaf(p, 1), sd_leaf(p, -1))
    return min(((board, 'cover'), (pages, 'pages')), key=lambda a: a[0])

# --- the colours. The boards are the tracer's red, the way every solid boss is
# red. The pages are paper on the grey ramp, ruled with grey lines of print
# where their faces are seen: courses of leaves along the edges, lines of text
# on the open pages. The cover has a panel framed in slate with the title in
# paper, and the spine its raised bands. The fore-edge carries the thumb index
# -- the half-moons cut down the side of a dictionary to find a letter by --
# as ink notches stepping down the block.
NOTCHES = 6

def paper(diff, spec, line):
    if line: return 'g' if diff > 0.45 else 's'
    if spec > 0.6 or diff > 0.45: return 'w'
    return 'g' if diff > 0.12 else 's'

def shade_shut(q, m, diff, spec, n, lift=0.0):
    x, y, z = q
    if m == 'endpaper':
        # Lit whichever way it faces: the inside of the mouth is the one place
        # a slate shadow would read as a hole rather than as paper.
        return 'w' if diff > 0.2 or n[1] < 0 else 'g'
    if m == 'pages':
        # (The normal is the room's, turned with the heading: which face of the
        # block a point is on is asked of the point, in the model.)
        if x < -W+1.6 and abs(n[1]) < 0.5:
            # The fore-edge, and the thumb index stepping down it.
            for k in range(NOTCHES):
                zk = -Z+3.2+k*(2*Z-6.4)/(NOTCHES-1)
                yk = T-BOARD-1.2-k*(T-2*BOARD-2.4)/(NOTCHES-1)
                if (z-zk)**2+(y-yk)**2*1.6 < 1.6: return 'o'
        if abs(n[1]) < 0.5:
            return paper(diff, spec, int(y*1.25) % 3 == 0)
        # The top of the block, seen when the board is up: lines of print.
        line = abs(z) < Z-3 and x < W-4 and x > -W+2.5 and (z+Z) % 2.6 < 0.9
        return paper(diff, spec, line)
    if m == 'cover':
        qq = lifted(q, lift) if lift else q
        cx, cy, cz = qq
        if cy > T-BOARD-0.1 and n[1] > 0.3:
            # The top: a panel framed in slate, a title in paper across it.
            fx, fz = (W-4.2)-abs(cx+1.0), (Z-3.0)-abs(cz)
            if (0 < fx < 0.9 and fz > 0) or (0 < fz < 0.9 and fx > 0): return 's'
            if fx > 0 and fz > 0 and abs(cx+1.0) < 1.2 and abs(cz) < Z-6.0:
                return 'w' if diff > 0.4 else 'g'
        if x > W-SPINE_R+0.6:
            # The spine's bands.
            if any(abs(abs(z)-b) < 0.55 for b in (Z-3.0, Z-6.0)): return 's'
    return None

def shade_ajar(q, m, diff, spec, n):
    return shade_shut(q, m, diff, spec, n, LIFT)

def shade_open(q, m, diff, spec, n):
    x, y, z = q
    if m == 'pages':
        if n[1] > 0.5:
            ax = abs(x)
            line = (abs(z) < Z-3 and GUTTER+2.2 < ax < LEAF-INSET-2.2
                    and (z+Z) % 2.6 < 0.9)
            return paper(diff, spec, line)
        return paper(diff, spec, int(y*1.25) % 3 == 0)
    return None

PIVOT = (0.0, T/2, 0.0)            # the middle of the closed book: the bulk of it
OPEN_PIVOT = (0.0, T/2, 0.0)       # the spine, at the same height

def rig(model, shade, pivot):
    return Rig('dictionary', model, shade, pivot=pivot, views=16, unit=S, pitch=PITCH, half=36)

# Which headings each pose is baked at: open is the same either way round.
POSES = (('shut', shut_model, shade_shut, PIVOT, range(16)),
         ('ajar', ajar_model, shade_ajar, PIVOT, range(16)),
         ('open', open_model, shade_open, OPEN_PIVOT, range(8)))

def bake():
    sets, rigs = [], []
    for name, model, shade, pivot, ks in POSES:
        r = rig(model, shade, pivot)
        rigs.append(r)
        sets.append([r.render(k*2*math.pi/16) for k in ks])
    rows, ox, oy = share(sets)
    r = rigs[0]
    n = len(sets[0][0])
    bias = r.half/r.unit-n//2
    # Where the floor under the pivot is, in pixels below the origin: what the
    # game lines the clap's spine up with the ruling by.
    foot = (PIVOT[1]*math.cos(r.pitch))/S+bias
    return rows, ox, oy, foot, r

ROWS, OX, OY, FOOT, RIG = bake()

def lua():
    out = ["    -- BAKE:dictionary begin",
           "    -- Written by art/dictionary.py; edit the model there, not these rows.",
           "    Sprites.DICTIONARY = {",
           "        ox = %d, oy = %d," % (OX, OY),
           "        -- How far below the origin the floor under the middle of the",
           "        -- book is, in pixels: where src/dictionary.lua puts the spine.",
           "        foot = %d," % round(FOOT)]
    for (name, _, _, _, ks), frames in zip(POSES, ROWS):
        out.append("        %s = {" % name)
        for k, f in zip(ks, frames):
            out.append("            { -- heading %d/16" % k)
            out += ['                "%s",' % r for r in f]
            out.append("            },")
        out.append("        },")
    out.append("    }")
    out.append("    -- BAKE:dictionary end")
    return "\n".join(out)

# --- the preview: every pose at every heading on the GRAMMAR page.
def preview(path):
    from PIL import Image
    pal = {'w':(0xe6,0xec,0xef),'g':(0xb2,0xb1,0xc0),'s':(0x5b,0x4f,0x6e),
           'o':(0x28,0x07,0x32),'r':(0xe1,0x5e,0x6e),'k':(0xf3,0xa8,0xa8),
           'b':(0x71,0x94,0xf0),'c':(0xab,0xc9,0xf1)}
    shut, ajar, open_ = ROWS
    rings = [('shut', shut), ('ajar', ajar), ('open', [open_[k % 8] for k in range(16)])]
    w, h = len(shut[0][0]), len(shut[0])
    cw, ch = w+4, h+10
    img = Image.new('RGB', (cw*16, ch*len(rings)), pal['w'])
    px = img.load()
    for y in range(img.size[1]):
        at = y % 30
        for x in range(img.size[0]):
            if at < 2 or 10 <= at < 12: px[x, y] = pal['c']
    foot = round(FOOT)
    for j, (name, frames) in enumerate(rings):
        for k, f in enumerate(frames):
            X0, Y0 = k*cw+2, j*ch+5
            for y, r in enumerate(f):
                for x, c in enumerate(r):
                    if c != '.': px[X0+x, Y0+y] = pal[c]
            # The floor under the pivot.
            px[X0+OX, Y0+OY+foot] = pal['r']
    img = img.resize((img.size[0]*3, img.size[1]*3), Image.NEAREST)
    img.save(path)
    print("wrote", path)

if '--bake' in sys.argv:
    RIG.rows, RIG.views, RIG.ox, RIG.oy = ROWS[0], 16, OX, OY  # for write()'s line
    RIG.write(lua())
    print("baked shut 16, ajar 16, open 8; %dx%d, origin %d,%d, foot %d" % (
        len(ROWS[0][0][0]), len(ROWS[0][0]), OX, OY, round(FOOT)))
elif '--preview' in sys.argv:
    preview(sys.argv[sys.argv.index('--preview')+1])
else:
    print(lua())
