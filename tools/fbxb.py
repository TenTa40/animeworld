import struct, zlib
import numpy as np
class Node:
    def __init__(s,name): s.name=name; s.props=[]; s.children=[]
    def find(s,n): return [c for c in s.children if c.name==n]
def parse(path):
    b=open(path,'rb').read()
    ver=struct.unpack('<I',b[23:27])[0]; big=ver>=7500
    pos=27
    def rec(pos):
        if big: end,np_,pl,nl=struct.unpack('<QQQB',b[pos:pos+25]); pos+=25
        else: end,np_,pl,nl=struct.unpack('<IIIB',b[pos:pos+13]); pos+=13
        if end==0: return None,pos
        n=Node(b[pos:pos+nl].decode('latin1')); pos+=nl
        for _ in range(np_):
            t=chr(b[pos]); pos+=1
            if t in 'YCFDLIfdlib' and t in 'YCFDLI':
                fmt={'Y':'<h','C':'<B','I':'<i','F':'<f','D':'<d','L':'<q'}[t]
                sz=struct.calcsize(fmt); n.props.append(struct.unpack(fmt,b[pos:pos+sz])[0]); pos+=sz
            elif t in 'fdlib':
                cnt,enc,cl=struct.unpack('<III',b[pos:pos+12]); pos+=12
                raw=b[pos:pos+cl]; pos+=cl
                if enc==1: raw=zlib.decompress(raw)
                dt={'f':'<f4','d':'<f8','l':'<i8','i':'<i4','b':'u1'}[t]
                n.props.append(np.frombuffer(raw,dtype=dt,count=cnt))
            elif t in 'SR':
                l=struct.unpack('<I',b[pos:pos+4])[0]; pos+=4
                raw=b[pos:pos+l]; pos+=l
                n.props.append(raw.decode('latin1') if t=='S' else raw)
        while pos<end:
            c,pos=rec(pos)
            if c is None: break
            n.children.append(c)
        return n,end
    root=Node('root')
    while pos<len(b)-100:
        n,pos2=rec(pos)
        if n is None: break
        root.children.append(n); pos=pos2
    return root
