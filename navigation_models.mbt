///|
pub struct NavigationState {
  satellite : String
  family : String
  elapsed_seconds : Double
  x : Double
  y : Double
  z : Double
  clock_seconds : Double
  frame : String
  clock_reference : String
  velocity_mps : Array[Double]?
  group_delays : Array[NavigationField]
} derive(ToJson)

///|
pub extend NavigationState with ToJson::{to_json}

///|
fn navigation_elapsed(seconds : Double, limit : Double) -> Unit raise NavError {
  if seconds.is_nan() || seconds.is_inf() || seconds.abs() > limit {
    raise InvalidNavigation("elapsed SI seconds outside model interval")
  }
}

///|
fn navigation_finite(value : Double) -> Double raise NavError {
  if value.is_nan() || value.is_inf() {
    raise InvalidNavigation("nonfinite navigation model result")
  }
  value
}

///|
fn NavigationMessage::delays(
  self : NavigationMessage,
) -> Array[NavigationField] {
  self.fields.filter(f => {
    f.name.has_prefix("bgd_") ||
    f.name.has_prefix("tgd") ||
    f.name.has_prefix("isc_") ||
    f.name == "delta_tau"
  })
}

///|
// PZ-90 rotating-frame central gravity + J2 + broadcast lunisolar acceleration.
// GLONASS FDMA ICD numerical model. State order is [x,y,z,vx,vy,vz], SI units.
fn navigation_glo_derivative(
  q : Array[Double],
  acc : Array[Double],
) -> Array[Double] raise NavError {
  let radius2 = q[0] * q[0] + q[1] * q[1] + q[2] * q[2]
  if radius2 < 1.0e12 || radius2.is_inf() || radius2.is_nan() {
    raise InvalidNavigation("invalid GLONASS radius")
  }
  let grav = 3.9860044e14 / (radius2 * radius2.sqrt())
  let oblateness = 1.5 * 1.0826257e-3 * 6378136.0 * 6378136.0 / radius2
  let z_fraction = q[2] * q[2] / radius2
  let xy_factor = -grav * (1.0 + oblateness * (1.0 - 5.0 * z_fraction))
  let z_factor = -grav * (1.0 + oblateness * (3.0 - 5.0 * z_fraction))
  let spin = 7.292115e-5
  [
    q[3],
    q[4],
    q[5],
    xy_factor * q[0] + spin * spin * q[0] + 2.0 * spin * q[4] + acc[0],
    xy_factor * q[1] + spin * spin * q[1] - 2.0 * spin * q[3] + acc[1],
    z_factor * q[2] + acc[2],
  ]
}

///|
fn NavigationMessage::glo_state(
  self : NavigationMessage,
  seconds : Double,
) -> NavigationState raise NavError {
  if self.required("health") != 0.0 {
    raise UnhealthyEphemeris
  }
  let mk = match self.value("status") {
    Some(status) => {
      let bits = nav_int(status)
      if bits > 511 {
        raise InvalidNavigation("GLONASS status exceeds9bits")
      }
      ((bits >> 7) & 3) == 1
    }
    None => false
  }
  match self.value("health_flags") {
    Some(flags) => {
      let bits = nav_int(flags)
      if bits > 7 {
        raise InvalidNavigation("GLONASS health flags exceed3bits")
      }
      if ((bits & 2) != 0 && (bits & 1) == 0) || (mk && (bits & 4) != 0) {
        raise UnhealthyEphemeris
      }
    }
    _ => ()
  }
  let channel = self.required("frequency_channel")
  if channel < -7.0 || channel > 13.0 || @math.floor(channel) != channel {
    raise InvalidNavigation("GLONASS FDMA channel must be -7..13")
  }
  let state = [
    self.required("x") * 1000.0,
    self.required("y") * 1000.0,
    self.required("z") * 1000.0,
    self.required("vx") * 1000.0,
    self.required("vy") * 1000.0,
    self.required("vz") * 1000.0,
  ]
  let acc = [
    self.required("ax") * 1000.0,
    self.required("ay") * 1000.0,
    self.required("az") * 1000.0,
  ]
  ignore(navigation_glo_derivative(state, acc))
  let mut remaining = seconds
  while remaining.abs() > 1.0e-9 {
    let h = if remaining > 0.0 {
      remaining.min(60.0)
    } else {
      remaining.max(-60.0)
    }
    let k1 = navigation_glo_derivative(state, acc)
    let k2 = navigation_glo_derivative(
      [
        for i in 0..<6 => state[i] + h * k1[i] / 2.0
      ],
      acc,
    )
    let k3 = navigation_glo_derivative(
      [
        for i in 0..<6 => state[i] + h * k2[i] / 2.0
      ],
      acc,
    )
    let k4 = navigation_glo_derivative(
      [
        for i in 0..<6 => state[i] + h * k3[i]
      ],
      acc,
    )
    for i in 0..<6 {
      state[i] += h * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]) / 6.0
    }
    remaining -= h
  }
  {
    satellite: self.satellite,
    family: self.family,
    elapsed_seconds: seconds,
    x: navigation_finite(state[0]),
    y: navigation_finite(state[1]),
    z: navigation_finite(state[2]),
    velocity_mps: Some(state[3:6].to_owned()),
    clock_seconds: navigation_finite(
      self.required("clock_bias") + self.required("clock_drift") * seconds,
    ),
    clock_reference: "broadcast -tau_n + gamma_n*dt; no extra relativity or group-delay correction",
    frame: "PZ-90",
    group_delays: self.delays(),
  }
}

///|
/// Broadcast position at elapsed SI seconds from the record's clock epoch.
/// No implicit UTC/GST/BDT conversion. GLO bound 1800s, others caller bound up
/// to4h; BDS retains the existing <=2h and explicit MEO/IGSO/GEO policy.
/// Galileo signal is E1B/E5b for INAV or E5a for FNAV; health is per signal.
pub fn NavigationMessage::state_at_offset(
  self : NavigationMessage,
  seconds : Double,
  signal? : String = "",
  bds_orbit? : BdsOrbit,
  max_age_seconds? : Double = 7200.0,
) -> NavigationState raise NavError {
  if !self.known || self.category != "EPH" {
    raise InvalidNavigation("typed EPH record required")
  }
  if max_age_seconds <= 0.0 ||
    max_age_seconds > 14400.0 ||
    max_age_seconds.is_nan() ||
    max_age_seconds.is_inf() {
    raise InvalidNavigation("max age must be finite in(0,14400]")
  }
  navigation_elapsed(seconds, 14400.0)
  if seconds.abs() > max_age_seconds {
    raise EphemerisExpired
  }
  if self.model == "glo_fdma" {
    if seconds.abs() > 1800.0 {
      raise EphemerisExpired
    }
    return self.glo_state(seconds)
  }
  if !["gps_lnav", "bds_legacy", "galileo"].contains(self.model) ||
    !["G", "C", "E"].contains(self.system) {
    raise InvalidNavigation(
      "no orbit model for " + self.system + "/" + self.family,
    )
  }
  let mut delay_name = if self.system == "C" { "tgd_b1_b3" } else { "tgd" }
  let mut reference = "broadcast clock including eccentricity relativity; group delays unapplied"
  if self.system == "E" {
    let source = nav_int(self.required("data_sources"))
    let health = nav_int(self.required("health"))
    if source > 1023 || health > 511 {
      raise InvalidNavigation("Galileo source/health bits out of range")
    }
    let shift = match signal {
      "E1B" if (source & 5) != 0 && (source & 512) != 0 && (source & 256) == 0 =>
        0
      "E5b" if (source & 5) != 0 && (source & 512) != 0 && (source & 256) == 0 =>
        6
      "E5a" if (source & 2) != 0 && (source & 256) != 0 && (source & 512) == 0 =>
        3
      _ =>
        raise InvalidNavigation(
          "Galileo signal incompatible with data-source/clock bits",
        )
    }
    if (self.family == "INAV" && signal == "E5a") ||
      (self.family == "FNAV" && signal != "E5a") {
      raise InvalidNavigation("Galileo descriptor/source mismatch")
    }
    if ((health >> shift) & 7) != 0 {
      raise UnhealthyEphemeris
    }
    delay_name = if signal == "E5a" { "bgd_e5a_e1" } else { "bgd_e5b_e1" }
    reference = if signal == "E5a" {
      "Galileo E5a/E1 ionosphere-free clock; both raw BGDs retained, unapplied"
    } else {
      "Galileo E5b/E1 ionosphere-free clock; both raw BGDs retained, unapplied"
    }
  } else if self.required("health") != 0.0 {
    raise UnhealthyEphemeris
  }
  let epoch = match self.epoch {
    Some(t) => t
    None => raise InvalidNavigation("missing clock epoch")
  }
  let bds = self.system == "C"
  let toe_sow = self.required("toe_sow")
  let toe = NavTime::week(nav_int(self.required("week")), toe_sow, bdt=bds)
  let toc : NavTime = {
    gps_ticks: epoch.calendar_ticks + (if bds { 140000000L } else { 0L }),
  }
  if ((toc.gps_ticks - toe.gps_ticks).to_double() / 10000000.0).abs() > 604800.0 {
    raise InvalidNavigation("inconsistent continuous week and epoch")
  }
  let data = [ for i in 3..<31 => self.fields[i].value ]
  // The shared Kepler engine uses only the orbital slots, fit interval and
  // selected raw group delay. Signal health was checked above, never flattened.
  data[22] = Some(self.required(delay_name))
  let record : NavRecord = {
    satellite: self.satellite,
    message: self.family,
    toc,
    toe,
    toe_sow,
    health: 0,
    data,
    clock: [
      self.required("clock_bias"),
      self.required("clock_drift"),
      self.required("clock_drift_rate"),
    ],
  }
  let time : NavTime = {
    gps_ticks: toc.gps_ticks + @math.round(seconds * 10000000.0).to_int64(),
  }
  let state = record.satellite_position(time, bds_orbit?, max_age_seconds~)
  {
    satellite: self.satellite,
    family: self.family,
    elapsed_seconds: seconds,
    x: state.x,
    y: state.y,
    z: state.z,
    clock_seconds: state.clock_seconds,
    frame: state.frame,
    clock_reference: reference,
    velocity_mps: None,
    group_delays: self.delays(),
  }
}

///|
/// A0+A1*dt+A2*dt² only: excludes any leap-second component in the system
/// conversion. Sign is the correction_type convention, never silently inverted.
pub fn NavigationMessage::system_time_offset(
  self : NavigationMessage,
  seconds : Double,
) -> Double raise NavError {
  if self.model != "sto" {
    raise InvalidNavigation("STO record required")
  }
  navigation_elapsed(seconds, 604800.0)
  navigation_finite(
    self.required("a0") +
    self.required("a1") * seconds +
    self.required("a2") * seconds * seconds,
  )
}

///|
pub struct NavigationEarthOrientation {
  xp_arcsec : Double
  yp_arcsec : Double
  delta_ut1_seconds : Double
  delta_ut1_reference : String
} derive(ToJson)

///|
pub extend NavigationEarthOrientation with ToJson::{to_json}

///|
/// EOP rates are per day. delta_ut1 remains ICD-dependent UT1-UTC/UT1-GPST.
pub fn NavigationMessage::earth_orientation(
  self : NavigationMessage,
  seconds : Double,
) -> NavigationEarthOrientation raise NavError {
  if self.model != "eop" {
    raise InvalidNavigation("EOP record required")
  }
  navigation_elapsed(seconds, 604800.0)
  let days = seconds / 86400.0
  {
    xp_arcsec: navigation_finite(
      self.required("xp") +
      self.required("xp_rate") * days +
      self.required("xp_accel") * days * days / 2.0,
    ),
    yp_arcsec: navigation_finite(
      self.required("yp") +
      self.required("yp_rate") * days +
      self.required("yp_accel") * days * days / 2.0,
    ),
    delta_ut1_seconds: navigation_finite(
      self.required("delta_ut1") +
      self.required("delta_ut1_rate") * days +
      self.required("delta_ut1_accel") * days * days / 2.0,
    ),
    delta_ut1_reference: "ICD-dependent UT1-UTC or UT1-GPST; not converted",
  }
}
