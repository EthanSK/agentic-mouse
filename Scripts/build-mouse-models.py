"""Author the two showcase meshes in Blender; run with blender -b -t 4 -P this_file.

Dimensions are in millimetres in the authoring code, converted to showcase units at
export. The top, side and angled manufacturer photographs guide separate profiles.
These are authored reconstructions, not scans or manufacturer CAD. Button geometry
uses printed numbers; the browser derives all actions from the native export.
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/models'
ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument('--renders')
parser.add_argument('--mouse', choices=['razer', 'corsair', 'both'], default='both')
args = parser.parse_args(ARGS)


def point(x, height, length):
    """Convert authored x/up/front-back coordinates into Blender's Z-up space."""
    return (x / 20, -length / 20, (height - 20) / 20)


def material(name, color, roughness=.55, metal=0, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metal
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = emission
    return mat


def mesh(name, vertices, faces, mat, bevel=0, solid=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata([point(*p) for p in vertices], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(data)
    bm.free()
    for face in data.polygons:
        face.use_smooth = True
    if solid:
        modifier = obj.modifiers.new('Moulded panel thickness', 'SOLIDIFY')
        modifier.thickness = solid / 20
        modifier.offset = -1
    if bevel:
        modifier = obj.modifiers.new('Manufactured edge radius', 'BEVEL')
        modifier.width = bevel / 20
        modifier.segments = 3
        modifier.limit_method = 'ANGLE'
    return obj


def cube(name, position, size, mat, bevel=.5):
    x, h, z = position
    w, d, l = size
    vertices = [(x+a*w/2, h+b*d/2, z+c*l/2) for a,b,c in
                [(-1,-1,-1), (1,-1,-1), (1,1,-1), (-1,1,-1),
                 (-1,-1,1), (1,-1,1), (1,1,1), (-1,1,1)]]
    obj = mesh(name, vertices, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)], mat, bevel)
    if bevel:  # Smooth cube normals made flat key faces look inflated; weight the large faces after the bevel.
        normal = obj.modifiers.new('Flat faces with rounded edges', 'WEIGHTED_NORMAL')
        normal.keep_sharp = True
    origin = Vector(point(*position))
    for vertex in obj.data.vertices:
        vertex.co -= origin
    obj.location = origin
    return obj


def profile(rows, z):
    """Interpolate measured profile stations without Catmull-Rom overshoot at the heel."""
    if z <= rows[0][0]:
        return rows[0][1:]
    if z >= rows[-1][0]:
        return rows[-1][1:]
    i = next(i for i in range(len(rows)-1) if rows[i][0] <= z <= rows[i+1][0])
    dz = rows[i+1][0]-rows[i][0]
    t = (z-rows[i][0])/dz
    result = []
    for k in range(1, len(rows[0])):
        slope = (rows[i+1][k]-rows[i][k])/dz
        before = (rows[i][k]-rows[max(0,i-1)][k])/(rows[i][0]-rows[max(0,i-1)][0]) if i else slope
        after = (rows[min(len(rows)-1,i+2)][k]-rows[i+1][k])/(rows[min(len(rows)-1,i+2)][0]-rows[i+1][0]) if i+2 < len(rows) else slope
        m0 = 0 if before*slope <= 0 else 2*before*slope/(before+slope)
        m1 = 0 if after*slope <= 0 else 2*after*slope/(after+slope)
        result.append((2*t**3-3*t*t+1)*rows[i][k] + (t**3-2*t*t+t)*dz*m0 + (-2*t**3+3*t*t)*rows[i+1][k] + (t**3-t*t)*dz*m1)
    if z > 48:
        end = math.sqrt(max(0.00001, 1-((z-15)/45)**2))
        anchor = math.sqrt(1-((48-15)/45)**2)
        for k in [0,1]:
            result[k] = profile(rows,48)[k]*end/anchor
    return result


def patch(name, sample, mat, nu=32, nv=72, solid=.7):
    vertices = [sample(i/nu, j/nv) for j in range(nv+1) for i in range(nu+1)]
    faces = []
    for j in range(nv):
        for i in range(nu):
            k = j*(nu+1)+i
            faces.append((k,k+1,k+nu+2,k+nu+1))
    return mesh(name, vertices, faces, mat, .15, solid)


def tube(name, points, radius, mat, cyclic=False):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 12
    curve.bevel_depth = radius/20
    curve.bevel_resolution = 2
    spline = curve.splines.new('POLY')
    spline.points.add(len(points)-1)
    for p, co in zip(spline.points, points):
        p.co = (*point(*co), 1)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def cylinder(name, center, radius, width, mat, axis='x', segments=64):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=radius/20, depth=width/20, location=point(*center))
    obj = bpy.context.object
    obj.name = name
    if axis == 'x':
        obj.rotation_euler[1] = math.pi/2
    elif axis == 'length':
        obj.rotation_euler[0] = math.pi/2
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    bevel = obj.modifiers.new('Soft moulding edge', 'BEVEL')
    bevel.width = .2/20
    bevel.segments = 2
    return obj


def text(name, value, center, size, mat, side, rotation=0):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = value
    curve.align_x = 'CENTER'
    curve.align_y = 'CENTER'
    curve.size = size/20
    curve.resolution_u = 5
    curve.extrude = 0
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.location = point(*center)
    normal = Vector((side,0,0))
    horizontal = Vector((0,side,0))
    vertical = Vector((0,0,1))
    from mathutils import Matrix
    basis = Matrix((horizontal,vertical,normal)).transposed()
    obj.rotation_euler = (basis @ __import__('mathutils').Matrix.Rotation(rotation,3,'Z')).to_euler()
    obj.data.materials.append(mat)
    return obj


def make_mouse(brand):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    razer = brand == 'razer'
    side = 1 if razer else -1
    shell = material('Graphite moulded ABS', (.021,.024,.028), .68)
    click = material('Satin click plates', (.025,.028,.032), .64)
    rubber = material('Fine rubber grip', (.012,.014,.016), .86)
    black = material('Panel seams and chassis', (.004,.005,.006), .65)
    key_mat = material('Keycaps', (.018,.020,.023), .78)
    textured = material('Textured keycaps', (.018,.020,.023), .78)
    for mat in [key_mat, textured]:  # The SE alternates texture, not silver and black keys; its coated keys need a muted dielectric reflection.
        mat.node_tree.nodes.get('Principled BSDF').inputs['Specular IOR Level'].default_value = .12
    yellow = material('Scimitar yellow insert', (.8,.65,.003), .45)
    green = material('Naga green lighting', (.012,.65,.001), .4, emission=.5)
    white = material('White markings', (.82,.85,.85), .48, emission=.12)
    accent = green if razer else yellow
    # Every station is z, left width, right width, centre height, left shoulder height, right shoulder height.
    rows = ([[-60,24,25,15,14,14],[-57,27,28,17,15,15],[-48,28,31,23,19,19],[-32,28,32,29,23,24],[-15,29,31,36,29,30],[0,30,30,41,34,35],[15,30,30,43,36,36],[30,28,28,39,32,32],[42,24,24,31,25,25],[52,18,18,23,18,18],[58,9,9,16,14,14],[60,.1,.1,11,11,11]] if razer else
            [[-60,26,26,20,18,18],[-57,29,29,21,19,19],[-45,30,31,27,24,23],[-28,31,32,34,31,28],[-10,31,34,39,36,33],[8,32,36,42,37,35],[23,33,35,40,34,32],[37,30,30,31,26,25],[48,23,23,24,21,21],[57,12,12,16,14,14],[60,.1,.1,10,10,10]])

    def top(x,z):
        left,right,h,lh,rh = profile(rows,z)
        u = x/(right if x>=0 else left)
        shoulder = rh if x>=0 else lh
        # Broad transverse crowns meet explicit shoulders; a circular cross-section incorrectly makes these mice egg-shaped.
        return h-(h-shoulder)*(abs(u)**2.6)

    def upper(u,z):
        left,right,*_ = profile(rows,z)
        x = (-left*(1-u*2)) if u<.5 else right*(u*2-1)
        return x,top(x,z),z

    if razer:
        # Naga's click fingers continue into the palm. Do not invent the Scimitar's transverse click-plate seam here.
        vertices=[upper(i/64,-60+j) for j in range(121) for i in range(65)]
        faces=[]
        for j in range(120):
            for i in range(64):
                if j<63 and i in [31,32]:continue
                k=j*65+i
                faces.append((k,k+1,k+66,k+65))
        mesh('Continuous Naga top',vertices,faces,click,.15,.7)
    else:
        for sign in [-1,1]:
            def scimitar_click(u,v,sign=sign):
                x_at_edge=30 if sign<0 else 32
                back=-20+8*u**.65
                z=-60+(back+60)*v
                l,r,*_=profile(rows,z)
                inner=5.1 if z<-18 else 4.9
                x=sign*(inner+((r if sign>0 else l)-inner)*u)
                return x,top(x,z)+.1,z
            patch('Independent click plate '+str(sign),scimitar_click,click,28,54)
        def palm(u,v):
            x,h,z=upper(u,0)
            start=-19.5+8*abs(u*2-1)**.65
            z=start+(60-start)*v
            return upper(u,z)
        patch('Scimitar palm shell',palm,shell,64,100)

    # Side shells follow their own widths at the base, waist and shoulder. The Naga's finger rest is a real flare on its left side.
    flanks = {}
    for sign in [-1,1]:
        def flank(u,v,sign=sign):
            z=-59.7+119.5*v
            l,r,h,lh,rh=profile(rows,z)
            w=r if sign>0 else l
            sh=(rh if sign>0 else lh)-.9
            y=2.3+(sh-2.3)*u
            wing=(9*math.exp(-((z+2)/32)**2) if razer and sign<0 else 0)
            base=w*(.93 if sign==side else 1.0)+wing*.8
            waist=w-(4.1 if sign==side else 1.5)+wing*math.sin(math.pi*u)
            width=(base+(waist-base)*math.sin(u*math.pi))*(1-u**3)+w*u**3
            if not razer and sign == side and -56 < z < 30:
                width = min(width, 25.5 + 5.5*u**12)
            return sign*width,y,z + 8*(1-u)*math.exp(-((z+60)/10)**2)
        flanks[sign] = flank
        patch('Thumb housing' if sign==side else 'Finger-rest shell',flank,shell,36,116)
        seam=[]
        for i in range(121):
            z=-59.7+119.5*i/120
            l,r,h,lh,rh=profile(rows,z)
            seam.append((sign*(r if sign>0 else l), (rh if sign>0 else lh)-.65,z))
        tube('Upper shell separation '+str(sign),seam,.32,black)

    # Close the underside with a low perimeter lip, following the full asymmetric footprint.
    def bottom(u,v):
        z=-59.8+119.6*v
        l,r,*_=profile(rows,z)
        wing=7.2*math.exp(-((z+2)/32)**2) if razer else 0
        x=-(l+wing)*(1-2*u) if u<.5 else r*(2*u-1)
        return x,1.2,z+8*math.exp(-((z+60)/10)**2)
    patch('Underside',bottom,black,40,80,solid=1.2)

    # The opposite side has its own curved rubber pad, fitted onto the finger-rest contour.
    grip_side=-side
    def grip_point(z,h,lift=.25):
        l,r,_,lh,rh=profile(rows,z)
        w=r if grip_side>0 else l
        sh=(rh if grip_side>0 else lh)-.9
        u=(h-2.3)/(sh-2.3)
        wing=9*math.exp(-((z+2)/32)**2) if razer else 0
        base=w+wing*.8
        waist=w-1.5+wing*math.sin(math.pi*u)
        width=(base+(waist-base)*math.sin(u*math.pi))*(1-u**3)+w*u**3
        return grip_side*(width+lift),h,z
    def grip_surface(u,v):
        z=-21+63*v
        low=4
        high=low+(16 if razer else 23)*math.sin(math.pi*v)**.6
        return grip_point(z,low+(high-low)*u)
    patch('Curved rubber finger grip',grip_surface,rubber,20,64,solid=.5)
    for row in range(10):
        for col in range(29):
            z=-19+col*2.05+(row%2)*1.025
            h=5+row*1.7
            cap=4+(16 if razer else 23)*math.sin(math.pi*(z+21)/63)**.6
            if h>cap-1:continue
            points=[grip_point(z+math.cos(a*math.tau/6)*.85,h+math.sin(a*math.tau/6)*.85,.31) for a in range(6)]
            tube('Hexagonal rubber texture',points,.10,black,True)

    # Nose panels and ports are set below the front click lips, never sealed with an ellipsoid cap.
    nose_height=14 if razer else 19
    nose=lambda h: -52.4-(h-3)*7.2/(nose_height-3)
    patch('Sloping front fascia',lambda u,v: ((u-.5)*51,3+(nose_height-3)*v,-52.4-7.2*v),black,30,16,solid=1)
    if razer:
        for sign in [-1,1]:
            patch('Front grille '+str(sign),lambda u,v,sign=sign: (sign*15+(u-.5)*19,4+8*v,nose(4+8*v)-.15),rubber,16,10,solid=.3)
            for row in range(5):
                for col in range(9):
                    x=sign*15+(col-4)*1.85+(row%2)*.8
                    h=4.8+row*1.6
                    vertices=[(x+math.cos(a*math.tau/6)*.55,h+math.sin(a*math.tau/6)*.55,nose(h+math.sin(a*math.tau/6)*.55)-.25) for a in range(6)]
                    mesh('Honeycomb vent',vertices,[(0,1,2,3,4,5)],black)
        cablepts=[(14*t*t,6-4*t*t,-58-35*t+9*t*t) for t in (i/50 for i in range(51))]  # A straight cable read as a broken rod; let the braid leave the strain relief in a relaxed curve.
        tube('Braided cable',cablepts,1.35,rubber)
        cylinder('Cable strain relief',(0,6,-58.5),2.4,9,black,'length')
        for i in range(5):
            cylinder('Cable boot rib',(0,6,-55-i*1.8),2.65,.8,rubber,'length')
    else:
        cube('USB-C recess',(0,10,-56.2),(10,4.8,.8),black,1.8)
        cube('USB-C inner tongue',(0,10,-56.5),(7,.7,.3),key_mat,.2)

    # Match the photographed side panel: Naga's individual sockets, Scimitar's entire yellow Key Slider bezel.
    centers=[]
    if razer:
        cols=[-14,-3.6,6.8,17.2]
        key_w,key_h=8.2,9.0
        for col,z in enumerate(cols):
            for row in range(3):
                y=29.4-row*9.8-(abs(col-1.5)*.42)
                centers.append((col*3+row+1,z+row*2.0,y,col))
    else:
        cols=[-23,-10,3,16]
        key_w,key_h=11.4,7.5
        for col,z in enumerate(cols):
            for row in range(3):
                y=19+(26.2-row*9.2+col*1.0-19)*.9  # The outer rows crossed the yellow rim in the side view; keep the complete key grid inside its recessed well.
                centers.append((col*3+(3-row),z+row*1.0,y,col))
        # Build the SE insert as a hollow housing with a recessed well and a rolled edge, not a single yellow sheet.
        outline=[(-37,3),(-38,28),(-29,33),(-10,36),(14,37),(24,34),(28,27),(30,12),(28,5),(21,2)]
        def rounded(points):
            result=[]
            for i,b in enumerate(points):
                a=points[i-1]; c=points[(i+1)%len(points)]
                incoming=tuple(b[k]+(a[k]-b[k])*.16 for k in range(2))
                outgoing=tuple(b[k]+(c[k]-b[k])*.16 for k in range(2))
                for j in range(7):
                    t=j/6
                    result.append(tuple((1-t)**2*incoming[k]+2*t*(1-t)*b[k]+t*t*outgoing[k] for k in range(2)))
            return result
        outer=[(z,min(h,profile(rows,z)[3]-1.2)) for z,h in rounded(outline)]
        inner=[(-4+(z+4)*.94,19+(h-19)*.91) for z,h in outer]
        n=len(outer)
        loops=[[(x,h,z) for z,h in shape] for x,shape in [(-26,outer),(-33.0,outer),(-33.2,inner),(-30.7,inner)]]
        vertices=sum(loops,[])
        faces=[]
        for layer in range(3):
            for i in range(n):
                j=(i+1)%n
                faces.append((layer*n+i,layer*n+j,(layer+1)*n+j,(layer+1)*n+i))
        mesh('Solid yellow Key Slider housing',vertices,faces,yellow,.35,.4)
        mesh('Recessed keypad backing',loops[3],[tuple(range(n))],black,.25,1)
        front=[(z,min(h,profile(rows,z)[3]-1.2)) for z,h in rounded([(-53,3),(-59,17),(-48,24),(-36,28),(-35,3)])]
        vertices=[(x,h,z) for x in [-32.8,-25] for z,h in front]
        n=len(front)
        faces=[tuple(range(n)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        mesh('Textured yellow front insert',vertices,faces,yellow,.35)
        text('Scimitar side engraving','// S C I M I T A R',(-33.12,19.3,-45),1.5,black,side,0)
        for row in range(8):
            for col in range(7):
                z=-51+col*2+(row%2)
                h=4+row*1.7
                tube('Yellow insert engraving',[(-33.1,h+.4,z-.4),(-33.1,h,z),(-33.1,h+.4,z+.4)],.09,black)

    for number,z,y,col in centers:
        x=side*32.3
        if razer:  # A planar grid floated away from the curved Naga flank; seat each socket into its own local surface.
            shoulder=profile(rows,z)[4]-.9
            x=flanks[side]((y-2.3)/(shoulder-2.3),(z+59.7)/119.5)[0]-side*.4
        existing = set(bpy.context.scene.objects)
        # Key faces tilt with the thumb housing and have separate black sockets, chamfers and alternating Scimitar textures.
        socket=cube('Socket '+str(number),(x-side*.7,y,z),(2.0,key_h+1.4,key_w+1.3),black,1.2)
        key=cube('button_'+str(number),(x+side*.7,y,z),(2.5,key_h,key_w),key_mat if razer or col%2==0 else textured,.65)
        key['printed']=number
        label=text('number_'+str(number),str(number),(x+side*(2.01 if razer else 2.14),y,z),3.8 if razer else 5,green if razer else white,side,-math.pi/2 if razer else 0)
        if not razer and col%2==1:
            for r in range(10):
                for c in range(13):
                    zz=z+(c-6)*.75
                    yy=y+(r-4.5)*.75
                    # The manufacturer SE hero photograph shows alternating triangular texture; keep it fine enough to read as moulding, not corrosion.
                    tube('Key texture',[(x+side*2.04,yy-.19,zz-.22),(x+side*2.08,yy+.19,zz),(x+side*2.04,yy-.19,zz+.22)],.055,textured)

        assembly = bpy.data.objects.new('Key assembly '+str(number), None)
        bpy.context.collection.objects.link(assembly)
        assembly.location = point(x,y,z)
        assembly['button'] = number
        bpy.context.view_layer.update()
        for obj in set(bpy.context.scene.objects)-existing-{assembly}:
            world = obj.matrix_world.copy()
            obj.parent = assembly
            obj.matrix_world = world
        assembly.rotation_euler[0] = -.20 if razer else -.10
        assembly.rotation_euler[1] = side*.13 if razer else -side*.13

    if razer:
        for sign in [-1,1]:
            line=[]
            for i in range(90):
                z=-57+75*i/89
                x=sign*(24.4+1.8*math.sin(i/89*math.pi))
                line.append((x,top(x,z)+.08,z))
            tube('Naga curved click-plate parting line',line,.23,black)
        patch('Naga centre spine',lambda u,v: ((u-.5)*(10.5 if v<.6 else 6.8),top((u-.5)*(10.5 if v<.6 else 6.8),-59+61*v)+.13,-59+61*v),shell,12,72,solid=.3)
        for sign in [-1,1]:
            x=sign*8.5
            z=-33.5
            points=[(x+sign*.8,top(x+sign*.8,z-1)+.15,z-1),(x,top(x,z)+.15,z),(x+sign*.8,top(x+sign*.8,z+1)+.15,z+1)]
            tube('Wheel tilt marking',points,.17,black)

    # A central recessed spine leaves the wheel genuinely above the shell, with the speech control immediately behind it.
    wheel_z=-34 if razer else -35
    wheel_y=top(0,wheel_z)-4.4
    cavity=cube('Wheel cavity',(0,wheel_y+2,wheel_z),(9.8,1.2,22),black,1.5)
    cavity.rotation_euler[0]=-math.atan((top(0,wheel_z+.1)-top(0,wheel_z-.1))/.2)
    cylinder('Wheel rubber',(0,wheel_y,wheel_z),10.0 if razer else 10.4,6.4,rubber)
    for x in [-3.5,3.5]:
        cylinder('Wheel illuminated side' if razer else 'Yellow wheel hub',(x,wheel_y,wheel_z),9.3,.5,accent)
        if razer:
            cylinder('Wheel dark hub',(x+math.copysign(.3,x),wheel_y,wheel_z),8.45,.22,rubber)
    for row in range(72):
        a=row*math.tau/72
        for col in range(5):
            x=(col-2)*1.18
            radius=10.12 if razer else 10.52
            h=wheel_y+math.sin(a)*radius
            z=wheel_z+math.cos(a)*radius
            cylinder_obj=cube('Wheel tread',(x,h,z),(.75,.22,.55),rubber,.08)
            cylinder_obj.rotation_euler[0]=-a
    if razer:
        for z in [-18,-8]:
            h=top(0,z)+.15
            recess=cube('Top control recess '+str(z),(0,h-.15,z),(6.5,.7,10.6),black,1.2)
            recess.rotation_euler[0]=-math.atan((top(0,z+.1)-top(0,z-.1))/.2)
            button=cube('speech' if z==-8 else 'top_secondary',(0,h+.55,z),(5.4,1.2,9.2),key_mat,.7)
            button.rotation_euler[0]=recess.rotation_euler[0]
            button['speech']=z==-8
    else:
        patch('Central control spine',lambda u,v: ((u-.5)*9.7,top((u-.5)*9.7,-60+54*v)-.7,-60+54*v),black,8,54,solid=.5)
        speech=cube('speech',(0,top(0,-13)+.35,-13),(7.3,1.1,12.1),key_mat,.7)
        speech.rotation_euler[0]=-math.atan((top(0,-12.9)-top(0,-13.1))/.2)
        speech['speech']=True
        indicator=cube('Status indicator',(0,top(0,-23)+.15,-23),(6.4,.35,1.8),white,.7)
        indicator.rotation_euler[0]=speech.rotation_euler[0]

    # Import the actual trademark outlines as a thin conforming inlay, rather than inventing replacement wordmarks.
    outlines=json.loads((OUT/'marks.json').read_text())[brand]
    curve=bpy.data.curves.new('Manufacturer emblem','CURVE')
    curve.dimensions='2D'
    curve.fill_mode='BOTH'
    for outline in outlines:
        spline=curve.splines.new('POLY')
        spline.points.add(len(outline)-1)
        for p,(x,y) in zip(spline.points,outline):
            p.co=((x-12)/20,-(y-12)/20,0,1)
        spline.use_cyclic_u=True
    logo=bpy.data.objects.new('Manufacturer emblem',curve)
    bpy.context.collection.objects.link(logo)
    logo.data.materials.append(green if razer else white)
    bpy.context.view_layer.objects.active=logo
    logo.select_set(True)
    bpy.ops.object.convert(target='MESH')
    logo=bpy.context.object
    bm=bmesh.new()
    bm.from_mesh(logo.data)
    bmesh.ops.triangulate(bm,faces=bm.faces[:])
    bmesh.ops.subdivide_edges(bm,edges=bm.edges[:],cuts=2,use_grid_fill=True)
    bm.to_mesh(logo.data)
    bm.free()
    scale=.77 if razer else .78
    for p in logo.data.vertices:
        x=p.co.x*20*scale
        z=-p.co.y*20*scale+34
        p.co=point(x,top(x,z)+.14,z)
    logo.select_set(False)

    # Sensor, feet and screws keep a full rotation believable without exporting private serial labels.
    cube('Optical sensor housing',(0,.55,0),(12,1.2,18),rubber,3)
    cube('Sensor lens',(0,-.15,0),(4,.3,7),material('Sensor glass',(.012,.016,.023),.12,.15),1.5)
    feet=material('PTFE feet',(.38,.39,.4),.55)
    for z,w in [(-48,37),(43,32)]:
        cube('PTFE glide',(0,.1,z),(w,.5,8),feet,3)
    for x in [-20,20]:
        cylinder('Base screw',(x,.4,28),1.65,.35,black,'up',16)

    # A small generated normal tile supplies material grain in both Blender and glTF; it is not a photo or a second shape source.
    import numpy as np
    image=bpy.data.images.new('Moulded plastic microtexture',width=256,height=256,alpha=True)
    rng=np.random.default_rng(24)
    heights=rng.random((256,256))
    dx=(np.roll(heights,1,0)-np.roll(heights,-1,0))*.15
    dy=(np.roll(heights,1,1)-np.roll(heights,-1,1))*.15
    pixels=np.ones((256,256,4),dtype=np.float32)
    pixels[:,:,0]=.5+dx
    pixels[:,:,1]=.5+dy
    pixels[:,:,2]=.99
    image.pixels.foreach_set(pixels.ravel())
    image.colorspace_settings.name='Non-Color'
    image.pack()
    for mat in [shell,click,rubber,key_mat,textured]:
        nodes=mat.node_tree.nodes
        texture=nodes.new('ShaderNodeTexImage')
        texture.image=image
        texture.extension='REPEAT'
        normal=nodes.new('ShaderNodeNormalMap')
        normal.inputs['Strength'].default_value=.3 if mat in [shell,click,key_mat] else .55
        mat.node_tree.links.new(texture.outputs['Color'],normal.inputs['Color'])
        mat.node_tree.links.new(normal.outputs['Normal'],nodes.get('Principled BSDF').inputs['Normal'])

    # Convert curves and apply bevels for reproducible glTF geometry, with every hardware key left independently pickable.
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.convert(target='MESH')
    for obj in list(bpy.context.scene.objects):
        if obj.type=='MESH':
            bpy.context.view_layer.objects.active=obj
            for mod in list(obj.modifiers):
                bpy.ops.object.modifier_apply(modifier=mod.name)
    for obj in list(bpy.context.scene.objects):
        if obj.type!='MESH':continue
        uv=obj.data.uv_layers.new(name='Material grain')
        for face in obj.data.polygons:
            dominant=max(range(3),key=lambda i:abs(face.normal[i]))
            axes=[i for i in range(3) if i!=dominant]
            for loop in face.loop_indices:
                p=obj.data.vertices[obj.data.loops[loop].vertex_index].co
                uv.data[loop].uv=(p[axes[0]]*2,p[axes[1]]*2)
    # Batch fixed parts by material; hundreds of individual grip details would otherwise overwhelm mobile draw calls.
    for assembly in [o for o in bpy.context.scene.objects if o.get('button')]:
        children=[o for o in assembly.children if o.type=='MESH']
        bpy.ops.object.select_all(action='DESELECT')
        for obj in children:obj.select_set(True)
        bpy.context.view_layer.objects.active=children[0]
        bpy.ops.object.join()
        children[0].name='Key surfaces '+str(assembly['button'])
    batches={}
    for obj in list(bpy.context.scene.objects):
        if obj.type=='MESH' and not obj.parent and not obj.get('speech'):
            name=obj.data.materials[0].name
            batches.setdefault(name,[]).append(obj)
    for name,objects in batches.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        bpy.ops.object.join()
        objects[0].name='Fixed '+name
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT/(brand+'.glb')),export_format='GLB',export_extras=True,export_yup=True,export_cameras=False,export_lights=False,export_draco_mesh_compression_enable=True,export_draco_mesh_compression_level=6)
    if args.renders:
        render_views(brand)


def render_views(brand):
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.samples=32
    scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED'
    scene.render.threads=4
    scene.render.resolution_x=1000
    scene.render.resolution_y=760
    scene.render.resolution_percentage=100
    scene.world.color=(.25,.25,.25)
    scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.32,.35,.4,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.35
    scene.view_settings.view_transform='AgX'
    ground=material('Render ground',(.31,.32,.34),.85)
    cube('Render ground',(0,-1.2,0),(200,.2,200),ground,0)
    for name,pos,power,size in [('Large key',(-5,8,-3),650,7),('Rim',(5,6,4),800,5),('Front fill',(0,4,-8),160,4)]:
        data=bpy.data.lights.new(name,'AREA')
        data.energy=power
        data.shape='DISK'
        data.size=size
        obj=bpy.data.objects.new(name,data)
        bpy.context.collection.objects.link(obj)
        obj.location=(pos[0],-pos[2],pos[1])
        obj.rotation_euler=(-obj.location).to_track_quat('-Z','Y').to_euler()
    camera_data=bpy.data.cameras.new('Comparison camera')
    camera=bpy.data.objects.new('Comparison camera',camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera=camera
    camera_data.type='ORTHO'
    camera_data.ortho_scale=8.2
    side=1 if brand=='razer' else -1
    for view,pos in [('angle',(side*7,8,-9)),('side',(side*12,2,-.5)),('top',(0,16,.01))]:
        camera.location=(pos[0],-pos[2],pos[1])
        target=Vector((0,0,0))
        camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(Path(args.renders)/(brand+'-'+view+'.png'))
        bpy.ops.render.render(write_still=True)


OUT.mkdir(exist_ok=True)
for mouse in ['corsair','razer'] if args.mouse=='both' else [args.mouse]:
    make_mouse(mouse)
