# The P.E. whistle boss's sprites (`Sprites.WHISTLE` in src/sprites.lua), modelled
# rather than drawn: a cylinder for the barrel, a rounded box for the mouthpiece
# with the window cut out of its top, a torus for the lanyard ring. The model is
# stood on the page and turned to each of VIEWS headings about the barrel's
# middle, then ray-marched straight to palette keys at sprite size -- one sample
# a pixel, so nothing is ever averaged into a ninth colour -- from a camera
# looking down at the page, with the light fixed in the room (top left) rather
# than on the whistle, so it stays put however the thing is turned. Ink goes
# round the silhouette and a step darker along the creases where one face turns
# into another. All of that is the shared tracer, art/raytrace.py; this file is
# the model and its colours.
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
from raytrace import Rig, length, sub, sd_box

VIEWS = 16
S = 0.92                      # world units per pixel

# --- the model, in its own space: x along the whistle (mouthpiece at -x), y up,
# z across it. The barrel's middle is at (BX, 0, 0) and is the pivot.
BX = 7.0
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

# The red ramp is the tracer's default; what is said here is the two holes,
# painted ink where they are, and the ring's three steps of blue.
def shade(q, m, diff, spec, n):
    if m == 'body':
        if sd_window(q) < 0.25 and q[1] < 10.6: return 'o'                # the slot
        if q[0] < -21.0 and abs(q[2]) < 3.0 and 7.6 < q[1] < 10.6: return 'o'  # the mouth
        return None
    return 'c' if diff > 0.7 else ('b' if diff > 0.3 else 's')

rig = Rig('whistle', model, shade, pivot=(BX, 0, 0), views=VIEWS, unit=S, half=34)
rig.bake()

if '--bake' in sys.argv:
    rig.write(rig.lua('WHISTLE'))
else:
    print(rig.lua('WHISTLE'))
