# The P.E. whistle boss's sprite (`whistle` in src/sprites.lua), modelled rather
# than drawn: a cylinder for the barrel, a rounded box for the mouthpiece with the
# window cut out of its top, a torus for the lanyard ring. Ray-marched straight to
# palette keys at sprite size -- one sample a pixel, so nothing is ever averaged
# into a ninth colour -- lit from the top left, with ink round the silhouette and
# a step darker along the creases where one face turns into another. The face is
# authored flat and laid on the barrel's front cap where it projects.
#
#   python3 art/whistle.py [world units per pixel, default 1.0] > rows.txt
#   YAW=-22 PITCH=16 python3 art/whistle.py 0.92      # what ships
#
# Paste the rows over the sprite and re-measure its origin (the barrel's middle,
# `ox`/`oy` on the newSprite call) if the size or the angle moves.
import math, sys
# --- tiny SDF ray marcher, orthographic, rendered straight to palette keys ---
def v(x,y,z): return (x,y,z)
def add(a,b): return (a[0]+b[0],a[1]+b[1],a[2]+b[2])
def sub(a,b): return (a[0]-b[0],a[1]-b[1],a[2]-b[2])
def mul(a,k): return (a[0]*k,a[1]*k,a[2]*k)
def dot(a,b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def norm(a):
    l=math.sqrt(dot(a,a)) or 1; return mul(a,1/l)
def length(a): return math.sqrt(dot(a,a))

BX=7.0   # barrel centre x
def sd_barrel(p):   # cylinder, axis z, slightly rounded rims
    x,y,z=p[0]-BX,p[1],p[2]
    r=11.5; h=6.5; rr=1.6
    dx=math.hypot(x,y)-(r-rr); dz=abs(z)-(h-rr)
    return min(max(dx,dz),0)+length((max(dx,0),max(dz,0),0))-rr
def sd_box(p,c,b,rr):
    q=(abs(p[0]-c[0])-b[0]+rr,abs(p[1]-c[1])-b[1]+rr,abs(p[2]-c[2])-b[2]+rr)
    return length((max(q[0],0),max(q[1],0),max(q[2],0)))+min(max(q[0],max(q[1],q[2])),0)-rr
def sd_tube(p):     # the mouthpiece, flattening towards the tip
    x=p[0]
    t=min(1,max(0,(x+22)/26))
    hy=3.2+1.3*t          # half height grows towards the barrel
    cy=11.5-hy            # top edge level with the barrel's top
    return sd_box(p,(-9,cy,0),(13,hy,4.6),1.4)
def sd_window(p):   # the slot cut in the top where tube meets barrel
    return sd_box(p,(-1.0,10.8,0),(3.6,3.4,3.6),0.3)
def sd_ring(p):     # lanyard ring on the barrel's back shoulder
    q=sub(p,(BX+9.5,9.5,0))
    # torus in the xy plane tilted: axis along z
    a=math.hypot(q[0],q[1])-3.0
    return math.hypot(a,q[2])-0.9
def body(p):
    return max(min(sd_barrel(p),sd_tube(p)),-sd_window(p))
def scene(p):
    b=body(p); r=sd_ring(p)
    return (b,'body') if b<r else (r,'ring')

# camera: look at the whistle from front, a little above and a little to the right
import os
yaw=math.radians(float(os.getenv('YAW','-22'))); pitch=math.radians(float(os.getenv('PITCH','16')))
def rot(p):  # world -> camera
    x,y,z=p
    x,z = x*math.cos(yaw)+z*math.sin(yaw), -x*math.sin(yaw)+z*math.cos(yaw)
    y,z = y*math.cos(pitch)-z*math.sin(pitch), y*math.sin(pitch)+z*math.cos(pitch)
    return (x,y,z)
def unrot(p):
    x,y,z=p
    y,z = y*math.cos(-pitch)-z*math.sin(-pitch), y*math.sin(-pitch)+z*math.cos(-pitch)
    x,z = x*math.cos(-yaw)+z*math.sin(-yaw), -x*math.sin(-yaw)+z*math.cos(-yaw)
    return (x,y,z)

LIGHT=norm((-0.5,0.65,0.8))
VIEW=unrot((0,0,1))
def trace(cx,cy):
    o=unrot((cx,cy,60)); d=unrot((0,0,-1))
    t=0
    for _ in range(160):
        p=add(o,mul(d,t)); dist,m=scene(p)
        if dist<0.02: return p,m
        t+=dist
        if t>140: break
    return None,None
def normal(p):
    e=0.05
    f=lambda q: scene(q)[0]
    return norm((f(add(p,(e,0,0)))-f(sub(p,(e,0,0))),
                 f(add(p,(0,e,0)))-f(sub(p,(0,e,0))),
                 f(add(p,(0,0,e)))-f(sub(p,(0,0,e)))))
def shadowed(p,n):
    o=add(p,mul(n,0.3)); t=0.2
    for _ in range(60):
        d,_=scene(add(o,mul(LIGHT,t)))
        if d<0.02: return True
        t+=d
        if t>40: break
    return False

def face_decal(p,n):
    return None
def _old(p,n):
    # painted on the barrel's front cap (local z ~ +6.5, normal facing +z)
    if n[2]<0.8 or p[2]<5: return None
    x,y=p[0]-BX,p[1]
    for ex in (-4.2,4.2):
        dx,dy=x-ex,y+0.5
        if dx*dx/(2.3**2)+dy*dy/(2.9**2)<=1:
            # pupils sit low and towards the middle: a scowl
            px,py=dx-(-0.9 if ex>0 else 0.9),dy+1.0
            if px*px+py*py<=1.45**2: return 'o'
            return 'w'
        # brow: a slanted bar above each eye, low at the middle
        s=-1 if ex<0 else 1
        by=3.6-0.55*s*(x-ex)  # higher at the outside
        if abs(x-ex)<=3.0 and abs(y-by)<=0.75: return 'o'
    # grimace
    if abs(y+6.2)<=0.6 and abs(x)<=3.8: return 'o'
    if abs(x)>=3.2 and abs(x)<=4.0 and -6.2<=y<=-5.0: return 'o'
    return None

def shade(p,m):
    n=normal(p)
    if m=='body':
        dec=face_decal(p,n)
        if dec: return dec
        if sd_window(p)<0.25 and p[1]<10.6: return 'o'   # inside the slot
        if p[0]<-21.0 and abs(p[2])<3.0 and 7.6<p[1]<10.6: return 'o'  # the mouth
    diff=max(0,dot(n,LIGHT))
    if shadowed(p,n): diff*=0.35
    h=norm(add(LIGHT,VIEW)); spec=max(0,dot(n,h))**40
    if m=='ring':
        return 'c' if diff>0.7 else ('b' if diff>0.3 else 's')
    if spec>0.6: return 'w'
    if diff>0.78: return 'k'
    if diff>0.2: return 'r'
    # the shadow side, with light bounced back up off the page along its
    # bottom edge -- what stops the dark half reading as a flat cut-out
    if n[1]<-0.55 and diff>0.02: return 'r'
    return 's'

S=float(sys.argv[1]) if len(sys.argv)>1 else 1.0   # world units per pixel
X0,X1,Y0,Y1=-26,22,-16,17
W=int((X1-X0)/S); H=int((Y1-Y0)/S)
g=[]; NR={}
for j in range(H):
    row=[]
    for i in range(W):
        cx=X0+(i+0.5)*S; cy=Y1-(j+0.5)*S
        p,m=trace(cx,cy)
        row.append(shade(p,m) if p else '.')
        NR[(j,i)]=(normal(p),m) if p else None
    g.append(row)
# crease lines: where the surface turns a corner (cap rim, tube onto barrel),
# drawn a step darker so the planes read as planes
for j in range(H):
    for i in range(W):
        a=NR[(j,i)]
        if not a or g[j][i] in 'o': continue
        for di,dj in ((1,0),(0,1)):
            b=NR.get((j+dj,i+di))
            if b and b[1]==a[1] and dot(a[0],b[0])<0.55:
                if g[j][i] in 'kr': g[j][i]='s'
                break
# the face, authored flat and laid on the barrel's front cap where it projects
FACE=[
"oo.......oo",
".ooo...ooo.",
"..oo...oo..",
".www...www.",
".www...www.",
".woo...oow.",
".woo...oow.",
"...........",
"...........",
"..o.....o..",
"...ooooo...",
]
c=rot((BX,-0.8,6.6))
fx=int(round((c[0]-X0)/S-0.5))-len(FACE[0])//2; fy=int(round((Y1-c[1])/S-0.5))-len(FACE)//2
for y,r in enumerate(FACE):
    for x,ch in enumerate(r):
        if ch!='.': g[fy+y][fx+x]=ch
# ink rim round the silhouette
H=len(g); W=len(g[0])
out=[r[:] for r in g]
for y in range(H):
    for x in range(W):
        if g[y][x]=='.':
            continue
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
            X,Y=x+dx,y+dy
            if not(0<=X<W and 0<=Y<H) or g[Y][X]=='.':
                out[y][x]='o'; break
rows=[''.join(r) for r in out]
while rows and set(rows[0])=={'.'}: rows.pop(0)
while rows and set(rows[-1])=={'.'}: rows.pop()
l=min(len(r)-len(r.lstrip('.')) for r in rows); rr=min(len(r)-len(r.rstrip('.')) for r in rows)
rows=[r[l:len(r)-rr] for r in rows]
if len(rows[0])%2==0: rows=[r+'.' for r in rows]
for r in rows: print('"'+r+'",')
print(len(rows[0]),'x',len(rows),file=sys.stderr)
