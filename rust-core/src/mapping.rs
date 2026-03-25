use crate::config::ModifierOverrides;

pub const HID_USAGE_KEYBOARD_APPLICATION: u64 = 0x700000065;
pub const HID_USAGE_KEYBOARD_LEFT_ALT: u64 = 0x7000000E2;
pub const HID_USAGE_KEYBOARD_LEFT_GUI: u64 = 0x7000000E3;
pub const HID_USAGE_KEYBOARD_RIGHT_ALT: u64 = 0x7000000E6;
pub const HID_USAGE_KEYBOARD_RIGHT_GUI: u64 = 0x7000000E7;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HidRemapEntry {
    pub src: u64,
    pub dst: u64,
}

pub fn modifier_remap_entries(overrides: &ModifierOverrides) -> Vec<HidRemapEntry> {
    let mut entries = Vec::with_capacity(5);

    if overrides.swap_left_alt_win {
        entries.push(HidRemapEntry {
            src: HID_USAGE_KEYBOARD_LEFT_ALT,
            dst: HID_USAGE_KEYBOARD_LEFT_GUI,
        });
        entries.push(HidRemapEntry {
            src: HID_USAGE_KEYBOARD_LEFT_GUI,
            dst: HID_USAGE_KEYBOARD_LEFT_ALT,
        });
    }

    if overrides.swap_right_alt_win {
        entries.push(HidRemapEntry {
            src: HID_USAGE_KEYBOARD_RIGHT_ALT,
            dst: HID_USAGE_KEYBOARD_RIGHT_GUI,
        });
        entries.push(HidRemapEntry {
            src: HID_USAGE_KEYBOARD_RIGHT_GUI,
            dst: HID_USAGE_KEYBOARD_RIGHT_ALT,
        });
    }

    if !overrides.disable_context_menu_remap {
        entries.push(HidRemapEntry {
            src: HID_USAGE_KEYBOARD_APPLICATION,
            dst: HID_USAGE_KEYBOARD_RIGHT_GUI,
        });
    }

    entries
}

pub fn user_key_mapping_json(overrides: &ModifierOverrides) -> String {
    let mappings = modifier_remap_entries(overrides)
        .into_iter()
        .map(|entry| {
            format!(
                "{{\"HIDKeyboardModifierMappingSrc\":{},\"HIDKeyboardModifierMappingDst\":{}}}",
                entry.src, entry.dst
            )
        })
        .collect::<Vec<_>>()
        .join(",");

    format!("{{\"UserKeyMapping\":[{mappings}]}}")
}

#[cfg(test)]
mod tests {
    use super::{
        modifier_remap_entries, user_key_mapping_json, HidRemapEntry,
        HID_USAGE_KEYBOARD_APPLICATION, HID_USAGE_KEYBOARD_LEFT_ALT,
        HID_USAGE_KEYBOARD_LEFT_GUI, HID_USAGE_KEYBOARD_RIGHT_ALT, HID_USAGE_KEYBOARD_RIGHT_GUI,
    };
    use crate::config::ModifierOverrides;

    #[test]
    fn default_mapping_only_remaps_context_menu() {
        assert_eq!(
            modifier_remap_entries(&ModifierOverrides::default()),
            vec![HidRemapEntry {
                src: HID_USAGE_KEYBOARD_APPLICATION,
                dst: HID_USAGE_KEYBOARD_RIGHT_GUI,
            }]
        );
    }

    #[test]
    fn left_swap_generates_bidirectional_mapping() {
        let overrides = ModifierOverrides {
            swap_left_alt_win: true,
            ..ModifierOverrides::default()
        };

        assert_eq!(
            modifier_remap_entries(&overrides),
            vec![
                HidRemapEntry {
                    src: HID_USAGE_KEYBOARD_LEFT_ALT,
                    dst: HID_USAGE_KEYBOARD_LEFT_GUI,
                },
                HidRemapEntry {
                    src: HID_USAGE_KEYBOARD_LEFT_GUI,
                    dst: HID_USAGE_KEYBOARD_LEFT_ALT,
                },
                HidRemapEntry {
                    src: HID_USAGE_KEYBOARD_APPLICATION,
                    dst: HID_USAGE_KEYBOARD_RIGHT_GUI,
                },
            ]
        );
    }

    #[test]
    fn right_swap_generates_bidirectional_mapping() {
        let overrides = ModifierOverrides {
            swap_right_alt_win: true,
            ..ModifierOverrides::default()
        };

        assert_eq!(
            modifier_remap_entries(&overrides),
            vec![
                HidRemapEntry {
                    src: HID_USAGE_KEYBOARD_RIGHT_ALT,
                    dst: HID_USAGE_KEYBOARD_RIGHT_GUI,
                },
                HidRemapEntry {
                    src: HID_USAGE_KEYBOARD_RIGHT_GUI,
                    dst: HID_USAGE_KEYBOARD_RIGHT_ALT,
                },
                HidRemapEntry {
                    src: HID_USAGE_KEYBOARD_APPLICATION,
                    dst: HID_USAGE_KEYBOARD_RIGHT_GUI,
                },
            ]
        );
    }

    #[test]
    fn context_menu_override_can_disable_extra_mapping() {
        let overrides = ModifierOverrides {
            disable_context_menu_remap: true,
            ..ModifierOverrides::default()
        };

        assert!(modifier_remap_entries(&overrides).is_empty());
        assert_eq!(user_key_mapping_json(&overrides), "{\"UserKeyMapping\":[]}");
    }

    #[test]
    fn json_contains_expected_pairs() {
        let overrides = ModifierOverrides {
            swap_left_alt_win: true,
            swap_right_alt_win: true,
            disable_context_menu_remap: false,
        };

        let json = user_key_mapping_json(&overrides);
        for usage in [
            HID_USAGE_KEYBOARD_LEFT_ALT,
            HID_USAGE_KEYBOARD_LEFT_GUI,
            HID_USAGE_KEYBOARD_RIGHT_ALT,
            HID_USAGE_KEYBOARD_RIGHT_GUI,
            HID_USAGE_KEYBOARD_APPLICATION,
        ] {
            assert!(json.contains(&format!("\"HIDKeyboardModifierMappingSrc\":{usage}")));
        }
    }
}
