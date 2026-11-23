import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

// --- Configuration ---
const __filename_local = fileURLToPath(import.meta.url);
const __dirname_local = path.dirname(__filename_local);
const WORDS_FILE = path.resolve(__dirname_local, "../utils/words_greek.txt");
const PROGRESS_FILE = path.resolve(__dirname_local, "progress.json");
const FAILED_FILE = path.resolve(__dirname_local, "failed-words.json");
const DELAY_MS = 1000;
const MAX_RETRIES = 3;
const TIMEOUT_MS = 10000;

// --- CLI args ---
const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
const limitIdx = args.indexOf("--limit");
const LIMIT = limitIdx !== -1 ? parseInt(args[limitIdx + 1], 10) : Infinity;

// --- Types ---
interface ProgressState {
  lastProcessedIndex: number;
  totalToProcess: number;
  updatedCount: number;
  failedCount: number;
  timestamp: string;
}

interface FailedWord {
  word: string;
  lineNumber: number;
  reason: string;
  timestamp: string;
}

interface EnglishEntry {
  lineIndex: number;
  word: string;
  posTag: string;
  englishDescription: string;
}

// --- Utility functions ---

function stripAccents(str: string): string {
  return str.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

function isEnglishDescription(description: string): boolean {
  // English if it has NO Greek characters and at least one ASCII letter
  const hasGreek = /[\u0370-\u03FF\u1F00-\u1FFF]/.test(description);
  const hasAsciiLetter = /[a-zA-Z]/.test(description);
  return !hasGreek && hasAsciiLetter;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchWithRetry(url: string): Promise<any> {
  for (let i = 0; i < MAX_RETRIES; i++) {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);

      const response = await fetch(url, {
        headers: {"User-Agent": "CallMyWord/1.0 (dictionary update script)"},
        signal: controller.signal,
      });

      clearTimeout(timeout);

      if (response.status === 429) {
        console.log(`  Rate limited, waiting ${2000 * (i + 1)}ms...`);
        await sleep(2000 * (i + 1));
        continue;
      }

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      return await response.json();
    } catch (e: any) {
      if (i === MAX_RETRIES - 1) throw e;
      console.log(`  Retry ${i + 1}/${MAX_RETRIES}: ${e.message}`);
      await sleep(2000 * (i + 1));
    }
  }
  throw new Error("Max retries exceeded");
}

// --- Wiktionary API ---

const POS_MAP: Record<string, string[]> = {
  "επίρρημα": ["Επίρρημα"],
  "ουσιαστικό": ["Ουσιαστικό"],
  "επίθετο": ["Επίθετο", "Μορφή επιθέτου"],
  "ρήμα": ["Ρήμα", "Μορφή ρήματος"],
  "επιφώνημα": ["Επιφώνημα"],
  "αντωνυμία": ["Αντωνυμία", "Πρόθεση", "Σύνδεσμος", "Μόριο"],
  "μόριο": ["Μόριο", "Σύνδεσμος", "Πρόθεση"],
  "σύνδεσμος": ["Σύνδεσμος", "Μόριο"],
  "πρόθεση": ["Πρόθεση", "Μόριο", "Σύνδεσμος"],
  "αριθμητικό": ["Αριθμητικό", "Επίθετο"],
};

async function findAccentedForm(
  uppercaseWord: string,
): Promise<string | null> {
  const lowercase = uppercaseWord.toLowerCase();

  const searchUrl =
    `https://el.wiktionary.org/w/api.php?action=query&list=search` +
    `&srsearch=${encodeURIComponent(lowercase)}&srnamespace=0&srlimit=10&format=json`;

  const data = await fetchWithRetry(searchUrl);
  const results = data?.query?.search || [];

  // Find exact match (after stripping accents)
  const strippedInput = stripAccents(lowercase);
  for (const result of results) {
    if (stripAccents(result.title) === strippedInput) {
      return result.title;
    }
  }

  // Also try direct page access (some words may not appear in search)
  const directUrl =
    `https://el.wiktionary.org/w/api.php?action=query` +
    `&titles=${encodeURIComponent(lowercase)}&format=json`;
  const directData = await fetchWithRetry(directUrl);
  const pages = directData?.query?.pages || {};
  const page = Object.values(pages)[0] as any;
  if (page && page.pageid && !page.missing) {
    return page.title;
  }

  return null;
}

async function fetchDefinition(
  accentedWord: string,
): Promise<string | null> {
  const extractUrl =
    `https://el.wiktionary.org/w/api.php?action=query` +
    `&titles=${encodeURIComponent(accentedWord)}&prop=extracts&explaintext=1&format=json`;

  const data = await fetchWithRetry(extractUrl);
  const pages = data?.query?.pages || {};
  const page = Object.values(pages)[0] as any;

  return page?.extract || null;
}

function extractDefinitionFromText(
  plainText: string,
  posTag: string,
): string | null {
  const targetHeaders = POS_MAP[posTag] || [posTag];
  const lines = plainText.split("\n");

  // Try matching the exact POS section first
  for (const header of targetHeaders) {
    const definition = extractFromSection(lines, header);
    if (definition) return definition;
  }

  // Fallback: try any section that has a definition
  const allHeaders = [
    "Ουσιαστικό", "Επίθετο", "Ρήμα", "Επίρρημα",
    "Επιφώνημα", "Αντωνυμία", "Πρόθεση", "Σύνδεσμος", "Μόριο",
  ];
  for (const header of allHeaders) {
    if (targetHeaders.includes(header)) continue; // Already tried
    const definition = extractFromSection(lines, header);
    if (definition) return definition;
  }

  return null;
}

function extractFromSection(lines: string[], sectionName: string): string | null {
  // Find the section header (=== Sectionname === or == Sectionname ==)
  const headerIndex = lines.findIndex((l) => {
    const trimmed = l.trim();
    return (
      trimmed === `=== ${sectionName} ===` ||
      trimmed === `== ${sectionName} ==` ||
      trimmed === `===${sectionName}===` ||
      trimmed === `==${sectionName}==`
    );
  });

  if (headerIndex === -1) return null;

  const defLines: string[] = [];
  for (let i = headerIndex + 1; i < lines.length; i++) {
    const line = lines[i].trim();
    // Stop at next section header
    if (/^={2,}/.test(line)) break;
    if (line === "") continue;

    // Skip metadata-like lines
    if (line.startsWith("≈") || line.startsWith("~")) continue;
    if (/^(ΔΦΑ|IPA|Ετυμολογία|Συνώνυμα|Αντώνυμα|Παράγωγα|Σύνθετα|Μεταφράσεις|Αναφορές|Πηγές)/i.test(line)) continue;

    defLines.push(line);
  }

  if (defLines.length === 0) return null;

  // Skip first line if it's just the word + gender/type info
  let startIdx = 0;
  if (defLines[0]) {
    const first = defLines[0];
    // Lines like "άρμα ουδέτερο" or "αγάν ποσοτικό επίρρημα"
    if (/^[\u0370-\u03FF\u1F00-\u1FFF\u0386-\u03CE]+\s+(ουδέτερο|αρσενικό|θηλυκό|αρσ\.|θηλ\.|ουδ\.|ποσοτικό|τροπικό|χρονικό)/.test(first)) {
      startIdx = 1;
    }
  }

  const definition = defLines.slice(startIdx).join(" ").trim();

  // Clean up: remove excessive whitespace, limit length
  const cleaned = definition.replace(/\s+/g, " ").trim();
  if (cleaned.length === 0) return null;

  // Limit to ~500 chars to match file style
  if (cleaned.length > 500) {
    return cleaned.substring(0, 500).replace(/\s+\S*$/, "");
  }

  return cleaned;
}

// --- Progress management ---

function loadProgress(): ProgressState | null {
  try {
    if (fs.existsSync(PROGRESS_FILE)) {
      return JSON.parse(fs.readFileSync(PROGRESS_FILE, "utf-8"));
    }
  } catch {
    // Ignore corrupt progress file
  }
  return null;
}

function saveProgress(state: ProgressState): void {
  fs.writeFileSync(PROGRESS_FILE, JSON.stringify(state, null, 2), "utf-8");
}

function loadFailedWords(): FailedWord[] {
  try {
    if (fs.existsSync(FAILED_FILE)) {
      return JSON.parse(fs.readFileSync(FAILED_FILE, "utf-8"));
    }
  } catch {
    // Ignore
  }
  return [];
}

function saveFailedWords(words: FailedWord[]): void {
  fs.writeFileSync(FAILED_FILE, JSON.stringify(words, null, 2), "utf-8");
}

// --- Main ---

async function main(): Promise<void> {
  console.log("=== Greek Dictionary Description Updater ===");
  console.log(`Dry run: ${DRY_RUN}`);
  console.log(`Limit: ${LIMIT === Infinity ? "none" : LIMIT}`);
  console.log();

  // Read the file (handle CRLF line endings)
  const rawContent = fs.readFileSync(WORDS_FILE, "utf-8");
  const hasCRLF = rawContent.includes("\r\n");
  const lines = rawContent.split(/\r?\n/);
  console.log(`Total lines in file: ${lines.length} (line endings: ${hasCRLF ? "CRLF" : "LF"})`);

  // Identify English-description entries
  const LINE_REGEX = /^(\S+) - \(([^)]+)\) (.+)$/;
  const englishEntries: EnglishEntry[] = [];

  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(LINE_REGEX);
    if (!match) continue;

    const [, word, posTag, description] = match;
    if (isEnglishDescription(description)) {
      englishEntries.push({
        lineIndex: i,
        word,
        posTag,
        englishDescription: description,
      });
    }
  }

  console.log(`Found ${englishEntries.length} entries with English descriptions`);
  console.log();

  // Load progress
  const existingProgress = loadProgress();
  let startFrom = 0;
  let updatedCount = 0;
  let failedCount = 0;
  const failedWords = loadFailedWords();

  if (existingProgress && !DRY_RUN) {
    startFrom = existingProgress.lastProcessedIndex + 1;
    updatedCount = existingProgress.updatedCount;
    failedCount = existingProgress.failedCount;
    console.log(`Resuming from entry ${startFrom}/${englishEntries.length} (${updatedCount} updated, ${failedCount} failed)`);
    console.log();
  }

  const toProcess = Math.min(englishEntries.length, startFrom + LIMIT);

  for (let idx = startFrom; idx < toProcess; idx++) {
    const entry = englishEntries[idx];
    const progress = `[${idx + 1}/${englishEntries.length}]`;

    try {
      process.stdout.write(`${progress} ${entry.word} (${entry.posTag})... `);

      // Step 1: Find accented form
      const accentedForm = await findAccentedForm(entry.word);
      if (!accentedForm) {
        console.log("SKIP: not found on Wiktionary");
        failedWords.push({
          word: entry.word,
          lineNumber: entry.lineIndex + 1,
          reason: "not_found_on_wiktionary",
          timestamp: new Date().toISOString(),
        });
        failedCount++;
        saveFailedWords(failedWords);
        saveProgress({lastProcessedIndex: idx, totalToProcess: englishEntries.length, updatedCount, failedCount, timestamp: new Date().toISOString()});
        await sleep(DELAY_MS);
        continue;
      }

      // Step 2: Fetch definition
      const extractText = await fetchDefinition(accentedForm);
      if (!extractText) {
        console.log(`SKIP: no extract for "${accentedForm}"`);
        failedWords.push({
          word: entry.word,
          lineNumber: entry.lineIndex + 1,
          reason: "no_extract_text",
          timestamp: new Date().toISOString(),
        });
        failedCount++;
        saveFailedWords(failedWords);
        saveProgress({lastProcessedIndex: idx, totalToProcess: englishEntries.length, updatedCount, failedCount, timestamp: new Date().toISOString()});
        await sleep(DELAY_MS);
        continue;
      }

      // Step 3: Parse definition
      const greekDef = extractDefinitionFromText(extractText, entry.posTag);
      if (!greekDef) {
        console.log(`SKIP: no ${entry.posTag} definition in extract`);
        failedWords.push({
          word: entry.word,
          lineNumber: entry.lineIndex + 1,
          reason: `no_definition_for_pos_${entry.posTag}`,
          timestamp: new Date().toISOString(),
        });
        failedCount++;
        saveFailedWords(failedWords);
        saveProgress({lastProcessedIndex: idx, totalToProcess: englishEntries.length, updatedCount, failedCount, timestamp: new Date().toISOString()});
        await sleep(DELAY_MS);
        continue;
      }

      // Step 4: Update the line
      const newLine = `${entry.word} - (${entry.posTag}) ${greekDef}`;
      const preview = greekDef.length > 60 ? greekDef.substring(0, 60) + "..." : greekDef;
      console.log(`OK: "${preview}"`);

      if (!DRY_RUN) {
        lines[entry.lineIndex] = newLine;
      }

      updatedCount++;
      saveProgress({lastProcessedIndex: idx, totalToProcess: englishEntries.length, updatedCount, failedCount, timestamp: new Date().toISOString()});
    } catch (e: any) {
      console.log(`ERROR: ${e.message}`);
      failedWords.push({
        word: entry.word,
        lineNumber: entry.lineIndex + 1,
        reason: `error: ${e.message}`,
        timestamp: new Date().toISOString(),
      });
      failedCount++;
      saveFailedWords(failedWords);
      saveProgress({lastProcessedIndex: idx, totalToProcess: englishEntries.length, updatedCount, failedCount, timestamp: new Date().toISOString()});
    }

    await sleep(DELAY_MS);
  }

  // Write updated file
  if (!DRY_RUN && updatedCount > 0) {
    console.log();
    console.log("Writing updated file...");
    const separator = hasCRLF ? "\r\n" : "\n";
    fs.writeFileSync(WORDS_FILE, lines.join(separator), "utf-8");
    console.log("File saved.");
  }

  // Summary
  console.log();
  console.log("=== Summary ===");
  console.log(`Total English entries: ${englishEntries.length}`);
  console.log(`Updated: ${updatedCount}`);
  console.log(`Failed: ${failedCount}`);
  console.log(`Remaining: ${englishEntries.length - (updatedCount + failedCount)}`);

  if (failedWords.length > 0) {
    console.log(`\nFailed words saved to: ${FAILED_FILE}`);
  }

  // Clean up progress file when done
  if (updatedCount + failedCount >= englishEntries.length && !DRY_RUN) {
    if (fs.existsSync(PROGRESS_FILE)) {
      fs.unlinkSync(PROGRESS_FILE);
      console.log("Progress file cleaned up (all entries processed).");
    }
  }
}

main().catch((e) => {
  console.error("Fatal error:", e);
  process.exit(1);
});
