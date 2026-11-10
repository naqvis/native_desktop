require "log"

module NativeDesktop::Platform::Idle
  extend self

  @[Link(framework: "CoreGraphics")]
  lib LibCoreGraphicsIdle
    fun CGEventSourceSecondsSinceLastEventType(state : Int32, event_type : UInt32) : Float64
  end

  COMBINED_SESSION = 0_i32
  ANY_INPUT_EVENT  = UInt32::MAX

  def duration : Time::Span
    seconds = LibCoreGraphicsIdle.CGEventSourceSecondsSinceLastEventType(COMBINED_SESSION, ANY_INPUT_EVENT)
    return 0.seconds unless seconds.finite? && seconds >= 0
    seconds.seconds
  rescue ex
    Log.warn(exception: ex) { "could not read macOS idle time" }
    0.seconds
  end
end
