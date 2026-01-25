# Accessibility Testing Documentation

This document provides comprehensive guidance for implementing WCAG 2.1 AA compliance testing in your projects using the Claude Code accessibility framework.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Automated Testing](#automated-testing)
4. [Manual Testing](#manual-testing)
5. [CI/CD Integration](#cicd-integration)
6. [Remediation Strategies](#remediation-strategies)
7. [WCAG 2.1 Reference](#wcag-21-reference)

---

## Overview

Web Content Accessibility Guidelines (WCAG) 2.1 defines how to make web content more accessible to people with disabilities. This framework provides:

- **Automated testing** with axe-core, pa11y, and Lighthouse
- **Manual testing checklists** for QA teams
- **Accessible component patterns** for React/TypeScript
- **CI/CD integration** for continuous compliance
- **Remediation guidance** for common violations

### Compliance Levels

| Level | Description | Target |
|-------|-------------|--------|
| A | Basic accessibility (30 criteria) | Minimum required |
| AA | Standard compliance (20 criteria) | **Recommended target** |
| AAA | Enhanced accessibility (28 criteria) | Aspirational |

---

## Quick Start

### 1. Use the Accessibility Auditor Agent

```
Use the accessibility-auditor subagent.

Audit: src/components/
Target: WCAG 2.1 AA
Output: Violations report + CI/CD setup
```

### 2. Install Testing Dependencies

```bash
# Core testing libraries
npm install --save-dev @axe-core/puppeteer @axe-core/react jest-axe pa11y

# Linting
npm install --save-dev eslint-plugin-jsx-a11y stylelint-a11y
```

### 3. Copy Templates

```bash
# Copy skill templates to your project
cp .claude/skills/accessibility-testing/templates/jest-axe.config.js ./test/
cp .claude/skills/accessibility-testing/templates/pa11y.config.json ./
cp .claude/skills/accessibility-testing/templates/accessibility.yml ./.github/workflows/
cp .claude/skills/accessibility-testing/templates/eslint-a11y.js ./
```

---

## Automated Testing

### Component-Level Testing (jest-axe)

Test individual components in isolation:

```javascript
import { render } from '@testing-library/react';
import { axe, toHaveNoViolations } from 'jest-axe';
import { Button } from './Button';

expect.extend(toHaveNoViolations);

describe('Button Accessibility', () => {
  it('should have no accessibility violations', async () => {
    const { container } = render(<Button>Click me</Button>);
    const results = await axe(container);
    expect(results).toHaveNoViolations();
  });
});
```

### Page-Level Testing (pa11y)

Test full pages in a browser context:

```bash
# Single URL test
npx pa11y http://localhost:3000 --standard WCAG2AA

# CI configuration test
npx pa11y-ci --config .pa11yci.json
```

### Lighthouse Audits

Track accessibility score over time:

```bash
# Run Lighthouse CI
npx lhci autorun --config=lighthouserc.json

# Check scores
npx lhci assert --assertions.categories:accessibility=0.9
```

### ESLint Static Analysis

Catch issues during development:

```javascript
// .eslintrc.js
module.exports = {
  extends: ['plugin:jsx-a11y/recommended'],
  rules: {
    'jsx-a11y/alt-text': 'error',
    'jsx-a11y/label-has-associated-control': 'error',
  },
};
```

---

## Manual Testing

Automated tools catch approximately 30-50% of accessibility issues. Manual testing is essential for:

- Keyboard navigation flow
- Screen reader announcements
- Cognitive accessibility
- Context and meaning

### Testing Checklist

See `.claude/skills/accessibility-testing/templates/manual-testing-checklist.md` for a complete checklist covering:

1. **Keyboard Navigation** - Tab order, focus management, keyboard traps
2. **Screen Reader** - Landmarks, headings, announcements
3. **Visual** - Contrast, zoom, color independence
4. **Cognitive** - Clear language, error handling, consistency
5. **Mobile** - Touch targets, gestures, orientation

### Screen Reader Testing

| Platform | Screen Reader | Get Started |
|----------|---------------|-------------|
| Windows | NVDA | Free download from nvaccess.org |
| macOS | VoiceOver | Built-in (Cmd+F5) |
| iOS | VoiceOver | Settings > Accessibility |
| Android | TalkBack | Settings > Accessibility |

### Browser Extensions

| Tool | Purpose |
|------|---------|
| WAVE | Visual accessibility errors |
| axe DevTools | Comprehensive automated testing |
| Accessibility Insights | Microsoft's full testing toolkit |
| HeadingsMap | Visualize heading structure |

---

## CI/CD Integration

### GitHub Actions Workflow

The template at `.claude/skills/accessibility-testing/templates/accessibility.yml` provides:

1. **Component Tests** - jest-axe on every PR
2. **Page Tests** - pa11y against staging
3. **Lighthouse Audit** - Score tracking
4. **PR Comments** - Automated accessibility report

### Pre-commit Hook

Install the pre-commit hook for early detection:

```bash
cp .claude/skills/accessibility-testing/templates/pre-commit-a11y.sh .husky/pre-commit
chmod +x .husky/pre-commit
```

### Quality Gates

Set minimum thresholds in CI:

```yaml
# Fail build if score drops below 90
- name: Check Lighthouse score
  run: |
    SCORE=$(cat .lighthouseci/lhr-*.json | jq '.categories.accessibility.score * 100')
    if (( $(echo "$SCORE < 90" | bc -l) )); then
      exit 1
    fi
```

---

## Remediation Strategies

### Critical Violations (Fix Immediately)

#### Missing Alt Text

```html
<!-- Problem -->
<img src="hero.jpg">

<!-- Solution: Informative image -->
<img src="hero.jpg" alt="Team collaborating in modern office space">

<!-- Solution: Decorative image -->
<img src="decoration.svg" alt="" role="presentation">
```

#### Missing Form Labels

```html
<!-- Problem -->
<input type="email" placeholder="Email">

<!-- Solution -->
<label for="email">Email address</label>
<input type="email" id="email" name="email">
```

#### Keyboard Traps

```javascript
// Problem: Modal traps focus forever
// Solution: Allow escape and manage focus
useEffect(() => {
  const handleKeyDown = (e) => {
    if (e.key === 'Escape') closeModal();
  };
  document.addEventListener('keydown', handleKeyDown);
  return () => document.removeEventListener('keydown', handleKeyDown);
}, []);
```

### Serious Violations (Fix Soon)

#### Insufficient Contrast

```css
/* Problem: 2.5:1 contrast */
.text { color: #999; background: #fff; }

/* Solution: 4.5:1 contrast */
.text { color: #595959; background: #fff; }
```

#### Missing Focus Indicators

```css
/* Problem */
:focus { outline: none; }

/* Solution */
:focus-visible {
  outline: 2px solid #0066cc;
  outline-offset: 2px;
}
```

### Accessible Component Patterns

Use the patterns in `.claude/skills/accessibility-testing/templates/accessible-components.tsx`:

- **SkipLink** - First focusable element
- **AccessibleButton** - Loading states, icons
- **AccessibleInput** - Labels, errors, descriptions
- **AccessibleModal** - Focus trap, escape handling
- **AccessibleTabs** - Arrow key navigation
- **LiveRegion** - Dynamic announcements
- **AccessibleAccordion** - Expand/collapse
- **AccessibleDropdown** - Menu keyboard support

---

## WCAG 2.1 Reference

### Principle 1: Perceivable

| Guideline | Key Success Criteria |
|-----------|---------------------|
| 1.1 Text Alternatives | Alt text for images, captions for video |
| 1.2 Time-based Media | Captions, audio descriptions |
| 1.3 Adaptable | Semantic structure, reading order |
| 1.4 Distinguishable | Contrast, resize text, spacing |

### Principle 2: Operable

| Guideline | Key Success Criteria |
|-----------|---------------------|
| 2.1 Keyboard Accessible | All functionality via keyboard |
| 2.2 Enough Time | Adjustable time limits |
| 2.3 Seizures | No flashing content |
| 2.4 Navigable | Skip links, page titles, focus order |
| 2.5 Input Modalities | Pointer gestures, target size |

### Principle 3: Understandable

| Guideline | Key Success Criteria |
|-----------|---------------------|
| 3.1 Readable | Page language, abbreviations |
| 3.2 Predictable | Consistent navigation, no context changes |
| 3.3 Input Assistance | Error identification, suggestions |

### Principle 4: Robust

| Guideline | Key Success Criteria |
|-----------|---------------------|
| 4.1 Compatible | Valid HTML, name/role/value |

### Common axe-core Rule IDs

| Rule ID | WCAG Criteria | Description |
|---------|---------------|-------------|
| `image-alt` | 1.1.1 | Images must have alt text |
| `label` | 1.3.1, 4.1.2 | Form inputs must have labels |
| `color-contrast` | 1.4.3 | Text must have sufficient contrast |
| `heading-order` | 1.3.1 | Heading levels should not skip |
| `link-name` | 2.4.4 | Links must have discernible text |
| `button-name` | 4.1.2 | Buttons must have accessible names |
| `html-has-lang` | 3.1.1 | HTML must have lang attribute |
| `landmark-one-main` | Best practice | Page should have one main landmark |

---

## Resources

- [WCAG 2.1 Quick Reference](https://www.w3.org/WAI/WCAG21/quickref/)
- [axe-core Rules](https://github.com/dequelabs/axe-core/blob/develop/doc/rule-descriptions.md)
- [Deque University](https://dequeuniversity.com/)
- [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/)
- [A11Y Project Checklist](https://www.a11yproject.com/checklist/)
- [Inclusive Components](https://inclusive-components.design/)
