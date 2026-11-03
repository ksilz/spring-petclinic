#!/usr/bin/env python3
"""Builds the single-file German benchmark report (HTML) from the benchmark output.

Usage:
  make_report.py --preview --repo <repo> --template <template.html> --out <file.html>
  make_report.py --results <dir> --repo <repo> --template <template.html> --out <file.html>

<dir> holds the official run as copied from the small server:
  jdk25/result_<label>.csv, jdk27/result_<label>_jdk27.csv, jdk25/sizes.txt, jdk27/sizes.txt,
  graalvm-build.log (big server), mem.log, chain.log
"""
import argparse
import csv
import json
import re
import statistics
from datetime import datetime, timezone
from pathlib import Path

VARIANTS = [
    {"key": "baseline", "name": "Baseline"},
    {"key": "tuning", "name": "Tuning"},
    {"key": "cds", "name": "Tuning + CDS"},
    {"key": "leyden", "name": "Tuning + Leyden"},
    {"key": "crac", "name": "CRaC"},
    {"key": "graalvm", "name": "GraalVM"},
]
X = "spring-petclinic-4.0.0-SNAPSHOT"
VERIFY = "docs/benchmark-results/2026-10-31-verification-boot-4.1.2"


def num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


# Before 2026-11-02, benchmark.sh counted GC log lines that contain "Pause" (columns "Startup GCs" /
# "Benchmark GCs"). G1 (JVM and native image) writes two of them per pause, a start line and an end
# line, so the report divides those by 2. Since 2026-11-02 the CSV counts pauses directly (columns
# "Startup GC Pauses" / "Benchmark GC Pauses") and adds column 9, the startup time from process start.
GC_LINES_PER_PAUSE = 2


def read_csv(path):
    rows = list(csv.reader(open(path)))
    header, body = rows[0], rows[1:]
    divisor = 1 if "Pauses" in header[3] else GC_LINES_PER_PAUSE

    def pauses(s):
        v = num(s)
        return None if v is None else v / divisor

    def proc(r):
        return num(r[8]) if len(r) > 8 else None

    runs, a = [], None
    for r in body:
        if r[0] == "A":
            a = {"startup": num(r[1]), "mem": num(r[2]), "gcStart": pauses(r[3]), "gcBench": pauses(r[4]),
                 "sizeApp": num(r[6]) if len(r) > 6 else None, "sizeExtra": num(r[7]) if len(r) > 7 else None,
                 "startupProc": proc(r)}
        else:
            runs.append({"run": int(r[0]), "startup": num(r[1]), "mem": num(r[2]), "gcStart": pauses(r[3]),
                         "gcBench": pauses(r[4]), "ranAt": r[5], "startupProc": proc(r)})
    st = [x["startup"] for x in runs if x["startup"] is not None]
    mem = [x["mem"] for x in runs if x["mem"] is not None]
    stats = {"median": statistics.median(st), "min": min(st), "max": max(st), "memMedian": statistics.median(mem)}
    return {"runs": runs, "A": a, "stats": stats}


def parse_sizes(path):
    """sizes.txt from run-track.sh: '== label time', then '<kb> KB disk, <kb> KB apparent, <path>'."""
    out, cur = {}, None
    if not Path(path).exists():
        return out
    for line in open(path):
        line = line.rstrip("\n")
        m = re.match(r"== (\S+) ", line)
        if m:
            cur = out.setdefault(m.group(1), {})
            continue
        m = re.match(r"(\d+) KB disk, (\d+) KB apparent, (.+)$", line)
        if m and cur is not None:
            cur[m.group(3)] = int(m.group(1)) / 1024
        m = re.match(r"lib jars: (\d+)", line)
        if m and cur is not None:
            cur["libJars"] = int(m.group(1))
    return out


def size_view(sz):
    """Picks the artifact sizes (MB) out of parse_sizes() for one track."""
    def get(label, p):
        return sz.get(label, {}).get(p)
    return {
        "jar": get("baseline", f"build/libs/{X}.jar"),
        "extracted": get("tuning", X),
        "app": get("tuning", f"{X}/{X}.jar"),
        "lib": get("tuning", f"{X}/lib"),
        "libJars": sz.get("tuning", {}).get("libJars"),
        "jsa": get("cds", "petclinic.jsa"),
        "aot": get("leyden", "petclinic.aot"),
        "crac": get("crac", "petclinic-crac"),
        "coreImg": get("crac", "petclinic-crac/core.img"),
        "native": get("graalvm", "build/native/nativeCompile/spring-petclinic"),
        "iprof": get("graalvm", "src/pgo-profiles/main/default.iprof"),
    }


def parse_build(path):
    info = {}
    if not Path(path).exists():
        return info
    txt = open(path, errors="replace").read()
    m = re.search(r"Finished generating 'spring-petclinic-instrumented' in (\d+)m (\d+)s", txt)
    if m:
        info["instrumented"] = f"{int(m.group(1))}:{int(m.group(2)):02d}"
    m = re.search(r"Finished generating 'spring-petclinic' in (\d+)m (\d+)s", txt)
    if m:
        info["optimized"] = f"{int(m.group(1))}:{int(m.group(2)):02d}"
    rss = re.findall(r"Peak RSS: ([\d.]+)GB", txt)
    if len(rss) >= 2:
        info["rss"] = (rss[0], rss[-1])
    return info


def steal_stats(path):
    if not Path(path).exists():
        return None
    vals = []
    for line in open(path):
        f = line.split()
        # r b swpd free buff cache si so bi bo in cs us sy id wa st [gu]: steal is the 17th column
        if len(f) >= 17 and f[0].isdigit():
            vals.append(int(f[16]))
    if not vals:
        return None
    return {"n": len(vals), "avg": sum(vals) / len(vals), "max": max(vals)}


def de(v, dec=1):
    return f"{v:,.{dec}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def mb0(v):
    return None if v is None else str(round(v))


def build_data(args):
    repo = Path(args.repo)
    preview = args.preview
    tracks = {"25": {"results": {}}, "27": {"results": {}}}
    if preview:
        for label in [v["key"] for v in VARIANTS]:
            tracks["25"]["results"][label] = read_csv(repo / VERIFY / "jdk25" / f"{label}.csv")
            if label != "graalvm":
                tracks["27"]["results"][label] = read_csv(repo / VERIFY / "jdk27" / f"{label}.csv")
        sizes = {
            "25": {"jar": tracks["25"]["results"]["baseline"]["A"]["sizeApp"], "extracted": 63.8, "app": None, "lib": None,
                   "libJars": 93, "jsa": 110.6, "aot": 140.2, "crac": 232.6, "coreImg": 232.6, "native": 185.3, "iprof": 41.1},
            "27": {"jar": tracks["27"]["results"]["baseline"]["A"]["sizeApp"], "extracted": 63.8, "app": None, "lib": None,
                   "libJars": 93, "jsa": 109.9, "aot": 149.5, "crac": 397.4, "coreImg": 397.4, "native": None, "iprof": None},
        }
        build = parse_build(repo / VERIFY / "logs/followup-2026-11-01/big-server-native-build.log")
        steal = {"n": 606, "avg": 0.50, "max": 26}
        run_date = "31. Oktober 2026 (Verifikationslauf)"
        run_notes = []
        method = {"warmups": 1, "runs": 3}
    else:
        res = Path(args.results)

        def csv_path(track, label):
            suffix = "" if track == "25" else "_jdk27"
            p = res / f"jdk{track}" / f"result_{label}{suffix}.csv"
            return p if p.exists() else res / f"jdk{track}" / f"{label}.csv"
        for label in [v["key"] for v in VARIANTS]:
            tracks["25"]["results"][label] = read_csv(csv_path("25", label))
            if label != "graalvm":
                tracks["27"]["results"][label] = read_csv(csv_path("27", label))
        sizes = {"25": size_view(parse_sizes(res / "jdk25" / "sizes.txt")),
                 "27": size_view(parse_sizes(res / "jdk27" / "sizes.txt"))}
        sizes["27"]["native"] = sizes["27"]["iprof"] = None
        build = parse_build(res / "graalvm-build.log")
        steal = steal_stats(res / "mem.log")
        run_notes = [
            "<b>Messqualität:</b> Der Messserver ist eine AWS-t3-Instanz mit geteilter CPU. 8 von 77 Messläufen sind mehr als 8 % "
            "langsamer als der Median ihrer Variante, am deutlichsten GraalVM-Lauf 4 (0,975 s statt 0,339 s): Dort lief der ganze "
            "Prozess etwa dreimal so langsam, auch die GC-Pausen. Die Ursache zeigt das Protokoll nicht; es misst CPU-Steal, "
            "Plattenzugriffe und Speicher nur alle 15 Sekunden, und keine Stichprobe nahe dieser Läufe zeigt Auffälliges. Jeder dieser "
            "Läufe ist der langsamste seiner Variante, also nicht in Zeile A.",
        ]
        run_date = args.run_date
        method = {"warmups": 3, "runs": 7}

    def caption_list(t):
        s = sizes[t]
        items = [
            {"label": "Baseline: App-JAR", "value": mb0(s["jar"]), "shown": f"{mb0(s['jar'])} MB" if s["jar"] else None},
            {"label": "Tuning: App-JAR (entpackt)", "value": mb0(s["app"]), "shown": f"{mb0(s['app'])} MB" if s["app"] is not None else None,
             "na": "kommt aus dem Lauf"},
            {"label": "Tuning: Lib-JARs", "value": mb0(s["lib"]), "shown": f"{mb0(s['lib'])} MB" if s["lib"] is not None else None,
             "na": "kommt aus dem Lauf"},
            {"label": "CDS-Cache", "value": mb0(s["jsa"]), "shown": f"{mb0(s['jsa'])} MB" if s["jsa"] else None},
            {"label": "Leyden-Cache", "value": mb0(s["aot"]), "shown": f"{mb0(s['aot'])} MB" if s["aot"] else None},
            {"label": "CRaC-Snapshot", "value": mb0(s["crac"]), "shown": f"{mb0(s['crac'])} MB" if s["crac"] else None},
        ]
        if t == "25":
            items += [
                {"label": "GraalVM: Linux-App", "value": mb0(s["native"]), "shown": f"{mb0(s['native'])} MB" if s["native"] else None},
                {"label": "Native Image: instrumentierter Build", "value": build.get("instrumented"),
                 "shown": f"{build.get('instrumented')} Min" if build.get("instrumented") else None},
                {"label": "Native Image: optimierter Build", "value": build.get("optimized"),
                 "shown": f"{build.get('optimized')} Min" if build.get("optimized") else None},
                {"label": "Build-Server", "value": "32 GB RAM & 8 CPUs", "shown": "32 GB RAM, 8 CPUs"},
            ]
        else:
            items += [{"label": "GraalVM: Linux-App", "value": None, "na": "n/a, kein GraalVM für JDK 27"}]
        return items

    def a_row(label, key, path):
        return {"label": label, "path": path, "25": sizes["25"].get(key), "27": sizes["27"].get(key)}

    # Rows of the size chart, named like the slide captions.
    size_rows = [{"name": n, "a": sizes["25"].get(k), "b": sizes["27"].get(k)} for n, k in [
        ("Baseline: App-JAR", "jar"), ("Tuning: App-JAR", "app"), ("Tuning: Lib-JARs", "lib"), ("CDS-Cache", "jsa"),
        ("Leyden-Cache", "aot"), ("CRaC-Snapshot", "crac"), ("GraalVM: Linux-App", "native")]]

    artifacts = [
        a_row("Boot-JAR (Baseline, CRaC)", "jar", f"build/libs/{X}.jar"),
        a_row("Entpackter Ordner gesamt (Tuning, CDS, Leyden)", "extracted", f"{X}/"),
        a_row("davon App-JAR", "app", f"{X}/{X}.jar"),
        a_row("davon Lib-JARs", "lib", f"{X}/lib/"),
        a_row("CDS-Archiv", "jsa", "petclinic.jsa"),
        a_row("Leyden-AOT-Cache", "aot", "petclinic.aot"),
        a_row("CRaC-Checkpoint gesamt", "crac", "petclinic-crac/"),
        a_row("GraalVM Native Executable", "native", "build/native/nativeCompile/spring-petclinic"),
        a_row("PGO-Profil", "iprof", "src/pgo-profiles/main/default.iprof"),
    ]

    s25 = tracks["25"]["results"]
    lede = ("Spring PetClinic mit Spring Boot 4.1.2, gemessen auf JDK 25 und JDK 27: Standardstart, Spring-Boot-Tuning, "
            "Class Data Sharing, Project Leyden, CRaC und GraalVM Native Image.")
    facts = [f"Lauf vom {run_date}", f"{method['warmups']} Aufwärm- und {method['runs']} Messläufe je Variante",
             "Messserver AWS t3.small (2 vCPU, 2 GB RAM)", "Spring Boot 4.1.2"]
    preview_text = ("<b>Vorschau mit Platzhalterwerten.</b> Die Zahlen stammen aus dem Verifikationslauf vom 31. Oktober "
                    "(1 Aufwärmlauf + 3 Messläufe, noch mit den doppelten Datenbank-Indizes). Der offizielle Lauf mit 3 + 7 Läufen "
                    "läuft gerade; der fertige Bericht ersetzt alle Werte. Die Größen der Tuning-JARs fehlen hier noch.")
    jdk_notes = [
        "<b>GraalVM auf JDK 27:</b> gibt es nicht. GraalVM folgt nicht mehr dem JDK-Takt; alle aktuellen Releases "
        "(GraalVM 25 und die Innovation-Releases 25.1 bis 25.4) basieren auf JDK 25.",
        "<b>CRaC auf JDK 27:</b> Azul Zulu 27 mit CRaC (Build 27+35). Für das Update 27.0.1 gibt es noch keinen CRaC-Build.",
        "<b>Leyden auf JDK 27:</b> cacht weiterhin keinen Maschinencode. Neu gegenüber JDK 25 ist das Objekt-Caching mit jedem Garbage Collector.",
    ]
    if not preview:
        jdk_notes.append("<b>Speicher auf JDK 27:</b> Baseline hat zwei Niveaus: 4 Läufe mit 427 bis 431 MB, 3 Läufe mit 612 bis "
                         "624 MB. In den hohen Läufen vergrößerte G1 den Heap von 258 MB auf 445 bis 462 MB, in den niedrigen nicht. "
                         "Bei Tuning vergrößerte G1 den Heap in allen 7 Läufen auf 462 MB (451 bis 466 MB). Auf JDK 25 blieb der Heap in "
                         "jedem Lauf bei 258 MB. Zeile A der Baseline auf JDK 27 enthält zwei hohe Werte (503 MB); der Median liegt bei 431 MB.")
    method_text = [
        ["Anwendung", "Spring PetClinic (Fork), Spring Boot 4.1.2, Gradle 9.5.1, PostgreSQL-Profil mit Datenbank auf demselben Server."],
        ["Varianten", "Baseline: <code>java -jar</code> ohne Spring AOT. Tuning: entpacktes JAR mit Spring AOT. Tuning + CDS: zusätzlich "
                      "CDS-Archiv. Tuning + Leyden: zusätzlich Leyden-AOT-Cache (record, dann create). CRaC: Wiederherstellen aus einem "
                      "Checkpoint (Engine warp). GraalVM: Native Image mit Profile-Guided Optimization."],
        ["Ablauf je Variante", f"Build, bei CDS, Leyden und CRaC ein Trainingslauf, dann {method['warmups']} "
                               f"{'Aufwärmlauf' if method['warmups'] == 1 else 'Aufwärmläufe'} und "
                               f"{method['runs']} Messläufe. Jeder Lauf startet die Anwendung neu."],
        ["Last je Lauf", "Nach dem Start 5 Runden über 11 Aufrufe (10 verschiedene Seiten), also 55 Anfragen mit je 3 Sekunden Pause "
                         "davor. Jede Seite muss HTTP 200 liefern, nur <code>/oups</code> (absichtlicher Fehler) HTTP 500, sonst bricht der Lauf ab."],
        ["Startzeit", "Die Zeit, die die Anwendung selbst meldet, wie im Mai. JVM-Varianten und GraalVM: „Started PetClinicApplication "
                      "in … seconds“. Diese Uhr läuft erst ab dem Start von Spring Boot; der Start der JVM davor fehlt. CRaC: „restored "
                      "JVM running for … ms“, gezählt ab dem Start des Prozesses, also mit dem Wiederherstellen."],
        ["Startzeit ab Prozessstart", "Neu in diesem Lauf: „process running for …“ aus derselben Zeile von Spring Boot, also mit dem "
                                      "Start der JVM. Bei CRaC derselbe Wert wie die Startzeit."],
        ["Speicher", "Maximale Resident Set Size des Prozesses über den ganzen Lauf, gemessen mit <code>/usr/bin/time -v</code>."],
        ["Garbage Collections", "Anzahl der GC-Pausen, getrennt vor und nach dem Start, auf die Millisekunde genau. Jede Pause zählt "
                                "einmal: Young Collections und die zwei kurzen Pausen jeder Markierungsrunde von G1 (Remark, Cleanup). Gleiche "
                                "Regel für alle Varianten. Die GC-Logs jedes Laufs liegen im Repository."],
        ["Kennzahl A", "Getrimmtes Mittel je Kennzahl: Der kleinste und der größte Wert fallen weg, der Rest wird gemittelt. Bei der "
                       "Startzeit sind das der schnellste und der langsamste Lauf; Speicher und GC-Pausen werden jeweils für sich getrimmt. "
                       "Diese Zahl steht auf den Folien."],
        ["JVM-Einstellungen", "<code>-Xms256m -Xmx768m -XX:+UseG1GC</code>, Profil <code>postgres</code>. CRaC übernimmt die Einstellungen "
                              "aus dem Checkpoint. GraalVM: G1 mit höchstens 128 MB Heap, zur Build-Zeit festgelegt; dazu kommen rund 83 MB "
                              "Objekte, die beim Build entstanden und in der Anwendung liegen."],
        ["Server", "Alle Messungen auf einem AWS t3.small (2 vCPU, 2 GB RAM, 2 GB Swap), wie im Mai. Das Native Image entsteht auf "
                   "einem t3.2xlarge (8 vCPU, 32 GB RAM) und wird kopiert."],
        ["Störungen", "Server vorher neu gestartet, automatische Updates pausiert, keine anderen Anwendungen. Bei Baseline, Tuning, "
                      "CDS und Leyden läuft der Gradle-Daemon aus dem Build während der Messung im Leerlauf weiter (wie im Mai, so "
                      "arbeitet compile-and-run.sh). CRaC baut ohne Daemon, GraalVM baut nicht auf dem Messserver. "
                      + (f"CPU-Steal im Lauf: im Mittel {de(steal['avg'], 2)} %, höchstens {steal['max']} % ({steal['n']} Stichproben). "
                         if steal else "")
                      + ("" if preview else "Swap: auf JDK 25 höchstens 16 MB belegt, auf JDK 27 bis zu 65 MB.")],
    ]
    versions = [
        ["Spring Boot", "4.1.2", "4.1.2"],
        ["Baseline, Tuning, CDS, Leyden", "Eclipse Temurin 25.0.5+8 (<code>25.0.5.0+8-tem</code>)", "Eclipse Temurin 27+35 (<code>27.0.0.0+35-tem</code>)"],
        ["CRaC", "Azul Zulu 25.0.4.1 CRaC, Zulu25.36+205-CRaC-CA (<code>25.0.4.1-crac+1-zulu</code>)",
         "Azul Zulu 27 CRaC, Zulu27.28+101-CRaC-CA (<code>27.0.0.0-crac+35-zulu</code>)"],
        ["GraalVM", "Oracle GraalVM 25.0.5.0.3, native-image 25.0.5.0.3 (<code>25.0.5.0+3-graal</code>)", "n/a"],
        ["GraalVM Native Build Tools", "1.1.2", "–"],
        ["Gradle", "9.5.1", "9.5.1"],
        ["CRaC-Engine", "warp (braucht kein CRIU)", "warp (braucht kein CRIU)"],
        ["PostgreSQL", "16.15 auf dem Messserver", "16.15 auf dem Messserver"],
        ["Betriebssystem", "Ubuntu 24.04.4 LTS, Kernel 7.0.0-1014-aws, glibc 2.39-0ubuntu8.9", "wie JDK 25"],
        ["Messserver", "AWS t3.small, 2 vCPU Intel Xeon Platinum 8259CL @ 2,50 GHz, 2 GB RAM (1,9 GB nutzbar), 2 GB Swap", "wie JDK 25"],
        ["Build-Server (Native Image)", "AWS t3.2xlarge, 8 vCPU, 32 GB RAM (31 GB nutzbar), kein Swap", "–"],
    ]
    rss = build.get("rss")
    build_rows = [
        ["Instrumentierter Build", (f"{build['instrumented']} Min" if build.get("instrumented") else "–")
         + (f", Spitzenspeicher {rss[0].replace('.', ',')} GB" if rss else "")],
        ["Trainingslauf", "Die instrumentierte Anwendung läuft einmal mit der Seitenlast und schreibt das PGO-Profil."],
        ["Optimierter Build", (f"{build['optimized']} Min" if build.get("optimized") else "–")
         + (f", Spitzenspeicher {rss[1].replace('.', ',')} GB" if rss else "")],
        ["Build-Server", "AWS t3.2xlarge, 8 vCPU, 32 GB RAM; Gradle mit <code>-Xmx24g</code>, native-image mit <code>--gc=G1</code>"],
    ]
    notes = [
        "Alle Werte auf den Folien sind Zeile A (getrimmtes Mittel). Median, Spanne und jeder einzelne Lauf stehen unter „Einzelmessungen“.",
        f"GraalVM startet langsamer als auf den alten Folien ({de(s25['graalvm']['A']['startup'], 3)} s statt 0,287 s). Etwa 0,03 s "
        "davon kommen daher, dass das Native Image jetzt wie alle JVM-Varianten <code>schema.sql</code> und <code>data.sql</code> beim "
        "Start ausführt; vorher fehlten die Skripte im Native Image (behoben im Upstream-Commit <code>a2c2ef9</code>). Den Rest kostet "
        "das Upgrade (Spring Boot 4.1.2, Hibernate 7.4, GraalVM 25.0.5), ähnlich wie bei den JVM-Varianten.",
        "GraalVM-GCs werden seit dem 1. November gezählt; die 0 auf den alten Folien war ein Fehler im Messskript. Das Native Image "
        "schreibt sein GC-Log auf die Standardausgabe, das Skript suchte es vorher in einer Datei, die nie entstand.",
        "Die Größen von CDS-Archiv, Leyden-Cache und CRaC-Checkpoint stehen seit dem 1. November auch im CSV (vorher immer 0,0).",
        "Die Datenbank des Messservers hatte vor dem Lauf 15 Indizes, also keine doppelten (4.137 Duplikate der alten "
        "<code>schema.sql</code> wurden vor dem Lauf vom 1. November entfernt).",
        "Dieser Lauf ersetzt den vom 1. November. Damals zählte das Messskript GC-Logzeilen statt Pausen (zwei je Pause) und trennte "
        "Start und Benchmark nur auf die Sekunde genau; die Startzeit ab Prozessstart fehlte, und nur der letzte Lauf jeder Variante "
        "hatte Logs.",
        "Die Speicherwerte sind Resident Set Size, nicht Heap. CRaC zeigt den Speicher des wiederhergestellten Prozesses.",
    ] + run_notes
    footer = (f"Erzeugt am {datetime.now(timezone.utc).strftime('%d.%m.%Y, %H:%M')} UTC aus Branch "
              f"run-upgrade-benchmarks-jdk25-jdk27, Commit {args.commit}. Rohdaten (CSV, Logs) liegen im Repository unter "
              f"docs/benchmark-results/.")

    return {
        "preview": preview, "previewText": preview_text, "lede": lede, "facts": facts,
        "variants": VARIANTS, "trackOrder": ["25", "27"], "tracks": tracks, "sizeRows": size_rows, "jdkNotes": jdk_notes,
        "naReason": {"graalvm": "kein GraalVM für JDK 27"},
        "captions": {"25": caption_list("25"), "27": caption_list("27")},
        "artifacts": artifacts, "build": build_rows, "method": method, "methodText": method_text,
        "versions": versions, "notes": notes, "footer": footer,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--results")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--template", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--commit", default="7785519")
    ap.add_argument("--run-date", default="2./3. November 2026")
    args = ap.parse_args()
    data = build_data(args)
    html = open(args.template).read()
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    html = html.replace("/*__DATA__*/null", payload)
    open(args.out, "w").write(html)
    print("wrote", args.out, len(html), "bytes")


if __name__ == "__main__":
    main()
