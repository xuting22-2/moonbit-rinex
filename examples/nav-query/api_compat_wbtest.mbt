///|
test "previous mapping constructor keeps inference in an external consumer" {
  let mapping = @r.Ambiguous(["C1P", "C1W"])
  assert_true(mapping is @r.CodeMapping::Ambiguous(_))
  assert_eq(mapping.to_json().stringify(), "[\"Ambiguous\",[\"C1P\",\"C1W\"]]")
}
