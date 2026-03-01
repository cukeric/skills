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
