# Accessibility WCAG Reference

## WCAG 2.1 AA Checklist

### Perceivable

- [ ] All images have `alt` text (or `aria-hidden="true"` for decorative)
- [ ] Video has captions and audio descriptions
- [ ] Content is readable without styles (semantic structure)
- [ ] Color contrast: 4.5:1 for normal text, 3:1 for large text
- [ ] No information conveyed by color alone
- [ ] Text can be resized to 200% without loss of content
- [ ] Content reflows at 320px width (no horizontal scrolling)

### Operable

- [ ] All functionality accessible via keyboard
- [ ] No keyboard traps (can always Tab away)
- [ ] Skip navigation link provided
- [ ] Focus indicator visible on all interactive elements
- [ ] No time limits (or adjustable/extendable)
- [ ] No content that flashes more than 3 times per second
- [ ] Page titles are descriptive and unique
- [ ] Focus order is logical and intuitive
- [ ] Touch targets at least 44×44px

### Understandable

- [ ] Page language declared (`<html lang="en">`)
- [ ] Language changes marked with `lang` attribute
- [ ] Navigation consistent across pages
- [ ] Form inputs have visible labels
- [ ] Error messages identify the field and suggest correction
- [ ] No unexpected context changes on focus or input

### Robust

- [ ] Valid HTML (no duplicate IDs, proper nesting)
- [ ] ARIA attributes used correctly
- [ ] Custom components have appropriate roles
- [ ] Status messages use `aria-live` regions

---

## Semantic HTML Quick Reference

```tsx
// Landmark regions
<header>     → Site header, logo, nav
<nav>        → Navigation links
<main>       → Primary content (one per page)
<article>    → Self-contained content
<section>    → Thematic group of content
<aside>      → Related/sidebar content
<footer>     → Footer, copyright

// Interactive
<button>     → Clickable actions (NOT <div onClick>)
<a href="">  → Navigation to URL
<details>    → Expandable content
<dialog>     → Modal/non-modal dialog

// Forms
<label>      → Input label (always pair with input)
<fieldset>   → Group of related inputs
<legend>     → Fieldset description
<output>     → Calculation result
```

---

## Accessible Forms

```tsx
function ContactForm() {
  const [errors, setErrors] = useState({})

  return (
    <form noValidate aria-label="Contact form">
      {/* Label connected to input */}
      <div>
        <label htmlFor="email">
          Email <span aria-hidden="true">*</span>
          <span className="sr-only">(required)</span>
        </label>
        <input
          id="email"
          type="email"
          required
          aria-required="true"
          aria-invalid={!!errors.email}
          aria-describedby={errors.email ? 'email-error' : undefined}
        />
        {errors.email && (
          <p id="email-error" role="alert" className="error">
            {errors.email}
          </p>
        )}
      </div>

      {/* Submit button with loading state */}
      <button type="submit" disabled={isSubmitting} aria-busy={isSubmitting}>
        {isSubmitting ? 'Sending...' : 'Send Message'}
      </button>
    </form>
  )
}
```

---

## Screen Reader Only Text

```css
/* Visually hidden but accessible to screen readers */
.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}
```

---

## Skip Link

```tsx
// First element in body
<a href="#main-content" className="skip-link">
  Skip to main content
</a>

<main id="main-content">
  {/* Page content */}
</main>
```

```css
.skip-link {
  position: absolute;
  top: -100%;
  left: 0;
  z-index: 9999;
  padding: 8px 16px;
  background: #000;
  color: #fff;
}
.skip-link:focus {
  top: 0;
}
```

---

## `aria-label` for Branded Acronyms (Pronunciation Forcing)

Screen readers (NVDA, JAWS, VoiceOver) heuristically pronounce all-caps single tokens. A 5-7 letter all-caps token gets either spelled letter-by-letter ("A-I-G-I-S-T") or pronounced as a single word ("ageist"). The word-pronunciation path is the dangerous one: it can produce a homophone of an offensive or unrelated word and **undo a visual rebrand for screen-reader users**.

### Real-world case study (AIGIST 2026-05)

The brand `AIGIST` was visually rebranded to `AiGIST` (capital A, lowercase i, capital GIST) specifically to break the "ageist" auditory collision. The dashboard added a two-tone wordmark, a watermark on the login page explaining the split, and IDENTITY.md spec — but the `<Wordmark>` component used `aria-label="AIGIST"`. Screen readers pronounced it "ageist." The entire rebrand work was invisible to AT users.

**Fix:** `aria-label="AI GIST"` (with the space). Forces the AT to announce two syllables, matching the visual two-tone treatment.

### Rule

For any branded acronym, initialism, or stylised wordmark that is split visually for typographic reasons:

1. **The `aria-label` must match the intended phonetic pronunciation, not the visual letters.**
2. If the pronunciation is letter-by-letter, use periods or spaces: `aria-label="A.I.G.I.S.T."` or `aria-label="A I G I S T"`.
3. If the pronunciation is two syllables ("AI" + "GIST"), use a single space: `aria-label="AI GIST"`.
4. If the pronunciation is a single word ("Spotify"), the natural form works.
5. **Test with an actual screen reader** (VoiceOver: Cmd+F5; NVDA: free Windows download). What you think a screen reader will say is rarely what it says.

### Pattern

```tsx
// Visual: two-tone wordmark with intentional case split
<span aria-label="AI GIST" role="img">
  <span aria-hidden="true">Ai</span>
  <span aria-hidden="true">GIST</span>
</span>
```

- Child spans get `aria-hidden="true"` so AT does not announce each fragment separately.
- Parent provides the accessible name — and the accessible name is the **pronunciation**, not the spelling.
- If the lockup is decorative chrome rather than meaningful content, consider `aria-hidden="true"` on the parent and let the surrounding heading carry the accessible name.

### When to use `<abbr>` instead

For technical acronyms in body copy (PIPEDA, GDPR, OWASP, OAuth), `<abbr title="...">` gives a hover/tooltip expansion without forcing pronunciation. Use `aria-label` for branded marks. Use `<abbr>` for industry acronyms.

### Verification

- [ ] Every branded acronym tested with VoiceOver or NVDA — confirm the announced pronunciation matches intent.
- [ ] If natural AT pronunciation produces a different word, `aria-label` overrides with the intended pronunciation.
- [ ] No fragment span carries an unhidden accessible name (`aria-hidden="true"` on all stylistic split children).
