mod config;
mod mapping;

use config::{AppConfig, PermissionAccess, PermissionState};
use std::collections::BTreeMap;
use std::ffi::{CStr, CString};
use std::fs::OpenOptions;
use std::io::Write;
use std::os::raw::{c_char, c_void};
use std::process::Command;
use std::ptr;
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};

pub use config::{ModifierOverrides, PresetKind};
pub use mapping::{modifier_remap_entries, user_key_mapping_json};

type Boolean = u8;
type CFAllocatorRef = *const c_void;
type CFTypeRef = *const c_void;
type CFStringRef = *const c_void;
type CFNumberRef = *const c_void;
type CFBooleanRef = *const c_void;
type CFDictionaryRef = *const c_void;
type CFArrayRef = *const c_void;
type CFSetRef = *const c_void;
type CFRunLoopRef = *const c_void;
type CFTypeID = usize;
type CFIndex = isize;
type CFTimeInterval = f64;
type IOReturn = i32;
type IOOptionBits = u32;
type IOHIDManagerRef = *mut c_void;
type IOHIDDeviceRef = *mut c_void;

#[repr(C)]
struct CFArrayCallBacks {
    version: CFIndex,
    retain: *const c_void,
    release: *const c_void,
    copy_description: *const c_void,
    equal: *const c_void,
}

#[repr(C)]
struct CFDictionaryKeyCallBacks {
    version: CFIndex,
    retain: *const c_void,
    release: *const c_void,
    copy_description: *const c_void,
    equal: *const c_void,
    hash: *const c_void,
}

#[repr(C)]
struct CFDictionaryValueCallBacks {
    version: CFIndex,
    retain: *const c_void,
    release: *const c_void,
    copy_description: *const c_void,
    equal: *const c_void,
}

const K_CF_STRING_ENCODING_UTF8: u32 = 0x08000100;
const K_CF_NUMBER_SINT64_TYPE: i32 = 4;
const K_IO_HID_OPTIONS_TYPE_NONE: IOOptionBits = 0;
const K_IO_HID_REQUEST_TYPE_LISTEN_EVENT: u32 = 1;
const K_IO_HID_ACCESS_GRANTED: u32 = 0;
const K_IO_HID_ACCESS_DENIED: u32 = 1;
const K_IO_HID_ACCESS_UNKNOWN: u32 = 2;
const K_IO_RETURN_SUCCESS: IOReturn = 0;
const K_IO_RETURN_UNSUPPORTED: IOReturn = -536_870_201;
const K_IO_RETURN_NOT_PERMITTED: IOReturn = -536_870_174;
const K_IO_HID_USAGE_PAGE_GENERIC_DESKTOP: i64 = 0x01;
const K_IO_HID_USAGE_KEYBOARD: i64 = 0x06;

type IOHIDDeviceCallback =
    Option<unsafe extern "C" fn(*mut c_void, IOReturn, *mut c_void, IOHIDDeviceRef)>;

#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFRetain(cf: CFTypeRef) -> CFTypeRef;
    fn CFRelease(cf: CFTypeRef);
    fn CFGetTypeID(cf: CFTypeRef) -> CFTypeID;
    fn CFStringGetTypeID() -> CFTypeID;
    fn CFNumberGetTypeID() -> CFTypeID;
    fn CFBooleanGetTypeID() -> CFTypeID;
    fn CFArrayGetTypeID() -> CFTypeID;
    fn CFDictionaryGetTypeID() -> CFTypeID;
    fn CFNumberCreate(
        allocator: CFAllocatorRef,
        number_type: i32,
        value_ptr: *const c_void,
    ) -> CFNumberRef;
    fn CFStringCreateWithCString(
        alloc: CFAllocatorRef,
        c_str: *const c_char,
        encoding: u32,
    ) -> CFStringRef;
    fn CFStringGetCString(
        string: CFStringRef,
        buffer: *mut c_char,
        buffer_size: CFIndex,
        encoding: u32,
    ) -> Boolean;
    fn CFNumberGetValue(number: CFNumberRef, number_type: i32, value_ptr: *mut c_void) -> Boolean;
    fn CFBooleanGetValue(boolean: CFBooleanRef) -> Boolean;
    fn CFRunLoopGetCurrent() -> CFRunLoopRef;
    fn CFRunLoopRunInMode(
        mode: CFStringRef,
        seconds: CFTimeInterval,
        return_after_source_handled: Boolean,
    ) -> i32;
    fn CFRunLoopStop(run_loop: CFRunLoopRef);
    fn CFArrayGetCount(the_array: CFArrayRef) -> CFIndex;
    fn CFArrayGetValueAtIndex(the_array: CFArrayRef, idx: CFIndex) -> *const c_void;
    fn CFArrayCreate(
        allocator: CFAllocatorRef,
        values: *const *const c_void,
        num_values: CFIndex,
        callbacks: *const CFArrayCallBacks,
    ) -> CFArrayRef;
    fn CFDictionaryCreate(
        allocator: CFAllocatorRef,
        keys: *const *const c_void,
        values: *const *const c_void,
        num_values: CFIndex,
        key_callbacks: *const CFDictionaryKeyCallBacks,
        value_callbacks: *const CFDictionaryValueCallBacks,
    ) -> CFDictionaryRef;
    fn CFDictionaryGetValue(the_dict: CFDictionaryRef, key: *const c_void) -> *const c_void;
    fn CFSetGetCount(the_set: CFSetRef) -> CFIndex;
    fn CFSetGetValues(the_set: CFSetRef, values: *mut *const c_void);
    static kCFRunLoopDefaultMode: CFStringRef;
    static kCFTypeArrayCallBacks: CFArrayCallBacks;
    static kCFTypeDictionaryKeyCallBacks: CFDictionaryKeyCallBacks;
    static kCFTypeDictionaryValueCallBacks: CFDictionaryValueCallBacks;
}

#[link(name = "IOKit", kind = "framework")]
extern "C" {
    fn IOHIDCheckAccess(request_type: u32) -> u32;
    fn IOHIDRequestAccess(request_type: u32) -> Boolean;
    fn IOHIDManagerCreate(allocator: CFAllocatorRef, options: IOOptionBits) -> IOHIDManagerRef;
    fn IOHIDManagerOpen(manager: IOHIDManagerRef, options: IOOptionBits) -> IOReturn;
    fn IOHIDManagerClose(manager: IOHIDManagerRef, options: IOOptionBits) -> IOReturn;
    fn IOHIDManagerSetDeviceMatching(manager: IOHIDManagerRef, matching: CFDictionaryRef);
    fn IOHIDManagerCopyDevices(manager: IOHIDManagerRef) -> CFSetRef;
    fn IOHIDManagerRegisterDeviceMatchingCallback(
        manager: IOHIDManagerRef,
        callback: IOHIDDeviceCallback,
        context: *mut c_void,
    );
    fn IOHIDManagerRegisterDeviceRemovalCallback(
        manager: IOHIDManagerRef,
        callback: IOHIDDeviceCallback,
        context: *mut c_void,
    );
    fn IOHIDManagerScheduleWithRunLoop(
        manager: IOHIDManagerRef,
        run_loop: CFRunLoopRef,
        run_loop_mode: CFStringRef,
    );
    fn IOHIDManagerUnscheduleFromRunLoop(
        manager: IOHIDManagerRef,
        run_loop: CFRunLoopRef,
        run_loop_mode: CFStringRef,
    );
    fn IOHIDDeviceGetProperty(device: IOHIDDeviceRef, key: CFStringRef) -> CFTypeRef;
}

#[derive(Clone, Debug)]
struct DeviceDescriptor {
    id: String,
    name: String,
    manufacturer: String,
    transport: String,
    vendor_id: i64,
    product_id: i64,
    location_id: i64,
    built_in: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RemapMode {
    System,
}

impl RemapMode {
    fn as_str(self) -> &'static str {
        match self {
            Self::System => "system",
        }
    }
}

#[derive(Debug)]
struct DeviceRecord {
    descriptor: DeviceDescriptor,
    device: IOHIDDeviceRef,
    selected: bool,
    active: bool,
    remap_mode: Option<RemapMode>,
    last_error: Option<String>,
}

impl Drop for DeviceRecord {
    fn drop(&mut self) {
        unsafe {
            if !self.device.is_null() {
                CFRelease(self.device as CFTypeRef);
            }
        }
    }
}

unsafe impl Send for DeviceRecord {}

#[derive(Debug, Default)]
struct EngineState {
    running: bool,
    stop_requested: bool,
    config: AppConfig,
    permissions: PermissionState,
    startup_error: Option<String>,
    devices: BTreeMap<String, DeviceRecord>,
    run_loop: Option<CFRunLoopRef>,
    manager: Option<IOHIDManagerRef>,
}

unsafe impl Send for EngineState {}

#[derive(Debug, Default)]
struct SharedEngine {
    state: Mutex<EngineState>,
}

pub struct Engine {
    shared: Arc<SharedEngine>,
    worker: Mutex<Option<JoinHandle<()>>>,
}

impl Default for Engine {
    fn default() -> Self {
        Self {
            shared: Arc::new(SharedEngine::default()),
            worker: Mutex::new(None),
        }
    }
}

impl Engine {
    fn start(&self) -> bool {
        let mut worker = self.worker.lock().expect("worker mutex poisoned");
        if worker.is_some() {
            return false;
        }

        {
            let mut state = self.shared.state.lock().expect("state mutex poisoned");
            request_missing_permissions(&mut state.permissions);
            state.permissions = refresh_permission_state();
            state.startup_error = None;
            state.stop_requested = false;
        }

        let shared = Arc::clone(&self.shared);
        *worker = Some(thread::spawn(move || run_engine_thread(shared)));
        true
    }

    fn stop(&self) {
        let handle = self.worker.lock().expect("worker mutex poisoned").take();
        if let Some(handle) = handle {
            let run_loop = {
                let mut state = self.shared.state.lock().expect("state mutex poisoned");
                state.stop_requested = true;
                state.run_loop
            };

            if let Some(run_loop) = run_loop {
                unsafe { CFRunLoopStop(run_loop) };
            }

            let _ = handle.join();
        }
    }

    fn snapshot_json(&self) -> String {
        let state = self.shared.state.lock().expect("state mutex poisoned");
        let status = if !state.running {
            "stopped"
        } else if state.startup_error.is_some()
            || state.permissions.hid_listen != PermissionAccess::Granted
        {
            "degraded"
        } else {
            "running"
        };

        let devices = state
            .devices
            .values()
            .map(|device| {
                format!(
                    "{{\"id\":\"{}\",\"name\":\"{}\",\"manufacturer\":\"{}\",\"transport\":\"{}\",\"vendorId\":{},\"productId\":{},\"locationId\":{},\"builtIn\":{},\"selected\":{},\"active\":{},\"remapMode\":{},\"lastError\":{}}}",
                    escape_json(&device.descriptor.id),
                    escape_json(&device.descriptor.name),
                    escape_json(&device.descriptor.manufacturer),
                    escape_json(&device.descriptor.transport),
                    device.descriptor.vendor_id,
                    device.descriptor.product_id,
                    device.descriptor.location_id,
                    device.descriptor.built_in,
                    device.selected,
                    device.active,
                    match device.remap_mode {
                        Some(mode) => format!("\"{}\"", mode.as_str()),
                        None => "null".to_string(),
                    },
                    match &device.last_error {
                        Some(value) => format!("\"{}\"", escape_json(value)),
                        None => "null".to_string(),
                    }
                )
            })
            .collect::<Vec<_>>()
            .join(",");

        format!(
            "{{\"engineStatus\":\"{}\",\"enabled\":{},\"preset\":\"{}\",\"permissions\":{{\"hidListen\":\"{}\"}},\"overrides\":{{\"swapLeftAltWin\":{},\"swapRightAltWin\":{},\"disableContextMenuRemap\":{}}},\"startupError\":{},\"devices\":[{}]}}",
            status,
            state.config.enabled,
            state.config.preset.as_str(),
            state.permissions.hid_listen.as_str(),
            state.config.overrides.swap_left_alt_win,
            state.config.overrides.swap_right_alt_win,
            state.config.overrides.disable_context_menu_remap,
            match &state.startup_error {
                Some(value) => format!("\"{}\"", escape_json(value)),
                None => "null".to_string(),
            },
            devices
        )
    }

    fn request_permissions(&self) -> bool {
        let granted = unsafe { IOHIDRequestAccess(K_IO_HID_REQUEST_TYPE_LISTEN_EVENT) != 0 };
        let mut state = self.shared.state.lock().expect("state mutex poisoned");
        state.permissions = refresh_permission_state();
        granted
    }

    fn set_global_enabled(&self, enabled: bool) {
        let mut state = self.shared.state.lock().expect("state mutex poisoned");
        state.config.enabled = enabled;
        sync_all_devices_locked(&mut state);
    }

    fn set_overrides(
        &self,
        swap_left_alt_win: bool,
        swap_right_alt_win: bool,
        disable_context_menu_remap: bool,
    ) {
        let mut state = self.shared.state.lock().expect("state mutex poisoned");
        state.config.overrides.swap_left_alt_win = swap_left_alt_win;
        state.config.overrides.swap_right_alt_win = swap_right_alt_win;
        state.config.overrides.disable_context_menu_remap = disable_context_menu_remap;
        sync_all_devices_locked(&mut state);
    }

    fn set_device_enabled(&self, identifier: &str, enabled: bool) {
        let mut state = self.shared.state.lock().expect("state mutex poisoned");
        state
            .config
            .device_selections
            .insert(identifier.to_string(), enabled);
        if let Some(device) = state.devices.get_mut(identifier) {
            device.selected = enabled;
        }
        sync_all_devices_locked(&mut state);
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        self.stop();
    }
}

fn run_engine_thread(shared: Arc<SharedEngine>) {
    let context = Arc::into_raw(Arc::clone(&shared)) as *mut c_void;
    log_debug("engine thread starting");

    unsafe {
        let run_loop = CFRunLoopGetCurrent();
        if run_loop.is_null() {
            let mut state = shared.state.lock().expect("state mutex poisoned");
            state.startup_error = Some("failed to obtain run loop".to_string());
            state.running = false;
            let _ = Arc::from_raw(context as *const SharedEngine);
            return;
        }

        CFRetain(run_loop as CFTypeRef);

        let manager = IOHIDManagerCreate(ptr::null(), K_IO_HID_OPTIONS_TYPE_NONE);
        if manager.is_null() {
            let mut state = shared.state.lock().expect("state mutex poisoned");
            state.startup_error = Some("failed to create IOHIDManager".to_string());
            state.running = false;
            CFRelease(run_loop as CFTypeRef);
            let _ = Arc::from_raw(context as *const SharedEngine);
            return;
        }

        if let Some(matching) = create_keyboard_matching_dictionary() {
            IOHIDManagerSetDeviceMatching(manager, matching);
            CFRelease(matching as CFTypeRef);
        }

        IOHIDManagerRegisterDeviceMatchingCallback(manager, Some(device_matched_callback), context);
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Some(device_removed_callback), context);
        IOHIDManagerScheduleWithRunLoop(manager, run_loop, kCFRunLoopDefaultMode);

        let open_result = IOHIDManagerOpen(manager, K_IO_HID_OPTIONS_TYPE_NONE);
        log_debug(&format!("IOHIDManagerOpen -> {}", open_result));

        {
            let mut state = shared.state.lock().expect("state mutex poisoned");
            state.run_loop = Some(run_loop);
            state.manager = Some(manager);
            state.permissions = refresh_permission_state();
            state.running = open_result == K_IO_RETURN_SUCCESS;
            if open_result != K_IO_RETURN_SUCCESS {
                state.startup_error = Some(format_io_return_error(open_result));
            }
        }

        if open_result == K_IO_RETURN_SUCCESS {
            enumerate_existing_devices(&shared, manager);
            loop {
                let should_stop = {
                    let state = shared.state.lock().expect("state mutex poisoned");
                    state.stop_requested
                };
                if should_stop {
                    break;
                }
                let _ = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, 0);
            }
        }

        let mut state = shared.state.lock().expect("state mutex poisoned");
        deactivate_all_devices_locked(&mut state, false);
        if let Some(manager) = state.manager.take() {
            IOHIDManagerUnscheduleFromRunLoop(manager, run_loop, kCFRunLoopDefaultMode);
            let _ = IOHIDManagerClose(manager, K_IO_HID_OPTIONS_TYPE_NONE);
            CFRelease(manager as CFTypeRef);
        }
        state.devices.clear();
        state.run_loop = None;
        state.running = false;
        log_debug("engine thread stopping");

        CFRelease(run_loop as CFTypeRef);
        let _ = Arc::from_raw(context as *const SharedEngine);
    }
}

fn enumerate_existing_devices(shared: &SharedEngine, manager: IOHIDManagerRef) {
    unsafe {
        let devices = IOHIDManagerCopyDevices(manager);
        if devices.is_null() {
            log_debug("IOHIDManagerCopyDevices -> null");
            return;
        }

        let count = CFSetGetCount(devices);
        log_debug(&format!("IOHIDManagerCopyDevices count -> {}", count));
        if count > 0 {
            let mut values = vec![ptr::null(); count as usize];
            CFSetGetValues(devices, values.as_mut_ptr());
            for value in values {
                if !value.is_null() {
                    handle_device_arrival(shared, value as IOHIDDeviceRef);
                }
            }
        }

        CFRelease(devices as CFTypeRef);
    }
}

unsafe extern "C" fn device_matched_callback(
    context: *mut c_void,
    result: IOReturn,
    _sender: *mut c_void,
    device: IOHIDDeviceRef,
) {
    if context.is_null() || device.is_null() || result != K_IO_RETURN_SUCCESS {
        return;
    }
    let shared = &*(context as *const SharedEngine);
    handle_device_arrival(shared, device);
}

unsafe extern "C" fn device_removed_callback(
    context: *mut c_void,
    result: IOReturn,
    _sender: *mut c_void,
    device: IOHIDDeviceRef,
) {
    if context.is_null() || device.is_null() || result != K_IO_RETURN_SUCCESS {
        return;
    }
    let shared = &*(context as *const SharedEngine);
    handle_device_removal(shared, device);
}

unsafe fn handle_device_arrival(shared: &SharedEngine, device: IOHIDDeviceRef) {
    let Some(descriptor) = build_device_descriptor(device) else {
        return;
    };

    log_debug(&format!(
        "device detected: {} transport={} built_in={}",
        descriptor.name, descriptor.transport, descriptor.built_in
    ));

    let mut state = shared.state.lock().expect("state mutex poisoned");
    let selected = state
        .config
        .device_selections
        .get(&descriptor.id)
        .copied()
        .unwrap_or(!descriptor.built_in);

    let identifier = descriptor.id.clone();
    if let Some(mut existing) = state.devices.remove(&identifier) {
        deactivate_record(&mut existing, false);
    }

    CFRetain(device as CFTypeRef);
    state.devices.insert(
        identifier.clone(),
        DeviceRecord {
            descriptor,
            device,
            selected,
            active: false,
            remap_mode: None,
            last_error: None,
        },
    );

    sync_device_locked(&mut state, &identifier);
}

unsafe fn handle_device_removal(shared: &SharedEngine, device: IOHIDDeviceRef) {
    let mut state = shared.state.lock().expect("state mutex poisoned");
    let identifier = state
        .devices
        .iter()
        .find(|(_, record)| record.device == device)
        .map(|(identifier, _)| identifier.clone());

    if let Some(identifier) = identifier {
        if let Some(mut record) = state.devices.remove(&identifier) {
            deactivate_record(&mut record, false);
        }
    }
}

fn sync_all_devices_locked(state: &mut EngineState) {
    let identifiers = state.devices.keys().cloned().collect::<Vec<_>>();
    for identifier in identifiers {
        sync_device_locked(state, &identifier);
    }
}

fn sync_device_locked(state: &mut EngineState, identifier: &str) {
    let config_enabled = state.config.enabled;
    let overrides = state.config.overrides.clone();

    if let Some(record) = state.devices.get_mut(identifier) {
        let should_remap = config_enabled && record.selected;
        if should_remap {
            match apply_hidutil_mapping(&record.descriptor, &overrides) {
                Ok(()) => {
                    if !record.active || record.remap_mode != Some(RemapMode::System) {
                        log_debug(&format!("system remap active for {}", record.descriptor.name));
                    }
                    record.active = true;
                    record.remap_mode = Some(RemapMode::System);
                    record.last_error = None;
                }
                Err(error) => {
                    record.active = false;
                    record.remap_mode = None;
                    record.last_error = Some(error.clone());
                    log_debug(&format!(
                        "failed to apply system remap for {}: {}",
                        record.descriptor.name, error
                    ));
                }
            }
        } else {
            deactivate_record(record, record.active);
        }
    }
}

fn deactivate_all_devices_locked(state: &mut EngineState, report_errors: bool) {
    for record in state.devices.values_mut() {
        deactivate_record(record, report_errors);
    }
}

fn deactivate_record(record: &mut DeviceRecord, report_errors: bool) {
    let was_active = record.active;
    match clear_hidutil_mapping(&record.descriptor) {
        Ok(()) => {
            if was_active {
                log_debug(&format!("system remap cleared for {}", record.descriptor.name));
            }
            record.active = false;
            record.remap_mode = None;
            record.last_error = None;
        }
        Err(error) => {
            record.active = false;
            record.remap_mode = None;
            if report_errors {
                record.last_error = Some(error.clone());
                log_debug(&format!(
                    "failed to clear system remap for {}: {}",
                    record.descriptor.name, error
                ));
            } else {
                record.last_error = None;
            }
        }
    }
}

fn refresh_permission_state() -> PermissionState {
    let hid_access = unsafe { IOHIDCheckAccess(K_IO_HID_REQUEST_TYPE_LISTEN_EVENT) };
    let hid_listen = match hid_access {
        K_IO_HID_ACCESS_GRANTED => PermissionAccess::Granted,
        K_IO_HID_ACCESS_DENIED => PermissionAccess::Denied,
        K_IO_HID_ACCESS_UNKNOWN => PermissionAccess::Unknown,
        _ => PermissionAccess::Unknown,
    };
    PermissionState { hid_listen }
}

fn request_missing_permissions(permissions: &mut PermissionState) {
    if permissions.hid_listen != PermissionAccess::Granted {
        let result = unsafe { IOHIDRequestAccess(K_IO_HID_REQUEST_TYPE_LISTEN_EVENT) != 0 };
        log_debug(&format!("IOHIDRequestAccess(listen) -> {}", result));
    }
}

fn format_io_return_error(code: IOReturn) -> String {
    match code {
        K_IO_RETURN_NOT_PERMITTED => {
            "Input Monitoring is not granted. Enable MacKeyMap in System Settings > Privacy & Security > Input Monitoring, then reopen the app.".to_string()
        }
        K_IO_RETURN_UNSUPPORTED => {
            "failed to open IOHIDManager: unsupported matching configuration".to_string()
        }
        _ => format!("failed to open IOHIDManager ({code})"),
    }
}

unsafe fn build_device_descriptor(device: IOHIDDeviceRef) -> Option<DeviceDescriptor> {
    if !device_supports_keyboard(device) {
        return None;
    }

    let vendor_id = get_number_property(device, "VendorID").unwrap_or_default();
    let product_id = get_number_property(device, "ProductID").unwrap_or_default();
    let location_id = get_number_property(device, "LocationID").unwrap_or_default();
    let transport = get_string_property(device, "Transport").unwrap_or_else(|| "Unknown".into());
    let manufacturer = get_string_property(device, "Manufacturer").unwrap_or_default();
    let product = get_string_property(device, "Product").unwrap_or_else(|| "Keyboard".into());
    let built_in = get_bool_property(device, "Built-In").unwrap_or(false);

    let name = if manufacturer.is_empty() {
        product.clone()
    } else {
        format!("{} {}", manufacturer, product)
    };

    let id = format!(
        "{}:{}:{}:{}",
        vendor_id,
        product_id,
        transport.to_lowercase(),
        location_id
    );

    Some(DeviceDescriptor {
        id,
        name,
        manufacturer,
        transport,
        vendor_id,
        product_id,
        location_id,
        built_in,
    })
}

unsafe fn device_supports_keyboard(device: IOHIDDeviceRef) -> bool {
    let primary_usage_page = get_number_property(device, "PrimaryUsagePage");
    let primary_usage = get_number_property(device, "PrimaryUsage");
    if primary_usage_page.is_some() || primary_usage.is_some() {
        return matches!(
            (primary_usage_page, primary_usage),
            (Some(K_IO_HID_USAGE_PAGE_GENERIC_DESKTOP), Some(K_IO_HID_USAGE_KEYBOARD))
        );
    }

    let device_usage_page = get_number_property(device, "DeviceUsagePage");
    let device_usage = get_number_property(device, "DeviceUsage");
    if device_usage_page.is_some() || device_usage.is_some() {
        return matches!(
            (device_usage_page, device_usage),
            (Some(K_IO_HID_USAGE_PAGE_GENERIC_DESKTOP), Some(K_IO_HID_USAGE_KEYBOARD))
        );
    }

    property_has_keyboard_usage_pair(device, "DeviceUsagePairs").unwrap_or(false)
}

unsafe fn property_has_keyboard_usage_pair(device: IOHIDDeviceRef, key: &str) -> Option<bool> {
    let key_ref = cfstring(key)?;
    let value = IOHIDDeviceGetProperty(device, key_ref);
    CFRelease(key_ref as CFTypeRef);
    if value.is_null() || CFGetTypeID(value) != CFArrayGetTypeID() {
        return None;
    }

    let array = value as CFArrayRef;
    let count = CFArrayGetCount(array);
    for index in 0..count {
        let item = CFArrayGetValueAtIndex(array, index);
        if item.is_null() || CFGetTypeID(item) != CFDictionaryGetTypeID() {
            continue;
        }

        let usage_page = get_number_from_dictionary(item as CFDictionaryRef, "DeviceUsagePage");
        let usage = get_number_from_dictionary(item as CFDictionaryRef, "DeviceUsage");
        if matches!(
            (usage_page, usage),
            (Some(K_IO_HID_USAGE_PAGE_GENERIC_DESKTOP), Some(K_IO_HID_USAGE_KEYBOARD))
        ) {
            return Some(true);
        }
    }

    Some(false)
}

unsafe fn get_number_from_dictionary(dictionary: CFDictionaryRef, key: &str) -> Option<i64> {
    let key_ref = cfstring(key)?;
    let value = CFDictionaryGetValue(dictionary, key_ref);
    CFRelease(key_ref as CFTypeRef);
    if value.is_null() || CFGetTypeID(value) != CFNumberGetTypeID() {
        return None;
    }

    let mut out: i64 = 0;
    if CFNumberGetValue(
        value as CFNumberRef,
        K_CF_NUMBER_SINT64_TYPE,
        (&mut out as *mut i64).cast::<c_void>(),
    ) == 0
    {
        return None;
    }
    Some(out)
}

unsafe fn get_string_property(device: IOHIDDeviceRef, key: &str) -> Option<String> {
    let key_ref = cfstring(key)?;
    let value = IOHIDDeviceGetProperty(device, key_ref);
    CFRelease(key_ref as CFTypeRef);
    if value.is_null() || CFGetTypeID(value) != CFStringGetTypeID() {
        return None;
    }

    let mut buffer = vec![0_i8; 1024];
    if CFStringGetCString(
        value as CFStringRef,
        buffer.as_mut_ptr(),
        buffer.len() as CFIndex,
        K_CF_STRING_ENCODING_UTF8,
    ) == 0
    {
        return None;
    }

    Some(CStr::from_ptr(buffer.as_ptr()).to_string_lossy().into_owned())
}

unsafe fn get_number_property(device: IOHIDDeviceRef, key: &str) -> Option<i64> {
    let key_ref = cfstring(key)?;
    let value = IOHIDDeviceGetProperty(device, key_ref);
    CFRelease(key_ref as CFTypeRef);
    if value.is_null() || CFGetTypeID(value) != CFNumberGetTypeID() {
        return None;
    }

    let mut out: i64 = 0;
    if CFNumberGetValue(
        value as CFNumberRef,
        K_CF_NUMBER_SINT64_TYPE,
        (&mut out as *mut i64).cast::<c_void>(),
    ) == 0
    {
        return None;
    }
    Some(out)
}

unsafe fn get_bool_property(device: IOHIDDeviceRef, key: &str) -> Option<bool> {
    let key_ref = cfstring(key)?;
    let value = IOHIDDeviceGetProperty(device, key_ref);
    CFRelease(key_ref as CFTypeRef);
    if value.is_null() || CFGetTypeID(value) != CFBooleanGetTypeID() {
        return None;
    }

    Some(CFBooleanGetValue(value as CFBooleanRef) != 0)
}

unsafe fn create_keyboard_matching_dictionary() -> Option<CFDictionaryRef> {
    let usage_page_key = cfstring("DeviceUsagePage")?;
    let usage_key = cfstring("DeviceUsage")?;
    let usage_pairs_key = cfstring("DeviceUsagePairs")?;

    let usage_page_value = cfnumber(K_IO_HID_USAGE_PAGE_GENERIC_DESKTOP)?;
    let usage_value = cfnumber(K_IO_HID_USAGE_KEYBOARD)?;

    let pair_keys = [usage_page_key.cast::<c_void>(), usage_key.cast::<c_void>()];
    let pair_values = [
        usage_page_value.cast::<c_void>(),
        usage_value.cast::<c_void>(),
    ];
    let pair = CFDictionaryCreate(
        ptr::null(),
        pair_keys.as_ptr(),
        pair_values.as_ptr(),
        pair_keys.len() as CFIndex,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks,
    );

    let result = if pair.is_null() {
        None
    } else {
        let pair_values = [pair.cast::<c_void>()];
        let usage_pairs = CFArrayCreate(
            ptr::null(),
            pair_values.as_ptr(),
            pair_values.len() as CFIndex,
            &kCFTypeArrayCallBacks,
        );
        if usage_pairs.is_null() {
            None
        } else {
            let keys = [usage_pairs_key.cast::<c_void>()];
            let values = [usage_pairs.cast::<c_void>()];
            let matching = CFDictionaryCreate(
                ptr::null(),
                keys.as_ptr(),
                values.as_ptr(),
                keys.len() as CFIndex,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks,
            );
            CFRelease(usage_pairs as CFTypeRef);
            if matching.is_null() {
                None
            } else {
                Some(matching)
            }
        }
    };

    if !pair.is_null() {
        CFRelease(pair as CFTypeRef);
    }
    CFRelease(usage_page_value as CFTypeRef);
    CFRelease(usage_value as CFTypeRef);
    CFRelease(usage_page_key as CFTypeRef);
    CFRelease(usage_key as CFTypeRef);
    CFRelease(usage_pairs_key as CFTypeRef);

    result
}

unsafe fn cfstring(value: &str) -> Option<CFStringRef> {
    let c_string = CString::new(value).ok()?;
    let string = CFStringCreateWithCString(ptr::null(), c_string.as_ptr(), K_CF_STRING_ENCODING_UTF8);
    if string.is_null() {
        None
    } else {
        Some(string)
    }
}

unsafe fn cfnumber(value: i64) -> Option<CFNumberRef> {
    let number = CFNumberCreate(
        ptr::null(),
        K_CF_NUMBER_SINT64_TYPE,
        (&value as *const i64).cast::<c_void>(),
    );
    if number.is_null() {
        None
    } else {
        Some(number)
    }
}

fn apply_hidutil_mapping(
    descriptor: &DeviceDescriptor,
    overrides: &ModifierOverrides,
) -> Result<(), String> {
    run_hidutil_property(descriptor, &user_key_mapping_json(overrides))
}

fn clear_hidutil_mapping(descriptor: &DeviceDescriptor) -> Result<(), String> {
    run_hidutil_property(descriptor, "{\"UserKeyMapping\":[]}")
}

fn run_hidutil_property(descriptor: &DeviceDescriptor, settings_json: &str) -> Result<(), String> {
    let matching_json = format!(
        "{{\"VendorID\":{},\"ProductID\":{},\"LocationID\":{},\"Transport\":\"{}\",\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}}",
        descriptor.vendor_id,
        descriptor.product_id,
        descriptor.location_id,
        escape_json(&descriptor.transport),
    );

    let output = Command::new("/usr/bin/hidutil")
        .args(["property", "--matching", &matching_json, "--set", settings_json])
        .output()
        .map_err(|error| format!("failed to execute hidutil: {error}"))?;

    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            Err(format!(
                "hidutil failed for {} with status {}",
                descriptor.name, output.status
            ))
        } else {
            Err(format!("hidutil failed for {}: {}", descriptor.name, stderr))
        }
    }
}

fn escape_json(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '\\' => escaped.push_str("\\\\"),
            '"' => escaped.push_str("\\\""),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            _ => escaped.push(ch),
        }
    }
    escaped
}

fn bool_from_u8(value: u8) -> bool {
    value != 0
}

fn log_debug(message: &str) {
    let path = "/tmp/MacKeyMap.log";
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{message}");
    }
}

unsafe fn engine_from_ptr<'a>(ptr: *mut Engine) -> Option<&'a Engine> {
    ptr.as_ref()
}

#[no_mangle]
pub extern "C" fn mackeymap_engine_create() -> *mut Engine {
    Box::into_raw(Box::new(Engine::default()))
}

#[no_mangle]
pub unsafe extern "C" fn mackeymap_engine_destroy(engine: *mut Engine) {
    if engine.is_null() {
        return;
    }
    drop(Box::from_raw(engine));
}

#[no_mangle]
pub unsafe extern "C" fn mackeymap_engine_start(engine: *mut Engine) -> u8 {
    engine_from_ptr(engine)
        .map(|engine| if engine.start() { 1 } else { 0 })
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn mackeymap_engine_stop(engine: *mut Engine) {
    if let Some(engine) = engine_from_ptr(engine) {
        engine.stop();
    }
}

#[no_mangle]
pub unsafe extern "C" fn mackeymap_engine_request_permissions(engine: *mut Engine) -> u8 {
    engine_from_ptr(engine)
        .map(|engine| if engine.request_permissions() { 1 } else { 0 })
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn mackeymap_engine_set_global_enabled(engine: *mut Engine, enabled: u8) {
    if let Some(engine) = engine_from_ptr(engine) {
        engine.set_global_enabled(bool_from_u8(enabled));
    }
}

#[no_mangle]
pub unsafe extern "C" fn mackeymap_engine_set_overrides(
    engine: *mut Engine,
    swap_left_alt_win: u8,
    swap_right_alt_win: u8,
    disable_context_menu_remap: u8,
) {
    if let Some(engine) = engine_from_ptr(engine) {
        engine.set_overrides(
            bool_from_u8(swap_left_alt_win),
            bool_from_u8(swap_right_alt_win),
            bool_from_u8(disable_context_menu_remap),
        );
    }
}

#[no_mangle]
pub unsafe extern "C" fn mackeymap_engine_set_device_enabled(
    engine: *mut Engine,
    identifier: *const c_char,
    enabled: u8,
) {
    let Some(engine) = engine_from_ptr(engine) else {
        return;
    };
    if identifier.is_null() {
        return;
    }
    let Ok(identifier) = CStr::from_ptr(identifier).to_str() else {
        return;
    };
    engine.set_device_enabled(identifier, bool_from_u8(enabled));
}

#[no_mangle]
pub unsafe extern "C" fn mackeymap_engine_copy_snapshot_json(
    engine: *mut Engine,
) -> *mut c_char {
    let Some(engine) = engine_from_ptr(engine) else {
        return ptr::null_mut();
    };
    let snapshot = engine.snapshot_json();
    CString::new(snapshot)
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn mackeymap_string_free(raw: *mut c_char) {
    if raw.is_null() {
        return;
    }
    drop(CString::from_raw(raw));
}

#[cfg(test)]
mod tests {
    use super::{config::AppConfig, config::ModifierOverrides, escape_json};

    #[test]
    fn json_escaping_handles_quotes() {
        assert_eq!(escape_json("A\"B\\C"), "A\\\"B\\\\C");
    }

    #[test]
    fn default_config_serializes() {
        let mut config = AppConfig::default();
        config.overrides = ModifierOverrides {
            swap_left_alt_win: true,
            swap_right_alt_win: true,
            disable_context_menu_remap: false,
        };
        let json = config.to_json();
        assert!(json.contains("\"swapLeftAltWin\":true"));
        assert!(json.contains("\"swapRightAltWin\":true"));
    }
}
