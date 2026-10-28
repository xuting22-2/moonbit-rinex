///|
extern "js" fn fail(message : String) -> Unit =
  #| (message) => { throw new Error(message); }

///|
pub fn create(year : Int, month : Int, day : Int, hour : Int) -> @r.Checker {
  if year == 0 {
    return @r.Checker::new()
  }
  try {
    let window = if hour == -1 {
      @r.Window::epn_daily(year, month, day)
    } else {
      @r.Window::epn_hourly(year, month, day, hour)
    }
    @r.Checker::new(window~)
  } catch {
    e => {
      fail(@debug.to_string(e))
      @r.Checker::new()
    }
  }
}

///|
pub fn feed(checker : @r.Checker, line : String) -> Unit {
  checker.feed_line(line) catch {
    e => fail(@debug.to_string(e))
  }
}

///|
pub fn finish(checker : @r.Checker) -> String {
  checker.finish().to_json().stringify() catch {
    e => {
      fail(@debug.to_string(e))
      ""
    }
  }
}

///|
fn main {

}
