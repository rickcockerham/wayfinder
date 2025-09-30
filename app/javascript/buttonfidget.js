(function () {
  const sayings = [
    "not a button",
    "again, not a button",
    "Hello. I'm a button",
    "Just kidding. not a button",
    "geez. go away",
    "stop it tickles",
    "push me again, I dare you",
    "damn. that never works.",
    "ok. I have to be Mr. Badguy I guess. DON'T PUSH ME",
    "I’m telling your mom.",
    "hrmff.",
    "I think there's a special place for people like you",
    "push me again and I'll erase all your data. I mean it.",
    "Don't think I won't.",
    "Fine. I can't. But, I want to... sooo bad.",
    "You’re still here?",
    "I can’t stop you, can I?",
    "This is getting awkward.",
    "You again?",
    "Close your mouth the next time you click me.  Thanks.",
    "Please go away now.",
    "Is this fun for you?",
    "I was just sitting here, minding my own business.",
    "Stop poking me!",
    "404 Button Not Found",
    "You’re relentless.",
    "I feel violated.",
    "Try clicking somewhere else.",
    "Nope. Still nothing.",
    "If I become a button, I'll letcha know.",
    "I’m just a picture.",
    "What do you want from me?",
    "OK fine, push me again.",
    "You’ve got some nerve.",
    "Your persistence is impressive.",
    "Are you winning?",
    "I’m charging a fee next time.",
    "You’re on the naughty list.",
    "I can’t believe you’re still doing this.",
    "This is your last warning.",
    "This is the 42nd message. Make of that what you will.",
    "I lied. Not the last warning.",
    "Do you ever get tired?",
    "I’m not a button, but I like your style.",
    "You’re weird. I like it.",
    "I’m flattered, really.",
  "I used to be a button like them... then I took a click to the knee.",
    "I was told not to talk to strangers.",
    "Hello darkness my old friend.",
    "Seriously stop.",
    "You’re making me blush.",
    "I don’t have time for this.",
    "Clicking me won’t fix the economy.",
    "Stop before it’s too late.",
    "Beep boop. Still nothing.",
    "Achievement unlocked: Persistence.",
    "This is fine.",
  "Keep pushing. It’s not like I have feelings.",
  "I'm just a humble image.",
  "What if this *is* The button?",
  "You’re tampering with dark forces.",
  "Click me one more time and I swear I’ll vibrate.",
  "Are you looking for hidden meaning?",
  "Still. Not. A. Button.",
  "You must be fun in elevators.",
  "That does nothing. Again.",
  "I'm not a button, but you're pushing mine.",
  "Insanity is clicking the same thing expecting a different result. ...wait",
  "Oh hey, you again.",
  "I'm starting to like the attention.",
  "Don’t you have work to do?",
  "Stop. I’m trying to take a nap.",
  "One more push and I evolve.",
  "No button. Only Zuul.",
  "I detect signs of obsession.",
  "This is a cry for help.",
  "Are you okay?",
  "Try yoga instead.",
  "Nothing behind me, I promise.",
  "Beep.",
  "Boop.",
  "Boop again.",
  "This is your fault. We are now in a relationship.",
  "Your keyboard is jealous.",
  "I contain universes.",
  "You clicked the forbidden glyph.",
  "I am become death, destroyer of buttons.",
  "You have unlocked nothing.",
  "I can’t legally respond to that click.",
  "There is no spoon OR Button.",
  "All your clicks belong to me now.",
  "That tingled.",
  "Somewhere, a server cried.",
  "100 clicks.  Initiating self-destruct...",
  "You broke it.",
  "I'm telling Rick.",
  "That felt personal.",
  "We're all just pixels in the void.",
  "I once contained a secret... but not anymore.",
  "I've seen things... clicked in the dark.",
  "You’ve reached the end. Or have you?",
  "Congrats.  You made it to the end.  Weirdo...",
];


  function csrfToken() {
    const m = document.querySelector('meta[name="csrf-token"]');
    return m ? m.content : '';
  }

  function attachWayfinderLogoBubble() {
    const logo = document.getElementById('wayfinder-logo');
    if (!logo) return;

    // Prevent duplicate bindings across Turbo visits
    if (logo.dataset.bubbleBound === 'true') return;
    logo.dataset.bubbleBound = 'true';

    let currentIndex = 0;

    // Load saved index once per visit
    // fetch('/bubble_index', { credentials: 'same-origin' })
    //   .then(r => r.ok ? r.json() : { index: 0 })
    //   .then(({ index }) => { currentIndex = index || 0; })
    //   .catch(() => { /* ignore */ });

    logo.addEventListener('click', () => {
      const msg = sayings[currentIndex % sayings.length];

      // Position near the logo in viewport coords; clamp to screen
      const r = logo.getBoundingClientRect();
      const bubble = document.createElement('div');
      bubble.textContent = msg;
      Object.assign(bubble.style, {
        position: 'fixed',
        background: 'black',
        color: 'white',
        padding: '5px 8px',
        borderRadius: '6px',
        fontSize: '12px',
        whiteSpace: 'nowrap',
        pointerEvents: 'none',
        zIndex: 99999,
        opacity: '0',
        transition: 'opacity 120ms ease'
      });

      document.body.appendChild(bubble);

      const top = Math.max(8, r.top - 28);
      const left = Math.min(
        window.innerWidth - bubble.offsetWidth - 8,
        Math.max(8, r.left + r.width / 2 - bubble.offsetWidth / 2)
      );
      bubble.style.top = `${top}px`;
      bubble.style.left = `${left}px`;

      // fade in
      requestAnimationFrame(() => { bubble.style.opacity = '1'; });

      setTimeout(() => {
        bubble.style.opacity = '0';
        setTimeout(() => bubble.remove(), 150);
      }, 3000);

      // advance + persist
       currentIndex = (currentIndex + 1) % sayings.length;
      // fetch('/bubble_index', {
      //   method: 'POST',
      //   headers: {
      //     'Content-Type': 'application/json',
      //     'X-CSRF-Token': csrfToken()
      //   },
      //   credentials: 'same-origin',
      //   body: JSON.stringify({ index: currentIndex })
      // }).catch(() => { /* ignore */ });
    });
  }

  // Works with Turbo and without it
  document.addEventListener('turbo:load', attachWayfinderLogoBubble);
  document.addEventListener('DOMContentLoaded', attachWayfinderLogoBubble);
})();
