"""Compare published MoonBit statistics with the pinned Rust adapter's real run.

This is a verification tool for the unmodified BRUX 2026-266 fixture, not a
second RINEX parser. It reads the two reports, never repairs their input.
"""
import argparse
import datetime
import json
from pathlib import Path

SOURCE_SHA256 = '0fe5e99ad02768434dc53b4c9d89603aa97e5ae924cf704e080b6c51279cd630'

def require(condition, message):
    if not condition:
        raise ValueError(message)

def count(text):
    require(text.isascii() and text.isdigit(), 'invalid reference count: '+text)
    return int(text)

def gps_ticks(text):
    # Pinned fixture has whole seconds. GPST calendar values remain GPST; no
    # UTC conversion or host timezone is involved in this comparison.
    value = datetime.datetime.strptime(text, '%Y-%m-%dT%H:%M:%S GPST')
    delta = value - datetime.datetime(1980, 1, 1)
    return (delta.days * 86400 + delta.seconds) * 10_000_000

def compare(moonbit_file, rust_file):
    product = json.loads(moonbit_file.read_text(encoding='utf-8-sig'))
    summary, types, lli = {}, {}, {}
    for line in rust_file.read_text(encoding='utf-8-sig').splitlines():
        parts = line.split('\t')
        if parts[0] == 'type_count':
            require(len(parts) == 4, 'invalid type_count row')
            key = (parts[1], parts[2])
            require(key not in types, 'duplicate type_count row')
            types[key] = count(parts[3])
        elif parts[0] == 'lli_count':
            require(len(parts) == 5, 'invalid lli_count row')
            key = (parts[1], parts[2], parts[3])
            require(key not in lli, 'duplicate lli_count row')
            require(parts[3] == 'absent' or parts[3] in [str(i) for i in range(8)], 'unexpected LLI bits')
            lli[key] = count(parts[4])
        elif len(parts) == 1 and '=' in line:
            key, value = line.split('=', 1)
            require(key not in summary, 'duplicate reference summary')
            summary[key] = value
    require(summary.get('parse') == 'ok', 'reference did not report a successful parse')
    require(summary.get('revision') == '4.01', 'reference did not parse RINEX 4.01')
    require(product['input']['sha256'] == SOURCE_SHA256, 'unexpected MoonBit source hash')
    require(product['complete'] is True, 'MoonBit did not finish the fixture')
    require(count(summary['epoch_iter_count']) == product['epochs'], 'epoch count differs')
    require(gps_ticks(summary['first_epoch']) == int(product['first']), 'first GPST differs')
    require(gps_ticks(summary['last_epoch']) == int(product['last']), 'last GPST differs')
    require(count(summary['unique_epoch_sv_rows']) == product['records'], 'satellite record count differs')
    require(count(summary['unknown_system_rows']) == 0, 'reference adapter has an unsupported constellation')
    rows = json.loads(summary['rows_by_system'])
    svs = json.loads(summary['unique_sv_by_system'])
    require(rows == {s['system']: s['records'] for s in product['systems']}, 'per-system rows differ')
    require(svs == {s['system']: len(s['satellites']) for s in product['systems']}, 'per-system SV counts differ')
    require(count(summary['unique_sv_count']) == sum(svs.values()), 'unique SV total differs')
    keys, phase_keys = set(), set()
    nonempty = 0
    for system in product['systems']:
        for signal in system['signals']:
            key = (system['system'], signal['code'])
            require(key not in keys, 'duplicate product signal key')
            keys.add(key)
            observed = types.get(key, 0)
            require(observed == signal['nonempty_fields'], f'nonempty count differs: {key}')
            nonempty += observed
            if signal['code'].startswith('L'):
                phase_keys.add(key)
                histogram = {bits: n for (sys, code, bits), n in lli.items() if (sys, code) == key}
                require(sum(histogram.values()) == observed, f'LLI coverage differs: {key}')
                nonzero = sum(n for bits, n in histogram.items() if bits not in ('absent', '0'))
                require(nonzero == signal['lli_nonzero'], f'nonzero LLI differs: {key}')
                for bit in range(3):
                    n = sum(n for bits, n in histogram.items() if bits != 'absent' and int(bits) & (1 << bit))
                    require(n == signal['lli_bit'+str(bit)], f'LLI bit {bit} differs: {key}')
    require(set(types).issubset(keys), 'reference contains an undeclared signal')
    require({(sys, code) for sys, code, _ in lli}.issubset(phase_keys), 'reference contains an undeclared phase signal')
    require(nonempty == count(summary['signal_value_count']), 'total signal values differ')
    return {'passed': True, 'reference': 'nav-solutions/rinex 0.22.0 (obs)',
            'sourceSha256': SOURCE_SHA256, 'revision': '4.01',
            'epochs': product['epochs'], 'satelliteRecords': product['records'],
            'uniqueSatellites': sum(svs.values()), 'systems': len(rows),
            'systemSignalKeysCompared': len(keys), 'phaseSignalKeysCompared': len(phase_keys),
            'nonemptySignalValues': nonempty,
            'productAcceptable': product['acceptable'], 'productFindings': product['finding_counts'],
            'notCompared': ['all raw numerical values', 'blank-slot counts directly from Rust',
                            'product QC verdict against another QC engine', 'positioning or observation quality']}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('moonbit', type=Path)
    parser.add_argument('rust', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = compare(args.moonbit, args.rust)
    text = json.dumps(result, ensure_ascii=False, indent=2)+'\n'
    if args.report:
        args.report.write_text(text, encoding='utf-8', newline='\n')
    print(text, end='')
