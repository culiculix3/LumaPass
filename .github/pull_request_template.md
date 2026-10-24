## Summary

## What changed for users?

## Privacy, accessibility, and Wallet considerations

- [ ] Does not collect or generate payment-card information.
- [ ] Does not reveal public-gallery content or personal drafts in logs or shared records.
- [ ] Uses native Wallet fields and the signed PassKit flow for actual passes.
- [ ] Preserves keyboard, Dynamic Type, VoiceOver, sufficient contrast, and reduced motion.
- [ ] Documents any database or deployment change.

## Validation

- [ ] `python -m pytest`
- [ ] `ruff check backend`
- [ ] `ruff format --check backend`
- [ ] iOS simulator build/tests (on macOS), or explain why unavailable.
