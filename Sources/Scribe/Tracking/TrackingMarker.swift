public protocol TrackingMarker {
  var _$_tracker: Tracker? { get set }
}

@attached(memberAttribute)
@attached(member, names: named(_$_tracker))
@attached(extension, conformances: TrackingMarker)
public macro Tracking() = #externalMacro(module: "TrackingMacros", type: "TrackingMacro")

@attached(peer, names: prefixed(_$_))
@attached(accessor, names: named(init), named(get), named(set))
public macro Tracked() = #externalMacro(module: "TrackingMacros", type: "TrackedMacro")

@attached(accessor, names: named(willSet))
public macro TrackerIgnored() =
  #externalMacro(module: "TrackingMacros", type: "TrackerIgnoredMacro")
