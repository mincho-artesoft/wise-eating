import json, re, glob, sqlite3, unicodedata, collections, sys
STOP={'raw','fresh','dried','whole','ground','powder','seed','seeds','the','and','of','in','with',
      'nfs','cooked','boiled','indian','common','edible','a','or'}
def toks(s):
    s=unicodedata.normalize('NFKD',s or '').encode('ascii','ignore').decode().lower()
    s=re.sub(r'\([^)]*\)',' ',s); s=re.sub(r'[^a-z0-9 ]',' ',s)
    t=[w for w in s.split() if w and w not in STOP]
    return set(w[:-1] if len(w)>3 and w.endswith('s') and not w.endswith('ss') else w for w in t)
foods=json.load(open('Ayura/Legacy/foods.json'))
idx=collections.defaultdict(list)
ftok={}
for f in foods:
    t=toks(f['name']); ftok[f['id']]=t
    for w in t: idx[w].append(f['id'])
byid={f['id']:f for f in foods}
dr={it['id']:it for p in glob.glob('ayurveda-data/dravyas/batch-*.json') for it in json.load(open(p))['items']}
c=sqlite3.connect('/tmp/dbw/db.store')
ph={r[0]:r[1] for r in c.execute("select ZFOODID,ZID from ZAYURVEDAPROFILE where ZKIND='dravya' and ZFOODID>=900000")}
out={}
for fid,did in ph.items():
    d=dr.get(did,{})
    best=(0.0,None)
    cand=collections.Counter()
    names=[d.get('name'),d.get('sanskrit')]+list(d.get('aliases') or [])
    for n in names:
        for w in toks(n):
            for x in idx.get(w,[]): cand[x]+=1
    for x,_ in cand.most_common(400):
        for n in names:
            a=toks(n); b=ftok[x]
            if not a or not b: continue
            j=len(a&b)/len(a|b)
            cov=len(a&b)/len(a)
            score=j*0.5+cov*0.5
            if score>best[0]: best=(score,x)
    if best[1] and best[0]>=0.60:
        out[did]={'fdcId':best[1],'name':byid[best[1]]['name'],'score':round(best[0],3)}
json.dump(out,open('/tmp/analogues.json','w'),indent=1,ensure_ascii=False)
print(f"analogue found for {len(out)} of {len(ph)}  (threshold 0.60)")
for d,v in sorted(out.items())[:14]:
    print(f"   {dr[d]['name'][:34]:<34} -> {v['name'][:44]:<44} {v['score']}")
