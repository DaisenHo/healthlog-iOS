#!/usr/bin/env python3
"""T07 Chinese catalog for health records, charts, profile, and other health modules.

    python3 scripts/t07_zh.py --apply
    python3 scripts/t07_zh.py --check
"""
import copy, json, os, re, sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
CATALOG_PATH = "HealthLog/Resources/Localizable.xcstrings"
MEMORY_PATH = "docs/project/t07-zh-memory.json"
COVERAGE_PATH = "docs/project/t07-localization-coverage.json"
KEY_VALUE_OVERRIDE = {
    ("biomarker.editor.identity", "Identity"): "名称",
    ("aboutMe.profile.name", "Name"): "姓名",
    ("cycle.cervix.opening.open", "Open"): "张开",
    ("labs.detail.takenAt", "Taken"): "采样时间",
    ("cycle.capture.period.header", "Period"): "经期",
    ("cycle.history.period", "Period"): "经期",
    ("cycle.legend.period", "Period"): "经期",
    ("allergy.status.active", "Active"): "仍存在",
    ("allergy.status.resolved", "Resolved"): "已消退",
}
LOCKED_DE_EN = {
    "Educational estimate from EMA-published population pharmacokinetics. Not a measurement.",
    "Estimated level (relative)",
    "Estimated drug level",
}

SCREEN_DIRS = {
    "Measurements","Measure","Charts","Dashboard","Insights","CustomMetrics",
    "Cycle","Labs","Mood","Illness","Documents","MentalHealth","Nutrition",
    "Environment","PersonalRecords","PersonalSettings","AboutMe","Records",
    "Workouts","Achievements","Capture","Sharing","Shared",
}
MODEL_DIRS = {"Labs","CustomMetrics","Records","Illness","Cycle","MentalHealth","Environment","Documents"}
MODEL_FILES = {
    "Achievement.swift","AnamnesisFact.swift","AnamnesisFact+Copy.swift","AnamnesisFactFailure.swift",
    "BPDerivedReadout.swift","ClinicalSignalsDTO.swift","ComprehensiveDigest.swift",
    "CorrelationDiscoveryDTO.swift","CorrelationPatternDTO.swift","DailyDigest.swift","DailyPulseValue.swift",
    "Dashboard.swift","DashboardHeroItemKind.swift","DashboardHeroRingReconciler.swift","DashboardScoreRing.swift",
    "DashboardSnapshotBriefing.swift","DashboardWidgetLayout.swift","DashboardWidgetLayout+HeroItems.swift",
    "DashboardWidgetLayout+ScoreRings.swift","DerivedBatchDTO.swift","DerivedMetricDTO.swift","DiabetesFlagDTO.swift",
    "EcgDTO.swift","EcgIngestDTO.swift","GlucoseContext.swift","HealthScore.swift","HealthScoreConfig.swift",
    "Insight.swift","InsightsLayout.swift","InsightsLayoutSections.swift","IntradayPulseDTO.swift",
    "Measurement.swift","Measurement+DisplayableLatest.swift","Measurement+KindRouting.swift",
    "Measurement+MirrorPolicy.swift","Measurement+SyntheticRow.swift","MeasurementAvailabilityDTO.swift",
    "MeasurementDTO.swift","MeasurementDTO+Create.swift","MeasurementDTO+Source.swift","MeasurementDTO+UnknownType.swift",
    "MeasurementRanges.swift","MeasurementSeries.swift","MetricDataState.swift","MetricKindDescriptor.swift",
    "MetricKindDescriptor+AuditB4.swift","MetricKindDescriptor+B3Decoder.swift","MetricKindDescriptor+Catalog.swift",
    "MetricKindDescriptor+IC.swift","MetricKindDescriptor+Sugar.swift","MetricKindDescriptor+V125.swift",
    "MetricSeriesProjection.swift","MetricValueFormatter.swift","Mood.swift","MoodDailySeries.swift","MoodPattern.swift",
    "MoodRelationsDTO.swift","MoodStability.swift","MoodTagCatalog.swift","NarrativeDTO.swift","NutrientBatchDTO.swift",
    "NutrientCode+Unknown.swift","NutrientDisplay.swift","NutrientReadDTO.swift","PersonalRecord.swift","PersonalRecordDTO.swift",
    "RecoveryInsightsDTO.swift","RhythmEventsDTO.swift","SameTimeBaseline.swift","SleepNightDTO.swift","SleepRhythmDTO.swift",
    "SleepStageBreakdownDTO.swift","SourcePriorityDTO.swift","ThresholdMetric+AccountUnit.swift","TrendDirectionSentiment.swift",
    "TrendVerdict.swift","UserThresholdsDTO.swift","WeightTrendJudgement.swift","WorkoutDTO.swift","WorkoutIngestDTO.swift",
}
OTHER_PREFIXES = ("DesignSystem/","Components/","MedicalSources/","Screens/Shared/")
EXTRA_FILES = {"Util/HLError.swift","Util/Int+SafeServer.swift"}
DYNAMIC = [
    "anamnesis.kind.","anamnesis.value.","biomarker.explainer.","cycle.insights.metric.","cycle.phase.",
    "daily.action.","dashboard.metric.title.","dashboard.metric.unit.","illness.daylog.impact.",
    "insights.metric.","insights.subPage.explainer.","labs.catalog.","labs.scan.",
    "mood.tag.","mood.tagCategory.","nutrients.names.","sources.caveat.","sources.method.","sources.methodTitle.",
]
INSTRUMENT_EXACT = {
    "mentalHealth.functionalTitle",
    "mentalHealth.stem",
    "mentalHealth.stem.who5",
}
# 药物浓度曲线的说明与图表标题同属用药模块，保持原来的德英。
EXCLUDED_KEYS = {
    "sources.method.glp1PK",
    "sources.methodTitle.glp1PK",
}
INSTRUMENT_PREFIXES = (
    "mentalHealth.items.","mentalHealth.stems.","mentalHealth.options.",
    "mentalHealth.who5Options.","mentalHealth.sciOptions.","mentalHealth.functional.",
)
FORMAT_SPEC = re.compile(
    r"%(?:\d+\$)?[-+ #0]*[\d]*(?:\.\d+)?(?:ll|l|h|hh|z|t|q|L|j)?[@diufFeEgGxXoscpaA]"
    r"|%#@[A-Za-z0-9_]+@|%arg"
)
FORBIDDEN = re.compile(r"[·—–→•]")

def in_scope_file(rel):
    if rel in EXTRA_FILES:
        return "shared-errors"
    if rel.startswith(OTHER_PREFIXES):
        return rel.split("/")[0]
    parts = rel.split("/")
    if parts[0] == "Screens" and len(parts) > 1 and parts[1] in SCREEN_DIRS:
        return "Screens/" + parts[1]
    if parts[0] == "Models" and len(parts) > 1 and parts[1] in MODEL_DIRS:
        return "Models/" + parts[1]
    if parts[0] == "Models" and len(parts) == 2 and parts[-1] in MODEL_FILES:
        return "Models/health"
    return None

multiline_re = re.compile(r'"""\n(.*?)^[ \t]*"""', re.S | re.M)

def multiline_value(body, closing_indent):
    lines = body.split("\n")
    if lines and lines[-1].strip() == "":
        lines = lines[:-1]
    lines = [line[len(closing_indent):] if line.startswith(closing_indent) else line.lstrip() for line in lines]
    pieces = []
    for index, line in enumerate(lines):
        if line.endswith("\\") and not line.endswith("\\\\"):
            pieces.append(line[:-1]); continue
        pieces.append(line)
        if index < len(lines) - 1:
            pieces.append("\n")
    return "".join(pieces)

def _read_literal(text, index):
    body, nested, size = [], [], len(text)
    while index < size:
        char = text[index]
        if char == "\\" and index + 1 < size:
            if text[index + 1] == "(":
                depth, cursor = 0, index + 1
                while cursor < size:
                    inner = text[cursor]
                    if inner == '"':
                        value, cursor, deeper = _read_literal(text, cursor + 1)
                        nested.append(value); nested.extend(deeper); continue
                    if inner == "(": depth += 1
                    elif inner == ")":
                        depth -= 1
                        if depth == 0:
                            cursor += 1; break
                    elif inner == "\n":
                        break
                    cursor += 1
                body.append(text[index:cursor]); index = cursor; continue
            body.append(text[index:index + 2]); index += 2; continue
        if char == '"':
            return "".join(body), index + 1, nested
        if char == "\n":
            return "".join(body), index, nested
        body.append(char); index += 1
    return "".join(body), index, nested

def literals_in(text):
    found, index, size = [], 0, len(text)
    while index < size:
        if text[index] == '"':
            value, index, nested = _read_literal(text, index + 1)
            found.append(value); found.extend(nested); continue
        index += 1
    return found

def interpolation_segments(literal):
    segments, buffer, i, size, found = [], [], 0, len(literal), False
    escapes = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
    while i < size:
        if literal[i] == "\\" and i + 1 < size:
            if literal[i + 1] == "(":
                found = True
                segments.append("".join(buffer)); buffer = []; depth, i = 0, i + 1
                while i < size:
                    if literal[i] == "(": depth += 1
                    elif literal[i] == ")":
                        depth -= 1
                        if depth == 0:
                            i += 1; break
                    i += 1
                continue
            buffer.append(escapes.get(literal[i + 1], literal[i + 1])); i += 2; continue
        buffer.append(literal[i]); i += 1
    segments.append("".join(buffer))
    return segments if found else None

def scan():
    by_module = defaultdict(set)
    for dirpath, dirs, files in os.walk("HealthLog"):
        for name in files:
            if not name.endswith(".swift"): continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, "HealthLog")
            module = in_scope_file(rel)
            if not module: continue
            text = open(path, encoding="utf-8", errors="replace").read()
            lits = set()
            for match in multiline_re.finditer(text):
                closing = text[match.start():match.end()].rsplit("\n", 1)[-1]
                indent = closing[:len(closing) - len(closing.lstrip())]
                lits.add(multiline_value(match.group(1), indent))
            lits.update(literals_in(multiline_re.sub('""', text)))
            by_module[module].update(lits)
    all_lits = set().union(*by_module.values())
    patterns = []
    mod_patterns = {}
    fmt = r"%(?:\d+\$)?[-+ #0]*[\d]*(?:\.\d+)?(?:ll|l|h|hh|z|t|q)?[@diufFeEgGxXoscpaA]"
    for mod, lits in by_module.items():
        pats = []
        for literal in lits:
            segments = interpolation_segments(literal)
            if segments:
                joined = fmt.join(re.escape(segment) for segment in segments)
                pats.append(re.compile("^" + joined + "$"))
        mod_patterns[mod] = pats
        patterns.extend(pats)
    return by_module, all_lits, patterns, mod_patterns

def instrument(key):
    return key in INSTRUMENT_EXACT or key.startswith(INSTRUMENT_PREFIXES)

def dynamic_module(key):
    for p in DYNAMIC:
        if key.startswith(p):
            return "dynamic:" + p
    if key.startswith("mentalHealth.") and not instrument(key):
        return "Screens/MentalHealth"
    return None

def walk_strings(node, path, out):
    if isinstance(node, dict):
        if "value" in node and isinstance(node["value"], str) and path.endswith("stringUnit"):
            out.append((path, node["value"]))
        for k, v in node.items():
            walk_strings(v, path + "/" + k, out)

ALLOW_TOKENS = {
    "bmi","ecg","ekg","hrv","spo2","vo2","who","phq","gad","sci","loinc","fhir","pdf","csv",
    "json","api","id","ok","am","pm","kg","lb","mg","ml","dl","bpm","ms","kcal","kj","mmhg",
    "hba1c","hdl","ldl","gps","uv","rem","nrem","iso","url","qr","pin","icu","hl","ios","ip",
    "utf","ascii","uuid","mac","sms","otp","hr","rr","bp","dbp","sbp","cgm","ogtt","hba",
    "who5","phq9","gad7","audit","cv","sd","ci","n","sdnn","rmssd","pnn","lf","hf","bmi",
    "mmol","mgdl","mcg","µg","ug","iu","meq","ng","pg","ml","l","g","cm","mm","m","km","ft",
    "in","oz","lb","st","kcal","cal","bpm","rpm","w","kw","hz","khz","min","sec","hr","hrs",
    "db","spl","dbhl","ahi","rdi","spo","pa","fio","map","pp","co","hrmax","hrr","met","mets",
    "dxa","bia","who","icd","snomed","ucum","si","us","uk","eu","ema","fda","cdc","nih",
    "apple","health","healthkit","withings","fitbit","garmin","oura","whoop","xiaomi","mi",
    "pdf","png","jpg","jpeg","heic","xml","html","http","https","wifi","ble","nfc","qr",
    "glp","sema","ozempic",  # product names shouldn't appear as whole strings often
}

def is_verbatim(s):
    stripped = FORMAT_SPEC.sub(" ", s)
    words = re.findall(r"[A-Za-zμµ][A-Za-z0-9μµ%/+.-]*", stripped)
    if not words:
        return True
    for w in words:
        token = w.lower().strip(".")
        if token in ALLOW_TOKENS:
            continue
        if re.fullmatch(r"[A-Z0-9]{1,6}", w):  # short abbreviations
            continue
        if re.fullmatch(r"(vo2|spo2|hba1c|mmhg)", token):
            continue
        return False
    return True

def arg_sig(value):
    pattern = r"%(?:(\d+)\$)?([-+ #0]*)(\d*)(?:\.(\d+))?(hh|h|ll|l|q|L|z|j|t)?([@dDiuUxXoOfFeEgGcCsSpaAb%])"
    regex = re.compile(pattern)
    out = []
    index = 0
    for m in regex.finditer(value):
        conv = m.group(6)
        if conv == "%":
            continue
        flags = m.group(2) or ""
        if "#" in flags and conv == "@":
            continue
        pos = m.group(1)
        index += 1
        length = m.group(5) or ""
        out.append((int(pos) if pos else index, length + conv))
    out.sort()
    return tuple(x[1] for x in out)

def flatten(obj, prefix=""):
    out = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                out.update(flatten(v, p))
            elif isinstance(v, str):
                out[p] = v
    return out

def scope_map(catalog):
    by_module, all_lits, patterns, mod_patterns = scan()
    owners = {}
    for key in catalog:
        if instrument(key) or key in LOCKED_DE_EN or key in EXCLUDED_KEYS:
            continue
        mods = set()
        dynamic = dynamic_module(key)
        if dynamic:
            mods.add(dynamic)
        if key in all_lits or any(pattern.match(key) for pattern in patterns):
            for module, literals in by_module.items():
                if key in literals:
                    mods.add(module)
            if not any(key in literals for literals in by_module.values()):
                for module, module_patterns in mod_patterns.items():
                    if any(pattern.match(key) for pattern in module_patterns):
                        mods.add(module)
            if not mods:
                mods.add("interpolated")
        if mods:
            owners[key] = sorted(mods)
    return owners


def string_units(node):
    found = []
    walk_strings(node, "root", found)
    return [value for _, value in found]


def web_memory():
    english = flatten(json.load(open("../HealthLog/messages/en.json", encoding="utf-8")))
    chinese = flatten(json.load(open("../HealthLog/messages/zh-CN.json", encoding="utf-8")))
    german = flatten(json.load(open("../HealthLog/messages/de.json", encoding="utf-8")))
    by_english = defaultdict(list)
    for key, value in english.items():
        translation = chinese.get(key, "").strip()
        if translation and not FORBIDDEN.search(translation) and arg_sig(translation) == arg_sig(value):
            by_english[value].append((translation, german.get(key, "")))
    return by_english


def choose_web(by_english, english, german):
    choices = by_english.get(english) or []
    distinct = {translation for translation, _ in choices}
    if len(distinct) == 1:
        return next(iter(distinct))
    if german:
        matched = {translation for translation, source in choices if source == german}
        if len(matched) == 1:
            return next(iter(matched))
    return None


def translate_tree(node, key, manual, by_english, german_units, missing):
    index = 0

    def visit(current, path):
        nonlocal index
        if not isinstance(current, dict):
            return
        if path.endswith("stringUnit") and isinstance(current.get("value"), str):
            english = current["value"]
            german = german_units[index] if index < len(german_units) else ""
            index += 1
            override = KEY_VALUE_OVERRIDE.get((key, english))
            if override:
                chinese = override
            elif english in manual:
                chinese = manual[english]
            elif is_verbatim(english):
                chinese = english
            else:
                chinese = choose_web(by_english, english, german)
            if not chinese or (FORBIDDEN.search(chinese) and chinese not in {"—", "–"}):
                missing.append(english)
                chinese = english
            current["value"] = chinese
            current["state"] = "translated"
        for name, value in current.items():
            visit(value, path + "/" + name)

    visit(node, "root")


def load_catalog():
    with open(CATALOG_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def argument_signature(value):
    pattern = re.compile(
        r"%(?:(\d+)\$)?([-+ #0]*)(\d*)(?:\.(\d+))?(hh|h|ll|l|q|L|z|j|t)?([@dDiuUxXoOfFeEgGcCsSpaAb%])"
    )
    found = []
    index = 0
    for match in pattern.finditer(value):
        conversion = match.group(6)
        if conversion == "%":
            continue
        flags = match.group(2) or ""
        if "#" in flags and conversion == "@":
            continue
        index += 1
        position = int(match.group(1)) if match.group(1) else index
        length = match.group(5) or ""
        found.append((position, length + conversion))
    found.sort()
    return [item[1] for item in found]


def top_string(localization):
    unit = (localization or {}).get("stringUnit") or {}
    return unit.get("value")


def check(catalog, owners):
    problems = []
    for key in EXCLUDED_KEYS:
        if "zh-Hans" in (catalog["strings"].get(key, {}).get("localizations") or {}):
            problems.append(f"excluded key was translated: {key}")
    for key in LOCKED_DE_EN:
        languages = set((catalog["strings"].get(key, {}).get("localizations") or {}))
        if languages != {"de", "en"}:
            problems.append(f"locked copy changed: {key} -> {sorted(languages)}")
    for key, entry in catalog["strings"].items():
        if not instrument(key):
            continue
        if "zh-Hans" in (entry.get("localizations") or {}):
            problems.append(f"instrument translated: {key}")
    for key, modules in owners.items():
        entry = catalog["strings"][key]
        localizations = entry.get("localizations") or {}
        chinese = localizations.get("zh-Hans")
        english = localizations.get("en")
        if not chinese:
            problems.append(f"missing zh-Hans: {key}")
            continue
        if not string_units(chinese):
            problems.append(f"empty zh-Hans: {key}")
        for value in string_units(chinese):
            if value not in {"—", "–"} and FORBIDDEN.search(value):
                problems.append(f"punctuation: {key}")
        if argument_signature(key) and top_string(english) and top_string(chinese):
            if argument_signature(top_string(english)) != argument_signature(top_string(chinese)):
                problems.append(f"signature: {key}")
        if "de" not in localizations or "en" not in localizations:
            problems.append(f"lost de/en: {key}")
    return problems


def write_coverage(owners):
    counts = defaultdict(int)
    for modules in owners.values():
        counts[modules[0]] += 1
    payload = {
        "task": "T07",
        "inScopeKeys": len(owners),
        "instrumentKeysKeptInEnglish": sum(
            1 for key in json.load(open(CATALOG_PATH, encoding="utf-8"))["strings"] if instrument(key)
        ),
        "modules": {name: counts[name] for name in sorted(counts)},
        "deferred": [
            "Medications", "GLP1", "Notifications", "goals-and-reminders",
            "DoctorReport", "InfoPlist", "Widgets", "Watch", "WatchWidgets",
            "NotificationServiceExtension", "Settings", "Onboarding", "Coach",
            "Intents", "Spotlight",
        ],
        "validatedInstrumentsKeptInEnglish": list(INSTRUMENT_PREFIXES) + sorted(INSTRUMENT_EXACT),
    }
    with open(COVERAGE_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return payload


def apply_catalog():
    manual = json.load(open(MEMORY_PATH, encoding="utf-8"))
    by_english = web_memory()
    catalog = load_catalog()
    owners = scope_map(catalog["strings"])
    missing = []
    for key, modules in owners.items():
        entry = catalog["strings"][key]
        localizations = entry.setdefault("localizations", {})
        english = localizations.get("en")
        if not english:
            missing.append(key)
            continue
        german = string_units(localizations.get("de") or {})
        chinese = copy.deepcopy(english)
        translate_tree(chinese, key, manual, by_english, german, missing)
        localizations["zh-Hans"] = chinese
    if missing:
        print(f"missing translations: {len(missing)}")
        for item in missing[:30]:
            print(" ", item[:160])
        raise SystemExit(1)
    text = json.dumps(catalog, ensure_ascii=False, indent=2) + "\n"
    with open(CATALOG_PATH, "w", encoding="utf-8") as handle:
        handle.write(text)
    problems = check(load_catalog(), owners)
    coverage = write_coverage(owners)
    print(f"applied {coverage['inScopeKeys']} keys across {len(coverage['modules'])} modules")
    if problems:
        print(f"check failed: {len(problems)}")
        for problem in problems[:30]:
            print(" ", problem)
        raise SystemExit(1)
    print("check ok")


def main():
    if "--apply" in sys.argv:
        apply_catalog()
        return
    if "--check" not in sys.argv:
        print("usage: scripts/t07_zh.py --apply | --check")
        raise SystemExit(2)
    catalog = load_catalog()
    owners = scope_map(catalog["strings"])
    problems = check(catalog, owners)
    expected = json.load(open(COVERAGE_PATH, encoding="utf-8"))
    if expected.get("inScopeKeys") != len(owners):
        problems.append(f"coverage count {expected.get('inScopeKeys')} != {len(owners)}")
    if problems:
        print(f"check failed: {len(problems)}")
        for problem in problems[:40]:
            print(" ", problem)
        raise SystemExit(1)
    print(f"check ok: {len(owners)} in-scope keys")


if __name__ == "__main__":
    main()
