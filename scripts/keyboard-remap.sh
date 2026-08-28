#!/usr/bin/env bash
# Apply the Logitech MX Keys Mini key mappings used by keyboard-watcher.

set -euo pipefail

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
  echo "Keyboard remapping is only supported on macOS." >&2
  exit 3
fi

hidutil=/usr/bin/hidutil
if [[ ! -x "$hidutil" ]]; then
  echo "Error: hidutil was not found at $hidutil." >&2
  exit 127
fi

device_match='{"VendorID":0x46d,"ProductID":0xb369}'
key_mapping='{
  "UserKeyMapping": [
    {
      "HIDKeyboardModifierMappingSrc": 0x700000064,
      "HIDKeyboardModifierMappingDst": 0x700000035
    },
    {
      "HIDKeyboardModifierMappingSrc": 0x700000035,
      "HIDKeyboardModifierMappingDst": 0xFF00000003
    }
  ]
}'

# Logitech MX Keys Mini (VendorID 0x46d, ProductID 0xb369):
#   Non-US \| (ISO key by left Shift) -> Grave/Tilde (`)
#   Grave/Tilde (`)                   -> Fn / Globe
"$hidutil" property --matching "$device_match" --set "$key_mapping"
