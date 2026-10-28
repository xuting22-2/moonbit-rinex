use rinex::prelude::{Observable, Rinex};
use std::collections::{BTreeMap, HashSet};
use std::{env, process};

fn constellation_code(sv_debug: &str) -> &'static str {
    if sv_debug.contains("constellation: GPS") { "G" }
    else if sv_debug.contains("constellation: Glonass") { "R" }
    else if sv_debug.contains("constellation: BeiDou") { "C" }
    else if sv_debug.contains("constellation: Galileo") { "E" }
    else if sv_debug.contains("constellation: IRNSS") { "I" }
    else { "?" }
}

fn observable_code(observable: &Observable) -> String {
    match observable {
        Observable::PseudoRange(code)
        | Observable::PhaseRange(code)
        | Observable::Doppler(code)
        | Observable::SSI(code) => code.clone(),
        other => format!("{other:?}"),
    }
}

fn main() {
    let path = match env::args().nth(1) {
        Some(value) => value,
        None => { eprintln!("usage: rinex-4-brux-reference <file.rnx>"); process::exit(2); }
    };
    match Rinex::from_file(&path) {
        Err(error) => { eprintln!("parse_error={error:?}"); process::exit(1); }
        Ok(rinex) => {
            println!("parse=ok");
            println!("revision={}.{:02}", rinex.header.version.major, rinex.header.version.minor);
            println!("rinex_type={:?}", rinex.header.rinex_type);
            let epochs: Vec<_> = rinex.epoch_iter().collect();
            println!("epoch_iter_count={}", epochs.len());
            println!("first_epoch={}", epochs.first().map(|e| e.to_string()).unwrap_or_default());
            println!("last_epoch={}", epochs.last().map(|e| e.to_string()).unwrap_or_default());
            println!("unique_sv_count={}", rinex.sv_iter().count());
            println!("constellations={:?}", rinex.constellations_iter().collect::<Vec<_>>());

            let mut row_keys: HashSet<(String, String, String)> = HashSet::new();
            let mut type_counts: BTreeMap<(String, String), u64> = BTreeMap::new();
            let mut lli_counts: BTreeMap<(String, String), BTreeMap<String, u64>> = BTreeMap::new();
            let mut samples: Vec<(String, String, String, String, String)> = Vec::new();
            let mut total_signal_values = 0u64;

            for (key, signal) in rinex.signal_observations_iter() {
                total_signal_values += 1;
                let sv_debug = format!("{:?}", signal.sv);
                let system = constellation_code(&sv_debug).to_string();
                let code = observable_code(&signal.observable);
                let observable_debug = format!("{:?}", signal.observable);
                *type_counts.entry((system.clone(), code.clone())).or_default() += 1;

                let epoch_debug = format!("{:?}", key.epoch);
                row_keys.insert((epoch_debug.clone(), sv_debug.clone(), system.clone()));

                if matches!(&signal.observable, Observable::PhaseRange(_)) {
                    let lli = signal.lli.map(|flags| flags.bits().to_string()).unwrap_or_else(|| "absent".to_string());
                    *lli_counts.entry((system.clone(), code)).or_default().entry(lli).or_default() += 1;
                }

                if samples.len() < 24 {
                    let value = format!("{:.3}", signal.value);
                    let lli = signal.lli.map(|flags| flags.bits().to_string()).unwrap_or_else(|| "absent".to_string());
                    samples.push((epoch_debug, sv_debug, observable_debug, value, lli));
                }
            }

            let mut rows_by_system: BTreeMap<String, u64> = BTreeMap::new();
            let mut unknown_system_rows = 0u64;
            for (_, _, system) in &row_keys {
                if system == "?" { unknown_system_rows += 1; }
                *rows_by_system.entry(system.clone()).or_default() += 1;
            }
            let mut sv_keys: HashSet<(String, String)> = HashSet::new();
            for (_, sv, system) in &row_keys { sv_keys.insert((system.clone(), sv.clone())); }
            let mut unique_sv_by_system: BTreeMap<String, u64> = BTreeMap::new();
            for (system, _) in &sv_keys { *unique_sv_by_system.entry(system.clone()).or_default() += 1; }

            println!("unique_epoch_sv_rows={}", row_keys.len());
            println!("rows_by_system={:?}", rows_by_system);
            println!("unique_sv_by_system={:?}", unique_sv_by_system);
            println!("unknown_system_rows={}", unknown_system_rows);
            println!("signal_value_count={}", total_signal_values);
            for ((system, code), count) in type_counts {
                println!("type_count\t{}\t{}\t{}", system, code, count);
            }
            for ((system, code), by_lli) in lli_counts {
                for (bits, count) in by_lli {
                    println!("lli_count\t{}\t{}\t{}\t{}", system, code, bits, count);
                }
            }
            for (epoch, sv, kind, value, lli) in samples {
                println!("sample\t{}\t{}\t{}\t{}\t{}", epoch, sv, kind, value, lli);
            }
        }
    }
}