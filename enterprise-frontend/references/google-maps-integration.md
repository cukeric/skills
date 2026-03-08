# Google Maps API Integration Reference

Patterns for integrating Google Maps APIs into React/Next.js applications: Places Autocomplete for address input, Static Maps for map images, and Geocoding for coordinate lookup.

---

## Setup & Configuration

### API Key

```bash
NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=AIzaSy...
```

Enable these APIs in Google Cloud Console:
- **Maps JavaScript API** — for Places Autocomplete widget
- **Places API** — for address predictions
- **Maps Static API** — for map image generation
- **Geocoding API** — for address ↔ coordinate conversion (optional)

### Cost (as of 2026-03)

Google Maps provides **$200/month free credit** covering:
- ~28,000 Places Autocomplete requests
- ~100,000 Static Maps loads
- ~40,000 Geocoding requests

For most SaaS applications, the free tier covers all development + early production usage.

### Script Loading (Next.js)

```typescript
// app/layout.tsx
import Script from "next/script"

{process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY && (
  <Script
    src={`https://maps.googleapis.com/maps/api/js?key=${process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY}&libraries=places`}
    strategy="lazyOnload"
  />
)}
```

**Why `lazyOnload`?** The Maps script is ~200KB. Loading it eagerly blocks LCP. `lazyOnload` defers until after hydration.

### TypeScript Types

```bash
npm install --save-dev @types/google.maps
```

This provides the `google.maps` namespace types for the Autocomplete widget.

---

## Places Autocomplete Component (React)

A reusable address input component that provides Google-powered address suggestions and extracts structured address components.

```typescript
'use client'

import { useEffect, useRef, useCallback } from 'react'

export interface PlaceResult {
  address: string     // street address (e.g., "123 Main St")
  city: string
  state: string
  latitude: number | null
  longitude: number | null
}

interface AddressAutocompleteProps {
  value: string
  onChange: (value: string) => void
  onPlaceSelected: (place: PlaceResult) => void
  placeholder?: string
  className?: string
  id?: string
}

export default function AddressAutocomplete({
  value,
  onChange,
  onPlaceSelected,
  placeholder = 'Start typing an address...',
  className,
  id,
}: AddressAutocompleteProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const autocompleteRef = useRef<google.maps.places.Autocomplete | null>(null)

  const initAutocomplete = useCallback(() => {
    if (!inputRef.current || autocompleteRef.current) return
    if (typeof google === 'undefined' || !google.maps?.places) return

    const autocomplete = new google.maps.places.Autocomplete(inputRef.current, {
      types: ['address'],
      fields: ['address_components', 'geometry', 'formatted_address'],
      // No country restriction — works worldwide
    })

    autocomplete.addListener('place_changed', () => {
      const place = autocomplete.getPlace()
      if (!place.address_components) return

      const get = (type: string) =>
        place.address_components?.find((c) => c.types.includes(type))?.long_name || ''

      const streetNumber = get('street_number')
      const route = get('route')
      const address = streetNumber ? `${streetNumber} ${route}` : route

      onPlaceSelected({
        address: address || place.formatted_address || '',
        city: get('locality') || get('sublocality') || get('administrative_area_level_2'),
        state: get('administrative_area_level_1'),
        latitude: place.geometry?.location?.lat() ?? null,
        longitude: place.geometry?.location?.lng() ?? null,
      })
    })

    autocompleteRef.current = autocomplete
  }, [onPlaceSelected])

  useEffect(() => {
    // Try immediately
    initAutocomplete()

    // Retry if Google Maps loads after component mount
    if (!autocompleteRef.current) {
      const interval = setInterval(() => {
        if (typeof google !== 'undefined' && google.maps?.places) {
          initAutocomplete()
          clearInterval(interval)
        }
      }, 500)
      return () => clearInterval(interval)
    }
  }, [initAutocomplete])

  return (
    <input
      ref={inputRef}
      id={id}
      type="text"
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      className={className}
      autoComplete="off"  // Prevent browser autocomplete overlay
    />
  )
}
```

### Key Implementation Details

1. **Retry initialization**: The Google Maps script loads with `lazyOnload`, so it may not be available when the component mounts. The 500ms retry interval handles this race condition.

2. **`autoComplete="off"`**: Prevents the browser's built-in autocomplete from overlapping with Google's dropdown.

3. **`types: ['address']`**: Restricts predictions to addresses only (not businesses, regions, etc.).

4. **No country restriction**: Omit `componentRestrictions` for worldwide address support.

5. **`fields` whitelist**: Only request fields you need — each field category has different pricing.

### Wiring Into a Form

```typescript
const [form, setForm] = useState({
  address: '',
  city: '',
  state: '',
  latitude: null as number | null,
  longitude: null as number | null,
})

const handlePlaceSelected = useCallback((place: PlaceResult) => {
  setForm(prev => ({
    ...prev,
    address: place.address,
    city: place.city,
    state: place.state,
    latitude: place.latitude,
    longitude: place.longitude,
  }))
}, [])

// In JSX:
<AddressAutocomplete
  value={form.address}
  onChange={(v) => setForm(prev => ({ ...prev, address: v }))}
  onPlaceSelected={handlePlaceSelected}
/>
```

---

## Static Maps (Server-Rendered Map Images)

For embedding non-interactive map images (e.g., in microsites, emails, PDFs):

```typescript
// Build Static Maps URL
const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY || ''
const mapUrl = `https://maps.googleapis.com/maps/api/staticmap?` +
  `center=${latitude},${longitude}` +
  `&zoom=15` +
  `&size=640x400` +
  `&scale=2` +        // Retina (@2x)
  `&maptype=roadmap` +
  `&markers=color:red%7C${latitude},${longitude}` +
  `&key=${apiKey}`

// Render as clickable image linking to Google Maps
<a
  href={`https://www.google.com/maps/search/?api=1&query=${latitude},${longitude}`}
  target="_blank"
  rel="noopener noreferrer"
>
  <img src={mapUrl} alt={`Map of ${address}`} loading="lazy" />
</a>
```

### Parameters

| Param | Value | Purpose |
|---|---|---|
| `size` | `640x400` | Max free tier size (640x640) |
| `scale` | `2` | Retina display support (1280x800 actual pixels) |
| `zoom` | `15` | Neighborhood-level (13-16 typical for properties) |
| `maptype` | `roadmap` | Standard map (also: `satellite`, `terrain`, `hybrid`) |
| `markers` | `color:red%7Clat,lng` | Pin marker at coordinates |

### Conditional Rendering

Only show map when coordinates are available:

```typescript
if (params.latitude != null && params.longitude != null) {
  sections.push({
    type: 'location',
    content: {
      heading: 'Location',
      subheading: address,
      latitude: params.latitude,
      longitude: params.longitude,
    },
  })
}
```

---

## Environment Variable Handling

```typescript
// Client-side: NEXT_PUBLIC_ prefix required
const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY

// The Static Maps URL includes the API key — this is safe because:
// 1. Google Maps API keys are designed to be public (referrer-restricted)
// 2. Restrict the key in Google Cloud Console to your domain(s)
// 3. Enable only the specific APIs needed
```

### API Key Restrictions (Security)

In Google Cloud Console → Credentials → Edit key:

1. **Application restrictions**: HTTP referrers → add `yourdomain.com/*`
2. **API restrictions**: Restrict to only Maps JavaScript, Places, Static Maps, Geocoding
3. **Quotas**: Set daily limits per API to prevent bill shock

---

## Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| Autocomplete dropdown doesn't appear | Google Maps script not loaded yet | Add retry interval on component mount |
| Browser autocomplete overlaps Google dropdown | `autocomplete` attribute not set | Add `autoComplete="off"` to input |
| `google is not defined` TypeScript error | Missing types package | Install `@types/google.maps` |
| Static map shows "For development purposes only" | API key missing or billing not enabled | Enable billing in Google Cloud Console |
| Autocomplete returns no results | API key not authorized for Places API | Enable Places API in Cloud Console |
| Lat/lng are null after place selection | `geometry` not in `fields` array | Add `'geometry'` to Autocomplete `fields` option |
