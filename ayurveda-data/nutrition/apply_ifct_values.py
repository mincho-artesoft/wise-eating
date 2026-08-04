import argparse
import collections
import csv
import json
import sys
from pathlib import Path

from phase2_rulings import (
    AMBIGUOUS_BINDINGS,
    AMBIGUOUS_DEFERRALS,
    AMBIGUOUS_MATCH_STATUS,
    DIRECT_BINDINGS,
    DIRECT_DECLINES,
    DIRECT_MATCH_STATUS,
    F016_WITHDRAWAL_STATUS,
    LATE_WITHDRAWALS,
    PUBLISHED_LITERATURE,
)
B='ayurveda-data/nutrition/'
WITHDRAWN_STATUS='withdrawn — wrong IFCT row, see TASK-NUT1 §2'
WITHDRAWN={
 'dravya.petha-murabba':('D001','Ash gourd'),
 'dravya.kanda-poha':('A011','Rice flakes'),
 'dravya.foxtail-millet':('A017','Varagu'),
 'dravya.elephant-apple':('E067','Wood Apple'),
 'dravya.mosambi-juice':('E034','Lime, sweet, pulp'),
 'dravya.chickpea-white':('B002','Bengal gram, whole'),
}
WITHDRAWN.update(LATE_WITHDRAWALS)
REVIEWED_COLLISIONS={
 'dravya.ash-gourd-juice-flesh':{
   'ifctCode':'D001','status':'reviewed — identical by construction',
   'note':'Two raw ash-gourd cuts share the same measured base row.'},
 'dravya.ash-gourd-strips':{
   'ifctCode':'D001','status':'reviewed — identical by construction',
   'note':'Two raw ash-gourd cuts share the same measured base row.'},
}
rows=list(csv.DictReader(open(B+'ifct2017-compositions.csv',encoding='utf-8',errors='replace')))
C={c.split('; ')[-1]:c for c in rows[0]}
byc={r[C['code']]:r for r in rows}
G=1000.0; U=1000000.0            # IFCT stores every nutrient as g/100g
# IFCT header labels are not reliable. Verify every new mapping against the
# data, never against the header:
#   `glu`   is labelled "Glucose" but is glutamic acid in the amino-acid
#           block. Free glucose is the separate `glus` column.
#   `amiac` is labelled "Essential Amino acids" but equals essential +
#           conditionally essential + non-essential amino acids.
MAP={
 'macronutrients':{'carbohydrates':('choavldf',1),'protein':('protcnt',1),'fat':('fatce',1),
                   'fiber':('fibtg',1),'totalSugars':('fsugar',1),
                   'insolubleFiber':('fibins',1),'solubleFiber':('fibsol',1)},
 'other':{'water':('water',1),'ash':('ash',1),'cholesterol':('cholc',G)},
 'vitamins':{'vitaminC':('vitc',G),'vitaminE':('vite',G),'vitaminB1_Thiamin':('thia',G),
             'vitaminB2_Riboflavin':('ribf',G),'vitaminB3_Niacin':('nia',G),
             'vitaminB5_PantothenicAcid':('pantac',G),'vitaminB6':('vitb6c',G),
             'folateTotal':('folsum',U),'vitaminK':('vitk',U),'vitaminA_RAE':('vita',U),
             'retinol':('retol',U),'caroteneBeta':('cartb',U),'caroteneAlpha':('carta',U),
             'cryptoxanthinBeta':('crypxb',U),'lycopene':('lycpn',U),'luteinZeaxanthin':('lutn',U),
             'vitaminD':('vitd',U),'biotin':('biot',U),'vitaminD2':('ergcal',U),
             'vitaminD3':('chocal',U),'vitaminD3_25Hydroxy':('doh25',U),
             'vitaminK1':('vitk1',U),'vitaminK2':('vitk2',U)},
 'carbDetails':{'starch':('starch',1),'sucrose':('sucs',1),'glucose':('glus',1),
                'fructose':('frus',1),'maltose':('mals',1),'lactose':('lactose',1),
                'availableCarbohydratesBySummation':('cho',1)},
 'sterols':{'phytosterols':('phystr',G),'campesterol':('camt',G),'stigmasterol':('stgstr',G),
            'betaSitosterol':('stostrb',G)},
 'aminoAcids':{'histidine':('his',1),'isoleucine':('ile',1),'leucine':('leu',1),'lysine':('lys',1),
   'methionine':('met',1),'cystine':('cys',1),'phenylalanine':('phe',1),'threonine':('thr',1),
   'tryptophan':('trp',1),'valine':('val',1),'alanine':('ala',1),'arginine':('arg',1),
   'asparticAcid':('asp',1),'glutamicAcid':('glu',1),'glycine':('gly',1),'proline':('pro',1),
   'serine':('ser',1),'tyrosine':('tyr',1)},
 'lipids':{'totalSaturated':('fasat',1),'totalMonounsaturated':('fams',1),
   'totalPolyunsaturated':('fapu',1),'totalTrans':('fatrn',1),
   'totalUnsaturated':('fauns',1),'totalEssentialFattyAcids':('faess',1),
   'totalCisFattyAcids':('facis',1),'totalCisOmega3':('facn3',1),
   'totalCisOmega6':('facn6',1),'totalCisOmega9':('facn9',1),
   'totalCisOmega5':('facn5',1),'totalCisOmega7':('facn7',1),
   'sfa4_0':('f4d0',1),'sfa6_0':('f6d0',1),'sfa8_0':('f8d0',1),
   'sfa10_0':('f10d0',1),'sfa12_0':('f12d0',1),'sfa14_0':('f14d0',1),
   'sfa15_0':('f15d0',1),'sfa16_0':('f16d0',1),'sfa18_0':('f18d0',1),
   'sfa20_0':('f20d0',1),'sfa22_0':('f22d0',1),'sfa24_0':('f24d0',1),
   'mufa14_1':('f14d1cn5',1),'mufa16_1':('f16d1cn7',1),
   'mufa18_1':('f18d1cn9',1),'mufa20_1':('f20d1cn9',1),
   'mufa22_1':('f22d1cn9',1),'mufa24_1':('f24d1cn9',1),
   'tfa18_1_t':('f18d1tn9',1),
   'pufa18_2':('f18d2cn6',1),'pufa18_3':('f18d3n3',1),
   'pufa20_2':('f20d2n6',1),'pufa20_3':('f20d3n6',1),
   'pufa20_4':('f20d4n6',1),'pufa20_5':('f20d5n3',1),
   'pufa22_5':('f22d5n3',1),'pufa22_6':('f22d6n3',1),
   'sfa11_0':('f11d0',1),'pufa22_2':('f22d2n6',1)},
 'aminoAcidTotals':{'total':('amiac',1),'essential':('amiace',1),
   'conditionallyEssential':('amiacce',1),'nonEssential':('amiacne',1)},
 'carotenoids':{'total':('cartoid',U),'totalCarotenes':('carot',U),
   'totalXanthophylls':('xantp',U),'betaCaroteneEquivalents':('cartbeq',U),
   'zeaxanthin':('zea',U),'gammaCarotene':('cartg',U)},
 'polyphenols':{'total':('polyph',G)},
 'vitaminForms':{'totalTocopherols':('tocph',G),'totalTocotrienols':('toctr',G)},
 'organicAcids':{'total':('orgac',1),'cisAconiticAcid':('caconac',1),
   'citricAcid':('citac',1),'fumaricAcid':('fumac',1),'malicAcid':('malac',1),
   'quinicAcid':('quinac',1),'succinicAcid':('sucac',1),'tartaricAcid':('tarac',1)},
 'antiNutrients':{'phytate':('phytac',G),'saponins':('sapon',G)},
 'mineralTotals':{'essentialQuantity':('mnrleq',G),'essentialTrace':('mnrlet',G),
   'possiblyEssentialTrace':('mnrlpet',U),'nonEssentialTrace':('mnrlnet',U),
   'toxic':('mnrltx',U)},
 'oligosaccharides':{'total':('olsac',1),'raffinose':('rafs',1),
   'stachyose':('stas',1),'verbascose':('vers',1),'ajugose':('ajgs',1)},
 'oxalates':{'total':('oxalt',G),'soluble':('oxals',G),'insoluble':('oxali',G)},
 'minerals':{'calcium':('ca',G),'iron':('fe',G),'magnesium':('mg',G),'phosphorus':('p',G),
             'potassium':('k',G),'sodium':('na',G),'zinc':('zn',G),'copper':('cu',G),
             'manganese':('mn',G),'selenium':('se',U),'aluminium':('al',U),
             'arsenic':('as',U),'cadmium':('cd',U),'chromium':('cr',U),'cobalt':('co',U),
             'lead':('pb',U),'lithium':('li',U),'mercury':('hg',U),
             'molybdenum':('mo',U),'nickel':('ni',U)},
}
def num(r,k):
    v=(r.get(C.get(k,''),'') or '').strip()
    try: return float(v)
    except: return None


def projected_value(value, multiplier):
    """Keep the established precision unless it would erase a measurement."""
    projected = value * multiplier
    rounded_value = round(projected, 4)
    if projected != 0 and rounded_value == 0:
        return round(projected, 12)
    return rounded_value


def apply_reviewed_batch(argv):
    parser = argparse.ArgumentParser(
        description="Apply a director-reviewed IFCT decision file without rerunning matching."
    )
    parser.add_argument("--reviewed", required=True, type=Path)
    parser.add_argument("--foods", default=Path(B) / "dravya_foods.json", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    reviewed = json.loads(args.reviewed.read_text(encoding="utf-8"))
    accepted = [*reviewed.get("accept", []), *reviewed.get("accept_with_note", [])]
    if len(accepted) != 17:
        raise SystemExit(f"reviewed input must contain 17 accepts, got {len(accepted)}")
    accepted_ids = [item["dravyaId"] for item in accepted]
    if len(set(accepted_ids)) != len(accepted_ids):
        raise SystemExit("reviewed input contains a duplicate accepted dravyaId")

    foods = json.loads(args.foods.read_text(encoding="utf-8"))
    before = json.loads(json.dumps(foods, ensure_ascii=False))
    by_dravya = {row["dravyaId"]: row for row in foods}
    if len(by_dravya) != len(foods):
        raise SystemExit("dravya_foods.json contains duplicate dravyaId values")

    status_before = collections.Counter(
        row.get("_review", {}).get("status", "<missing>") for row in foods
    )
    changed_rows = []
    zero_writes = []
    invalid_zero_writes = []
    for decision in accepted:
        dravya_id = decision["dravyaId"]
        row = by_dravya.get(dravya_id)
        if row is None:
            raise SystemExit(f"reviewed target is absent from dravya_foods.json: {dravya_id}")
        code = decision["ifct"]
        ifct_row = byc.get(code)
        if ifct_row is None:
            raise SystemExit(f"reviewed IFCT code is absent: {code}")
        actual_name = ifct_row[C["name"]]
        if actual_name != decision["ifctName"]:
            raise SystemExit(
                f"{dravya_id}: IFCT name drift for {code}: "
                f"expected {decision['ifctName']!r}, got {actual_name!r}"
            )

        existing = [
            f"{group}.{field}"
            for group, fields in MAP.items()
            for field in fields
            if field in row.get(group, {})
            and row[group][field].get("value") is not None
        ]
        if existing:
            raise SystemExit(
                f"{dravya_id}: refusing to replace existing values: {existing[:8]}"
            )

        populated = 0
        for group, fields in MAP.items():
            for field, (ifct_field, multiplier) in fields.items():
                if field not in row.get(group, {}):
                    continue
                value = num(ifct_row, ifct_field)
                if value is None:
                    continue
                projected = projected_value(value, multiplier)
                row[group][field]["value"] = projected
                populated += 1
                if projected == 0:
                    trace = f"{dravya_id}:{group}.{field}<-{ifct_field}"
                    zero_writes.append(trace)
                    if value != 0:
                        invalid_zero_writes.append(f"{trace} (source={value})")
        energy = num(ifct_row, "enerc")
        if energy is not None and "energyKcal" in row.get("other", {}):
            projected_energy = round(energy / 4.184, 1)
            row["other"]["energyKcal"]["value"] = projected_energy
            populated += 1
            if projected_energy == 0:
                trace = f"{dravya_id}:other.energyKcal<-enerc"
                zero_writes.append(trace)
                if energy != 0:
                    invalid_zero_writes.append(f"{trace} (source={energy})")
        if populated == 0:
            raise SystemExit(f"{dravya_id}: reviewed IFCT row populated no values")

        previous_review = row.get("_review", {})
        review = {
            "source": (
                f"IFCT 2017 [{code}] {decision['ifctName']}; "
                f"director-reviewed identity: {decision['why']}"
            ),
            "spread": (
                f"regions sampled: {ifct_row[C['regn']]}; each nutrient has a "
                "published SD in the _e column of ifct2017-compositions.csv"
            ),
            "status": "measured — IFCT 2017, director-reviewed NUT5 batch 1",
            "provenance": "IFCT 2017",
            "ifctCode": code,
            "ifctName": decision["ifctName"],
            "currentMinAgeMonths": previous_review.get("currentMinAgeMonths"),
            "proposedMinAgeMonths": previous_review.get("proposedMinAgeMonths"),
            "ageReason": previous_review.get("ageReason"),
        }
        if "note" in decision:
            review["note"] = decision["note"]
        row["_review"] = review
        changed_rows.append((dravya_id, code, populated))

    changed_ids = {
        after["dravyaId"]
        for old, after in zip(before, foods, strict=True)
        if old != after
    }
    if changed_ids != set(accepted_ids):
        raise SystemExit(
            "reviewed apply changed the wrong rows: "
            f"expected={sorted(accepted_ids)}, actual={sorted(changed_ids)}"
        )
    if invalid_zero_writes:
        raise SystemExit(
            "reviewed apply wrote zero from a nonzero source: "
            f"{invalid_zero_writes}"
        )

    status_after = collections.Counter(
        row.get("_review", {}).get("status", "<missing>") for row in foods
    )
    print("reviewed IFCT accepts")
    for dravya_id, code, populated in changed_rows:
        print(f"{dravya_id}|{code}|{populated}")
    print("status histogram before:", json.dumps(status_before, ensure_ascii=False, sort_keys=True))
    print("status histogram after:", json.dumps(status_after, ensure_ascii=False, sort_keys=True))
    print(f"literal-source zero writes: {len(zero_writes)}")
    if not args.dry_run:
        args.foods.write_text(
            json.dumps(foods, indent=1, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {args.foods}")


if __name__ == "__main__" and ("--reviewed" in sys.argv or "--help" in sys.argv):
    apply_reviewed_batch(sys.argv[1:])
    raise SystemExit(0)


m=json.load(open('/tmp/match.json'))
exact={x[0]:(x[2],x[3]) for x in m['exact']}
resolved_ambiguous={x[0]:x for x in m.get('resolvedAmbiguous',[])}
remaining_ambiguous={x[0]:x for x in m['ambiguous']}
foods=json.load(open(B+'dravya_foods.json'))
n=0
for rec in foods:
    if rec['dravyaId'] in WITHDRAWN: continue
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
    if rec['dravyaId'] in DIRECT_BINDINGS:
        rec['_review']['status']=DIRECT_MATCH_STATUS
        rec['_review']['provenance']='IFCT 2017'
        rec['_review']['note']='Director-reviewed ratio 1.000 identity binding; not derived.'
    if rec['dravyaId'] in AMBIGUOUS_BINDINGS:
        ruling=AMBIGUOUS_BINDINGS[rec['dravyaId']]
        original=resolved_ambiguous.get(rec['dravyaId'])
        if not original:
            raise SystemExit(f"{rec['dravyaId']}: ruled ambiguous binding was not ambiguous")
        losing=[{'ifctCode':candidate[0],'ifctName':candidate[1]}
                for candidate in original[2] if candidate[0] != code]
        rec['_review']['status']=AMBIGUOUS_MATCH_STATUS
        rec['_review']['provenance']='IFCT 2017'
        rec['_review']['manualResolution']={
            'selectedIfctCode':code,
            'selectedIfctName':iname,
            'losingCandidates':losing,
            'reason':ruling['reason']}
    if rec['dravyaId'] in REVIEWED_COLLISIONS:
        rec['_review']['reverseCollision']=REVIEWED_COLLISIONS[rec['dravyaId']]

for rec in foods:
    literature=PUBLISHED_LITERATURE.get(rec['dravyaId'])
    if not literature: continue
    for grp,fields in literature['values'].items():
        for field,value in fields.items():
            if field not in rec.get(grp,{}):
                raise SystemExit(f"{rec['dravyaId']}: literature field {grp}.{field} is absent")
            rec[grp][field]['value']=value
    previous=rec['_review']
    rec['_review']={
        'source':literature['source'],
        'spread':literature['spread'],
        'status':'measured — published literature, TASK-NUT1 Phase 2b',
        'provenance':'published-literature',
        'note':literature['note'],
        'currentMinAgeMonths':previous.get('currentMinAgeMonths'),
        'proposedMinAgeMonths':previous.get('proposedMinAgeMonths'),
        'ageReason':previous.get('ageReason')}

for rec in foods:
    decline=DIRECT_DECLINES.get(rec['dravyaId'])
    if not decline: continue
    previous=rec['_review']
    rec['_review']={
        'source':None,
        'spread':None,
        'status':'declined — direct IFCT binding, TASK-NUT1 Phase 2b',
        'declinedIfctCode':decline['ifctCode'],
        'declinedIfctName':decline['ifctName'],
        'reason':decline['reason'],
        'currentMinAgeMonths':previous.get('currentMinAgeMonths'),
        'proposedMinAgeMonths':previous.get('proposedMinAgeMonths'),
        'ageReason':previous.get('ageReason')}

if set(remaining_ambiguous) != set(AMBIGUOUS_DEFERRALS):
    raise SystemExit(
        'Phase 2c dispositions do not cover the remaining ambiguous set: '
        f"unruled={sorted(set(remaining_ambiguous)-set(AMBIGUOUS_DEFERRALS))}, "
        f"stale={sorted(set(AMBIGUOUS_DEFERRALS)-set(remaining_ambiguous))}"
    )
for rec in foods:
    reason=AMBIGUOUS_DEFERRALS.get(rec['dravyaId'])
    if not reason: continue
    original=remaining_ambiguous[rec['dravyaId']]
    previous=rec['_review']
    rec['_review']={
        'source':None,
        'spread':None,
        'status':'deferred — ambiguous IFCT identity, TASK-NUT1 Phase 2c',
        'ambiguousCandidates':[
            {'ifctCode':candidate[0],'ifctName':candidate[1]}
            for candidate in original[2]],
        'reason':reason,
        'currentMinAgeMonths':previous.get('currentMinAgeMonths'),
        'proposedMinAgeMonths':previous.get('proposedMinAgeMonths'),
        'ageReason':previous.get('ageReason')}
for rec in foods:
    withdrawn=WITHDRAWN.get(rec['dravyaId'])
    if not withdrawn: continue
    code,iname=withdrawn
    r=byc[code]
    for grp in MAP:
        for field in rec.get(grp,{}).values():
            field['value']=None
    previous=rec['_review']
    status=(F016_WITHDRAWAL_STATUS
            if rec['dravyaId'] in LATE_WITHDRAWALS else WITHDRAWN_STATUS)
    rec['_review']={
        'source':f'IFCT 2017 [{code}] {iname}',
        'spread':f"regions sampled: {r[C['regn']]}; each nutrient has a published SD in the _e column of ifct2017-compositions.csv",
        'status':status,
        'withdrawnIfctCode':code,
        'withdrawnIfctName':iname,
        'currentMinAgeMonths':previous.get('currentMinAgeMonths'),
        'proposedMinAgeMonths':previous.get('proposedMinAgeMonths'),
        'ageReason':previous.get('ageReason')}
json.dump(foods,open(B+'dravya_foods.json','w'),indent=1,ensure_ascii=False)
json.dump({'ambiguous':m['ambiguous'],'resolvedAmbiguous':m.get('resolvedAmbiguous',[]),
           'unmatched':m['none'],'withdrawn':m.get('withdrawn',[])},
          open(B+'ifct-unresolved.json','w'),indent=1,ensure_ascii=False)
print(f"filled {n} foods from IFCT 2017 measured values")
srcd=sum(1 for f in foods if any(
    field.get('value') is not None
    for grp in MAP
    for field in f.get(grp,{}).values()))
print(f"total with nutrition now: {srcd} of {len(foods)}")
print(f"withdrew {len(WITHDRAWN)} wrong IFCT matches")
print(f"published-literature foods: {len(PUBLISHED_LITERATURE)}")
print(f"manually resolved ambiguous foods: {len(AMBIGUOUS_BINDINGS)}")
print(f"explicitly deferred ambiguous foods: {len(AMBIGUOUS_DEFERRALS)}")
print(f"derived provenance records: {sum(1 for f in foods if f.get('_review',{}).get('provenance') == 'derived')}")
