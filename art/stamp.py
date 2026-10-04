# The FINANCE boss's body (`Sprites.STAMP` in src/sprites.lua): an office rubber
# stamp, modelled and traced by art/raytrace.py like the whistle and the
# metronome -- a red wooden mount with a paper label on its top, a metal collar,
# a turned neck and a round knob to hold it by, and the rubber underneath.
#
# Its pad is the size of one cell of the ledger, which is the point of it: a
# cell is 40 across and 12 down, and the pad is exactly that seen from the
# camera, so the rubber under the thing standing on the page covers the box it
# is about to print -- a long, low stamp, the proportions of a PAID stamp. src/stamp.lua lands it on the printed cells and the mark it
# leaves fills one.
#
# **More pictures than the others, because it moves more.** A whistle turns and
# a metronome turns; a stamp also rocks back before it jumps, pitches forward as
# it comes down, and flattens when it hits. Each of those is a *pose*, and each
# pose is a whole ring of headings, all cut to one box with the pivot at the
# same pixel (raytrace.share), so swapping a pose is as still as swapping a
# view:
#
#   stand    upright, the body at rest and in the air
#   rear     rocked back on its heel, front lifted -- the wind-up
#   squash   pressed into the page -- the impact
#
# and a fourth the game uses, `lean`, pitched forward onto its toe, which is not
# baked at all: the stamp is the same front and back, so leaning forward facing
# one way is rearing back facing the other, and the loader in src/sprites.lua
# builds the lean ring out of the rear one turned half round. The same symmetry
# is why stand and squash are baked at eight headings rather than sixteen --
# heading k and heading k + 8 are the same picture -- so the four rings of
# sixteen the game turns through are thirty-two pictures on disk.
#
# Every pose is posed about a point on the floor -- the heel, the toe, the
# middle of the pad -- so it never leaves the page in a way the game did not ask
# for: lifting it is the game's (`hop`, Enemy:footing), never the bake's.
#
#   python3 art/stamp.py              -- print the views
#   python3 art/stamp.py --bake       -- write them between the BAKE:stamp markers
#   python3 art/stamp.py --preview f  -- every pose and view on the FINANCE
#                                        page, with the cell the pad covers
#                                        drawn under it, as a PNG

import math, os, sys
from raytrace import Rig, length, sd_box, share

S = 0.92
PITCH = 34

# --- the model: front along -x, y up off the page, z across it, floor at y = 0.
# Half-depths along x, half-widths along z. The pad is one ledger cell: 40px
# across is 40 * S units, and 12px down the screen is a floor depth of
# 12 * S / sin(PITCH) -- the camera looks down at the page, so depth along the
# floor is foreshortened by the sine of the tilt and height by its cosine.
PAD_Z = 40*S/2 - 0.6
PAD_X = 12*S/math.sin(math.radians(PITCH))/2 - 0.6
PAD_H = 2.4
BLOCK_Y0, BLOCK_Y1 = PAD_H, 9.6
GROW = 0.8                         # how far the mount stands out past the rubber
NECK_Y0, NECK_Y1 = BLOCK_Y1, 17.5
KNOB_Y = 21.5

def sd_cyl(p, r, y0, y1, rr):
    x, y, z = p
    dx = math.hypot(x, z)-(r-rr)
    dy = abs(y-(y0+y1)/2)-((y1-y0)/2-rr)
    return min(max(dx, dy), 0)+length((max(dx, 0), max(dy, 0), 0))-rr

def sd_pad(p):
    return sd_box(p, (0, PAD_H/2, 0), (PAD_X, PAD_H/2, PAD_Z), 0.7)

def sd_block(p):
    return sd_box(p, (0, (BLOCK_Y0+BLOCK_Y1)/2, 0),
                  (PAD_X+GROW, (BLOCK_Y1-BLOCK_Y0)/2, PAD_Z+GROW), 1.5)

def sd_collar(p):
    return sd_cyl(p, 5.0, BLOCK_Y1-0.6, BLOCK_Y1+2.2, 0.6)

def sd_neck(p):
    # Waisted: thinnest a third of the way up, the way a turned handle is.
    x, y, z = p
    t = (y-NECK_Y0)/(NECK_Y1-NECK_Y0)
    r = 3.4-1.0*math.sin(math.pi*min(1, max(0, t)))
    return max(math.hypot(x, z)-r, abs(y-(NECK_Y0+NECK_Y1)/2)-(NECK_Y1-NECK_Y0)/2)

def sd_knob(p):
    x, y, z = p
    rx, ry = 7.6, 5.6
    q = (x/rx, (y-KNOB_Y)/ry, z/rx)
    k = length(q)
    return (k-1)*min(rx, ry)

def model(p):
    wood = min(sd_block(p), sd_neck(p), sd_knob(p))
    parts = ((wood, 'body'), (sd_collar(p), 'metal'), (sd_pad(p), 'rubber'))
    return min(parts, key=lambda a: a[0])

# The ramps. The wood is the tracer's red, the way the whistle and the
# metronome are red -- the one thing a body this big can say is "theirs". The
# top of the mount carries a paper label with a red frame printed on it, which
# is what a stamp's label is (a proof of what it prints) and what keeps the big
# flat top from being one slab of blush. The collar is metal on the three grey
# steps; the rubber is dark, and red along its bottom edge where it is inked.
LABEL_X, LABEL_Z = PAD_X-2.2, PAD_Z-2.6

def shade(q, m, diff, spec, n):
    x, y, z = q
    if m == 'metal':
        if spec > 0.6 or diff > 0.6: return 'w'
        return 'g' if diff > 0.2 else 's'
    if m == 'rubber':
        if y < 0.8: return 'r'
        return 'g' if diff > 0.62 else 's'
    if BLOCK_Y1-0.5 < y < BLOCK_Y1+0.4 and abs(x) < LABEL_X and abs(z) < LABEL_Z:
        fx, fz = LABEL_X-abs(x), LABEL_Z-abs(z)
        if (1.3 < fx < 2.5 and fz > 1.3) or (1.3 < fz < 2.5 and fx > 1.3):
            return 'r'
        return 'w' if diff > 0.45 else 'g'
    return None

# --- the poses. Each takes a point in the posed body back to the upright model,
# and says how much a distance shrinks on the way (so the march stays safe).
TILT = math.radians(20)
HEEL = PAD_X+GROW                  # the back edge it rocks on
SQUASH = (1.12, 0.68)              # across, and up

def rot(x, y, cx, a):
    dx = x-cx; c, s = math.cos(a), math.sin(a)
    return cx+dx*c-y*s, dx*s+y*c

def rear(p):
    # Rocked back on its heel: the front comes up off the page.
    x, y, z = p
    qx, qy = rot(x, y, HEEL, TILT)
    return (qx, qy, z), 1.0

def squash(p):
    x, y, z = p
    sx, sy = SQUASH
    return (x/sx, y/sy, z/sx), min(sx, sy)

def stand(p): return p, 1.0

PIVOT = (0.0, 6.0, 0.0)            # the middle of the mount: the bulk of it

def posed(pose):
    def m(p):
        q, k = pose(p)
        d, mat = model(q)
        return d*k, mat
    def s(q, mat, diff, spec, n):
        return shade(pose(q)[0], mat, diff, spec, n)
    return m, s

def rig(name, pose):
    m, s = posed(pose)
    return Rig('stamp', m, s, pivot=PIVOT, views=16, unit=S, pitch=PITCH, half=34)

# Which headings each pose is baked at: stand and squash look the same either
# way round, so only the first half turn of each.
POSES = (('stand', stand, range(8)), ('rear', rear, range(16)), ('squash', squash, range(8)))

def bake():
    sets, rigs = [], []
    for name, pose, ks in POSES:
        r = rig(name, pose)
        rigs.append(r)
        sets.append([r.render(k*2*math.pi/16) for k in ks])
    rows, ox, oy = share(sets)
    r = rigs[0]
    n = len(sets[0][0])
    bias = r.half/r.unit-n//2
    # Where the middle of the pad is on the page, in pixels below the origin:
    # the pivot is up in the mount, and what the game lines up with a cell is
    # the rubber under it.
    foot = (PIVOT[1]*math.cos(r.pitch))/S+bias
    return rows, ox, oy, foot, r

ROWS, OX, OY, FOOT, RIG = bake()

def lua():
    out = ["    -- BAKE:stamp begin",
           "    -- Written by art/stamp.py; edit the model there, not these rows.",
           "    Sprites.STAMP = {",
           "        ox = %d, oy = %d," % (OX, OY),
           "        -- How far below the origin the middle of the pad is, in pixels:",
           "        -- what src/stamp.lua lines up with the middle of a cell.",
           "        foot = %d," % round(FOOT)]
    for (name, _, ks), frames in zip(POSES, ROWS):
        out.append("        %s = {" % name)
        for k, f in zip(ks, frames):
            out.append("            { -- heading %d/16" % k)
            out += ['                "%s",' % r for r in f]
            out.append("            },")
        out.append("        },")
    out.append("    }")
    out.append("    -- BAKE:stamp end")
    return "\n".join(out)

# --- the preview: every pose at every heading on the ledger, with the cell the
# pad lands in outlined under it, so the foot can be checked against the page.
def preview(path):
    from PIL import Image
    pal = {'w':(0xe6,0xec,0xef),'g':(0xb2,0xb1,0xc0),'s':(0x5b,0x4f,0x6e),
           'o':(0x28,0x07,0x32),'r':(0xe1,0x5e,0x6e),'k':(0xf3,0xa8,0xa8),
           'b':(0x71,0x94,0xf0),'c':(0xab,0xc9,0xf1)}
    # The four rings as the game builds them.
    stand_, rear_, squash_ = ROWS
    ring = lambda half: [half[k % 8] for k in range(16)]
    rings = [('stand', ring(stand_)), ('rear', rear_),
             ('lean', [rear_[(k+8) % 16] for k in range(16)]), ('squash', ring(squash_))]
    w, h = len(stand_[0][0]), len(stand_[0])
    cw, ch = 52, max(h+14, 60)
    img = Image.new('RGB', (cw*16, ch*len(rings)), pal['w'])
    px = img.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            if (y-8) % 12 == 0 or (x-10) % 40 == 0: px[x, y] = pal['c']
    foot = round(FOOT)
    for j, (name, frames) in enumerate(rings):
        for k, f in enumerate(frames):
            cx, cy = k*cw+cw//2, j*ch+ch-20
            # The cell under the pad.
            for i in range(-20, 21):
                for yy in (cy+foot-6, cy+foot+6):
                    px[cx+i, yy] = pal['s']
            for yy in range(cy+foot-6, cy+foot+7):
                for i in (-20, 20): px[cx+i, yy] = pal['s']
            X0, Y0 = cx-OX, cy-OY
            for y, r in enumerate(f):
                for x, c in enumerate(r):
                    if c != '.' and 0 <= Y0+y < img.size[1]: px[X0+x, Y0+y] = pal[c]
    img = img.resize((img.size[0]*3, img.size[1]*3), Image.NEAREST)
    img.save(path)
    print("wrote", path)

if '--bake' in sys.argv:
    RIG.rows, RIG.views, RIG.ox, RIG.oy = ROWS[1], 16, OX, OY  # for write()'s line
    RIG.write(lua())
    print("baked stand 8, rear 16, squash 8; %dx%d, origin %d,%d, foot %d" % (
        len(ROWS[0][0][0]), len(ROWS[0][0]), OX, OY, round(FOOT)))
elif '--preview' in sys.argv:
    preview(sys.argv[sys.argv.index('--preview')+1])
else:
    print(lua())
