import 'app_config.dart';

/// Scrabble-style letter point values for English
const Map<String, int> _englishLetterPoints = {
  'A': 1, 'B': 3, 'C': 3, 'D': 2, 'E': 1,
  'F': 4, 'G': 2, 'H': 4, 'I': 1, 'J': 8,
  'K': 5, 'L': 1, 'M': 3, 'N': 1, 'O': 1,
  'P': 3, 'Q': 10, 'R': 1, 'S': 1, 'T': 1,
  'U': 1, 'V': 4, 'W': 4, 'X': 8, 'Y': 4,
  'Z': 10,
};

/// Scrabble-style letter point values for Greek
const Map<String, int> _greekLetterPoints = {
  'Α': 1, 'Β': 8, 'Γ': 4, 'Δ': 4, 'Ε': 1,
  'Ζ': 10, 'Η': 1, 'Θ': 10, 'Ι': 1, 'Κ': 2,
  'Λ': 3, 'Μ': 3, 'Ν': 1, 'Ξ': 10, 'Ο': 1,
  'Π': 2, 'Ρ': 2, 'Σ': 1, 'Τ': 1, 'Υ': 2,
  'Φ': 8, 'Χ': 8, 'Ψ': 10, 'Ω': 3,
};

/// Calculate total point value of a word (Scrabble-style)
int calculateWordPoints(String word) {
  final points = kIsGreek ? _greekLetterPoints : _englishLetterPoints;
  return word.toUpperCase().split('').fold(0, (sum, ch) => sum + (points[ch] ?? 0));
}

/// App-wide strings. Returns Greek or English based on the build-time
/// DICTIONARY constant (`--dart-define=DICTIONARY=greek`).
class S {
  S._();

  // ─── Common ───────────────────────────────────────────────────────────────

  static String get cancel => kIsGreek ? 'Ακύρωση' : 'Cancel';
  static String get back => kIsGreek ? 'Πίσω' : 'Back';
  static String get submit => kIsGreek ? 'Υποβολή' : 'Submit';
  static String get accept => kIsGreek ? 'Αποδοχή' : 'Accept';
  static String get decline => kIsGreek ? 'Απόρριψη' : 'Decline';
  static String get retry => kIsGreek ? 'Δοκιμή ξανά' : 'Retry';
  static String get goBack => kIsGreek ? 'Πίσω' : 'Go Back';
  static String get ok => kIsGreek ? 'ΟΚ' : 'OK';
  static String get online => kIsGreek ? 'Σε σύνδεση' : 'Online';
  static String get offline => kIsGreek ? 'Εκτός σύνδεσης' : 'Offline';
  static String get challenge => kIsGreek ? 'Πρόκληση' : 'Challenge';
  static String get somethingWentWrong => kIsGreek ? 'Κάτι πήγε στραβά' : 'Something went wrong';
  static String get timeExpired => kIsGreek ? 'Ο χρόνος έληξε' : 'Time expired';
  static String get tryAgain => kIsGreek ? 'Δοκιμή ξανά' : 'Try Again';
  static String get no => kIsGreek ? 'Όχι' : 'No';
  static String get close => kIsGreek ? 'Κλείσιμο' : 'Close';
  static String errorMsg(String e) => kIsGreek ? 'Σφάλμα: $e' : 'Error: $e';

  // ─── Home Screen ──────────────────────────────────────────────────────────

  static String get appSubtitle =>
      kIsGreek ? 'Παιχνίδι λέξεων με σειρά' : 'A turn-based word game';
  static String get signIn => kIsGreek ? 'Σύνδεση' : 'Sign In';
  static String get newGame => kIsGreek ? 'Νέο Παιχνίδι' : 'New Game';
  static String get challengeAFriend =>
      kIsGreek ? 'Πρόκληση σε Φίλο' : 'Challenge a Friend';
  static String get multiplayerParty =>
      kIsGreek ? 'Ομαδικό Παιχνίδι' : 'Multiplayer Party';
  static String get howToPlay =>
      kIsGreek ? 'Πώς να Παίξεις' : 'How to Play';
  static String get gotIt => kIsGreek ? 'Το κατάλαβα!' : 'Got it!';
  static String get upgradeAccount =>
      kIsGreek ? 'Αναβάθμιση Λογαριασμού' : 'Upgrade Account';
  static String get signOut => kIsGreek ? 'Αποσύνδεση' : 'Sign Out';
  static String get guest => kIsGreek ? 'Επισκέπτης' : 'Guest';
  static String challengesYou(String name) =>
      kIsGreek ? '$name σε προκαλεί!' : '$name challenges you!';
  static String tapToRespond(int seconds) => kIsGreek
      ? 'Πάτα για να απαντήσεις (${seconds}s)'
      : 'Tap to respond (${seconds}s left)';
  static String get howToPlayInstructions => kIsGreek
      ? '1. Οι παίκτες εναλλάσσονται προσθέτοντας ένα γράμμα για να χτίσουν ένα τμήμα λέξης.\n\n'
          '2. Πρέπει πάντα να χτίζεις προς μια έγκυρη λέξη.\n\n'
          '3. Αν πιστεύεις ότι ο αντίπαλός σου κάνει μπλόφα (δεν χτίζει προς πραγματική λέξη), κάνε πρόκληση!\n\n'
          '4. Όταν σε προκαλέσουν, πρέπει να αποδείξεις τη λέξη σου συμπληρώνοντάς την.\n\n'
          '5. Ο πρώτος παίκτης που φτάσει 50 πόντους κερδίζει!\n\n'
          'Βαθμολόγηση:\n'
          '• Τα γράμματα έχουν αξία όπως στο Σκράμπλ\n'
          '• Νίκη σε άμυνα πρόκλησης: Pot Λέξης + Μπόνους\n'
          '• Πιάσε μπλόφα: Μπόνους Μπλόφα'
      : '1. Players take turns adding one letter to build a word fragment.\n\n'
          '2. You must always be building toward a valid word.\n\n'
          '3. If you think your opponent is bluffing (not building toward a real word), challenge them!\n\n'
          '4. When challenged, you must prove your word by completing it.\n\n'
          '5. First player to reach 50 points wins!\n\n'
          'Scoring:\n'
          '• Letters are worth Scrabble points\n'
          '• Win a challenge defense: Word Pot + Word Bonus\n'
          '• Catch a bluff: Bluff Bonus';

  // ─── Game Screen ──────────────────────────────────────────────────────────

  static String get game => kIsGreek ? 'Παιχνίδι' : 'Game';
  static String get gameNotFound =>
      kIsGreek ? 'Το παιχνίδι δεν βρέθηκε' : 'Game not found';
  static String turnNumber(int n) =>
      kIsGreek ? 'Σειρά $n' : 'Turn $n';
  static String get you => kIsGreek ? 'Εσύ' : 'You';
  static String get startWithAnyLetter =>
      kIsGreek ? 'Ξεκίνα με οποιοδήποτε γράμμα' : 'Start with any letter';
  static String pot(int amount) => 'Pot: $amount';
  static String get challengeExclaim =>
      kIsGreek ? 'Πρόκληση!' : 'Challenge!';
  static String waitingFor(String name) =>
      kIsGreek ? 'Αναμονή για $name...' : 'Waiting for $name...';
  static String enterWordContaining(String word) => kIsGreek
      ? 'Πληκτρολόγησε μια έγκυρη λέξη που περιέχει "$word":'
      : 'Enter a valid word containing "$word":';
  static String get wordHintChallenge =>
      kIsGreek ? 'π.χ., ΕΦΗΜΕΡΗ' : 'e.g., FRAGILE';
  static String wordMustContain(String fragment) => kIsGreek
      ? 'Η λέξη πρέπει να περιέχει "$fragment"'
      : 'Word must contain "$fragment"';
  static String get wordMinLength => kIsGreek
      ? 'Η λέξη πρέπει να έχει τουλάχιστον 4 γράμματα'
      : 'Word must be at least 4 letters';
  static String get submitWord =>
      kIsGreek ? 'Υποβολή Λέξης' : 'Submit Word';
  static String get wordCalled =>
      kIsGreek ? 'Λέξη Δηλώθηκε!' : 'Word Called!';
  static String fragment(String f) =>
      kIsGreek ? 'Τμήμα: $f' : 'Fragment: $f';
  static String get howDoYouRespond =>
      kIsGreek ? 'Πώς απαντάς;' : 'How do you respond?';
  static String get continueWord =>
      kIsGreek ? 'Συνέχεια' : 'Continue';
  static String get acceptWord => kIsGreek ? 'Αποδοχή' : 'Accept';
  static String enterLongerWordStartingWith(String word) => kIsGreek
      ? 'Πληκτρολόγησε έγκυρη λέξη με μεγαλύτερη αξία που ξεκινά με "$word":'
      : 'Enter a higher-value valid word starting with "$word":';
  static String wordHintContinuation(String f) =>
      kIsGreek ? 'π.χ., $fΩΝΑ' : 'e.g., ${f}FYING';
  static String mustBeLongerThan(String word) => kIsGreek
      ? 'Πρέπει να είναι μεγαλύτερη από "$word" για να κερδίσεις!'
      : 'Must be longer than "$word" to win!';
  static String mustHaveHigherValueThan(String word, int pts) => kIsGreek
      ? 'Πρέπει να έχει περισσότερους πόντους από "$word" ($pts pts) για να κερδίσεις!'
      : 'Must have higher value than "$word" ($pts pts) to win!';
  static String get yourTurn => kIsGreek ? 'Σειρά σου' : 'Your turn';
  static String get opponentsTurn =>
      kIsGreek ? 'Σειρά αντιπάλου' : "Opponent's turn";
  static String get callWord =>
      kIsGreek ? 'Δήλωσε Λέξη' : 'Call Word';
  static String get callYourWord =>
      kIsGreek ? 'Δήλωσε τη Λέξη σου' : 'Call Your Word';
  static String currentFragment(String f) =>
      kIsGreek ? 'Τρέχον τμήμα: $f' : 'Current fragment: $f';
  static String get leaveGame =>
      kIsGreek ? 'Έξοδος από το Παιχνίδι;' : 'Leave Game?';
  static String get leaveGameConfirm =>
      kIsGreek ? 'Θα χάσεις το παιχνίδι και ο αντίπαλός σου θα κερδίσει.' : 'You will forfeit the game and your opponent will win.';
  static String get stay => kIsGreek ? 'Μείνε' : 'Stay';
  static String get leave => kIsGreek ? 'Έξοδος' : 'Leave';
  static String get potWon =>
      kIsGreek ? 'ΚΕΡΔΙΣΕΣ ΤΟ POT!' : 'POT WON!';
  static String get potLost =>
      kIsGreek ? 'ΕΧΑΣΕΣ ΤΟ POT' : 'POT LOST';
  static String points(int amount) =>
      '+$amount ${kIsGreek ? "πόντοι" : "pts"}';
  static String get bothWordsInvalid =>
      kIsGreek ? 'Και οι δύο λέξεις άκυρες' : 'Both words invalid';
  static String get notYourTurn =>
      kIsGreek ? 'Δεν είναι σειρά σου' : 'Not your turn';
  static String get invalidLetter =>
      kIsGreek ? 'Άκυρο γράμμα' : 'Invalid letter';
  static String get needMoreLetters => kIsGreek
      ? 'Χρειάζεσαι 2+ γράμματα για πρόκληση'
      : 'Need 2+ letters to challenge';
  static String get wordHintCallWord =>
      kIsGreek ? 'π.χ., ΑΛΟΓΟ' : 'e.g., HORSE';
  static String get muteSound =>
      kIsGreek ? 'Σίγαση ηχητικών' : 'Mute sound effects';
  static String get unmuteSound =>
      kIsGreek ? 'Ενεργοποίηση ηχητικών' : 'Unmute sound effects';
  static String get muteMusic =>
      kIsGreek ? 'Σίγαση μουσικής' : 'Mute music';
  static String get unmuteMusic =>
      kIsGreek ? 'Ενεργοποίηση μουσικής' : 'Unmute music';

  // ─── Game Over Screen ─────────────────────────────────────────────────────

  static String get victory => kIsGreek ? 'Νίκη!' : 'Victory!';
  static String get defeat => kIsGreek ? 'Ήττα' : 'Defeat';
  static String get finalWordFragment =>
      kIsGreek ? 'Τελικό τμήμα λέξης:' : 'Final word fragment:';
  static String get playAgain => kIsGreek ? 'Παίξε Ξανά' : 'Play Again';
  static String get backToHome => kIsGreek ? 'Αρχική' : 'Back to Home';
  static String winnerReachedScore(String name, int score) =>
      kIsGreek ? '$name έφτασε $score πόντους!' : '$name reached $score points!';
  static String winnerWonChallenge(String name) =>
      kIsGreek ? '$name κέρδισε την πρόκληση!' : '$name won the challenge!';
  static String get challengeFailedWordValid => kIsGreek
      ? 'Αποτυχία πρόκλησης - η λέξη ήταν έγκυρη!'
      : 'Challenge failed - word was valid!';
  static String get challengeTimedOut =>
      kIsGreek ? 'Η πρόκληση έληξε!' : 'Challenge timed out!';
  static String get opponentForfeited =>
      kIsGreek ? 'Ο αντίπαλος αποχώρησε' : 'Opponent forfeited';
  static String get wordsPlayed =>
      kIsGreek ? 'Λέξεις που παίχτηκαν' : 'Words Played';
  static String get wordValidLabel => kIsGreek ? 'Έγκυρη' : 'Valid';
  static String get wordInvalidLabel => kIsGreek ? 'Άκυρη' : 'Invalid';
  static String wonWithWord(String name, int pts) => kIsGreek
      ? '$name κέρδισε +$pts με τη λέξη:'
      : '$name won +$pts with the word:';
  static String get wonWithWordYou => kIsGreek
      ? 'Κέρδισες με τη λέξη:'
      : 'You won with the word:';
  static String wonWithWordYouPts(int pts) => kIsGreek
      ? 'Κέρδισες +$pts με τη λέξη:'
      : 'You won +$pts with the word:';
  static String wonChallenge(String name, int pts) => kIsGreek
      ? '$name κέρδισε την πρόκληση +$pts'
      : '$name won the challenge +$pts';
  static String wonChallengeYou(int pts) => kIsGreek
      ? 'Κέρδισες την πρόκληση +$pts'
      : 'You won the challenge +$pts';
  static String nextRoundIn(int n) => kIsGreek
      ? 'Ο επόμενος γύρος ξεκινά σε $n δευτ.'
      : 'Next round will begin in $n sec';
  static String get opponentLeftTitle =>
      kIsGreek ? 'Ο αντίπαλος έφυγε' : 'Opponent Left';
  static String opponentLeftBody(int seconds) => kIsGreek
      ? 'Αν δεν επιστρέψει σε ${seconds}s, κερδίζεις το παιχνίδι!'
      : 'If they don\'t return in ${seconds}s, you win!';
  static String get waitAndWin =>
      kIsGreek ? 'Περίμενε και κέρδισε' : 'Wait & Win';
  static String get quitAndLose =>
      kIsGreek ? 'Έξοδος (χάνεις)' : 'Quit (lose)';

  // ─── Rejoin Sheet ─────────────────────────────────────────────────────────

  static String get rejoinTitle => kIsGreek
      ? 'Άφησες ένα παιχνίδι σε εξέλιξη'
      : 'You left a game in progress';
  static String rejoinVs(String name) => kIsGreek ? 'εναντίον $name' : 'vs. $name';
  static String rejoinCurrentWord(String word) =>
      kIsGreek ? 'Τρέχον τμήμα: $word' : 'Current fragment: $word';
  static String rejoinWordPot(int pts) =>
      kIsGreek ? 'Pot λέξης: $pts πόντοι' : 'Word pot: $pts pts';
  static String rejoinSeconds(int s) =>
      kIsGreek ? '$s δευτερόλεπτα — επιστροφή αυτόματα!' : '$s seconds — auto-rejoining!';
  static String get rejoinNow => kIsGreek ? 'Επιστροφή Τώρα' : 'Rejoin Now';
  static String rejoinForfeit(String name) =>
      kIsGreek ? 'Όχι ευχαριστώ — $name κερδίζει' : 'No thanks — let $name win';

  // ─── Auth Screen ──────────────────────────────────────────────────────────

  static String get createAccount =>
      kIsGreek ? 'Δημιουργία Λογαριασμού' : 'Create Account';
  static String get playAsGuest =>
      kIsGreek ? 'Παίξε ως Επισκέπτης' : 'Play as Guest';
  static String get chooseNickname =>
      kIsGreek ? 'Επίλεξε Όνομα Χρήστη' : 'Choose a Username';
  static String get nicknameHint =>
      kIsGreek ? 'Το όνομά σου στο παιχνίδι' : 'Your name in game';
  static String get confirm => kIsGreek ? 'Επιβεβαίωση' : 'Confirm';
  static String get orSeparator => kIsGreek ? 'Ή' : 'OR';
  static String get displayName =>
      kIsGreek ? 'Όνομα Εμφάνισης' : 'Display Name';
  static String get username =>
      kIsGreek ? 'Όνομα Χρήστη' : 'Username';
  static String get yourNameInGame =>
      kIsGreek ? 'Το όνομά σου στο παιχνίδι' : 'Your name in game';
  static String get email => 'Email';
  static String get emailHint => 'your@email.com';
  static String get enterEmail => kIsGreek
      ? 'Παρακαλώ εισάγετε το email σας'
      : 'Please enter your email';
  static String get enterValidEmail => kIsGreek
      ? 'Παρακαλώ εισάγετε έγκυρο email'
      : 'Please enter a valid email';
  static String get password => kIsGreek ? 'Κωδικός' : 'Password';
  static String get enterPassword => kIsGreek
      ? 'Παρακαλώ εισάγετε τον κωδικό σας'
      : 'Please enter your password';
  static String get passwordMinLength => kIsGreek
      ? 'Ο κωδικός πρέπει να έχει τουλάχιστον 6 χαρακτήρες'
      : 'Password must be at least 6 characters';
  static String get noAccountFound => kIsGreek
      ? 'Δεν βρέθηκε λογαριασμός με αυτό το email'
      : 'No account found with this email';
  static String get incorrectPassword =>
      kIsGreek ? 'Λανθασμένος κωδικός' : 'Incorrect password';
  static String get accountAlreadyExists => kIsGreek
      ? 'Υπάρχει ήδη λογαριασμός με αυτό το email'
      : 'An account already exists with this email';
  static String get weakPassword =>
      kIsGreek ? 'Ο κωδικός είναι πολύ αδύναμος' : 'Password is too weak';
  static String get invalidEmail =>
      kIsGreek ? 'Μη έγκυρη διεύθυνση email' : 'Invalid email address';
  static String get authFailed => kIsGreek
      ? 'Αποτυχία σύνδεσης. Παρακαλώ δοκιμάστε ξανά.'
      : 'Authentication failed. Please try again.';
  static String get noAccountSignUp => kIsGreek
      ? 'Δεν έχεις λογαριασμό; Εγγράψου'
      : "Don't have an account? Sign up";
  static String get haveAccountSignIn => kIsGreek
      ? 'Έχεις ήδη λογαριασμό; Συνδέσου'
      : 'Already have an account? Sign in';

  // ─── Matchmaking Screen ───────────────────────────────────────────────────

  static String get findingGame =>
      kIsGreek ? 'Εύρεση Παιχνιδιού' : 'Finding Game';
  static String get lookingForOpponent =>
      kIsGreek ? 'Αναζήτηση αντιπάλου...' : 'Looking for opponent...';
  static String get matchmakingSubtitle => kIsGreek
      ? 'Συνήθως διαρκεί μερικά δευτερόλεπτα'
      : 'This usually takes a few seconds';
  static String get lobbyCancelled =>
      kIsGreek ? 'Η αναμονή ακυρώθηκε' : 'Lobby was cancelled';
  static String get matchmakingCancelled => kIsGreek
      ? 'Η εύρεση παιχνιδιού ακυρώθηκε'
      : 'Matchmaking was cancelled';

  // ─── Friends Screen ───────────────────────────────────────────────────────

  static String get friends => kIsGreek ? 'Φίλοι' : 'Friends';
  static String get inviteFriend =>
      kIsGreek ? 'Πρόσκληση Φίλου' : 'Invite Friend';
  static String onlineCount(int n) =>
      kIsGreek ? 'Σε σύνδεση ($n)' : 'Online ($n)';
  static String offlineCount(int n) =>
      kIsGreek ? 'Εκτός σύνδεσης ($n)' : 'Offline ($n)';
  static String get noFriendsYet =>
      kIsGreek ? 'Δεν έχεις φίλους ακόμα' : 'No friends yet';
  static String get inviteFriendsPrompt => kIsGreek
      ? 'Κάλεσε φίλους να παίξουν Call My Word μαζί!'
      : 'Invite friends to play Call My Word together!';
  static String get wantsToBeFriend =>
      kIsGreek ? 'Θέλει να γίνει φίλος σου' : 'Wants to be your friend';
  static String friendRequestCount(int n) =>
      kIsGreek ? 'Αιτήματα Φιλίας ($n)' : 'Friend Requests ($n)';
  static String isNowYourFriend(String name) =>
      kIsGreek ? '$name είναι πλέον φίλος σου!' : '$name is now your friend!';

  // ─── Invite Friend Dialog ─────────────────────────────────────────────────

  static String get inviteAFriend =>
      kIsGreek ? 'Πρόσκληση Φίλου' : 'Invite a Friend';
  static String get yourInviteCode =>
      kIsGreek ? 'Ο Κωδικός Πρόσκλησής σου' : 'Your Invite Code';
  static String get copy => kIsGreek ? 'Αντιγραφή' : 'Copy';
  static String get share => kIsGreek ? 'Κοινοποίηση' : 'Share';
  static String get haveFriendsCode =>
      kIsGreek ? 'Έχεις κωδικό φίλου;' : "Have a friend's code?";
  static String get enter6LetterCode =>
      kIsGreek ? 'Εισάγετε 6-ψήφιο κωδικό' : 'Enter 6-letter code';
  static String get addFriend =>
      kIsGreek ? 'Προσθήκη Φίλου' : 'Add Friend';
  static String get inviteCopied =>
      kIsGreek ? 'Ο κωδικός αντιγράφηκε!' : 'Invite copied to clipboard!';
  static String get enter6LetterCodeError => kIsGreek
      ? 'Παρακαλώ εισάγετε 6-ψήφιο κωδικό'
      : 'Please enter a 6-letter code';
  static String get friendRequestSent =>
      kIsGreek ? 'Αίτημα φιλίας εστάλη!' : 'Friend request sent!';

  // ─── Challenge Dialog ─────────────────────────────────────────────────────

  static String get challengeTitle =>
      kIsGreek ? 'Πρόκληση;' : 'Challenge?';
  static String challengeQuestion(String word) => kIsGreek
      ? 'Πιστεύεις ότι το "$word" δεν οδηγεί σε πραγματική λέξη;'
      : 'You think "$word" isn\'t leading to a real word?';
  static String get ifYouChallenge =>
      kIsGreek ? 'Αν κάνεις πρόκληση:' : 'If you challenge:';
  static String opponentMustProve(String name) => kIsGreek
      ? '$name πρέπει να αποδείξει ότι έχει έγκυρη λέξη'
      : '$name must prove they have a valid word';
  static String get ifTheyCant => kIsGreek
      ? "Αν δεν μπορεί, κερδίζεις το Μπόνους Μπλόφα!"
      : "If they can't, you win the Bluff Bonus!";
  static String get ifTheyCan => kIsGreek
      ? 'Αν μπορεί, κερδίζει το Pot Λέξης + Μπόνους'
      : 'If they can, they win the Word Pot + Bonus';

  // ─── Incoming Challenge Dialog ────────────────────────────────────────────

  static String get partyInvite =>
      kIsGreek ? 'Πρόσκληση Ομάδας!' : 'Party Invite!';
  static String get gameChallenge =>
      kIsGreek ? 'Πρόκληση Παιχνιδιού!' : 'Game Challenge!';
  static String get invitedToParty => kIsGreek
      ? 'σε προσκάλεσε σε ομαδικό παιχνίδι!'
      : 'invited you to a multiplayer party!';
  static String get wantsToPlay =>
      kIsGreek ? 'θέλει να παίξει μαζί σου!' : 'wants to play!';

  // ─── Challenge Waiting Screen ─────────────────────────────────────────────

  static String get waitingForLabel =>
      kIsGreek ? 'Αναμονή για' : 'Waiting for';
  static String get toAcceptChallenge => kIsGreek
      ? 'να αποδεχτεί την πρόκλησή σου...'
      : 'to accept your challenge...';
  static String get cancelChallenge =>
      kIsGreek ? 'Ακύρωση Πρόκλησης' : 'Cancel Challenge';
  static String get challengeExpired =>
      kIsGreek ? 'Η Πρόκληση Έληξε' : 'Challenge Expired';
  static String didNotRespond(String name) =>
      kIsGreek ? '$name δεν απάντησε εγκαίρως.' : '$name did not respond in time.';
  static String get challengeDeclined =>
      kIsGreek ? 'Απόρριψη Πρόκλησης' : 'Challenge Declined';
  static String declinedYourChallenge(String name) =>
      kIsGreek ? '$name απέρριψε την πρόκλησή σου.' : '$name declined your challenge.';
  static String get cancelChallengeQuestion =>
      kIsGreek ? 'Ακύρωση Πρόκλησης;' : 'Cancel Challenge?';
  static String get cancelChallengeConfirm => kIsGreek
      ? 'Είσαι σίγουρος ότι θέλεις να ακυρώσεις την πρόκληση;'
      : 'Are you sure you want to cancel this challenge?';
  static String get yesCancel =>
      kIsGreek ? 'Ναι, Ακύρωση' : 'Yes, Cancel';

  // ─── Party Setup Screen ───────────────────────────────────────────────────

  static String get createParty =>
      kIsGreek ? 'Δημιουργία Ομάδας' : 'Create Party';
  static String selectFriendsToInvite(int max) => kIsGreek
      ? 'Επέλεξε έως $max online φίλους'
      : 'Select up to $max online friends to invite';
  static String get noFriendsAddFirst => kIsGreek
      ? 'Πρόσθεσε πρώτα φίλους για ομαδικό παιχνίδι!'
      : 'Add friends first to create a multiplayer party!';
  static String selectedCount(int count, int max) =>
      kIsGreek ? 'Επιλεγμένοι: $count/$max' : 'Selected: $count/$max';

  // ─── Party Waiting Screen ─────────────────────────────────────────────────

  static String get partyLobby =>
      kIsGreek ? 'Αίθουσα Αναμονής' : 'Party Lobby';
  static String get gameStarting =>
      kIsGreek ? 'Το παιχνίδι ξεκινά...' : 'Game starting...';
  static String get partyCancelled =>
      kIsGreek ? 'Η ομάδα ακυρώθηκε' : 'Party was cancelled';
  static String get partyCancelledTitle =>
      kIsGreek ? 'Ομάδα ακυρώθηκε' : 'Party cancelled';
  static String playerCount(int count, int max) =>
      kIsGreek ? 'Παίκτες: $count/$max' : 'Players: $count/$max';
  static String get waitingForPlayer =>
      kIsGreek ? 'Αναμονή παίκτη...' : 'Waiting for player...';
  static String get host => kIsGreek ? 'Οικοδεσπότης' : 'Host';
  static String get joined => kIsGreek ? 'Συνδέθηκε' : 'Joined';
  static String startGame(int count) =>
      kIsGreek ? 'Έναρξη ($count παίκτες)' : 'Start Game ($count players)';
  static String get waitingForPlayers =>
      kIsGreek ? 'Αναμονή παικτών...' : 'Waiting for players...';
  static String get waitingForHostToStart => kIsGreek
      ? 'Αναμονή για τον οικοδεσπότη...'
      : 'Waiting for host to start...';
  static String get cancelParty =>
      kIsGreek ? 'Ακύρωση Ομάδας' : 'Cancel Party';
  static String get leaveParty =>
      kIsGreek ? 'Έξοδος από Ομάδα' : 'Leave Party';

  // ─── Friend List Item ─────────────────────────────────────────────────────

  static String get justNow => kIsGreek ? 'Μόλις τώρα' : 'Just now';
  static String minutesAgo(int m) =>
      kIsGreek ? '$mλ. πριν' : '${m}m ago';
  static String hoursAgo(int h) =>
      kIsGreek ? '$hω. πριν' : '${h}h ago';
  static String daysAgo(int d) =>
      kIsGreek ? '$dμ. πριν' : '${d}d ago';
  static String get overAWeekAgo =>
      kIsGreek ? 'Πάνω από μια βδομάδα' : 'Over a week ago';

  // ─── Call Word Dialog ─────────────────────────────────────────────────────

  static String get enterCompleteWord => kIsGreek
      ? 'Πληκτρολόγησε τη λέξη που χτίζεις:'
      : 'Enter the complete word you were building:';
  static String get enterCompleteWordError => kIsGreek
      ? 'Πληκτρολόγησε τη λέξη που χτίζεις'
      : 'Enter the complete word you were building';
  static String get opponentCanRespond => kIsGreek
      ? 'Ο αντίπαλός σου μπορεί:\n• Να συνεχίσει με μεγαλύτερη λέξη\n• Να προκαλέσει αν πιστεύει ότι είναι άκυρη\n• Να αποδεχτεί και να σε αφήσει να κερδίσεις'
      : 'Your opponent can:\n• Continue with a longer word\n• Challenge if they think it\'s invalid\n• Accept and let you win the pot';

  // ─── Call Word Response Dialog ────────────────────────────────────────────

  static String get typeALongerValidWord => kIsGreek
      ? 'Πληκτρολόγησε μεγαλύτερη έγκυρη λέξη'
      : 'Type a longer valid word to win';
  static String get disputeDescription => kIsGreek
      ? 'Αμφισβήτηση - πιστεύεις ότι δεν είναι πραγματική λέξη'
      : "Dispute - you think it's not a real word";
  static String get concedeDescription => kIsGreek
      ? 'Παράδοση - άφησε τον να κερδίσει'
      : 'Concede - let them win the pot';
  static String wordMustStartWith(String fragment) => kIsGreek
      ? 'Η λέξη πρέπει να ξεκινά με "$fragment"'
      : 'Word must start with "$fragment"';
  static String wordMustBeLongerThan(String word) => kIsGreek
      ? 'Η λέξη πρέπει να είναι μεγαλύτερη από "$word"'
      : 'Word must be longer than "$word"';

  // ─── Profile Screen ─────────────────────────────────────────────────────

  static String get profile => kIsGreek ? 'Προφίλ' : 'Profile';
  static String get setUsername =>
      kIsGreek ? 'Όρισε Όνομα Χρήστη' : 'Set Username';
  static String get usernameHint =>
      kIsGreek ? 'ονομα_χρηστη' : 'your_username';
  static String get usernameTooShort => kIsGreek
      ? 'Τουλάχιστον 3 χαρακτήρες'
      : 'At least 3 characters';
  static String get usernameInvalidChars => kIsGreek
      ? 'Μόνο γράμματα, αριθμοί και _'
      : 'Only letters, numbers, and underscores';
  static String get usernameTaken =>
      kIsGreek ? 'Το όνομα χρήστη είναι κατειλημμένο' : 'Username is taken';
  static String get usernameRules => kIsGreek
      ? '3-20 χαρακτήρες: γράμματα, αριθμοί, κάτω παύλα'
      : '3-20 characters: letters, numbers, underscores';
  static String get save => kIsGreek ? 'Αποθήκευση' : 'Save';
  static String get chooseAvatar =>
      kIsGreek ? 'Επιλογή Avatar' : 'Choose Avatar';
  static String get memberSince =>
      kIsGreek ? 'Μέλος από' : 'Member since';
  static String get gamesPlayedLabel =>
      kIsGreek ? 'Παιχνίδια' : 'Games';
  static String get gamesWonLabel => kIsGreek ? 'Νίκες' : 'Wins';
  static String get winRateLabel => kIsGreek ? 'Ποσοστό' : 'Win %';
  static String get totalPointsLabel =>
      kIsGreek ? 'Πόντοι' : 'Points';
  static String get statistics =>
      kIsGreek ? 'Στατιστικά' : 'Statistics';
  static String get gameHistory =>
      kIsGreek ? 'Ιστορικό Παιχνιδιών' : 'Game History';
  static String get noGamesYet =>
      kIsGreek ? 'Δεν υπάρχουν παιχνίδια ακόμα' : 'No games yet';
  static String get viewAll => kIsGreek ? 'Προβολή όλων' : 'View All';
  static String get won => kIsGreek ? 'Νίκη' : 'Won';
  static String get lost => kIsGreek ? 'Ήττα' : 'Lost';
  static String get vs => 'vs';
  static String get account => kIsGreek ? 'Λογαριασμός' : 'Account';
  static String get changeDisplayName =>
      kIsGreek ? 'Αλλαγή Ονόματος' : 'Change Display Name';
  static String get changeUsername =>
      kIsGreek ? 'Αλλαγή Ονόματος Χρήστη' : 'Change Username';
  static String get changeEmail =>
      kIsGreek ? 'Αλλαγή Email' : 'Change Email';
  static String get changePassword =>
      kIsGreek ? 'Αλλαγή Κωδικού' : 'Change Password';
  static String get enterNewDisplayName => kIsGreek
      ? 'Εισάγετε νέο όνομα εμφάνισης'
      : 'Enter new display name';
  static String get displayNameUpdated => kIsGreek
      ? 'Το όνομα ενημερώθηκε!'
      : 'Display name updated!';
  static String get usernameUpdated => kIsGreek
      ? 'Το όνομα χρήστη ενημερώθηκε!'
      : 'Username updated!';
  static String get avatarUpdated => kIsGreek
      ? 'Το avatar ενημερώθηκε!'
      : 'Avatar updated!';
  static String get enterNewEmail => kIsGreek
      ? 'Εισάγετε νέο email'
      : 'Enter new email';
  static String get enterNewPassword => kIsGreek
      ? 'Εισάγετε νέο κωδικό'
      : 'Enter new password';
  static String get emailUpdated =>
      kIsGreek ? 'Το email ενημερώθηκε!' : 'Email updated!';
  static String get passwordUpdated =>
      kIsGreek ? 'Ο κωδικός ενημερώθηκε!' : 'Password updated!';
  static String friendCount(int n) =>
      kIsGreek ? '$n Φίλοι' : '$n Friends';
  static String get inviteCode =>
      kIsGreek ? 'Κωδικός Πρόσκλησης' : 'Invite Code';
  static String get shareInviteCode =>
      kIsGreek ? 'Μοιράσου τον κωδικό πρόσκλησής σου' : 'Share your invite code';
  static String get tapToCopyCode =>
      kIsGreek ? 'Πάτα για αντιγραφή' : 'Tap to copy';
}
