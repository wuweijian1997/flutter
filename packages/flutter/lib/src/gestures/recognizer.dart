// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.


import 'dart:async';
import 'dart:collection';
import 'dart:ui' show Offset;

import 'package:vector_math/vector_math_64.dart';
import 'package:flutter/foundation.dart';

import 'arena.dart';
import 'binding.dart';
import 'constants.dart';
import 'debug.dart';
import 'events.dart';
import 'pointer_router.dart';
import 'team.dart';

export 'pointer_router.dart' show PointerRouter;

/// Generic signature for callbacks passed to
/// [GestureRecognizer.invokeCallback]. This allows the
/// [GestureRecognizer.invokeCallback] mechanism to be generically used with
/// anonymous functions that return objects of particular types.
typedef RecognizerCallback<T> = T Function();

/// 偏移的配置传递给[DragStartDetails]。
enum DragStartBehavior {
  /// 在检测到第一个下降事件的位置设置初始偏移量。
  down,

  /// 将初始位置设置在检测到拖动开始事件的位置。
  start,
}

/// 所有手势识别器都继承的基类。提供基本的API，供与手势识别器一起使用的类使用，但不关心手势识别器本身的具体细节。
abstract class GestureRecognizer extends GestureArenaMember with DiagnosticableTreeMixin {
  /// 初始化手势识别器。
  GestureRecognizer({ this.debugOwner, PointerDeviceKind? kind }) : _kindFilter = kind;

  /// The recognizer's owner.
  ///
  /// This is used in the [toString] serialization to report the object for which
  /// this gesture recognizer was created, to aid in debugging.
  final Object? debugOwner;

  /// 允许识别的设备类型。如果为null，则将跟踪和识别所有设备类型的事件。
  final PointerDeviceKind? _kindFilter;

  /// 保持指针ID与它们来自的设备类型之间的映射。
  final Map<int, PointerDeviceKind> _pointerToKind = <int, PointerDeviceKind>{};

  /// 注册可能与此手势检测器有关的新指针。
  ///
  /// 此手势识别器的所有者使用该手势应考虑的每个指针的PointerDownEvent调用addPointer（）。
  void addPointer(PointerDownEvent event) {
    _pointerToKind[event.pointer] = event.kind;
    if (isPointerAllowed(event)) {
      addAllowedPointer(event);
    } else {
      handleNonAllowedPointer(event);
    }
  }

  /// 注册一个新的指针，该手势识别器已对其进行检查。
  @protected
  void addAllowedPointer(PointerDownEvent event) { }

  /// 处理此识别器不允许添加的指针。
  @protected
  void handleNonAllowedPointer(PointerDownEvent event) { }

  /// 检查此识别器是否允许跟踪指针。
  @protected
  bool isPointerAllowed(PointerDownEvent event) {
    return _kindFilter == null || _kindFilter == event.kind;
  }

  /// 对于给定的指针ID，返回与其关联的设备类型。
  @protected
  PointerDeviceKind getKindForPointer(int pointer) {
    return _pointerToKind[pointer]!;
  }

  /// 释放对象使用的所有资源。
  @mustCallSuper
  void dispose() { }

  /// Returns a very short pretty description of the gesture that the
  /// recognizer looks for, like 'tap' or 'horizontal drag'.
  String get debugDescription;

  /// 调用应用程序提供的回调，捕获并记录所有异常。
  @protected
  T? invokeCallback<T>(String name, RecognizerCallback<T> callback, { String Function()? debugReport }) {
    T? result;
    try {
      result = callback();
    } catch (exception, stack) {
    }
    return result;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Object>('debugOwner', debugOwner, defaultValue: null));
  }
}

/// 手势识别器的基类，一次只能识别一个手势。例如，即使将多个指针放在同一控件上，单个[TapGestureRecognizer]也永远无法识别同时发生的两次轻击。
abstract class OneSequenceGestureRecognizer extends GestureRecognizer {
  /// 初始化对象。
  OneSequenceGestureRecognizer({
    Object? debugOwner,
    PointerDeviceKind? kind,
  }) : super(debugOwner: debugOwner, kind: kind);

  final Map<int, GestureArenaEntry> _entries = <int, GestureArenaEntry>{};
  final Set<int> _trackedPointers = HashSet<int>();

  @override
  void handleNonAllowedPointer(PointerDownEvent event) {
    resolve(GestureDisposition.rejected);
  }

  /// Called when a pointer event is routed to this recognizer.
  @protected
  void handleEvent(PointerEvent event);

  @override
  void acceptGesture(int pointer) { }

  @override
  void rejectGesture(int pointer) { }

  /// 当此识别器正在跟踪的指针数从1变为零时调用。T
  @protected
  void didStopTrackingLastPointer(int pointer);

  /// Resolves this recognizer's participation in each gesture arena with the
  /// given disposition.
  @protected
  @mustCallSuper
  void resolve(GestureDisposition disposition) {
    final List<GestureArenaEntry> localEntries = List<GestureArenaEntry>.from(_entries.values);
    _entries.clear();
    for (final GestureArenaEntry entry in localEntries)
      entry.resolve(disposition);
  }

  /// Resolves this recognizer's participation in the given gesture arena with
  /// the given disposition.
  @protected
  @mustCallSuper
  void resolvePointer(int pointer, GestureDisposition disposition) {
    final GestureArenaEntry? entry = _entries[pointer];
    if (entry != null) {
      _entries.remove(pointer);
      entry.resolve(disposition);
    }
  }

  @override
  void dispose() {
    resolve(GestureDisposition.rejected);
    for (final int pointer in _trackedPointers)
      GestureBinding.instance!.pointerRouter.removeRoute(pointer, handleEvent);
    _trackedPointers.clear();
    super.dispose();
  }

  /// 该识别器所属的团队（如果有）。
  GestureArenaTeam? get team => _team;
  GestureArenaTeam? _team;
  /// The [team] can only be set once.
  set team(GestureArenaTeam? value) {
    _team = value;
  }

  GestureArenaEntry _addPointerToArena(int pointer) {
    if (_team != null)
      return _team!.add(pointer, this);
    return GestureBinding.instance!.gestureArena.add(pointer, this);
  }

  /// Causes events related to the given pointer ID to be routed to this recognizer.
  ///
  /// The pointer events are transformed according to `transform` and then delivered
  /// to [handleEvent]. The value for the `transform` argument is usually obtained
  /// from [PointerDownEvent.transform] to transform the events from the global
  /// coordinate space into the coordinate space of the event receiver. It may be
  /// null if no transformation is necessary.
  ///
  /// Use [stopTrackingPointer] to remove the route added by this function.
  @protected
  void startTrackingPointer(int pointer, [Matrix4? transform]) {
    GestureBinding.instance!.pointerRouter.addRoute(pointer, handleEvent, transform);
    _trackedPointers.add(pointer);
    assert(!_entries.containsValue(pointer));
    _entries[pointer] = _addPointerToArena(pointer);
  }

  /// Stops events related to the given pointer ID from being routed to this recognizer.
  ///
  /// If this function reduces the number of tracked pointers to zero, it will
  /// call [didStopTrackingLastPointer] synchronously.
  ///
  /// Use [startTrackingPointer] to add the routes in the first place.
  @protected
  void stopTrackingPointer(int pointer) {
    if (_trackedPointers.contains(pointer)) {
      GestureBinding.instance!.pointerRouter.removeRoute(pointer, handleEvent);
      _trackedPointers.remove(pointer);
      if (_trackedPointers.isEmpty)
        didStopTrackingLastPointer(pointer);
    }
  }

  /// Stops tracking the pointer associated with the given event if the event is
  /// a [PointerUpEvent] or a [PointerCancelEvent] event.
  @protected
  void stopTrackingIfPointerNoLongerDown(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent)
      stopTrackingPointer(event.pointer);
  }
}

/// The possible states of a [PrimaryPointerGestureRecognizer].
///
/// The recognizer advances from [ready] to [possible] when it starts tracking a
/// primary pointer. When the primary pointer is resolved in the gesture
/// arena (either accepted or rejected), the recognizers advances to [defunct].
/// Once the recognizer has stopped tracking any remaining pointers, the
/// recognizer returns to [ready].
enum GestureRecognizerState {
  /// The recognizer is ready to start recognizing a gesture.
  ready,

  /// The sequence of pointer events seen thus far is consistent with the
  /// gesture the recognizer is attempting to recognize but the gesture has not
  /// been accepted definitively.
  possible,

  /// Further pointer events cannot cause this recognizer to recognize the
  /// gesture until the recognizer returns to the [ready] state (typically when
  /// all the pointers the recognizer is tracking are removed from the screen).
  defunct,
}

/// A base class for gesture recognizers that track a single primary pointer.
///
/// Gestures based on this class will stop tracking the gesture if the primary
/// pointer travels beyond [preAcceptSlopTolerance] or [postAcceptSlopTolerance]
/// pixels from the original contact point of the gesture.
///
/// If the [preAcceptSlopTolerance] was breached before the gesture was accepted
/// in the gesture arena, the gesture will be rejected.
abstract class PrimaryPointerGestureRecognizer extends OneSequenceGestureRecognizer {
  /// Initializes the [deadline] field during construction of subclasses.
  ///
  /// {@macro flutter.gestures.GestureRecognizer.kind}
  PrimaryPointerGestureRecognizer({
    this.deadline,
    this.preAcceptSlopTolerance = kTouchSlop,
    this.postAcceptSlopTolerance = kTouchSlop,
    Object? debugOwner,
    PointerDeviceKind? kind,
  }) : assert(
         preAcceptSlopTolerance == null || preAcceptSlopTolerance >= 0,
         'The preAcceptSlopTolerance must be positive or null',
       ),
       assert(
         postAcceptSlopTolerance == null || postAcceptSlopTolerance >= 0,
         'The postAcceptSlopTolerance must be positive or null',
       ),
       super(debugOwner: debugOwner, kind: kind);

  /// If non-null, the recognizer will call [didExceedDeadline] after this
  /// amount of time has elapsed since starting to track the primary pointer.
  ///
  /// The [didExceedDeadline] will not be called if the primary pointer is
  /// accepted, rejected, or all pointers are up or canceled before [deadline].
  final Duration? deadline;

  /// The maximum distance in logical pixels the gesture is allowed to drift
  /// from the initial touch down position before the gesture is accepted.
  ///
  /// Drifting past the allowed slop amount causes the gesture to be rejected.
  ///
  /// Can be null to indicate that the gesture can drift for any distance.
  /// Defaults to 18 logical pixels.
  final double? preAcceptSlopTolerance;

  /// The maximum distance in logical pixels the gesture is allowed to drift
  /// after the gesture has been accepted.
  ///
  /// Drifting past the allowed slop amount causes the gesture to stop tracking
  /// and signaling subsequent callbacks.
  ///
  /// Can be null to indicate that the gesture can drift for any distance.
  /// Defaults to 18 logical pixels.
  final double? postAcceptSlopTolerance;

  /// The current state of the recognizer.
  ///
  /// See [GestureRecognizerState] for a description of the states.
  GestureRecognizerState state = GestureRecognizerState.ready;

  /// The ID of the primary pointer this recognizer is tracking.
  int? primaryPointer;

  /// The location at which the primary pointer contacted the screen.
  OffsetPair? initialPosition;

  // Whether this pointer is accepted by winning the arena or as defined by
  // a subclass calling acceptGesture.
  bool _gestureAccepted = false;
  Timer? _timer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    if (state == GestureRecognizerState.ready) {
      state = GestureRecognizerState.possible;
      primaryPointer = event.pointer;
      initialPosition = OffsetPair(local: event.localPosition, global: event.position);
      if (deadline != null)
        _timer = Timer(deadline!, () => didExceedDeadlineWithEvent(event));
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    assert(state != GestureRecognizerState.ready);
    if (state == GestureRecognizerState.possible && event.pointer == primaryPointer) {
      final bool isPreAcceptSlopPastTolerance =
          !_gestureAccepted &&
          preAcceptSlopTolerance != null &&
          _getGlobalDistance(event) > preAcceptSlopTolerance!;
      final bool isPostAcceptSlopPastTolerance =
          _gestureAccepted &&
          postAcceptSlopTolerance != null &&
          _getGlobalDistance(event) > postAcceptSlopTolerance!;

      if (event is PointerMoveEvent && (isPreAcceptSlopPastTolerance || isPostAcceptSlopPastTolerance)) {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(primaryPointer!);
      } else {
        handlePrimaryPointer(event);
      }
    }
    stopTrackingIfPointerNoLongerDown(event);
  }

  /// Override to provide behavior for the primary pointer when the gesture is still possible.
  @protected
  void handlePrimaryPointer(PointerEvent event);

  /// Override to be notified when [deadline] is exceeded.
  ///
  /// You must override this method or [didExceedDeadlineWithEvent] if you
  /// supply a [deadline].
  @protected
  void didExceedDeadline() {
    assert(deadline == null);
  }

  /// Same as [didExceedDeadline] but receives the [event] that initiated the
  /// gesture.
  ///
  /// You must override this method or [didExceedDeadline] if you supply a
  /// [deadline].
  @protected
  void didExceedDeadlineWithEvent(PointerDownEvent event) {
    didExceedDeadline();
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer == primaryPointer) {
      _stopTimer();
      _gestureAccepted = true;
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == primaryPointer && state == GestureRecognizerState.possible) {
      _stopTimer();
      state = GestureRecognizerState.defunct;
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    assert(state != GestureRecognizerState.ready);
    _stopTimer();
    state = GestureRecognizerState.ready;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _stopTimer() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  double _getGlobalDistance(PointerEvent event) {
    final Offset offset = event.position - initialPosition!.global;
    return offset.distance;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<GestureRecognizerState>('state', state));
  }
}

/// A container for a [local] and [global] [Offset] pair.
///
/// Usually, the [global] [Offset] is in the coordinate space of the screen
/// after conversion to logical pixels and the [local] offset is the same
/// [Offset], but transformed to a local coordinate space.
class OffsetPair {
  /// Creates a [OffsetPair] combining a [local] and [global] [Offset].
  const OffsetPair({
    required this.local,
    required this.global,
  });

  /// Creates a [OffsetPair] from [PointerEvent.localPosition] and
  /// [PointerEvent.position].
  factory OffsetPair.fromEventPosition(PointerEvent event) {
    return OffsetPair(local: event.localPosition, global: event.position);
  }

  /// Creates a [OffsetPair] from [PointerEvent.localDelta] and
  /// [PointerEvent.delta].
  factory OffsetPair.fromEventDelta(PointerEvent event) {
    return OffsetPair(local: event.localDelta, global: event.delta);
  }

  /// A [OffsetPair] where both [Offset]s are [Offset.zero].
  static const OffsetPair zero = OffsetPair(local: Offset.zero, global: Offset.zero);

  /// The [Offset] in the local coordinate space.
  final Offset local;

  /// The [Offset] in the global coordinate space after conversion to logical
  /// pixels.
  final Offset global;

  /// Adds the `other.global` to [global] and `other.local` to [local].
  OffsetPair operator+(OffsetPair other) {
    return OffsetPair(
      local: local + other.local,
      global: global + other.global,
    );
  }

  /// Subtracts the `other.global` from [global] and `other.local` from [local].
  OffsetPair operator-(OffsetPair other) {
    return OffsetPair(
      local: local - other.local,
      global: global - other.global,
    );
  }

  @override
  String toString() => '${objectRuntimeType(this, 'OffsetPair')}(local: $local, global: $global)';
}
