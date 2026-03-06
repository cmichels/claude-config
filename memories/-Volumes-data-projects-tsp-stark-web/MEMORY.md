# Stark Web Memory

## Backend API Constraints (Staging)
- `PUT /core/persons/me` validates ALL Person fields including `password`, even when absent
- `GET /core/persons/me` never returns `password` (correct security practice)
- PATCH is blocked by security filter on ALL person endpoints (403)
- This creates a catch-22 for partial updates — backend fix required to allow PATCH
- See `Plans/OP-3243.md` for full investigation table

## Key Patterns
- `EndpointFactory` is the central HTTP hub — all requests go through it
- `handleError()` shows toast AND rethrows — components should NOT show duplicate toasts
- `AlertHelperService.showAlert()` must resolve translations with params before passing to AlertService
- LocalStorage is encrypted with CryptoJS AES (keys are SHA-256 hashed)

## Project Structure
- Feature modules in `ClientApp/src/app/modules/`
- All components extend `BasicAbstractComponentDirective`
- Tests: Jasmine + Karma, `ng test --include='**/file.spec.ts'`
- Pre-existing circular dep blocks tests: `ConfigurationService -> LocalStoreManager -> SearchService -> ConfigurationService`
