# Table form view

The **Form** table view supports creating entries and browsing existing rows.
Wide panes show an entry list; narrow panes use a row picker. Every field has
a copy action, and editable values have an edit action with **Save** and
**Cancel**. Location, date/time (including ranges), duration, files, checklists,
checkboxes, choices and relations have typed inputs directly in the form.
Button, counter and progress columns use the table's configured controls.
Computed properties remain read-only.

**Add custom field** creates a real column shared by every row and linked view.
Available types are Text, Hidden text, Encrypted text, Number, Website / URL,
Boolean, Location, Date and time, Duration, Files and images, Checklist,
Button, Counter and Progress. The field menu edits its name, description and required setting.
It also hides the field from the form; **Hidden fields** restores it.

New-entry drafts are held in memory; merely opening a form or choosing a file
creates no row and uploads nothing. Files are imported only on Save. Cancelling
an existing field edit restores its stored value. Selection and relation ids,
date flags and attachment metadata are read from native cell payloads rather
than reconstructed from display strings. The Time field is a duration in
minutes, edited as hours and minutes, not a timestamp.

## Hidden is not encrypted

- **Hidden text / Mask value** conceals the value in this form only. Other
  views, exports and historical copies may still contain plaintext.
- **Encrypted text / Encrypt field across table** uses the existing workspace
  vault to encrypt the text column's current values. This applies across rows
  and linked views. A passphrase confirmation is required to copy, reveal or
  edit a saved encrypted value; edits are encrypted before persistence.
- Encryption is limited to text columns. Names, descriptions and other table
  metadata are not encrypted. The primary/title column cannot be encrypted
  through this form, because it also identifies rows elsewhere in the app.
- Earlier history, exports and backups are **not** erased or retroactively
  encrypted. The workspace vault's key settings are device-local; this feature
  does not add password-manager sync, autofill, or Bitwarden compatibility.
  Keep the passphrase and existing encryption settings safe.
- Bulk conversion checks every payload before writing, uses a temporary copy
  of the key, and attempts to restore original values if a write fails. A failed
  conversion is never reported as success. Backends do not provide an atomic
  column transaction, so a failed rollback must be reviewed before retrying.

Revealed values conceal when leaving the app or locking the vault. Unsaved
encrypted drafts are cleared on concealment, with a notice. A sensitive copy
expires after 30 seconds if the clipboard still contains that text, and is
cleared on vault lock. Switching apps leaves time to paste. OS clipboard
history and other apps may retain their own copies.

## Regression coverage

- `test/unit_test/workspace/form_entry_service_test.dart`
- `test/unit_test/workspace/form_stage_test.dart`
- `test/unit_test/workspace/encrypted_column_rewrite_test.dart`
- `test/unit_test/shared/sensitive_clipboard_test.dart`

The widget tests use an isolated in-memory table and real AppFlowy light, dark
and paper themes. They do not open or modify the user's workspace.