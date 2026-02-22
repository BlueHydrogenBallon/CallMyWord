/**
 * Dictionary service for word validation
 * Uses a comprehensive English word list for word game validation
 */

import { ENGLISH_WORDS } from "./words";

// Build prefix set for quick prefix validation
const VALID_PREFIXES = new Set<string>();
for (const word of ENGLISH_WORDS) {
  for (let i = 1; i <= word.length; i++) {
    VALID_PREFIXES.add(word.substring(0, i));
  }
}

/**
 * Check if a word exists in the dictionary
 */
export function isValidWord(word: string): boolean {
  return ENGLISH_WORDS.has(word.toLowerCase());
}

/**
 * Check if a prefix could lead to a valid word
 */
export function isValidPrefix(prefix: string): boolean {
  return VALID_PREFIXES.has(prefix.toLowerCase());
}

/**
 * Get words that start with a given prefix
 */
export function getWordsWithPrefix(prefix: string, limit = 10): string[] {
  const p = prefix.toLowerCase();
  const matches: string[] = [];

  for (const word of ENGLISH_WORDS) {
    if (word.startsWith(p) && word.length > p.length) {
      matches.push(word);
      if (matches.length >= limit) break;
    }
  }

  return matches;
}

/**
 * Validation result for challenge response
 */
export interface WordValidationResult {
  isValid: boolean;
  failureReason: string | null;
  checks: {
    startsWithFragment: boolean;
    isInDictionary: boolean;
    meetsMinLength: boolean;
    isLongerThanFragment: boolean;
  };
}

/**
 * Validate a claimed word during challenge response
 */
export function validateClaimedWord(
  claimedWord: string,
  fragment: string,
  minWordLength: number
): WordValidationResult {
  const word = claimedWord.toUpperCase();
  const frag = fragment.toUpperCase();

  const checks = {
    startsWithFragment: false,
    isInDictionary: false,
    meetsMinLength: false,
    isLongerThanFragment: false,
  };

  // Check 1: Starts with the fragment
  checks.startsWithFragment = word.startsWith(frag);
  if (!checks.startsWithFragment) {
    return {
      isValid: false,
      failureReason: `Word must start with "${fragment}"`,
      checks,
    };
  }

  // Check 2: Longer than fragment
  checks.isLongerThanFragment = word.length > frag.length;
  if (!checks.isLongerThanFragment) {
    return {
      isValid: false,
      failureReason: "Word must be longer than the current letters",
      checks,
    };
  }

  // Check 3: Meets minimum length
  checks.meetsMinLength = word.length >= minWordLength;
  if (!checks.meetsMinLength) {
    return {
      isValid: false,
      failureReason: `Word must be at least ${minWordLength} letters`,
      checks,
    };
  }

  // Check 4: Exists in dictionary
  checks.isInDictionary = isValidWord(word);
  if (!checks.isInDictionary) {
    return {
      isValid: false,
      failureReason: `"${claimedWord}" is not in the dictionary`,
      checks,
    };
  }

  // All checks passed
  return {
    isValid: true,
    failureReason: null,
    checks,
  };
}
