# The MUSIC boss's body (`Sprites.METRONOME` in src/sprites.lua), modelled rather
# than drawn and traced by art/raytrace.py: a pyramid metronome standing on a
# plinth, in red for the reason the whistle is red -- the one thing a body this
# big can say on the page is "theirs" -- with a paper panel down its front for
# the tempo scale and a metal winding key out of its right side, which is what
# tells you which way round it is when it turns.
#
# The pendulum is *not* in these views. It swings, and a baked view is a fixed
# picture, so the arm is drawn live over the body every frame (src/metronome.lua)
# in the same projection the views are baked in. The numbers that projection
# needs -- where the arm's pivot is on the model, how long it is, the camera's
# tilt and the size of a pixel -- are written into the bake beside the views, so
# the arm and the body it hangs off can never disagree about where either is.
#
# A pyramid because a squat thing turns better than a long one (3dmethod.md):
# from every heading it is the same height and close to the same width, and the
# side it shows you is what changes.
#
#   python3 art/metronome.py              -- print the views
#   python3 art/metronome.py --bake       -- write them between the
#                                            BAKE:metronome markers
#   python3 art/metronome.py --preview f  -- every view, arm and all, on the
#                                            MUSIC page, as a PNG

import math, os, sys
from raytrace import Rig, length, sd_box, norm

VIEWS = 16
S = 0.92

# --- the model: front (the panel) along -x, y up off the page, z across it, the
# floor at y = 0. Half-depths are along x and half-widths along z.
BASE, TOP = 3.0, 34.0            # where the pyramid starts and stops
DX0, DX1 = 9.0, 3.4              # half-depth at the bottom and the top
DZ0, DZ1 = 12.0, 4.0             # half-width at the bottom and the top
KX = (DX0-DX1)/(TOP-BASE)
KZ = (DZ0-DZ1)/(TOP-BASE)

def smax(a, b, k):
    h = max(k-abs(a-b), 0)/k
    return max(a, b)+h*h*k*0.25

def depth(y): return DX0-KX*(y-BASE)   # how far the front face is from the middle
def width(y): return DZ0-KZ*(y-BASE)

def sd_pyramid(p):
    x, y, z = p
    dx = (abs(x)-depth(y))/math.sqrt(1+KX*KX)
    dz = (abs(z)-width(y))/math.sqrt(1+KZ*KZ)
    side = smax(dx, dz, 2.2)
    return smax(smax(side, y-TOP, 1.2), BASE-y, 0.6)

def sd_plinth(p):
    return sd_box(p, (0, 1.6, 0), (DX0+1.6, 1.6, DZ0+1.6), 0.8)

def sd_cap(p):
    return sd_box(p, (0, TOP+1.4, 0), (DX1+0.9, 1.4, DZ1+0.9), 0.8)

# The panel: a trapezoid let into the front face, a little way in so its rim is
# a crease, narrowing up the face the way the face does.
PY0, PY1 = 6.5, 30.5
def panel_half(y): return 6.2-3.6*(y-PY0)/(PY1-PY0)
def sd_panel_cut(p):
    x, y, z = p
    face = -depth(y)
    dz = abs(z)-panel_half(y)
    dy = max(PY0-y, y-PY1)
    dx = x-(face+0.7)
    return max(dz, dy, dx)

# The winding key: a stub out of the right side, and a butterfly on the end.
KY = 11.0
def sd_key(p):
    x, y, z = p
    zs = width(KY)-0.5
    stub = max(math.hypot(x, y-KY)-1.3, abs(z-(zs+2.0))-2.2)
    wing = sd_box(p, (0, KY, zs+4.6), (0.7, 3.0, 0.6), 0.5)
    return min(stub, wing)

def model(p):
    body = min(sd_pyramid(p), sd_plinth(p), sd_cap(p))
    body = max(body, -sd_panel_cut(p))
    key = sd_key(p)
    return (body, 'body') if body < key else (key, 'metal')

# The ramps. Red is the tracer's default; the panel is paper going down to
# graphite and slate, with the scale's ticks and the slot the arm hangs in down
# the middle painted where they fall; the key is metal on the same three steps.
def on_panel(q):
    x, y, z = q
    return PY0 < y < PY1 and abs(z) < panel_half(y) and x < -depth(y)+0.9

def shade(q, m, diff, spec, n):
    x, y, z = q
    paper = m == 'metal' or on_panel(q)
    if not paper: return None
    if m == 'body':
        if abs(z) < 0.55: return 's'                      # the slot
        tick = (y-PY0) % 3.0
        if 1.6 < abs(z) < 3.0 and tick < 0.9 and y < PY1-2: return 's'
    if spec > 0.6 or diff > 0.55: return 'w'
    if diff > 0.15: return 'g'
    return 's'

# Where the pendulum hangs from, in model space: low on the panel, just proud of
# the face, and how it leans at rest -- back with the face, so it lies along it
# rather than standing off it.
ARM_Y = 7.5
ARM_PIVOT = (-depth(ARM_Y)-0.6, ARM_Y, 0.0)
ARM_LEAN = KX
ARM_LEN = 38.0
ARM_BOB = 0.62                   # how far up the arm the weight sits

PIVOT = (0.0, 15.0, 0.0)         # the bulk of it: half way up, over the middle

rig = Rig('metronome', model, shade, pivot=PIVOT, views=VIEWS, unit=S, half=30)

def extra():
    px, py, pz = ARM_PIVOT
    return [
        "-- The arm is drawn live in this same projection (src/metronome.lua):",
        "-- its pivot and lean in the model, its length and where the weight",
        "-- sits, all in model units; and the camera -- its tilt, the size of a",
        "-- pixel, and where the turning pivot's own pixel is.",
        "arm = { x = %.3f, y = %.3f, z = %.3f, lean = %.4f, len = %.1f, bob = %.2f }," % (
            px-PIVOT[0], py-PIVOT[1], pz-PIVOT[2], ARM_LEAN, ARM_LEN, ARM_BOB),
        "cam = { pitch = %.5f, unit = %.3f, bias = %.4f }," % (rig.pitch, S, rig.bias),
    ]

# --- the arm, the way the game draws it, for the preview: the same sums as
# Metronome.armPoint in src/metronome.lua.
def arm_point(h, swing, along):
    px, py, pz = ARM_PIVOT
    px, py, pz = px-PIVOT[0], py-PIVOT[1], pz-PIVOT[2]
    d = norm((ARM_LEAN, math.cos(swing), math.sin(swing)))
    mx, my, mz = px+d[0]*along, py+d[1]*along, pz+d[2]*along
    a = h+math.pi
    c, s = math.cos(a), math.sin(a)
    x = mx*c-mz*s; z = mx*s+mz*c; y = my
    cp, sp = math.cos(rig.pitch), math.sin(rig.pitch)
    cy = y*cp-z*sp; depth_ = y*sp+z*cp
    return (cx_px(x), cy_px(cy), depth_)
def cx_px(cx): return cx/S+rig.bias
def cy_px(cy): return -cy/S+rig.bias

def preview(path):
    from PIL import Image
    pal = {'w':(0xe6,0xec,0xef),'g':(0xb2,0xb1,0xc0),'s':(0x5b,0x4f,0x6e),
           'o':(0x28,0x07,0x32),'r':(0xe1,0x5e,0x6e),'k':(0xf3,0xa8,0xa8),
           'b':(0x71,0x94,0xf0),'c':(0xab,0xc9,0xf1)}
    rows = rig.rows
    w, h = len(rows[0][0]), len(rows[0])
    cell_w, cell_h = w+16, h+30
    cols = 8
    img = Image.new('RGB', (cell_w*cols, cell_h*((len(rows)+cols-1)//cols)), pal['w'])
    px = img.load()
    for y in range(img.size[1]):
        at = y % 40
        if at < 20 and at % 4 == 0:
            for x in range(img.size[0]): px[x, y] = pal['c']
    for k, f in enumerate(rows):
        X0 = (k % cols)*cell_w+8; Y0 = (k//cols)*cell_h+22
        hd = k*2*math.pi/VIEWS
        swing = 0.45*math.cos(k*0.9)
        def plot_arm():
            n = int(ARM_LEN/S)+1
            for i in range(n+1):
                ax, ay, _ = arm_point(hd, swing, ARM_LEN*i/n)
                X, Y = X0+rig.ox+math.floor(ax), Y0+rig.oy+math.floor(ay)
                if 0 <= X < img.size[0] and 0 <= Y < img.size[1]: px[X, Y] = pal['o']
            bx, by, _ = arm_point(hd, swing, ARM_LEN*ARM_BOB)
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    X, Y = X0+rig.ox+math.floor(bx)+dx, Y0+rig.oy+math.floor(by)+dy
                    px[X, Y] = pal['o'] if abs(dx) == 1 or abs(dy) == 1 else pal['g']
        front = math.sin(hd) > -0.2
        if not front: plot_arm()
        for j, r in enumerate(f):
            for i, ch in enumerate(r):
                if ch != '.': px[X0+i, Y0+j] = pal[ch]
        if front: plot_arm()
    img = img.resize((img.size[0]*4, img.size[1]*4), Image.NEAREST)
    img.save(path)
    print("wrote", path)

rig.bake()
if '--bake' in sys.argv:
    rig.write(rig.lua('METRONOME', extra()))
elif '--preview' in sys.argv:
    preview(sys.argv[sys.argv.index('--preview')+1])
else:
    print(rig.lua('METRONOME', extra()))
