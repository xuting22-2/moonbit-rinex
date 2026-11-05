use rinex::Rinex;

fn main() {
    let file = std::env::args().nth(1).expect("INPUT NAV");
    let rinex = Rinex::from_file(&file).expect("independent RINEX parse");
    let rows: Vec<_> = rinex.record.as_nav().expect("navigation record").iter().collect();
    println!("{}", serde_json::json!({
        "version": rinex.header.version.to_string(),
        "count": rows.len(),
        "records": rows,
    }));
}
