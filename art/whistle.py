# The P.E. whistle boss's sprites (`Sprites.WHISTLE` in src/sprites.lua), modelled
# rather than drawn: a cylinder for the barrel, a rounded box for the mouthpiece
# with the window cut out of its top, a torus for the lanyard ring. The model is
# stood on the page and turned to each of VIEWS headings about the barrel's
# middle, then ray-marched straight to palette keys at sprite size -- one sample
# a pixel, so nothing is ever averaged into a ninth colour -- from a camera
# looking down at the page, with the light fixed in the room (top left) rather
# than on the whistle, so it stays put however the thing is turned. Ink goes
# round the silhouette and a step darker along the creases where one face turns
# into another.
#
# Every view is cut to the same box with the barrel's middle at the same pixel,
# which is the sprite origin the game draws at and measures the hit circle from:
# turning is swapping one picture for the next with the drum standing still.
#
#   python3 art/whistle.py            -- print the views
#   python3 art/whistle.py --bake     -- write them between the BAKE:whistle
#                                        markers in src/sprites.lua
#
# View k (1-based) points its mouthpiece at heading (k-1)/VIEWS of a turn,
# measured the way atan2(dy, dx) is on the screen: 0 is right, a quarter is down.

import math, os, sys

VIEWS = 16
S = 0.92                      # world units per pixel
PITCH = math.radians(float(os.getenv('PITCH', '34')))   # camera tilt off flat-on

def add(a, b): return (a[0]+b[0], a[1]+b[1], a[2]+b[2])
def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def mul(a, k): return (a[0]*k, a[1]*k, a[2]*k)
def dot(a, b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def length(a): return math.sqrt(dot(a, a))
def norm(a):
    l = length(a) or 1
    return mul(a, 1/l)

# --- the model, in its own space: x along the whistle (mouthpiece at -x), y up,
# z across it. The barrel's middle is at (BX, 0, 0) and is the pivot.
BX = 7.0
def sd_box(p, c, b, rr):
    q = (abs(p[0]-c[0])-b[0]+rr, abs(p[1]-c[1])-b[1]+rr, abs(p[2]-c[2])-b[2]+rr)
    return (length((max(q[0], 0), max(q[1], 0), max(q[2], 0)))
            + min(max(q[0], max(q[1], q[2])), 0) - rr)
def sd_barrel(p):
    x, y, z = p[0]-BX, p[1], p[2]
    r, h, rr = 11.5, 6.5, 1.6
    dx = math.hypot(x, y)-(r-rr); dz = abs(z)-(h-rr)
    return min(max(dx, dz), 0)+length((max(dx, 0), max(dz, 0), 0))-rr
def sd_tube(p):
    t = min(1, max(0, (p[0]+22)/26))
    hy = 3.2+1.3*t
    return sd_box(p, (-9, 11.5-hy, 0), (13, hy, 4.6), 1.4)
def sd_window(p):
    return sd_box(p, (-1.0, 10.8, 0), (3.6, 3.4, 3.6), 0.3)
def sd_ring(p):
    q = sub(p, (BX+9.5, 9.5, 0))
    a = math.hypot(q[0], q[1])-3.0
    return math.hypot(a, q[2])-0.9
def model(p):
    b = max(min(sd_barrel(p), sd_tube(p)), -sd_window(p))
    r = sd_ring(p)
    return (b, 'body') if b < r else (r, 'ring')

# --- the room: x right, y up off the page, z towards the viewer (down the
# screen). Turning by heading h about the pivot points the mouthpiece along
# (cos h, sin h) on the page.
class View:
    def __init__(self, h):
        a = h+math.pi
        self.c, self.s = math.cos(a), math.sin(a)
    def to_model(self, p):
        x, y, z = p
        mx = x*self.c+z*self.s
        mz = -x*self.s+z*self.c
        return (mx+BX, y, mz)
    def scene(self, p):
        return model(self.to_model(p))

def cam_to_world(p):
    x, y, z = p
    c, s = math.cos(PITCH), math.sin(PITCH)
    return (x, y*c+z*s, -y*s+z*c)

LIGHT = norm((-0.5, 0.75, 0.45))
EYE = cam_to_world((0, 0, 1))

def trace(v, cx, cy):
    o = cam_to_world((cx, cy, 80)); d = cam_to_world((0, 0, -1))
    t = 0
    for _ in range(200):
        p = add(o, mul(d, t)); dist, m = v.scene(p)
        if dist < 0.02: return p, m
        t += dist
        if t > 180: break
    return None, None

def normal(v, p):
    e = 0.05
    f = lambda q: v.scene(q)[0]
    return norm((f(add(p, (e, 0, 0)))-f(sub(p, (e, 0, 0))),
                 f(add(p, (0, e, 0)))-f(sub(p, (0, e, 0))),
                 f(add(p, (0, 0, e)))-f(sub(p, (0, 0, e)))))

def shadowed(v, p, n):
    o = add(p, mul(n, 0.3)); t = 0.2
    for _ in range(60):
        d, _ = v.scene(add(o, mul(LIGHT, t)))
        if d < 0.02: return True
        t += d
        if t > 40: break
    return False

def shade(v, p, m, n):
    q = v.to_model(p)
    if m == 'body':
        if sd_window(q) < 0.25 and q[1] < 10.6: return 'o'                # the slot
        if q[0] < -21.0 and abs(q[2]) < 3.0 and 7.6 < q[1] < 10.6: return 'o'  # the mouth
    diff = max(0, dot(n, LIGHT))
    if shadowed(v, p, n): diff *= 0.35
    spec = max(0, dot(n, norm(add(LIGHT, EYE))))**40
    if m == 'ring':
        return 'c' if diff > 0.7 else ('b' if diff > 0.3 else 's')
    if spec > 0.6: return 'w'
    if diff > 0.78: return 'k'
    if diff > 0.2: return 'r'
    # light bounced back up off the page into the bottom of the shadow side
    if n[1] < -0.55 and diff > 0.02: return 'r'
    return 's'

R = 34   # half the render box, in world units: enough for the tube at any heading
def render(h):
    v = View(h)
    n = int(2*R/S)
    g = [['.']*n for _ in range(n)]
    nr = {}
    for j in range(n):
        for i in range(n):
            cx = -R+(i+0.5)*S; cy = R-(j+0.5)*S
            p, m = trace(v, cx, cy)
            if p:
                nn = normal(v, p)
                g[j][i] = shade(v, p, m, nn)
                nr[(j, i)] = (nn, m)
    # creases, a step darker, so the planes read as planes
    for j in range(n):
        for i in range(n):
            a = nr.get((j, i))
            if not a or g[j][i] == 'o': continue
            for di, dj in ((1, 0), (0, 1)):
                b = nr.get((j+dj, i+di))
                if b and b[1] == a[1] and dot(a[0], b[0]) < 0.55:
                    if g[j][i] in 'kr': g[j][i] = 's'
                    break
    out = [r[:] for r in g]
    for y in range(n):
        for x in range(n):
            if g[y][x] == '.': continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                X, Y = x+dx, y+dy
                if not (0 <= X < n and 0 <= Y < n) or g[Y][X] == '.':
                    out[y][x] = 'o'; break
    return out

frames = [render(k*2*math.pi/VIEWS) for k in range(VIEWS)]
n = len(frames[0])
# The pivot projects to the middle of the render box (the camera looks at it).
piv = n//2
def used(f, axis):
    idx = [(y if axis else x) for y in range(n) for x in range(n) if f[y][x] != '.']
    return min(idx), max(idx)
x0 = min(used(f, 0)[0] for f in frames); x1 = max(used(f, 0)[1] for f in frames)
y0 = min(used(f, 1)[0] for f in frames); y1 = max(used(f, 1)[1] for f in frames)
# symmetric about the pivot left to right, so a heading and its mirror are the
# same box
half = max(piv-x0, x1-piv)
x0, x1 = piv-half, piv+half
rows = [[''.join(f[y][x0:x1+1]) for y in range(y0, y1+1)] for f in frames]
ox, oy = piv-x0, piv-y0

def lua():
    out = ["    -- BAKE:whistle begin",
           "    -- Written by art/whistle.py; edit the model there, not these rows.",
           "    Sprites.WHISTLE = {",
           "        ox = %d, oy = %d," % (ox, oy)]
    for k, f in enumerate(rows):
        out.append("        { -- heading %d/%d" % (k, VIEWS))
        out += ['            "%s",' % r for r in f]
        out.append("        },")
    out.append("    }")
    out.append("    -- BAKE:whistle end")
    return "\n".join(out)

if '--bake' in sys.argv:
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'sprites.lua')
    src = open(path).read()
    a = src.index("    -- BAKE:whistle begin"); b = src.index("    -- BAKE:whistle end")
    b += len("    -- BAKE:whistle end")
    open(path, 'w').write(src[:a]+lua()+src[b:])
    print("baked %d views, %dx%d, origin %d,%d" % (VIEWS, len(rows[0][0]), len(rows[0]), ox, oy))
else:
    print(lua())
