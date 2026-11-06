"""把本项目已确认的即梦绿幕片转成离线透明 WebM；不生成或重绘角色。"""
import argparse, json, subprocess
from pathlib import Path
import cv2
import numpy as np
from scipy.ndimage import binary_fill_holes

parser=argparse.ArgumentParser()
parser.add_argument('source',type=Path)
parser.add_argument('output',type=Path)
parser.add_argument('--size',type=int,default=1080)
parser.add_argument('--title',default='咕咕嘎嘎桌面提醒 · 透明背景')
args=parser.parse_args()
ffmpeg='/opt/homebrew/bin/ffmpeg'
args.output.parent.mkdir(parents=True,exist_ok=True)
# Both supplied films contain 24 unique frames/sec in a variable-rate container.
decoder=subprocess.Popen([ffmpeg,'-v','error','-i',str(args.source),'-vf',f'fps=24,scale={args.size}:{args.size}:flags=lanczos','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
encoder=subprocess.Popen([ffmpeg,'-v','error','-y','-f','rawvideo','-pix_fmt','rgba','-s',f'{args.size}x{args.size}','-r','24','-i','-','-an','-c:v','libvpx-vp9','-pix_fmt','yuva420p','-auto-alt-ref','0','-b:v','0','-crf','20','-deadline','good','-cpu-used','3','-row-mt','1','-metadata',f'title={args.title}',str(args.output)],stdin=subprocess.PIPE)
size=args.size; frame_bytes=size*size*3; count=0; first=None; last=None; stats=[]
while True:
 raw=decoder.stdout.read(frame_bytes)
 if not raw:break
 if len(raw)!=frame_bytes:raise RuntimeError('视频帧不完整')
 rgb=np.frombuffer(raw,np.uint8).reshape(size,size,3).astype(np.float32)
 r,g,b=rgb.transpose(2,0,1)
 # Normalized green dominance handles the source's gradients and floor shadow,
 # while cyan (G≈B), warm skin, yellow feet and neutral plush remain opaque.
 dominance=np.minimum(g-r,g-b)/np.maximum(g,1)
 a=np.clip((.18-dominance)/.13,0,1);a=a*a*(3-2*a)
 # Remove disconnected green floor residue; fill dark-fur compression pinholes.
 n,labels,components,_=cv2.connectedComponentsWithStats((a>.1).astype(np.uint8),8)
 if n>1:
  largest=1+np.argmax(components[1:,cv2.CC_STAT_AREA])
  keep=cv2.dilate((labels==largest).astype(np.uint8),np.ones((3,3),np.uint8));a*=keep
 a[binary_fill_holes(a>.95)]=1
 spill=np.maximum(0,g-np.maximum(r,b));rgb[:,:,1]-=spill*(1-a)*.95
 # The supplied close-up is cropped at the lower body: soften that source edge.
 edge=np.minimum(1,np.arange(size-1,-1,-1,dtype=np.float32)/(size*.065))
 edge=edge*edge*(3-2*edge);a*=edge[:,None]
 rgba=np.dstack([np.clip(rgb,0,255).astype(np.uint8),np.round(a*255).astype(np.uint8)])
 encoder.stdin.write(rgba.tobytes());count+=1
 if first is None:first=rgba.copy()
 last=rgba.copy()
 stats.append({'frame':count,'transparent':int(np.count_nonzero(rgba[:,:,3]==0)),'opaque':int(np.count_nonzero(rgba[:,:,3]==255)),'cornerAlpha':rgba[[0,0,-1,-1],[0,-1,0,-1],3].tolist()})
 if count%24==0:print(f'已处理 {count//24} 秒',flush=True)
encoder.stdin.close();decoder.stdout.close()
if decoder.wait() or encoder.wait():raise RuntimeError('FFmpeg 转码失败')
for name,rgba in [('poster',first),('hold',last)]:
 cv2.imwrite(str(args.output.with_name(args.output.stem+'-'+name+'.png')),cv2.cvtColor(rgba,cv2.COLOR_RGBA2BGRA))
report={'source':str(args.source),'output':str(args.output),'frames':count,'fps':24,'size':size,'audio':'muted','alphaCheck':{'allCornersTransparent':all(max(x['cornerAlpha'])==0 for x in stats),'minOpaquePixels':min(x['opaque'] for x in stats)},'framesCheck':stats}
args.output.with_suffix('.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({k:v for k,v in report.items() if k!='framesCheck'},ensure_ascii=False),flush=True)
