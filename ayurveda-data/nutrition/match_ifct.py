import csv,json,glob,re,sqlite3,unicodedata,collections
B='ayurveda-data/nutrition/'
rows=list(csv.DictReader(open(B+'ifct2017-compositions.csv',encoding='utf-8',errors='replace')))
C={c.split('; ')[-1]:c for c in rows[0]}
def norm(s):
    s=unicodedata.normalize('NFKD',s or '').encode('ascii','ignore').decode().lower()
    s=re.sub(r'\([^)]*\)',' ',s); s=re.sub(r'[^a-z0-9 ]',' ',s)
    STOP={'raw','the','and','of','a','an'}
    t=[w for w in s.split() if w and w not in STOP]
    return tuple(sorted(set(w[:-1] if len(w)>3 and w.endswith('s') and not w.endswith('ss') else w for w in t)))
# IFCT keys: english name + every local-language synonym
ikeys=collections.defaultdict(list)
for r in rows:
    names=[r[C['name']]]
    for part in (r[C['lang']] or '').split(';'):
        part=re.sub(r'^\s*[A-Za-z.]{1,5}\.\s*','',part.strip())
        if part: names.append(part)
    for n in names:
        k=norm(n)
        if k: ikeys[k].append(r)
dr={it['id']:it for f in glob.glob('ayurveda-data/dravyas/batch-*.json') for it in json.load(open(f))['items']}
c=sqlite3.connect('/tmp/dbw/db.store')
ph={r[0]:r[1] for r in c.execute("select ZFOODID,ZID from ZAYURVEDAPROFILE where ZKIND='dravya' and ZFOODID>=900000")}
exact,ambig,none_=[],[],[]
for fid,did in sorted(ph.items()):
    d=dr.get(did,{})
    cands={}
    for n in [d.get('name'),d.get('sanskrit')]+list(d.get('aliases') or []):
        k=norm(n)
        if k and k in ikeys:
            for r in ikeys[k]: cands[r[C['code']]]=r
    if len(cands)==1:
        r=list(cands.values())[0]; exact.append((did,d.get('name'),r[C['code']],r[C['name']]))
    elif len(cands)>1:
        ambig.append((did,d.get('name'),[(r[C['code']],r[C['name']]) for r in cands.values()]))
    else: none_.append((did,d.get('name')))
print(f"IFCT rows {len(rows)}   match keys {len(ikeys)}")
print(f"EXACT single match : {len(exact)}")
print(f"AMBIGUOUS (>1)     : {len(ambig)}")
print(f"NO MATCH           : {len(none_)}")
print("\nsample exact:")
for x in exact[:16]: print(f"   {x[1][:32]:<32} -> [{x[2]}] {x[3]}")
print("\nsample ambiguous:")
for x in ambig[:5]: print(f"   {x[1][:30]:<30} -> {[n for _,n in x[2]][:3]}")
json.dump({'exact':exact,'ambiguous':ambig,'none':none_},open('/tmp/match.json','w'),indent=1,ensure_ascii=False)
