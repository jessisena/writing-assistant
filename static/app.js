/* Writing Assistant — vanilla JS frontend */
"use strict";

// ─── DOM references ───────────────────────────────────────────────────────────
const inputText   = /** @type {HTMLTextAreaElement} */ (document.getElementById("input-text"));
const processBtn  = document.getElementById("process-btn");
const btnLabel    = processBtn.querySelector(".btn-label");
const btnSpinner  = processBtn.querySelector(".btn-spinner");
const errorBanner = document.getElementById("error-banner");
const results     = document.getElementById("results");
const langLabel   = document.getElementById("lang-label");
const polishedEl  = document.getElementById("polished-text");
const summaryEl   = document.getElementById("summary-content");
const copyBtn     = document.getElementById("copy-btn");

// ─── Keyboard shortcut: Cmd+Enter submits ────────────────────────────────────
document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
    e.preventDefault();
    handleSubmit();
  }
});

processBtn.addEventListener("click", handleSubmit);

// ─── Copy button ─────────────────────────────────────────────────────────────
copyBtn.addEventListener("click", async () => {
  const text = polishedEl.textContent ?? "";
  try {
    await navigator.clipboard.writeText(text);
    copyBtn.textContent = "Copied";
    copyBtn.classList.add("copied");
    setTimeout(() => {
      copyBtn.textContent = "Copy";
      copyBtn.classList.remove("copied");
    }, 2000);
  } catch {
    // Clipboard API not available (e.g., non-HTTPS in some browsers)
    copyBtn.textContent = "Copy failed";
    setTimeout(() => { copyBtn.textContent = "Copy"; }, 2000);
  }
});

// ─── Main submit handler ──────────────────────────────────────────────────────
async function handleSubmit() {
  const text = inputText.value.trim();
  if (!text) {
    showError("Please paste some text before processing.");
    return;
  }

  const channel = getSelectedChannel();
  if (!channel) {
    showError("Please select a channel.");
    return;
  }

  setLoading(true);
  hideError();
  showSkeletonResults();

  try {
    const response = await fetch("/api/polish", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text, channel }),
    });

    if (!response.ok) {
      const body = await response.json().catch(() => ({ detail: "Unexpected error" }));
      throw new Error(body.detail ?? `Server error ${response.status}`);
    }

    const data = await response.json();
    renderResults(data);
  } catch (err) {
    hideResults();
    showError(err instanceof Error ? err.message : "Something went wrong. Please try again.");
  } finally {
    setLoading(false);
  }
}

// ─── State helpers ────────────────────────────────────────────────────────────
function setLoading(loading) {
  processBtn.disabled = loading;
  btnLabel.hidden = loading;
  btnSpinner.hidden = !loading;
}

function getSelectedChannel() {
  const checked = /** @type {HTMLInputElement|null} */ (
    document.querySelector('input[name="channel"]:checked')
  );
  return checked ? checked.value : null;
}

function showError(message) {
  errorBanner.textContent = message;
  errorBanner.hidden = false;
}

function hideError() {
  errorBanner.hidden = true;
  errorBanner.textContent = "";
}

function hideResults() {
  results.hidden = true;
}

// ─── Skeleton loading state ───────────────────────────────────────────────────
function showSkeletonResults() {
  langLabel.textContent = "";
  langLabel.className = "card-meta";

  polishedEl.innerHTML = `
    <div class="skeleton skeleton-line" style="width:92%"></div>
    <div class="skeleton skeleton-line" style="width:78%"></div>
    <div class="skeleton skeleton-line" style="width:85%"></div>
    <div class="skeleton skeleton-line"></div>
  `;
  summaryEl.innerHTML = `
    <div class="skeleton skeleton-line" style="width:60%"></div>
    <div class="skeleton skeleton-line" style="width:80%"></div>
    <div class="skeleton skeleton-line"></div>
  `;
  results.hidden = false;
}

// ─── Render final results ─────────────────────────────────────────────────────
function renderResults(data) {
  // Polished text
  polishedEl.textContent = data.polished_text;

  // Language label
  const label = data.was_translated
    ? `Translated from ${data.detected_language}`
    : data.detected_language;
  langLabel.textContent = label;
  langLabel.className = data.was_translated ? "card-meta translated" : "card-meta";

  // Learning summary
  if (data.was_translated || data.learning_summary === null) {
    summaryEl.innerHTML = `<p class="summary-skipped">
      Original was in ${escHtml(data.detected_language)} — the summary is only shown when you
      write directly in English, since that's when your own English patterns are visible.
    </p>`;
  } else {
    summaryEl.innerHTML = renderLearningSummary(data.learning_summary);
  }

  results.hidden = false;

  // Scroll results into view — they may be below the fold on short windows
  results.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

function renderLearningSummary(summary) {
  const sections = [];

  // Corrections
  if (summary.corrections && summary.corrections.length > 0) {
    const items = summary.corrections.map((c) => `
      <li class="correction-item">
        <span class="correction-before">${escHtml(c.original)}</span>
        <span class="correction-after">${escHtml(c.corrected)}</span>
        <span class="correction-why">${escHtml(c.why)}</span>
      </li>
    `).join("");
    sections.push(`
      <div class="summary-section">
        <p class="summary-label">Corrections</p>
        <ul class="summary-list">${items}</ul>
      </div>
    `);
  }

  // Grammar insight
  if (summary.grammar_insight) {
    sections.push(`
      <div class="summary-section">
        <p class="summary-label">Grammar insight</p>
        <p class="summary-insight">${escHtml(summary.grammar_insight)}</p>
      </div>
    `);
  }

  // Vocabulary
  if (summary.vocabulary && summary.vocabulary.length > 0) {
    const items = summary.vocabulary.map((v) => `
      <li class="vocab-item">
        <span class="vocab-term">${escHtml(v.term)}</span>
        <span class="vocab-meaning"> — ${escHtml(v.meaning)}</span>
        <div class="vocab-example">"${escHtml(v.example)}"</div>
      </li>
    `).join("");
    sections.push(`
      <div class="summary-section">
        <p class="summary-label">New vocabulary</p>
        <ul class="summary-list">${items}</ul>
      </div>
    `);
  }

  if (sections.length === 0) {
    return `<p class="summary-empty">Nothing to flag here — the text was already clean.</p>`;
  }

  return sections.join("");
}

// ─── Utilities ────────────────────────────────────────────────────────────────
function escHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ─── PWA: service worker + heartbeat ─────────────────────────────────────────
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").catch(() => {});
  });
}
setInterval(() => { fetch("/api/heartbeat", { method: "POST" }).catch(() => {}); }, 15000);
