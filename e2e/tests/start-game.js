/**
 * start-game.js
 *
 * Opens two browser windows, signs in as Guest in each, starts matchmaking,
 * and waits until both players are matched into a game.
 * The windows are left open so you can continue manual testing.
 *
 * Prerequisites:
 *   1. Firebase emulators running:
 *        firebase emulators:start
 *
 *   2. Flutter web server running in PROFILE mode on port 3000:
 *        flutter run --profile -d web-server --web-port 3000
 *
 *      ⚠️  Use profile mode, not debug mode. Debug mode loads 700+ JS modules
 *          which takes too long before the first render.
 *
 *   3. Dependencies installed (first time only):
 *        npm install         (in the e2e/ directory)
 *        npm run install:browsers
 *
 * Run:
 *   npm run start-game
 *
 * Override the app URL:
 *   APP_URL=http://localhost:5000 npm run start-game
 *
 * Press Ctrl+C when done with manual testing.
 */

const { chromium } = require('playwright');

const APP_URL = process.env.APP_URL || 'http://localhost:3000';

/**
 * Use Chrome DevTools Protocol to move + resize a browser window so it fits
 * fully on screen. Call after page.goto() so Chrome has created the window.
 */
async function positionWindow(page, left, top, width, height) {
  const session = await page.context().newCDPSession(page);
  try {
    const { windowId } = await session.send('Browser.getWindowForTarget');
    await session.send('Browser.setWindowBounds', {
      windowId,
      bounds: { left, top, width, height },
    });
  } finally {
    await session.detach();
  }
}

// How long to wait for individual elements (covers boot + render + Firebase init)
const ELEMENT_TIMEOUT_MS = 120_000;

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function log(player, msg) {
  const tag = player ? `[${player}]` : '[setup ]';
  console.log(`  ${tag} ${msg}`);
}

/**
 * Enable Flutter web's semantic overlay.
 *
 * Flutter web (CanvasKit renderer) renders to a <canvas>. DOM interaction is
 * only possible through the flt-semantics overlay which is off-screen by
 * default. We wait for the placeholder to appear (dynamic — handles variable
 * load times), reposition it into the viewport, click it, then verify the
 * semantic tree is populated before continuing.
 */
async function enableSemantics(page, player) {
  log(player, 'Waiting for Flutter to initialise…');

  // Wait for the placeholder to appear — this signals Flutter has booted
  await page.locator('flt-semantics-placeholder').waitFor({ timeout: ELEMENT_TIMEOUT_MS });

  // Move the off-screen placeholder into viewport so Playwright can click it
  await page.evaluate(() => {
    const el = document.querySelector('flt-semantics-placeholder');
    if (el) {
      el.style.cssText = [
        'position:fixed!important',
        'top:0!important',
        'left:0!important',
        'width:100px!important',
        'height:100px!important',
        'z-index:999999!important',
        'opacity:0.01!important',
      ].join(';');
    }
  });

  await page.locator('flt-semantics-placeholder').click({ timeout: 5000 });

  // Wait until the semantic tree actually has button nodes (app has rendered UI)
  await page.locator('flt-semantics[role="button"]').first().waitFor({ timeout: ELEMENT_TIMEOUT_MS });
  log(player, 'Semantics enabled');
}

/**
 * Find a button by its visible text content.
 * Flutter semantic buttons have role="button" and text content (not aria-label).
 */
function btn(page, label) {
  return page.locator(`flt-semantics[role="button"]:has-text("${label}")`);
}

async function waitForBtn(page, label) {
  const locator = btn(page, label);
  await locator.waitFor({ timeout: ELEMENT_TIMEOUT_MS });
  return locator;
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-player flows
// ─────────────────────────────────────────────────────────────────────────────

async function signInAsGuest(page, player) {
  log(player, 'Clicking Sign In…');
  await (await waitForBtn(page, 'Sign In')).click();

  log(player, 'Waiting for auth screen…');
  await (await waitForBtn(page, 'Play as Guest')).click();
  log(player, 'Clicked Play as Guest');

  // Wait for home screen to re-appear with New Game button
  await waitForBtn(page, 'New Game');
  log(player, 'Signed in — home screen ready');
}

async function startMatchmaking(page, player) {
  await (await waitForBtn(page, 'New Game')).click();
  log(player, 'Clicked New Game — entering matchmaking');
}

async function waitForGameStart(page, player) {
  // Flutter's semantic tree nests elements, so text appears in multiple ancestor
  // nodes. Use .first() to avoid Playwright's strict-mode single-match requirement.
  const searching = page.locator('flt-semantics:has-text("Looking for opponent")').first();

  // Confirm we're in the matchmaking screen
  await searching.waitFor({ timeout: ELEMENT_TIMEOUT_MS });
  log(player, 'In matchmaking queue');

  // Wait for it to disappear (MatchmakingScreen replaced by GameScreen)
  await searching.waitFor({ state: 'hidden', timeout: ELEMENT_TIMEOUT_MS });
  log(player, 'Game started!');
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log('\n═══════════════════════════════════════════════');
  console.log('   CallMyWord — Gameplay Test Setup');
  console.log('═══════════════════════════════════════════════\n');
  console.log(`  App URL  : ${APP_URL}`);
  console.log('  Press Ctrl+C when you are done testing.\n');

  const browser = await chromium.launch({
    headless: false,
    // WebGL flags help CanvasKit render correctly
    args: ['--use-gl=angle', '--enable-webgl', '--ignore-gpu-blocklist'],
  });

  // Two isolated contexts = two independent Firebase auth sessions.
  // 430×720 fits the full game UI (keyboard included) on small monitors.
  const [ctx1, ctx2] = await Promise.all([
    browser.newContext({ viewport: { width: 430, height: 720 } }),
    browser.newContext({ viewport: { width: 430, height: 720 } }),
  ]);

  const [p1, p2] = await Promise.all([ctx1.newPage(), ctx2.newPage()]);

  // ── Load the app ──────────────────────────────────────────────────────────
  log(null, 'Loading app in both windows…');
  await Promise.all([
    p1.goto(APP_URL, { waitUntil: 'domcontentloaded', timeout: 90_000 }),
    p2.goto(APP_URL, { waitUntil: 'domcontentloaded', timeout: 90_000 }),
  ]);

  // Position windows side-by-side at the top of the screen so the full
  // game UI (including the on-screen keyboard at the bottom) is visible.
  // Chrome's UI (tab bar + address bar) takes ~100px.
  // Window height = viewport (720) + Chrome chrome (~100) = 820px.
  // This fits on most monitors (768px physical at standard DPI = ~728px usable).
  const WIN_WIDTH = 460;   // a little wider than viewport for Chrome borders
  const WIN_HEIGHT = 820;  // 720px viewport + ~100px Chrome chrome
  await Promise.all([
    positionWindow(p1, 0,         0, WIN_WIDTH, WIN_HEIGHT),
    positionWindow(p2, WIN_WIDTH, 0, WIN_WIDTH, WIN_HEIGHT),
  ]);
  log(null, 'Windows positioned side-by-side');
  console.log();

  // ── Enable semantics ──────────────────────────────────────────────────────
  log(null, 'Activating Flutter semantics overlay…');
  await enableSemantics(p1, 'Player 1');
  await enableSemantics(p2, 'Player 2');
  console.log();

  // ── Sign in ───────────────────────────────────────────────────────────────
  log(null, 'Signing in…');
  await signInAsGuest(p1, 'Player 1');
  await signInAsGuest(p2, 'Player 2');
  console.log();

  // ── Matchmaking ───────────────────────────────────────────────────────────
  log(null, 'Starting matchmaking…');
  await startMatchmaking(p1, 'Player 1');
  await p1.waitForTimeout(800); // slight delay so P1 enters queue first
  await startMatchmaking(p2, 'Player 2');
  console.log();

  // ── Wait for match ────────────────────────────────────────────────────────
  log(null, 'Waiting for both players to be matched…');
  await Promise.all([
    waitForGameStart(p1, 'Player 1'),
    waitForGameStart(p2, 'Player 2'),
  ]);

  console.log('\n✅  Both players are in the game.');

  // Wait a moment for the game screen to fully render, then snapshot.
  await p1.waitForTimeout(2000);
  const screenshotsDir = require('path').join(__dirname, '..', 'screenshots');
  require('fs').mkdirSync(screenshotsDir, { recursive: true });
  const path = require('path');
  await p1.screenshot({ path: path.join(screenshotsDir, 'player1-game.png'), fullPage: false });
  await p2.screenshot({ path: path.join(screenshotsDir, 'player2-game.png'), fullPage: false });
  console.log('  Screenshots saved to e2e/screenshots/');

  console.log('    Windows are open — continue testing manually.');
  console.log('    Press Ctrl+C to quit.\n');

  // Keep the process (and browser windows) alive indefinitely
  await new Promise(() => {});
}

process.on('SIGINT', () => {
  console.log('\n\nBye!\n');
  process.exit(0);
});

main().catch((err) => {
  console.error('\n❌  Error:', err.message);
  process.exit(1);
});
