# ART's encore's body (`Sprites.MARBLE` in src/sprites.lua): a block of marble
# with a bust in it, modelled and traced by art/raytrace.py like the whistle,
# the metronome, the stamp and the dictionary.
#
# **The poses are how far it has been carved.** The stamp's poses are the body
# bent; these are the body *taken away from*. The bust is modelled whole -- a
# round socle, a chest cut off under the shoulders, a neck, a head with a nose, a
# brow, a jaw, ears and a cap of hair -- and so is the block it is in. Each stage
# is the block with everything more than `margin` outside the bust cut off it:
#
#   carved(p) = max(block(p), bust(p) - margin)
#
# so an infinite margin is the block as it came out of the quarry, a margin of
# nought is the finished bust, and every stage between is the bust grown by its
# margin and cut square by the block's faces wherever it still reaches them --
# which is what a block half carved looks like: the flat faces it came with,
# with a rounded lump knocked out of them where the head is going to be. The
# game hands the stages out off the boss's health (src/marble.lua): every hit
# takes marble off.
#
#   block     the block: flat faces, the quarry's chisel marks
#   hewn      the top corners knocked off: a head-shaped lump on a slab
#   roughed   a head, shoulders and a socle, all of it still a size too big
#   modelled  nearly there: a nose, a chin, the hair standing off the head
#   bust      finished and polished, the chisel marks gone
#
# **Rough and polished are told apart by where the surface is.** A point on the
# carved surface further than a pixel out from the finished bust is stone that is
# still to come off, and it is drawn rough: short chisel strokes a step darker,
# laid in the model's own space so they stay on the stone as it turns. The
# finished bust is smooth, so the last stage is the one picture with none. The
# veins are the same trick at a different scale: a field in the model's space,
# so carving reveals more of the same veins rather than painting new ones on --
# red and blush, the one thing on a white body that says it is theirs.
#
# **It turns** like the whistle, eight headings a stage (a quarry block is the
# same at a quarter turn, but a head is not, and one ring of headings serves both),
# so the brain can keep the half-made thing facing the page and turn the finished
# one to look at you. The bake also writes where the bust's eyes are in every
# view of the last stage, for the brain to open them (`eyes`), and `foot`, the
# pixels from the origin down to the floor under the pivot.
#
#   python3 art/marble.py              -- print the views
#   python3 art/marble.py --bake       -- write them between the BAKE:marble markers
#   python3 art/marble.py --preview f  -- every stage and view on the ART page,
#                                         eyes marked, as a PNG

import math, os, sys
from raytrace import Rig, View, length, norm, sub, add, mul, dot, sd_box, share

S = 0.92
PITCH = 34
VIEWS = 8
HALF = 34

def smin(a, b, k):
    h = max(k-abs(a-b), 0)/k
    return min(a, b)-h*h*k*0.25

def smax(a, b, k):
    return -smin(-a, -b, k)

def sd_ell(p, c, r):
    # An ellipsoid's distance, near enough: exact on the surface, and scaled by
    # its smallest radius so a step never overshoots.
    q = ((p[0]-c[0])/r[0], (p[1]-c[1])/r[1], (p[2]-c[2])/r[2])
    return (length(q)-1)*min(r)

def sd_cap(p, a, b, r):
    pa, ba = sub(p, a), sub(b, a)
    h = max(0, min(1, dot(pa, ba)/dot(ba, ba)))
    return length(sub(pa, mul(ba, h)))-r

def sd_cyl(p, r, y0, y1):
    dx = math.hypot(p[0], p[2])-r
    dy = abs(p[1]-(y0+y1)/2)-(y1-y0)/2
    return min(max(dx, dy), 0)+length((max(dx, 0), max(dy, 0), 0))

# --- the model: front along -x, y up off the page, z across it, floor at y = 0.
# A bust about forty units tall, which is about forty-five pixels of sprite
# seen from the camera: a head bigger than the player, which a boss should be.
BLOCK_C = (0.0, 20.5, 0.0)
BLOCK_B = (11.0, 20.5, 13.0)

def sd_block(p):
    return sd_box(p, BLOCK_C, BLOCK_B, 0.8)

def sd_socle(p):
    base = sd_cyl(p, 8.4, 0, 2.4)-0.4
    t = min(1, max(0, (p[1]-2.4)/4.4))
    waist = sd_cyl(p, 5.6-1.4*math.sin(math.pi*t), 2.0, 6.8)
    cap = sd_cyl(p, 6.8, 6.6, 8.4)-0.4
    return min(base, waist, cap)

def sd_chest(p):
    c = sd_ell(p, (0.6, 15.0, 0), (6.2, 6.8, 11.6))
    # Cut off flat under the shoulders, the way a bust is, and rounded into the
    # socle rather than balanced on it.
    return smax(c, 9.2-p[1], 1.2)

def sd_head(p):
    head = sd_ell(p, (0.0, 31.4, 0), (7.6, 7.8, 6.9))
    jaw = sd_ell(p, (-3.2, 27.0, 0), (4.6, 3.4, 5.0))
    neck = sd_cap(p, (0.8, 18.0, 0), (-0.2, 26.0, 0), 3.4)
    d = smin(smin(head, jaw, 2.4), neck, 2.0)
    nose = sd_cap(p, (-7.2, 31.6, 0), (-9.4, 28.6, 0), 1.2)
    d = smin(d, nose, 1.0)
    brow = sd_cap(p, (-6.7, 33.2, -3.4), (-6.7, 33.2, 3.4), 1.2)
    d = smin(d, brow, 1.4)
    for zz in (-2.7, 2.7):
        d = smax(d, -sd_ell(p, (-7.8, 31.3, zz), (1.7, 1.3, 1.5)), 0.8)
    for zz in (-6.7, 6.7):
        d = smin(d, sd_ell(p, (1.0, 30.2, zz), (1.7, 2.6, 1.2)), 0.6)
    return d

def sd_hair(p):
    h = sd_ell(p, (1.0, 32.6, 0), (8.2, 8.0, 7.6))
    # Off the face and above the ears: a cap, swept back.
    face = -(p[0]+5.0-0.45*(p[1]-33))
    return max(h, face, 28.6-p[1]+0.3*max(0, p[0]))

def sd_bust(p):
    body = min(sd_socle(p), sd_chest(p), sd_head(p))
    hair = sd_hair(p)
    return min(body, hair), ('hair' if hair < body else 'marble')

# How far out from the finished bust each stage still is. None is the block.
STAGES = (('block', None), ('hewn', 7.0), ('roughed', 4.0), ('modelled', 1.8), ('bust', 0.0))

def staged(margin):
    def model(p):
        b = sd_block(p)
        if margin is None: return b, 'rough'
        d, m = sd_bust(p)
        if margin == 0: return d, m
        return max(b, d-margin), 'rough'
    return model

# --- the colours. Marble is the grey ramp -- paper lit, graphite, slate -- with
# light bounced up off the page into the bottom of the shadow side.
def vein(q):
    x, y, z = q
    v = math.sin(0.17*x+0.11*y-0.14*z+1.6*math.sin(0.15*y+0.11*z)+0.9*math.sin(0.13*x-0.1*z))
    return abs(v) < 0.075

def rough(q):
    # Chisel strokes: short slanting dashes, a cell of the model each, half the
    # cells struck. In the model's space, so they turn with it.
    x, y, z = q
    u = 0.55*x+0.8*y+0.45*z
    v = 0.7*x-0.3*y-0.65*z
    cu, cv = math.floor(u/4.5), math.floor(v/2.6)
    h = math.sin(cu*12.9898+cv*78.233)*43758.5453
    h -= math.floor(h)
    if h < 0.55: return False
    fu = u/4.5-cu
    fv = v/2.6-cv
    return 0.1 < fu < 0.9 and abs(fv-0.5) < 0.17

def shader(margin):
    def shade(q, m, diff, spec, n):
        lit = 2 if (spec > 0.6 or diff > 0.55) else 1 if diff > 0.2 else \
              1 if (n[1] < -0.55 and diff > 0.02) else 0
        if m == 'hair':
            # Locks: bands round the head, every other one a step down.
            x, y, z = q
            curl = math.sin(1.3*z+0.6*y+0.9*math.sin(0.8*x+0.5*y)) > 0.2
            lit = max(0, lit-1) if curl else lit
        elif m == 'rough' and margin != 0:
            # Stone still to come off is rough: anywhere a pixel or more out
            # from the finished bust.
            if (margin is None or sd_bust(q)[0] > 0.9) and rough(q):
                lit = max(0, lit-1)
        # The finished face is kept clear of veins, so the eyes the brain opens
        # in it are the only red on it.
        face = margin == 0 and q[1] > 24.5
        if vein(q) and lit > 0 and not face:
            return 'k' if lit == 2 else 'r'
        return ('s', 'g', 'w')[lit]
    return shade

PIVOT = (0.0, 16.0, 0.0)            # the chest: the bulk of the bust

def rig(margin):
    return Rig('marble', staged(margin), shader(margin), pivot=PIVOT, views=VIEWS,
               unit=S, pitch=PITCH, half=HALF)

# --- where the eyes are: the middle of each socket, projected the way the trace
# was, kept only where the surface the camera sees there is the socket itself.
EYES = ((-7.4, 30.6, -2.7), (-7.4, 30.6, 2.7))

def eye_pixels(r, k):
    h = k*2*math.pi/VIEWS
    v = View(r, h)
    a = h+math.pi
    c, s = math.cos(a), math.sin(a)
    out = []
    for q in EYES:
        mx, my, mz = q[0]-PIVOT[0], q[1]-PIVOT[1], q[2]-PIVOT[2]
        x = mx*c-mz*s
        z = mx*s+mz*c
        y = my
        cp, sp = math.cos(r.pitch), math.sin(r.pitch)
        cy = y*cp-z*sp
        cx = x
        n = int(2*r.half/r.unit)
        i = int((cx+r.half)/r.unit)
        j = int((r.half-cy)/r.unit)
        # Seen, if the ray through that pixel lands near the eye.
        ccx = -r.half+(i+0.5)*r.unit; ccy = r.half-(j+0.5)*r.unit
        p, _ = r.trace(v, ccx, ccy)
        if p and length(sub(v.to_model(p), q)) < 1.8:
            out.append((i-n//2, j-n//2))
    return out

# --- the bake, in parallel: forty pictures of a few thousand rays each.
def _job(args):
    si, k = args
    return rig(STAGES[si][1]).render(k*2*math.pi/VIEWS)

def bake():
    import multiprocessing as mp
    jobs = [(si, k) for si in range(len(STAGES)) for k in range(VIEWS)]
    with mp.get_context('fork').Pool() as pool:
        frames = pool.map(_job, jobs)
    sets = [frames[si*VIEWS:(si+1)*VIEWS] for si in range(len(STAGES))]
    rows, ox, oy = share(sets)
    r = rig(0)
    n = len(sets[0][0])
    bias = r.half/r.unit-n//2
    foot = PIVOT[1]*math.cos(r.pitch)/S+bias
    eyes = [eye_pixels(r, k) for k in range(VIEWS)]
    return rows, ox, oy, foot, eyes

def lua(rows, ox, oy, foot, eyes):
    out = ["    -- BAKE:marble begin",
           "    -- Written by art/marble.py; edit the model there, not these rows.",
           "    Sprites.MARBLE = {",
           "        ox = %d, oy = %d," % (ox, oy),
           "        -- How far below the origin the floor under the middle of it is,",
           "        -- in pixels: where src/marble.lua puts its feet.",
           "        foot = %d," % round(foot),
           "        -- Where the finished bust's eyes are in each view, from the",
           "        -- origin: none for a view that has its back to you.",
           "        eyes = {"]
    for k, es in enumerate(eyes):
        out.append("            { %s }," % ", ".join("{ %d, %d }" % e for e in es))
    out.append("        },")
    for (name, _), frames in zip(STAGES, rows):
        out.append("        %s = {" % name)
        for k, f in enumerate(frames):
            out.append("            { -- heading %d/%d" % (k, VIEWS))
            out += ['                "%s",' % r for r in f]
            out.append("            },")
        out.append("        },")
    out.append("    }")
    out.append("    -- BAKE:marble end")
    return "\n".join(out)

def write(text):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'sprites.lua')
    src = open(path).read()
    begin, end = "    -- BAKE:marble begin", "    -- BAKE:marble end"
    a = src.index(begin); b = src.index(end)+len(end)
    open(path, 'w').write(src[:a]+text+src[b:])

def preview(path, rows, ox, oy, foot, eyes):
    from PIL import Image
    pal = {'w':(0xe6,0xec,0xef),'g':(0xb2,0xb1,0xc0),'s':(0x5b,0x4f,0x6e),
           'o':(0x28,0x07,0x32),'r':(0xe1,0x5e,0x6e),'k':(0xf3,0xa8,0xa8),
           'b':(0x71,0x94,0xf0),'c':(0xab,0xc9,0xf1)}
    w, h = len(rows[0][0][0]), len(rows[0][0])
    cw, ch = w+8, h+10
    img = Image.new('RGB', (cw*VIEWS, ch*len(rows)), pal['w'])
    px = img.load()
    for j, frames in enumerate(rows):
        for k, f in enumerate(frames):
            cx, cy = k*cw+cw//2, j*ch+5+oy
            fy = cy+round(foot)
            for i in range(-12, 13): px[cx+i, fy] = pal['g']
            X0, Y0 = cx-ox, cy-oy
            for y, r in enumerate(f):
                for x, c in enumerate(r):
                    if c != '.': px[X0+x, Y0+y] = pal[c]
            if j == len(rows)-1:
                for ex, ey in eyes[k]: px[cx+ex, cy+ey] = pal['r']
    img = img.resize((img.size[0]*4, img.size[1]*4), Image.NEAREST)
    img.save(path)
    print("wrote", path)

if __name__ == '__main__':
    rows, ox, oy, foot, eyes = bake()
    print("%d stages of %d views, %dx%d, origin %d,%d, foot %.1f" % (
        len(rows), VIEWS, len(rows[0][0][0]), len(rows[0][0]), ox, oy, foot), file=sys.stderr)
    if '--bake' in sys.argv:
        write(lua(rows, ox, oy, foot, eyes))
    elif '--preview' in sys.argv:
        preview(sys.argv[sys.argv.index('--preview')+1], rows, ox, oy, foot, eyes)
    else:
        print(lua(rows, ox, oy, foot, eyes))
