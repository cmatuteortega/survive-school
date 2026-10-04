# The tracer the solid bosses share (3dmethod.md): everything about turning a
# model into a ring of baked ASCII views that is not the model itself. A
# character's own script (art/whistle.py, art/metronome.py) holds its signed
# distance functions and its colour ramps, and hands them to `Rig`; this file
# stands the model on the page, turns it to each heading about its pivot,
# ray-marches it one sample a pixel from a camera looking down at the page,
# draws the creases and the ink rim, crops every view to one shared box and
# writes the result between a pair of BAKE markers in src/sprites.lua.
#
# The light is fixed in the room rather than on the model, so it stays at the
# top left whichever way the thing is turned -- the same window both solid
# bosses are lit by. One sample a pixel, always: averaging is exactly what
# invents a ninth colour.
#
# Headings are measured the way atan2(dy, dx) is on the screen: 0 is right, a
# quarter turn is down. A model is built with its front along -x, y up off the
# page and z across it.

import math, os

def add(a, b): return (a[0]+b[0], a[1]+b[1], a[2]+b[2])
def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def mul(a, k): return (a[0]*k, a[1]*k, a[2]*k)
def dot(a, b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def length(a): return math.sqrt(dot(a, a))
def norm(a):
    l = length(a) or 1
    return mul(a, 1/l)

def sd_box(p, c, b, rr):
    q = (abs(p[0]-c[0])-b[0]+rr, abs(p[1]-c[1])-b[1]+rr, abs(p[2]-c[2])-b[2]+rr)
    return (length((max(q[0], 0), max(q[1], 0), max(q[2], 0)))
            + min(max(q[0], max(q[1], q[2])), 0) - rr)

LIGHT = norm((-0.5, 0.75, 0.45))

class View:
    # One heading. Turning by h about the pivot points the model's front (-x)
    # along (cos h, sin h) on the page; `to_model` takes a point in the room,
    # where the pivot is the origin, back into the model's own space.
    def __init__(self, rig, h):
        a = h+math.pi
        self.c, self.s = math.cos(a), math.sin(a)
        self.rig = rig
    def to_model(self, p):
        x, y, z = p
        mx = x*self.c+z*self.s
        mz = -x*self.s+z*self.c
        px, py, pz = self.rig.pivot
        return (mx+px, y+py, mz+pz)
    def scene(self, p):
        return self.rig.model(self.to_model(p))

class Rig:
    # model(q) -> (distance, material) in model space; shade(q, material,
    # diffuse, specular, normal) -> a palette key, or None for the default red
    # ramp. `pivot` is the model point that stays still while it turns.
    def __init__(self, name, model, shade, pivot, views=16, unit=0.92,
                 pitch=34, half=34):
        self.name, self.model, self.shade = name, model, shade
        self.pivot, self.views, self.unit, self.half = pivot, views, unit, half
        self.pitch = math.radians(float(os.getenv('PITCH', str(pitch))))
        self.eye = self.cam_to_world((0, 0, 1))

    # The room: x right, y up off the page, z towards the viewer (down the
    # screen); the camera is the room tilted by `pitch`.
    def cam_to_world(self, p):
        x, y, z = p
        c, s = math.cos(self.pitch), math.sin(self.pitch)
        return (x, y*c+z*s, -y*s+z*c)

    def trace(self, v, cx, cy):
        o = self.cam_to_world((cx, cy, 80)); d = self.cam_to_world((0, 0, -1))
        t = 0
        for _ in range(200):
            p = add(o, mul(d, t)); dist, m = v.scene(p)
            if dist < 0.02: return p, m
            t += dist
            if t > 180: break
        return None, None

    def normal(self, v, p):
        e = 0.05
        f = lambda q: v.scene(q)[0]
        return norm((f(add(p, (e, 0, 0)))-f(sub(p, (e, 0, 0))),
                     f(add(p, (0, e, 0)))-f(sub(p, (0, e, 0))),
                     f(add(p, (0, 0, e)))-f(sub(p, (0, 0, e)))))

    def shadowed(self, v, p, n):
        o = add(p, mul(n, 0.3)); t = 0.2
        for _ in range(60):
            d, _ = v.scene(add(o, mul(LIGHT, t)))
            if d < 0.02: return True
            t += d
            if t > 40: break
        return False

    def colour(self, v, p, m, n):
        diff = max(0, dot(n, LIGHT))
        if self.shadowed(v, p, n): diff *= 0.35
        spec = max(0, dot(n, norm(add(LIGHT, self.eye))))**40
        k = self.shade(v.to_model(p), m, diff, spec, n)
        if k: return k
        # The red ramp, the default body: paper for the glint, blush lit, red
        # in the middle, slate in shadow -- with light bounced back up off the
        # page into the bottom of the shadow side, without which the shadow
        # side reads as a hole cut in the body.
        if spec > 0.6: return 'w'
        if diff > 0.78: return 'k'
        if diff > 0.2: return 'r'
        if n[1] < -0.55 and diff > 0.02: return 'r'
        return 's'

    def render(self, h):
        v = View(self, h)
        S, R = self.unit, self.half
        n = int(2*R/S)
        g = [['.']*n for _ in range(n)]
        nr = {}
        for j in range(n):
            for i in range(n):
                cx = -R+(i+0.5)*S; cy = R-(j+0.5)*S
                p, m = self.trace(v, cx, cy)
                if p:
                    nn = self.normal(v, p)
                    g[j][i] = self.colour(v, p, m, nn)
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
                        elif g[j][i] in 'wg' and a[1] != 'body': g[j][i] = 's'
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

    # Every view in one box, symmetric left to right about the pivot, so a turn
    # swaps one picture for the next with the pivot standing still.
    def bake(self):
        frames = [self.render(k*2*math.pi/self.views) for k in range(self.views)]
        n = len(frames[0])
        piv = n//2
        def used(f, axis):
            idx = [(y if axis else x) for y in range(n) for x in range(n) if f[y][x] != '.']
            return min(idx), max(idx)
        x0 = min(used(f, 0)[0] for f in frames); x1 = max(used(f, 0)[1] for f in frames)
        y0 = min(used(f, 1)[0] for f in frames); y1 = max(used(f, 1)[1] for f in frames)
        half = max(piv-x0, x1-piv)
        x0, x1 = piv-half, piv+half
        self.rows = [[''.join(f[y][x0:x1+1]) for y in range(y0, y1+1)] for f in frames]
        self.ox, self.oy = piv-x0, piv-y0
        # Where the pivot's own pixel sits, for anything drawn live on top of the
        # views in the same projection (the metronome's arm): a point at camera
        # (cx, cy) lands (cx + half)/unit - piv pixels right of the origin.
        self.bias = self.half/self.unit-piv
        return self.rows

    def lua(self, upper, extra=()):
        out = ["    -- BAKE:%s begin" % self.name,
               "    -- Written by art/%s.py; edit the model there, not these rows." % self.name,
               "    Sprites.%s = {" % upper,
               "        ox = %d, oy = %d," % (self.ox, self.oy)]
        out += ["        " + line for line in extra]
        for k, f in enumerate(self.rows):
            out.append("        { -- heading %d/%d" % (k, self.views))
            out += ['            "%s",' % r for r in f]
            out.append("        },")
        out.append("    }")
        out.append("    -- BAKE:%s end" % self.name)
        return "\n".join(out)

    def write(self, text):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'sprites.lua')
        src = open(path).read()
        begin, end = "    -- BAKE:%s begin" % self.name, "    -- BAKE:%s end" % self.name
        a = src.index(begin); b = src.index(end)+len(end)
        open(path, 'w').write(src[:a]+text+src[b:])
        print("baked %d views, %dx%d, origin %d,%d" % (self.views, len(self.rows[0][0]),
              len(self.rows[0]), self.ox, self.oy))

# Several sets of views in one box -- a body with more than one pose (the
# FINANCE stamp's stand, rear and squash) -- so that whichever picture is up,
# the pivot is the same pixel. `sets` is a list of lists of frames, each frame
# rendered at the same `half` and `unit`; what comes back is the same lists cut
# to the shared box, and the origin in it. One box for every pose is the same
# rule as one box for every heading, for the same reason: swapping pictures
# must never move the thing.
def share(sets):
    n = len(sets[0][0])
    piv = n//2
    xs, ys = [], []
    for frames in sets:
        for f in frames:
            for y in range(n):
                for x in range(n):
                    if f[y][x] != '.': xs.append(x); ys.append(y)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    half = max(piv-x0, x1-piv)
    x0, x1 = piv-half, piv+half
    out = [[[''.join(f[y][x0:x1+1]) for y in range(y0, y1+1)] for f in frames]
           for frames in sets]
    return out, piv-x0, piv-y0
