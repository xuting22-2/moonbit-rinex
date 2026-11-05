///|
// Native field layouts transcribed from IGS RINEX 4.02 Tables A9-A40.
// A field occupies its physical slot even when blank or spare.
fn navigation_layout(key : String) -> Array[String] {
  let spec = match key {
    "gps_lnav" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 iode|integer crs|m delta_n|rad/s m0|rad cuc|rad eccentricity|1 cus|rad sqrt_a|sqrt(m) toe_sow|s cic|rad omega0|rad cis|rad i0|rad crc|m omega|rad omega_dot|rad/s idot|rad/s codes|bits week|week l2p|bits accuracy|m health|bits tgd|s iodc|integer transmission_time|s fit_interval|h spare| spare|"
    "galileo" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 iodnav|integer crs|m delta_n|rad/s m0|rad cuc|rad eccentricity|1 cus|rad sqrt_a|sqrt(m) toe_sow|s cic|rad omega0|rad cis|rad i0|rad crc|m omega|rad omega_dot|rad/s idot|rad/s data_sources|bits week|week spare| sisa|m health|bits bgd_e5a_e1|s bgd_e5b_e1|s transmission_time|s spare| spare| spare|"
    "bds_legacy" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 aode|integer crs|m delta_n|rad/s m0|rad cuc|rad eccentricity|1 cus|rad sqrt_a|sqrt(m) toe_sow|s cic|rad omega0|rad cis|rad i0|rad crc|m omega|rad omega_dot|rad/s idot|rad/s spare| week|week spare| accuracy|m health|bits tgd_b1_b3|s tgd_b2_b3|s transmission_time|s aodc|integer spare| spare|"
    "navic_lnav" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 iodec|integer crs|m delta_n|rad/s m0|rad cuc|rad eccentricity|1 cus|rad sqrt_a|sqrt(m) toe_sow|s cic|rad omega0|rad cis|rad i0|rad crc|m omega|rad omega_dot|rad/s idot|rad/s spare| week|week spare| accuracy|m health|bits tgd|s spare| transmission_time|s spare| spare| spare|"
    "glo_fdma" =>
      "clock_bias|s clock_drift|s/s frame_time|s x|km vx|km/s ax|km/s2 health|bits y|km vy|km/s ay|km/s2 frequency_channel|integer z|km vz|km/s az|km/s2 age|day status|bits delta_tau|s urai|integer health_flags|bits"
    "sbas" =>
      "clock_bias|s clock_drift|s/s frame_time|s x|km vx|km/s ax|km/s2 health|bits y|km vy|km/s ay|km/s2 accuracy|m z|km vz|km/s az|km/s2 iodn|integer"
    "cnav" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 a_dot|m/s crs|m delta_n|rad/s m0|rad cuc|rad eccentricity|1 cus|rad sqrt_a|sqrt(m) top|s cic|rad omega0|rad cis|rad i0|rad crc|m omega|rad omega_dot|rad/s idot|rad/s delta_n_dot|rad/s2 urai_ned0|integer urai_ned1|integer urai_ed|integer health|bits tgd|s urai_ned2|integer isc_l1ca|s isc_l2c|s isc_l5i5|s isc_l5q5|s transmission_time|s week_op|week flags|bits spare|"
    "cnv2" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 a_dot|m/s crs|m delta_n|rad/s m0|rad cuc|rad eccentricity|1 cus|rad sqrt_a|sqrt(m) top|s cic|rad omega0|rad cis|rad i0|rad crc|m omega|rad omega_dot|rad/s idot|rad/s delta_n_dot|rad/s2 urai_ned0|integer urai_ned1|integer urai_ed|integer health|bits tgd|s urai_ned2|integer isc_l1ca|s isc_l2c|s isc_l5i5|s isc_l5q5|s isc_l1cd|s isc_l1cp|s spare| spare| transmission_time|s week_op|week flags|bits spare|"
    "bds_cnv1" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 a_dot|m/s crs|m delta_n|rad/s m0|rad cuc|rad eccentricity|1 cus|rad sqrt_a|sqrt(m) toe_sow|s cic|rad omega0|rad cis|rad i0|rad crc|m omega|rad omega_dot|rad/s idot|rad/s delta_n_dot|rad/s2 orbit_type|integer top|s sisai_oe|integer sisai_ocb|integer sisai_oc1|integer sisai_oc2|integer isc_b1cd|s spare| tgd_b1cp|s tgd_b2ap|s sismai|integer health|bits integrity|bits iodc|integer transmission_time|s spare| spare| iode|integer"
    "bds_cnv2" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 a_dot|m/s crs|m delta_n|rad/s m0|rad cuc|rad eccentricity|1 cus|rad sqrt_a|sqrt(m) toe_sow|s cic|rad omega0|rad cis|rad i0|rad crc|m omega|rad omega_dot|rad/s idot|rad/s delta_n_dot|rad/s2 orbit_type|integer top|s sisai_oe|integer sisai_ocb|integer sisai_oc1|integer sisai_oc2|integer spare| isc_b2ad|s tgd_b1cp|s tgd_b2ap|s sismai|integer health|bits integrity|bits iodc|integer transmission_time|s spare| spare| iode|integer"
    "bds_cnv3" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 a_dot|m/s crs|m delta_n|rad/s m0|rad cuc|rad eccentricity|1 cus|rad sqrt_a|sqrt(m) toe_sow|s cic|rad omega0|rad cis|rad i0|rad crc|m omega|rad omega_dot|rad/s idot|rad/s delta_n_dot|rad/s2 orbit_type|integer top|s sisai_oe|integer sisai_ocb|integer sisai_oc1|integer sisai_oc2|integer sismai|integer health|bits integrity|bits tgd_b2bi|s transmission_time|s spare| spare| spare|"
    "glo_cdma" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 x|km vx|km/s ax|km/s2 health|bits y|km vy|km/s ay|km/s2 data_validity|bits z|km vz|km/s az|km/s2 group_delay|s satellite_type|integer source_flags|bits aode|day aodc|day attitude|bits tin|s tau1|s tau2|s yaw|rad sign|bits yaw_rate|rad/s yaw_accel|rad/s2 max_yaw_rate|rad/s pc_x|m pc_y|m pc_z|m urai_orbit|integer urai_clock|integer spare| transmission_time|s"
    "navic_l1nv" =>
      "clock_bias|s clock_drift|s/s clock_drift_rate|s/s2 a_dot|m/s crs|m delta_n|rad/s m0|rad cuc|rad eccentricity|1 cus|rad sqrt_a|sqrt(m) iodec|integer cic|rad omega0|rad cis|rad i0|rad crc|m omega|rad omega_dot|rad/s idot|rad/s delta_n_dot|rad/s2 spare| rsf|bits urai|integer health|bits tgd_l1p_l5|s tgd_s_l5|s isc_s_l1p|s isc_l1d_l1p|s isc_l1p_s|s isc_l1d_s|s transmission_time|s spare| spare| spare|"
    "sto" => "transmission_time|s a0|s a1|s/s a2|s/s2"
    "eop" =>
      "xp|arcsec xp_rate|arcsec/day xp_accel|arcsec/day2 spare| yp|arcsec yp_rate|arcsec/day yp_accel|arcsec/day2 transmission_time|s delta_ut1|s delta_ut1_rate|s/day delta_ut1_accel|s/day2"
    "klobuchar" =>
      "alpha0|s alpha1|s/semicircle alpha2|s/semicircle2 alpha3|s/semicircle3 beta0|s beta1|s/semicircle beta2|s/semicircle2 beta3|s/semicircle3 spare| spare| spare|"
    "nequick_g" =>
      "ai0|sfu ai1|sfu/deg ai2|sfu/deg2 disturbance_flags|bits spare| spare| spare|"
    "bdgim" =>
      "alpha1|TECu alpha2|TECu alpha3|TECu alpha4|TECu alpha5|TECu alpha6|TECu alpha7|TECu alpha8|TECu alpha9|TECu spare| spare|"
    "glo_ion" => "c_a|unspecified c_f107|unspecified c_ap|unspecified"
    "navic_klob" =>
      "iodk|integer spare| spare| alpha0|s alpha1|s/semicircle alpha2|s/semicircle2 alpha3|s/semicircle3 beta0|s beta1|s/semicircle beta2|s/semicircle2 beta3|s/semicircle3 longitude_min|deg longitude_max|deg latitude_min|deg latitude_max|deg"
    "navic_neqn" =>
      "iodn|integer spare| spare| a0_1|sfu a1_1|sfu/deg a2_1|sfu/deg2 idf_1|bits longitude_min_1|deg longitude_max_1|deg modip_min_1|deg modip_max_1|deg a0_2|sfu a1_2|sfu/deg a2_2|sfu/deg2 idf_2|bits longitude_min_2|deg longitude_max_2|deg modip_min_2|deg modip_max_2|deg a0_3|sfu a1_3|sfu/deg a2_3|sfu/deg2 idf_3|bits longitude_min_3|deg longitude_max_3|deg modip_min_3|deg modip_max_3|deg"
    _ => ""
  }
  spec.split(" ").map(s => s.to_owned()).filter(s => !s.is_empty()).collect()
}
