#!/usr/bin/env node
/**
 * IMG-2 — batch runner for the Flow Automator bridge.
 *
 * Watches ./queue for batch-NNN.json, runs each job strictly in order through
 * the bridge, and moves the batch file to ./done or ./failed when it finishes.
 * No model decides anything here: the prompt, filename and settings all come
 * from the batch file that build_batches.py wrote.
 *
 *   node runner.js --bridge http://localhost:8787 --out /abs/path/for/images
 *   node runner.js --once            run one batch and stop
 *   node runner.js --dry-run         print what would be submitted
 *
 * Deliberately serial. Flow is a single authenticated tab driven through the
 * DOM; parallel submissions interleave and the downloads come back mismatched.
 */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf("--" + k); return i === -1 ? d : (argv[i + 1] ?? true); };
const has = (k) => argv.includes("--" + k);

const BRIDGE = arg("bridge", "http://localhost:8787");
const OUTDIR = arg("out", null);
const DIR = __dirname;
const Q = path.join(DIR, "queue"), DONE = path.join(DIR, "done"), FAIL = path.join(DIR, "failed");
const JOBS_FILE = arg("jobs", path.join(DIR, "jobs.json"));
const LIMIT = Number(arg("limit", 100));
const DOWNLOADS = arg("downloads", path.join(process.env.HOME || "", "Downloads"));
const LEDGER = path.join(DIR, "results", "ledger.json");
const LOG = path.join(DIR, "runner.log");
const RUN_ID = Date.now().toString(36);
const POLL = Number(arg("poll", 5000));
const JOB_TIMEOUT = Number(arg("timeout", 330000));
const SETTLE = Number(arg("settle", 4000));
const RETRIES = Number(arg("retries", 0));

for (const d of [Q, DONE, FAIL]) fs.mkdirSync(d, { recursive: true });

const log = (m) => {
  const line = `${new Date().toISOString()} ${m}`;
  console.log(line);
  fs.appendFileSync(LOG, line + "\n");
};

async function api(method, p, body) {
  const res = await fetch(BRIDGE + p, {
    method,
    headers: { "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data; try { data = JSON.parse(text); } catch { data = text; }
  if (!res.ok) throw new Error(`${res.status} ${typeof data === "object" ? data.error : data}`);
  return data;
}

const TERMINAL = new Set(["done", "downloaded", "error", "cancelled"]);

// Exact-bytes duplicate detection, checked at run time rather than at validation.
// When the extension logs card_bind_failed_using_global_match it falls back to
// "newest image on the page", which can hand back the PREVIOUS job's result. That
// failure produces a plausible image under the wrong name, so catching it 30
// seconds later is worth much more than catching it 100 jobs later.
const seenHashes = new Map();
const IMG_EXT = [".jpeg", ".jpg", ".png", ".webp"];
const VID_EXT = [".mp4"];

// Keep these sets type-selected.  They must not be merged: a video job that
// lands a JPEG means Flow was left in Image mode, and accepting that file would
// silently spend a video job without producing a clip.
function extensionsFor(type) {
  if (type === "image") return IMG_EXT;
  if (type === "video") return VID_EXT;
  throw new Error(`unsupported job type "${type}" (expected image or video)`);
}

/**
 * Verify what actually landed on disk for this job, not what we asked for.
 *
 * Returns null if healthy, otherwise a human-readable problem. Three real
 * failures seen in the wild, all of which produce plausible-looking output:
 *   - the result card matched globally and returned an EARLIER job's image
 *     (byte-identical to something already accepted)
 *   - the job ran twice, so Chrome wrote "name (1).jpeg" alongside "name.jpeg"
 *     and it is no longer knowable which file belongs to which submission
 *   - nothing landed at all, or more than one new file did
 */
function landedPath(filename, type) {
  for (const ext of extensionsFor(type)) {
    const p = path.join(OUTDIR, filename + ext);
    if (fs.existsSync(p)) return p;   // _rejected/ is a subfolder, so never matched here
  }
  return null;
}

/**
 * A file sitting in Chrome's Downloads folder was generated AND downloaded; only
 * the move into OUTDIR failed. Recovering it costs nothing; regenerating it costs
 * a credit for an image that already exists.
 */
function rescueFromDownloads(filename, type) {
  if (!DOWNLOADS || !fs.existsSync(DOWNLOADS) || !OUTDIR) return null;
  for (const ext of extensionsFor(type)) {
    const src = path.join(DOWNLOADS, filename + ext);
    if (!fs.existsSync(src)) continue;
    const dst = path.join(OUTDIR, filename + ext);
    fs.mkdirSync(OUTDIR, { recursive: true });
    fs.copyFileSync(src, dst);
    return dst;
  }
  return null;
}

function loadLedger() {
  try { return JSON.parse(fs.readFileSync(LEDGER, "utf8")); } catch { return {}; }
}

function saveLedger(results) {
  const l = loadLedger();
  // mediaId is the durable handle on the generated image (extension >= 0.5.5).
  // Kept even for failed rows — especially for failed rows: a download failure
  // means the image EXISTS in the Flow project, so the id is what makes it
  // recoverable later without regenerating. Never overwrite a known id with
  // null on a retry.
  for (const r of results) {
    if (!r.filename) continue;
    const prev = l[r.filename] || {};
    l[r.filename] = {
      status: r.status, name: r.name, kind: r.kind, error: r.error || null,
      mediaId: r.mediaId || prev.mediaId || null,
    };
  }
  fs.mkdirSync(path.dirname(LEDGER), { recursive: true });
  fs.writeFileSync(LEDGER, JSON.stringify(l, null, 2));
}

function dupeVariants(filename, type) {
  // Chrome writes "name (1).jpeg" when the same name is downloaded twice.
  const esc = filename.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp("^" + esc + " \\(\\d+\\)$");
  return fs.readdirSync(OUTDIR).filter(
    (f) => extensionsFor(type).includes(path.extname(f).toLowerCase()) && re.test(path.basename(f, path.extname(f)))
  );
}

/**
 * Verify what landed for THIS job, by NAME rather than by counting new files.
 *
 * Counting every fresh file was wrong: a job that times out on a card-bind
 * stall usually finishes anyway, 60-90 seconds later, and its correctly-named
 * download then lands inside a LATER job's window. Checking the expected name
 * directly is immune to that and still catches the failures that matter.
 */
function verifyLanded(filename, sinceMs, type) {
  if (!OUTDIR || !fs.existsSync(OUTDIR)) return null;
  const p = landedPath(filename, type);
  if (!p) return `job reported success but no ${type} file with the expected name appeared`;
  const st = fs.statSync(p);
  if (st.mtimeMs < sinceMs - 1000)
    return `the file predates this job (${new Date(st.mtimeMs).toISOString()}) — it is a leftover from an earlier run`;
  const extra = dupeVariants(filename, type);
  if (extra.length)
    return `Chrome de-duplicated the name (${extra.join(", ")}) — this submission ran more than once`;
  const h = crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");
  if (seenHashes.has(h))
    return `byte-identical to ${seenHashes.get(h)} — the result card was matched globally and returned an earlier image`;
  seenHashes.set(h, filename);
  return null;
}

/**
 * Second pass over the failed rows. A card-bind stall still completes in the
 * tab, so by the end of a batch its image is usually on disk under the right
 * name. Recovering it here avoids re-spending a credit that was already spent.
 */
function reconcile(results, batchStart) {
  let recovered = 0;
  for (const r of results) {
    if (r.status !== "error" || !r.filename) continue;
    if (!verifyLanded(r.filename, batchStart, r.mediaType) ||
        (landedPath(r.filename, r.mediaType) && r.skippedExisting)) {
      log(`  recovered ${r.filename} — it landed after the runner gave up on it`);
      r.status = "downloaded"; r.error = null; r.recoveredLate = true; recovered++;
    }
  }
  if (recovered) log(`  reconciliation recovered ${recovered} row(s) that had timed out`);
  return recovered;
}

/** Map a known failure string to the action that fixes it. Unknown -> say so. */
function diagnose(err) {
  const e = String(err);
  if (/FLOW_POLICY_REFUSED/.test(e))
    return "Flow rejected THIS PROMPT on content policy. The account is fine and the run\n" +
           "                continues - the row is recorded as refused_policy and left with no file, so a\n" +
           "                later run picks it up. To clear it for good, reword the prompt (see\n" +
           "                yoga/soften_prompts.py) and re-run just the quarantine file.";
  if (/FLOW_REFUSED/.test(e))
    return "Flow REFUSED the request — this is an anti-abuse or quota block, not a stall.\n" +
           "                Stop. Do not retry in a loop: repeated submissions into a refusal are\n" +
           "                what escalate it. Wait for it to clear, then generate ONE image by hand\n" +
           "                in the Flow UI to confirm before running anything scripted again, and\n" +
           "                resume more gently: a SMALLER batch and a LONGER settle, e.g.\n" +
           "                --limit 100 --settle 90000. (settle is the pause AFTER each job, so a\n" +
           "                bigger number is slower. Earlier text here said --settle 30000, which is\n" +
           "                FASTER than the 60000 default and would have made the block worse.)";
  if (/already exists/.test(e))
    return "A bridge from an earlier run is still holding these job ids. Kill it and restart:\n" +
           "                lsof -ti:8787 | xargs kill   then re-run the bridge.";
  if (/Receiving end does not exist|Could not reach content script/.test(e))
    return "The extension cannot reach its content script. Reload the extension at\n" +
           "                chrome://extensions, THEN reload the Flow project tab — the content\n" +
           "                script only injects on page load.";
  if (/extension not connected/i.test(e))
    return "No Flow tab is connected. Open an authenticated labs.google Flow project tab.";
  if (/settings chip/.test(e))
    return "The extension could not find the composer's settings chip. Set the composer by hand\n" +
           "                (Image, 1:1, your model) and re-run with --no-settings, which skips the\n" +
           "                popover entirely. To debug the chip instead:\n" +
           "                curl -s localhost:8787/screenshot -o flow.png";
  if (/timeout/.test(e))
    return "Jobs are accepted but never report finishing. Usually the result card failed to\n" +
           "                bind — the image may well EXIST in the Flow project even though it was not\n" +
           "                downloaded. Check the project before re-queueing these rows, and raise\n" +
           "                --settle before raising --retries: a retry regenerates and re-charges.";
  return "Unrecognised failure — check the Flow tab and bridge log before re-running.";
}

async function waitFor(id) {
  const started = Date.now();
  for (;;) {
    if (Date.now() - started > JOB_TIMEOUT) throw new Error("timeout");
    await new Promise((r) => setTimeout(r, 3000));
    const jobs = await api("GET", "/jobs");
    const list = Array.isArray(jobs) ? jobs : jobs.jobs || [];
    const j = list.find((x) => x.id === id);
    if (!j) continue;
    if (TERMINAL.has(j.status)) return j;
  }
}

async function preflight() {
  // The extension connects a few seconds after the bridge starts, so a single
  // immediate check races it and fails on a perfectly healthy setup. Poll instead.
  const WAIT = Number(arg("wait", 60)) * 1000;
  const started = Date.now();
  let h, announced = false;
  for (;;) {
    try { h = await api("GET", "/health"); }
    catch (e) {
      if (Date.now() - started > WAIT) { log(`bridge unreachable at ${BRIDGE} — ${e.message}`); return false; }
      if (!announced) { log(`waiting for the bridge at ${BRIDGE} ...`); announced = true; }
      await new Promise((r) => setTimeout(r, 1000));
      continue;
    }
    if (h.extensionConnected) break;
    if (Date.now() - started > WAIT) {
      log(`bridge is up but no extension connected after ${WAIT / 1000}s —`);
      log("  load Flow Automator at chrome://extensions and open an authenticated Flow project tab");
      return false;
    }
    if (!announced) { log("bridge up, waiting for the extension to connect ..."); announced = true; }
    await new Promise((r) => setTimeout(r, 1000));
  }
  // Only PENDING jobs can interleave with this run. Finished ones just sit in the
  // bridge's map and are harmless — refusing on h.jobs alone made a clean restart
  // impossible without killing the bridge every single time.
  if (h.jobs > 0) {
    let pending = [];
    try {
      const jl = await api("GET", "/jobs");
      const list = Array.isArray(jl) ? jl : jl.jobs || [];
      pending = list.filter((j) => !TERMINAL.has(j.status));
    } catch { pending = []; }
    if (pending.length && !has("allow-stale")) {
      log(`REFUSING TO START — ${pending.length} job(s) from an earlier run are still IN FLIGHT.`);
      log(`  ${pending.slice(0, 4).map((j) => `${j.id}:${j.status}`).join(", ")}`);
      log("  They finish at arbitrary times, download under their own filenames, and interleave");
      log("  with this run — which is how an image ends up attached to the wrong food.");
      log("      lsof -ti:8787 | xargs kill && node <plugin>/bridge/server.js &");
      log("  then reload the Flow project tab. (--allow-stale overrides, but do not.)");
      return false;
    }
    log(`note: bridge holds ${h.jobs} finished job(s) from an earlier run — inert, continuing`);
  }
  // /inspect round-trips through the content script, so it proves the whole chain
  // works before we submit anything. Without this a broken tab costs three real jobs.
  let lastErr = null;
  while (Date.now() - started <= WAIT) {
    try {
      const r = await api("GET", "/inspect");
      if (r && r.error) throw new Error(r.error);
      lastErr = null;
      break;
    } catch (e) {
      lastErr = e;
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
  if (lastErr) {
    log("preflight FAILED — the extension cannot reach the Flow tab's content script.");
    log(`  ${diagnose("Receiving end does not exist")}`);
    log(`  (underlying: ${lastErr.message})`);
    return false;
  }
  log("preflight ok — bridge up, extension connected, content script responding");
  return true;
}

function seedFromDisk() {
  if (!OUTDIR || !fs.existsSync(OUTDIR)) return 0;
  let n = 0;
  for (const f of fs.readdirSync(OUTDIR)) {
    const ext = path.extname(f).toLowerCase();
    // This only seeds duplicate hashes.  Landing/skip correctness still uses
    // extensionsFor(job.type), so seeing both families here cannot make a
    // wrong-media job pass.
    if (!IMG_EXT.includes(ext) && !VID_EXT.includes(ext)) continue;
    const h = crypto.createHash("sha256").update(fs.readFileSync(path.join(OUTDIR, f))).digest("hex");
    if (!seenHashes.has(h)) seenHashes.set(h, path.basename(f, path.extname(f)));
    n++;
  }
  return n;
}

function materializeFiles(files, filename) {
  return files.map((spec) => {
    if (!spec.path) return { ...spec };
    const { path: sourcePath, ...wireSpec } = spec;
    const resolved = path.resolve(sourcePath);
    const bytes = fs.readFileSync(resolved);
    if (!bytes.length) throw new Error(`reference file is empty: ${resolved}`);
    const data = bytes.toString("base64");
    if (spec.role === "start") {
      log(`  start frame ${filename}: ${bytes.length} source bytes -> ${data.length} base64 characters`);
    }
    // The content script runs inside the page and cannot dereference a local
    // filesystem path.  Encode only the one file being submitted; keeping the
    // 907 source paths in jobs.json avoids a ~1.2 GB base64-tracked artifact.
    return { ...wireSpec, data };
  });
}

async function runBatch(file) {
  const batch = JSON.parse(fs.readFileSync(file, "utf8"));
  for (const job of batch.jobs) extensionsFor(job.type);
  const name = path.basename(file);
  log(`START ${name} — ${batch.jobs.length} jobs, styleHash ${batch.styleHash}` +
      (has("no-settings") ? " [--no-settings: using the composer's current state]" : ""));
  const batchStartedAt = Date.now();
  // Adaptive pacing. A rising stall rate means the service is struggling with us
  // or is starting to throttle; the correct response is to back off, never to
  // push harder. Slowing down is also what keeps a soft limit from becoming a
  // hard one.
  const recent = [];
  let settle = SETTLE;
  const stallRate = () => recent.length < 8 ? 0 : recent.filter((x) => !x).length / recent.length;
  // Existing images are both a skip-list and duplicate-detection state. Without
  // seeding, a re-run would neither skip finished rows nor notice that a new
  // download is byte-identical to one from an earlier run.
  const onDisk = seedFromDisk();
  if (onDisk) log(`  ${onDisk} media file(s) already in ${OUTDIR}`);
  const results = [];
  let consecutive = 0;
  const policyRefused = [];   // per-prompt content rejections; reported at the end
  let skippedExisting = 0;
  const ABORT_AFTER = Number(arg("abort-after", 3));
  for (const [i, job] of batch.jobs.entries()) {
    if (consecutive >= ABORT_AFTER) {
      const last = results[results.length - 1] || {};
      log(`ABORT — ${consecutive} consecutive failures, skipping the remaining ${batch.jobs.length - i} jobs.`);
      log(`        last error: ${last.error || last.status || "unknown"}`);
      log(`        ${diagnose(last.error || "")}`);
      for (const rest of batch.jobs.slice(i)) results.push({ ...rest._row, filename: rest.output.filename, mediaType: rest.type, status: "skipped", error: "aborted after consecutive failures" });
      break;
    }
    // The bridge keeps finished jobs in memory and rejects a repeated id with 409.
    // The batch id stays deterministic for traceability; the SUBMITTED id carries a
    // per-run suffix so re-running a batch against a still-live bridge works.
    const submitId = `${job.id}-${RUN_ID}`;
    // Already generated in an earlier run: do not pay for it twice. --force overrides.
    if (!has("force") && !landedPath(job.output.filename, job.type)) {
      const rescued = rescueFromDownloads(job.output.filename, job.type);
      if (rescued) log(`  rescued ${job.output.filename} from Downloads — already generated, never moved`);
    }
    if (!has("force") && landedPath(job.output.filename, job.type)) {
      skippedExisting++;
      results.push({ ...job._row, filename: job.output.filename, mediaType: job.type, status: "downloaded", skippedExisting: true });
      continue;
    }
    // --no-settings: leave the composer alone and reuse whatever it is set to.
    // The settings are identical for all 1,844 jobs, so driving the popover per
    // job repeats the most fragile interaction in the chain for no benefit.
    const payload = {
      id: submitId, type: job.type, prompt: job.prompt,
      // Materialize local reference paths here, one job at a time. The bridge
      // receives transport-safe base64 and the tracked job file stays compact.
      ...(job.files ? { files: materializeFiles(job.files, job.output.filename) } : {}),
      ...(has("no-settings") ? { skipSettings: true, settings: {} } : { settings: job.settings }),
      output: { ...job.output, ...(OUTDIR ? { moveTo: OUTDIR } : {}) },
    };
    if (has("dry-run")) { log(`  [dry] ${job.output.filename}`); results.push({ ...job._row, filename: job.output.filename, mediaType: job.type, status: "dry" }); continue; }

    const jobStartedAt = Date.now();
    log(`  submit ${i + 1}/${batch.jobs.length} ${job.type} ${job.output.filename}`);
    let done = null, lastErr = null;
    for (let attempt = 0; attempt <= RETRIES; attempt++) {
      const id = attempt === 0 ? submitId : `${submitId}-r${attempt}`;
      try {
        await api("POST", "/jobs", { ...payload, id });
        done = await waitFor(id);
        if (done.status === "done" || done.status === "downloaded") break;
        lastErr = done.error || done.status;
      } catch (e) {
        lastErr = e.message;
        done = null;
      }
      // NEVER retry a timeout or a post-submission error. A stall almost always
      // means Flow DID generate the image and only the result card failed to
      // bind — re-running it spends the credit twice for a picture that already
      // exists. Only failures that provably happened BEFORE generation are safe
      // to repeat. Default is 0 retries; --retries 1 only widens this set.
      // card_bind_failed joins that set from extension 0.5.1. In 0.4.x an
      // unbindable card fell back to global matching and claimed whatever image
      // appeared next — usually the NEXT job's — so the failure was invisible and
      // a retry compounded it. From 0.5.1 the job aborts before claiming
      // anything, so the filename is untouched and a repeat is safe. Inert at the
      // default --retries 0, where the row simply stays queued for the next round.
      const preGeneration = /already exists|not connected|content script|Receiving end|unreachable|ECONN|card_bind_failed/i.test(String(lastErr));
      if (attempt < RETRIES && preGeneration) {
        log(`  retry ${i + 1}/${batch.jobs.length} ${job.output.filename} — ${lastErr} (nothing was generated)`);
        await new Promise((r) => setTimeout(r, SETTLE * 2));
      } else {
        break;
      }
    }

    // A PER-PROMPT policy rejection is not an account block. On 2026-08-05 one
    // refused asana ("might violate our policies. Please try a different prompt")
    // was treated as an anti-abuse stop and skipped the remaining 96 jobs of a
    // healthy batch. Record it, leave no file so a later run retries it, move on.
    // The same prompt is not reliably refused - seated-meditation was refused in
    // one run and generated in the next - so this is a per-attempt verdict, not a
    // permanent property of the row.
    if (/FLOW_POLICY_REFUSED/.test(String(lastErr))) {
      log(`  REFUSED ${i + 1}/${batch.jobs.length} ${job.output.filename} — content policy, continuing`);
      policyRefused.push(job.output.filename);
      results.push({ ...job._row, filename: job.output.filename, mediaType: job.type, status: "refused_policy", error: String(lastErr) });
      try { saveLedger(results); } catch (e) { log(`  ledger write failed: ${e.message}`); }
      await new Promise((r) => setTimeout(r, settle));
      continue;
    }

    if (/FLOW_REFUSED/.test(String(lastErr))) {
      log(`  REFUSED ${i + 1}/${batch.jobs.length} ${job.output.filename}`);
      log(`        ${lastErr}`);
      log(`        ${diagnose(String(lastErr))}`);
      for (const rest of batch.jobs.slice(i)) results.push({ ...rest._row, filename: rest.output.filename, mediaType: rest.type, status: "skipped", error: "aborted: Flow refused" });
      break;
    }

    const ok = done && (done.status === "done" || done.status === "downloaded");
    const problem = ok ? verifyLanded(job.output.filename, jobStartedAt, job.type) : null;
    if (problem) {
      // A rejected download MUST NOT stay in OUTDIR under the correct name. If it
      // does, the next run finds the filename, skips the row, and the wrong image
      // becomes permanent — the failure the check exists to prevent, made durable.
      const bad = landedPath(job.output.filename, job.type);
      if (bad) {
        const q = path.join(OUTDIR, "_rejected");
        fs.mkdirSync(q, { recursive: true });
        const dest = path.join(q, path.basename(bad));
        try { fs.renameSync(bad, dest); log(`        quarantined -> _rejected/${path.basename(bad)}`); }
        catch (e) { log(`        COULD NOT quarantine ${bad}: ${e.message} — delete it by hand`); }
      }
      log(`  FAIL ${i + 1}/${batch.jobs.length} ${job.output.filename} — ${problem}`);
      consecutive += 1;
      results.push({ ...job._row, filename: job.output.filename, mediaType: job.type, status: "error", error: problem,
                     mediaId: (done && done.mediaId) || null });
    } else {
      log(`  ${ok ? "ok  " : "FAIL"} ${i + 1}/${batch.jobs.length} ${job.output.filename}${ok ? "" : " — " + lastErr}`);
      consecutive = ok ? 0 : consecutive + 1;
      results.push({ ...job._row, filename: job.output.filename, mediaType: job.type, status: ok ? done.status : "error",
                     error: ok ? null : lastErr, mediaId: (done && done.mediaId) || null });
    }

    // Persist after EVERY job, not only at the end of the batch.
    //
    // The ledger is now the record of which media id belongs to which food, and
    // that is precisely what a crashed or killed batch needs to have kept. A
    // single write at batch end loses the ids for every job in a run that dies
    // — including the failed ones, which are the rows the id exists to rescue.
    // Writing ~25 small JSON files per batch is free next to regenerating.
    try { saveLedger(results); } catch (e) { log(`  ledger write failed: ${e.message}`); }
    // A timeout is usually a SLOW SUCCESS: the card failed to bind, the runner gave
    // up, and the image lands a minute later — reconciliation then recovers it. On
    // 2026-07-28 six consecutive timeouts tripped the backoff at 75% and stopped an
    // unattended run; five of the six were recovered seconds later. Counting them as
    // failures measured the wrong thing. Only genuinely lost work counts here.
    const recoverableTimeout = !ok && /timeout/i.test(String(lastErr || ""));
    recent.push(!!ok && !problem ? true : recoverableTimeout ? true : false);
    if (recent.length > 20) recent.shift();
    const rate = stallRate();
    if (rate > 0.6) {
      log(`  BACKING OFF — ${Math.round(rate * 100)}% of the last ${recent.length} jobs failed unrecoverably.`);
      log("        Timeouts are excluded from this rate because they usually reconcile. This is");
      log("        real lost work, so stopping rather than continuing to submit.");
      for (const rest of batch.jobs.slice(i + 1)) results.push({ ...rest._row, filename: rest.output.filename, mediaType: rest.type, status: "skipped", error: "aborted: sustained failure rate" });
      break;
    }
    if (rate > 0.3 && settle < 60000) {
      settle = Math.min(60000, Math.round(settle * 1.5));
      log(`  pacing: ${Math.round(rate * 100)}% recent failures, settle -> ${settle} ms`);
    } else if (rate === 0 && recent.length >= 12 && settle > SETTLE) {
      settle = Math.max(SETTLE, Math.round(settle / 1.5));
      log(`  pacing: recovered, settle -> ${settle} ms`);
    }
    // Let the page return to a stable state before the next submission.
    await new Promise((r) => setTimeout(r, settle));
  }
  const stalls = results.filter((r) => /timeout/i.test(String(r.error || ""))).length;
  if (stalls) log(`  ${stalls}/${results.length} job(s) stalled on card binding (recovered below if their image landed)`);
  if (skippedExisting) log(`  skipped ${skippedExisting} row(s) already present on disk (--force to regenerate)`);
  if (policyRefused.length) {
    log(`  ${policyRefused.length} row(s) refused on content policy - no file written, still queued:`);
    for (const f of policyRefused) log(`        ${f}`);
    log("        Re-running may clear them; a row refused repeatedly needs its prompt reworded.");
  }
  if (!has("dry-run")) { await new Promise((r) => setTimeout(r, 8000)); reconcile(results, batchStartedAt); }
  const bad = results.filter((r) => !["done", "downloaded", "dry", "skipped"].includes(r.status));
  const skipped = results.filter((r) => r.status === "skipped");
  const resultPath = path.join(DIR, "results", name.replace(/\.json$/, "-results.json"));
  fs.mkdirSync(path.dirname(resultPath), { recursive: true });
  fs.writeFileSync(resultPath, JSON.stringify({ batch: batch.batch, results }, null, 2));
  saveLedger(results);
  // A batch that aborted goes back to queue/ untouched, not to failed/: nothing was
  // wrong with its data and the whole batch should re-run once the tab is fixed.
  if (skipped.length) {
    log(`      batch left in queue/ — fix the environment and re-run, no data change needed`);
    return false;
  }
  if (name === "_current-slice.json") {
    log(`END   slice — ${results.length - bad.length} ok, ${bad.length} failed`);
    log(`      python3 status.py --out ${OUTDIR}   to see what remains`);
    return bad.length === 0;
  }
  const dest = path.join(bad.length ? FAIL : DONE, name);
  fs.renameSync(file, dest);
  log(`END   ${name} — ${results.length - bad.length} ok, ${bad.length} failed -> ${path.basename(dest)}`);
  log(`      validate before continuing:  python3 validate_batch.py --batch ${batch.batch} --images ${OUTDIR || "<downloads>"}`);
  return bad.length === 0;
}

async function main() {
  if (!has("dry-run") && !(await preflight())) process.exit(1);
  if (fs.existsSync(JOBS_FILE) && !has("use-batches")) {
    const all = JSON.parse(fs.readFileSync(JOBS_FILE, "utf8"));
    seedFromDisk();
    for (const job of all.jobs) extensionsFor(job.type);
    const todo = all.jobs.filter((j) => !landedPath(j.output.filename, j.type));
    log(`master list ${all.jobs.length} prompts — ${all.jobs.length - todo.length} already done, ${todo.length} remaining`);
    if (!todo.length) { log("nothing left to generate"); return; }
    const slice = todo.slice(0, LIMIT);
    log(`this run: ${slice.length} (--limit ${LIMIT})`);
    const tmp = path.join(DIR, "results", "_current-slice.json");
    fs.mkdirSync(path.dirname(tmp), { recursive: true });
    fs.writeFileSync(tmp, JSON.stringify({ batch: "slice", count: slice.length, styleHash: all.styleHash, jobs: slice }, null, 2));
    await runBatch(tmp);
    return;
  }
  log(`runner watching ${Q} (bridge ${BRIDGE}, out ${OUTDIR || "Chrome Downloads"})`);
  for (;;) {
    const files = fs.readdirSync(Q).filter((f) => /^batch-\d+\.json$/.test(f)).sort();
    if (files.length) {
      await runBatch(path.join(Q, files[0]));
      if (has("once")) { log("--once set, stopping"); return; }
      log("PAUSED — validate this batch, then move the next batch file into queue/ (or re-run with --auto)");
      if (!has("auto")) return;
    } else {
      await new Promise((r) => setTimeout(r, POLL));
    }
  }
}

main().catch((e) => { log("fatal: " + e.message); process.exit(1); });
