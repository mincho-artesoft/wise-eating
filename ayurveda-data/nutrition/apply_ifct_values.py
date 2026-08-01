import csv,json
B='ayurveda-data/nutrition/'
rows=list(csv.DictReader(open(B+'ifct2017-compositions.csv',encoding='utf-8',errors='replace')))
C={c.split('; ')[-1]:c for c in rows[0]}
byc={r[C['code']]:r for r in rows}
G=1000.0; U=1000000.0            # IFCT stores every nutrient as g/100g
MAP={
 'macronutrients':{'carbohydrates':('choavldf',1),'protein':('protcnt',1),'fat':('fatce',1),
                   'fiber':('fibtg',1),'totalSugars':('fsugar',1)},
 'other':{'water':('water',1),'ash':('ash',1),'cholesterol':('cholc',G)},
 'minerals':{'calcium':('ca',G),'iron':('fe',G),'magnesium':('mg',G),'phosphorus':('p',G),
             'potassium':('k',G),'sodium':('na',G),'zinc':('zn',G),'copper':('cu',G),
             'manganese':('mn',G),'selenium':('se',U)},
 'vitamins':{'vitaminC':('vitc',G),'vitaminE':('vite',G),'vitaminB1_Thiamin':('thia',G),
             'vitaminB2_Riboflavin':('ribf',G),'vitaminB3_Niacin':('nia',G),
             'vitaminB5_PantothenicAcid':('pantac',G),'vitaminB6':('vitb6c',G),
             'folateTotal':('folsum',U),'vitaminK':('vitk',U),'vitaminA_RAE':('vita',U),
             'retinol':('retol',U),'caroteneBeta':('cartb',U),'caroteneAlpha':('carta',U),
             'cryptoxanthinBeta':('crypxb',U),'lycopene':('lycpn',U),'luteinZeaxanthin':('lutn',U)},
 'carbDetails':{'starch':('starch',1),'sucrose':('sucs',1),'glucose':('glus',1),
                'fructose':('frus',1),'maltose':('mals',1),'lactose':('lactose',1)},
 'sterols':{'phytosterols':('phystr',G),'campesterol':('camt',G),'stigmasterol':('stgstr',G),
            'betaSitosterol':('stostrb',G)},
 'aminoAcids':{'histidine':('his',1),'isoleucine':('ile',1),'leucine':('leu',1),'lysine':('lys',1),
   'methionine':('met',1),'cystine':('cys',1),'phenylalanine':('phe',1),'threonine':('thr',1),
   'tryptophan':('trp',1),'valine':('val',1),'alanine':('ala',1),'arginine':('arg',1),
   'asparticAcid':('asp',1),'glutamicAcid':('glu',1),'glycine':('gly',1),'proline':('pro',1),
   'serine':('ser',1),'tyrosine':('tyr',1)},
 'lipids':{'totalSaturated':('fasat',1),'totalMonounsaturated':('fams',1),
           'totalPolyunsaturated':('fapu',1),'totalTrans':('fatrn',1)},
}
def num(r,k):
    v=(r.get(C.get(k,''),'') or '').strip()
    try: return float(v)
    except: return None
m=json.load(open('/tmp/match.json'))
exact={x[0]:(x[2],x[3]) for x in m['exact']}
foods=json.load(open(B+'dravya_foods.json'))
n=0
for rec in foods:
    hit=exact.get(rec['dravyaId'])
    if not hit: continue
    code,iname=hit; r=byc[code]; n+=1
    for grp,fields in MAP.items():
        for our,(ifct,mult) in fields.items():
            if our not in rec.get(grp,{}): continue
            v=num(r,ifct)
            if v is not None: rec[grp][our]['value']=round(v*mult,4)
    e=num(r,'enerc')
    if e is not None and 'energyKcal' in rec['other']:
        rec['other']['energyKcal']['value']=round(e/4.184,1)
    rec['_review']={'source':f'IFCT 2017 [{code}] {iname}',
        'spread':f"regions sampled: {r[C['regn']]}; each nutrient has a published SD in the _e column of ifct2017-compositions.csv",
        'status':'measured — IFCT 2017, verify the name match',
        'ifctCode':code,'ifctName':iname,
        'currentMinAgeMonths':rec['_review'].get('currentMinAgeMonths'),
        'proposedMinAgeMonths':rec['_review'].get('proposedMinAgeMonths'),
        'ageReason':rec['_review'].get('ageReason')}
json.dump(foods,open(B+'dravya_foods.json','w'),indent=1,ensure_ascii=False)
json.dump({'ambiguous':m['ambiguous'],'unmatched':m['none']},
          open(B+'ifct-unresolved.json','w'),indent=1,ensure_ascii=False)
print(f"filled {n} foods from IFCT 2017 measured values")
srcd=sum(1 for f in foods if f['_review'].get('source'))
print(f"total with nutrition now: {srcd} of {len(foods)}")
