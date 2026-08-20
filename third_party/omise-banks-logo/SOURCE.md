# omise/banks-logo

- Source: https://github.com/omise/banks-logo
- Revision: `2d813bc9193fd3ebd8e2c94d7f60a8a25ba956b2`
- Imported assets: `th/*.svg` (XML `DOCTYPE` declarations removed as a safety hardening)
- License: MIT; see `LICENSE` in this directory.

The bank icons are trademarks of their respective owners. Their inclusion does
not indicate endorsement by the trademark holders or by Opn Payments.

`banks.json` is retained as upstream logo metadata. Its `code` values are not
treated as authoritative current Bank of Thailand institution or payment-routing
codes; financial accounts link to logos by the validated asset slug instead.

The application serves copied SVG files from `/bank-logos/` so account and
transaction screens remain local-only and do not contact GitHub at runtime.
