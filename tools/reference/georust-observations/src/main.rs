// Independent mature-reader adapter; no MoonBit parser or oracle code imported.
use rinex::prelude::{Observable, Rinex};
use std::{env, process};

fn code(observable: &Observable) -> String {
    match observable {
        Observable::PseudoRange(s) | Observable::PhaseRange(s)
        | Observable::Doppler(s) | Observable::SSI(s) => s.clone(),
        other => format!("{other:?}"),
    }
}
fn main() {
    let filename = env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: rinex-4-brux-reference INPUT.rnx"); process::exit(2);
    });
    let input = Rinex::from_file(&filename).unwrap_or_else(|error| {
        eprintln!("parse_error={error:?}"); process::exit(1);
    });
    println!("reference=rinex@0.22.0");
    println!("epochs={}", input.epoch_iter().count());
    for (key, signal) in input.signal_observations_iter() {
        let lli = signal.lli.map(|v| v.bits().to_string()).unwrap_or_else(|| "absent".to_string());
        println!("value\t{}\t{}\t{}\t{}\t{}", key.epoch, signal.sv, code(&signal.observable), signal.value, lli);
    }
}
