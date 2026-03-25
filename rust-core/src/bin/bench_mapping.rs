use mackeymap_core::{modifier_remap_entries, user_key_mapping_json, ModifierOverrides};
use std::hint::black_box;
use std::time::{Duration, Instant};

const SAMPLE_COUNT: usize = 8;
const ENTRY_ITERATIONS: usize = 2_000_000;
const JSON_ITERATIONS: usize = 500_000;

fn main() {
    let default_overrides = ModifierOverrides::default();
    let swapped_overrides = ModifierOverrides {
        swap_left_alt_win: true,
        swap_right_alt_win: true,
        disable_context_menu_remap: false,
    };

    println!("MacKeyMap mapping generation benchmark");
    println!("samples: {}", SAMPLE_COUNT);
    println!();

    print_result(benchmark_entries("modifier_remap_entries(default)", &default_overrides));
    print_result(benchmark_entries("modifier_remap_entries(swapped)", &swapped_overrides));
    print_result(benchmark_json("user_key_mapping_json(default)", &default_overrides));
    print_result(benchmark_json("user_key_mapping_json(swapped)", &swapped_overrides));
}

#[derive(Clone)]
struct BenchmarkResult {
    name: &'static str,
    iterations: usize,
    sample_durations: Vec<Duration>,
}

fn benchmark_entries(name: &'static str, overrides: &ModifierOverrides) -> BenchmarkResult {
    let mut sample_durations = Vec::with_capacity(SAMPLE_COUNT);
    for _ in 0..SAMPLE_COUNT {
        let started = Instant::now();
        let mut checksum = 0_u64;
        for _ in 0..ENTRY_ITERATIONS {
            let entries = modifier_remap_entries(black_box(overrides));
            checksum ^= entries.len() as u64;
            if let Some(first) = entries.first() {
                checksum ^= first.src;
                checksum ^= first.dst;
            }
        }
        black_box(checksum);
        sample_durations.push(started.elapsed());
    }

    BenchmarkResult {
        name,
        iterations: ENTRY_ITERATIONS,
        sample_durations,
    }
}

fn benchmark_json(name: &'static str, overrides: &ModifierOverrides) -> BenchmarkResult {
    let mut sample_durations = Vec::with_capacity(SAMPLE_COUNT);
    for _ in 0..SAMPLE_COUNT {
        let started = Instant::now();
        let mut checksum = 0_usize;
        for _ in 0..JSON_ITERATIONS {
            let json = user_key_mapping_json(black_box(overrides));
            checksum ^= json.len();
        }
        black_box(checksum);
        sample_durations.push(started.elapsed());
    }

    BenchmarkResult {
        name,
        iterations: JSON_ITERATIONS,
        sample_durations,
    }
}

fn print_result(result: BenchmarkResult) {
    let mut nanos = result
        .sample_durations
        .iter()
        .map(Duration::as_nanos)
        .collect::<Vec<_>>();
    nanos.sort_unstable();

    let median = nanos[nanos.len() / 2] as f64 / result.iterations as f64;
    let best = nanos[0] as f64 / result.iterations as f64;
    let worst = nanos[nanos.len() - 1] as f64 / result.iterations as f64;
    let average = nanos.iter().sum::<u128>() as f64 / nanos.len() as f64 / result.iterations as f64;

    println!("{}", result.name);
    println!("  iterations/sample: {}", result.iterations);
    println!("  median: {:.2} ns/op", median);
    println!("  average: {:.2} ns/op", average);
    println!("  best: {:.2} ns/op", best);
    println!("  worst: {:.2} ns/op", worst);
    println!();
}
