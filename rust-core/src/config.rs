#![cfg_attr(not(test), allow(dead_code))]

use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModifierOverrides {
    pub swap_left_alt_win: bool,
    pub swap_right_alt_win: bool,
    pub disable_context_menu_remap: bool,
}

impl Default for ModifierOverrides {
    fn default() -> Self {
        Self {
            swap_left_alt_win: false,
            swap_right_alt_win: false,
            disable_context_menu_remap: false,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PresetKind {
    StandardPcToMac,
}

impl Default for PresetKind {
    fn default() -> Self {
        Self::StandardPcToMac
    }
}

impl PresetKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::StandardPcToMac => "standard_pc_to_mac",
        }
    }

    fn from_str(value: &str) -> Option<Self> {
        match value {
            "standard_pc_to_mac" => Some(Self::StandardPcToMac),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AppConfig {
    pub enabled: bool,
    pub launch_at_login: bool,
    pub preset: PresetKind,
    pub overrides: ModifierOverrides,
    pub device_selections: BTreeMap<String, bool>,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            launch_at_login: true,
            preset: PresetKind::StandardPcToMac,
            overrides: ModifierOverrides::default(),
            device_selections: BTreeMap::new(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PermissionAccess {
    Unknown,
    Granted,
    Denied,
}

impl Default for PermissionAccess {
    fn default() -> Self {
        Self::Unknown
    }
}

impl PermissionAccess {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::Granted => "granted",
            Self::Denied => "denied",
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PermissionState {
    pub hid_listen: PermissionAccess,
}

impl AppConfig {
    pub fn to_json(&self) -> String {
        let devices = self
            .device_selections
            .iter()
            .map(|(id, enabled)| format!("\"{}\":{}", escape_json(id), enabled))
            .collect::<Vec<_>>()
            .join(",");

        format!(
            "{{\"enabled\":{},\"launchAtLogin\":{},\"preset\":\"{}\",\"overrides\":{{\"swapLeftAltWin\":{},\"swapRightAltWin\":{},\"disableContextMenuRemap\":{}}},\"deviceSelections\":{{{}}}}}",
            self.enabled,
            self.launch_at_login,
            self.preset.as_str(),
            self.overrides.swap_left_alt_win,
            self.overrides.swap_right_alt_win,
            self.overrides.disable_context_menu_remap,
            devices
        )
    }

    pub fn from_json(source: &str) -> Result<Self, String> {
        let mut parser = JsonParser::new(source);
        let root = parser.parse_value()?;
        parser.consume_whitespace();
        if !parser.is_eof() {
            return Err("unexpected trailing characters".into());
        }

        let root = root.as_object()?;
        let overrides = root
            .get("overrides")
            .ok_or_else(|| "missing overrides".to_string())?
            .as_object()?;
        let device_map = root
            .get("deviceSelections")
            .ok_or_else(|| "missing deviceSelections".to_string())?
            .as_object()?;

        let mut device_selections = BTreeMap::new();
        for (key, value) in device_map {
            device_selections.insert(key.clone(), value.as_bool()?);
        }

        Ok(Self {
            enabled: root
                .get("enabled")
                .ok_or_else(|| "missing enabled".to_string())?
                .as_bool()?,
            launch_at_login: root
                .get("launchAtLogin")
                .ok_or_else(|| "missing launchAtLogin".to_string())?
                .as_bool()?,
            preset: PresetKind::from_str(
                root.get("preset")
                    .ok_or_else(|| "missing preset".to_string())?
                    .as_str()?,
            )
            .ok_or_else(|| "unsupported preset".to_string())?,
            overrides: ModifierOverrides {
                swap_left_alt_win: overrides
                    .get("swapLeftAltWin")
                    .ok_or_else(|| "missing swapLeftAltWin".to_string())?
                    .as_bool()?,
                swap_right_alt_win: overrides
                    .get("swapRightAltWin")
                    .ok_or_else(|| "missing swapRightAltWin".to_string())?
                    .as_bool()?,
                disable_context_menu_remap: overrides
                    .get("disableContextMenuRemap")
                    .ok_or_else(|| "missing disableContextMenuRemap".to_string())?
                    .as_bool()?,
            },
            device_selections,
        })
    }
}

fn escape_json(value: &str) -> String {
    let mut result = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '\\' => result.push_str("\\\\"),
            '"' => result.push_str("\\\""),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            _ => result.push(ch),
        }
    }
    result
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum JsonValue {
    Object(BTreeMap<String, JsonValue>),
    String(String),
    Bool(bool),
}

impl JsonValue {
    fn as_object(&self) -> Result<&BTreeMap<String, JsonValue>, String> {
        match self {
            Self::Object(value) => Ok(value),
            _ => Err("expected object".into()),
        }
    }

    fn as_str(&self) -> Result<&str, String> {
        match self {
            Self::String(value) => Ok(value),
            _ => Err("expected string".into()),
        }
    }

    fn as_bool(&self) -> Result<bool, String> {
        match self {
            Self::Bool(value) => Ok(*value),
            _ => Err("expected bool".into()),
        }
    }
}

struct JsonParser<'a> {
    source: &'a [u8],
    index: usize,
}

impl<'a> JsonParser<'a> {
    fn new(source: &'a str) -> Self {
        Self {
            source: source.as_bytes(),
            index: 0,
        }
    }

    fn parse_value(&mut self) -> Result<JsonValue, String> {
        self.consume_whitespace();
        match self.peek() {
            Some(b'{') => self.parse_object(),
            Some(b'"') => self.parse_string().map(JsonValue::String),
            Some(b't') | Some(b'f') => self.parse_bool().map(JsonValue::Bool),
            _ => Err("unexpected token".into()),
        }
    }

    fn parse_object(&mut self) -> Result<JsonValue, String> {
        self.expect(b'{')?;
        self.consume_whitespace();
        let mut values = BTreeMap::new();
        if self.peek() == Some(b'}') {
            self.index += 1;
            return Ok(JsonValue::Object(values));
        }

        loop {
            self.consume_whitespace();
            let key = self.parse_string()?;
            self.consume_whitespace();
            self.expect(b':')?;
            let value = self.parse_value()?;
            values.insert(key, value);
            self.consume_whitespace();
            match self.peek() {
                Some(b',') => {
                    self.index += 1;
                }
                Some(b'}') => {
                    self.index += 1;
                    break;
                }
                _ => return Err("expected , or }".into()),
            }
        }

        Ok(JsonValue::Object(values))
    }

    fn parse_string(&mut self) -> Result<String, String> {
        self.expect(b'"')?;
        let mut result = String::new();
        while let Some(byte) = self.next() {
            match byte {
                b'"' => return Ok(result),
                b'\\' => match self.next().ok_or_else(|| "unterminated escape".to_string())? {
                    b'"' => result.push('"'),
                    b'\\' => result.push('\\'),
                    b'n' => result.push('\n'),
                    b'r' => result.push('\r'),
                    b't' => result.push('\t'),
                    other => return Err(format!("unsupported escape: {}", other as char)),
                },
                other => result.push(other as char),
            }
        }
        Err("unterminated string".into())
    }

    fn parse_bool(&mut self) -> Result<bool, String> {
        if self.remaining_starts_with(b"true") {
            self.index += 4;
            Ok(true)
        } else if self.remaining_starts_with(b"false") {
            self.index += 5;
            Ok(false)
        } else {
            Err("invalid bool".into())
        }
    }

    fn consume_whitespace(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\n' | b'\r' | b'\t')) {
            self.index += 1;
        }
    }

    fn expect(&mut self, expected: u8) -> Result<(), String> {
        match self.next() {
            Some(byte) if byte == expected => Ok(()),
            _ => Err(format!("expected {}", expected as char)),
        }
    }

    fn peek(&self) -> Option<u8> {
        self.source.get(self.index).copied()
    }

    fn next(&mut self) -> Option<u8> {
        let byte = self.peek()?;
        self.index += 1;
        Some(byte)
    }

    fn remaining_starts_with(&self, prefix: &[u8]) -> bool {
        self.source[self.index..].starts_with(prefix)
    }

    fn is_eof(&self) -> bool {
        self.index >= self.source.len()
    }
}

#[cfg(test)]
mod tests {
    use super::{AppConfig, ModifierOverrides};

    #[test]
    fn config_round_trip() {
        let mut config = AppConfig::default();
        config.enabled = false;
        config.launch_at_login = false;
        config.overrides = ModifierOverrides {
            swap_left_alt_win: true,
            swap_right_alt_win: false,
            disable_context_menu_remap: true,
        };
        config
            .device_selections
            .insert("usb-1".to_string(), true);
        config
            .device_selections
            .insert("usb-2".to_string(), false);

        let json = config.to_json();
        let reparsed = AppConfig::from_json(&json).expect("config should parse");
        assert_eq!(reparsed, config);
    }

    #[test]
    fn empty_device_map_is_supported() {
        let config = AppConfig::default();
        let json = config.to_json();
        let reparsed = AppConfig::from_json(&json).expect("config should parse");
        assert!(reparsed.device_selections.is_empty());
    }
}
