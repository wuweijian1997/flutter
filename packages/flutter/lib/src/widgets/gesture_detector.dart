// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

import 'basic.dart';
import 'framework.dart';

export 'package:flutter/gestures.dart' show
  DragDownDetails,
  DragStartDetails,
  DragUpdateDetails,
  DragEndDetails,
  GestureTapDownCallback,
  GestureTapUpCallback,
  GestureTapCallback,
  GestureTapCancelCallback,
  GestureLongPressCallback,
  GestureLongPressStartCallback,
  GestureLongPressMoveUpdateCallback,
  GestureLongPressUpCallback,
  GestureLongPressEndCallback,
  GestureDragDownCallback,
  GestureDragStartCallback,
  GestureDragUpdateCallback,
  GestureDragEndCallback,
  GestureDragCancelCallback,
  GestureScaleStartCallback,
  GestureScaleUpdateCallback,
  GestureScaleEndCallback,
  GestureForcePressStartCallback,
  GestureForcePressPeakCallback,
  GestureForcePressEndCallback,
  GestureForcePressUpdateCallback,
  LongPressStartDetails,
  LongPressMoveUpdateDetails,
  LongPressEndDetails,
  ScaleStartDetails,
  ScaleUpdateDetails,
  ScaleEndDetails,
  TapDownDetails,
  TapUpDetails,
  ForcePressDetails,
  Velocity;
export 'package:flutter/rendering.dart' show RenderSemanticsGestureHandler;

// Examples can assume:
// bool _lights;
// void setState(VoidCallback fn) { }
// String _last;
// Color _color;

/// Factory for creating gesture recognizers.
/// 用于创建手势识别器的工厂。
/// `T` is the type of gesture recognizer this class manages.
///
/// Used by [RawGestureDetector.gestures].
@optionalTypeArgs
abstract class GestureRecognizerFactory<T extends GestureRecognizer> {
  ///
  const GestureRecognizerFactory();

  /// Must return an instance of T.
  T constructor();

  /// Must configure the given instance (which will have been created by
  /// `constructor`).
  ///
  /// This normally means setting the callbacks.
  void initializer(T instance);

  bool _debugAssertTypeMatches(Type type) {
    assert(type == T, 'GestureRecognizerFactory of type $T was used where type $type was specified.');
    return true;
  }
}

/// Signature for closures that implement [GestureRecognizerFactory.constructor].
typedef GestureRecognizerFactoryConstructor<T extends GestureRecognizer> = T Function();

/// Signature for closures that implement [GestureRecognizerFactory.initializer].
typedef GestureRecognizerFactoryInitializer<T extends GestureRecognizer> = void Function(T instance);

/// Factory for creating gesture recognizers that delegates to callbacks.
///
/// Used by [RawGestureDetector.gestures].
class GestureRecognizerFactoryWithHandlers<T extends GestureRecognizer> extends GestureRecognizerFactory<T> {
  /// Creates a gesture recognizer factory with the given callbacks.
  ///
  /// The arguments must not be null.
  const GestureRecognizerFactoryWithHandlers(this._constructor, this._initializer)
    : assert(_constructor != null),
      assert(_initializer != null);

  final GestureRecognizerFactoryConstructor<T> _constructor;

  final GestureRecognizerFactoryInitializer<T> _initializer;

  @override
  T constructor() => _constructor();

  @override
  void initializer(T instance) => _initializer(instance);
}

/// A widget that detects gestures.
class GestureDetector extends StatelessWidget {
  /// Creates a widget that detects gestures.
  ///
  /// 平移和缩放回调不能同时使用，因为缩放是平移的超集。只需使用scale回调即可。
  /// 水平拖动和垂直拖动回调不能同时使用，因为水平拖动和垂直拖动的组合是平移。只需使用pan回调即可。
  /// 默认情况下，手势检测器将语义信息贡献给辅助技术使用的树。
  GestureDetector({
    Key key,
    this.child,
    this.onTapDown,
    this.onTapUp,
    this.onTap,
    this.onTapCancel,
    this.onSecondaryTap,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onSecondaryTapCancel,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.onTertiaryTapCancel,
    this.onDoubleTapDown,
    this.onDoubleTap,
    this.onDoubleTapCancel,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressUp,
    this.onLongPressEnd,
    this.onSecondaryLongPress,
    this.onSecondaryLongPressStart,
    this.onSecondaryLongPressMoveUpdate,
    this.onSecondaryLongPressUp,
    this.onSecondaryLongPressEnd,
    this.onVerticalDragDown,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
    this.onHorizontalDragDown,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.onHorizontalDragCancel,
    this.onForcePressStart,
    this.onForcePressPeak,
    this.onForcePressUpdate,
    this.onForcePressEnd,
    this.onPanDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.behavior,
    this.excludeFromSemantics = false,
    this.dragStartBehavior = DragStartBehavior.start,
  }) : super(key: key);

  /// 子组件
  final Widget child;

  /// 按下事件
  final GestureTapDownCallback onTapDown;

  /// 抬起事件
  final GestureTapUpCallback onTapUp;

  /// 点击事件
  /// 如果onTap没有赢得手势竞争,则会调用onCancel
  /// onTap和onTapUp会同时调用,onTapUp会包含点击位置的详细信息.
  final GestureTapCallback onTap;

  /// 如果onTap没有赢得手势竞争则会调用这个方法.
  final GestureTapCancelCallback onTapCancel;

  /// 辅助系列 onTap
  final GestureTapCallback onSecondaryTap;

  /// 辅助系列 onTapDown
  final GestureTapDownCallback onSecondaryTapDown;

  ///
  final GestureTapUpCallback onSecondaryTapUp;

  ///
  final GestureTapCancelCallback onSecondaryTapCancel;

  ///
  final GestureTapDownCallback onTertiaryTapDown;

  ///
  final GestureTapUpCallback onTertiaryTapUp;

  ///
  final GestureTapCancelCallback onTertiaryTapCancel;

  /// 双击按下事件
  final GestureTapDownCallback onDoubleTapDown;

  /// 双击事件
  final GestureTapCallback onDoubleTap;

  /// 双击取消事件
  final GestureTapCancelCallback onDoubleTapCancel;

  /// 长按事件
  final GestureLongPressCallback onLongPress;

  /// 长按开始事件
  final GestureLongPressStartCallback onLongPressStart;

  /// 长按移动事件
  final GestureLongPressMoveUpdateCallback onLongPressMoveUpdate;

  /// 长按抬起事件
  final GestureLongPressUpCallback onLongPressUp;

  /// 和onLongPressUp会同时调用,但是onLongPressEnd会包含位置信息
  final GestureLongPressEndCallback onLongPressEnd;

  /// 辅助长按
  final GestureLongPressCallback onSecondaryLongPress;

  /// 辅助长按开始
  final GestureLongPressStartCallback onSecondaryLongPressStart;

  /// 辅助长按移动
  final GestureLongPressMoveUpdateCallback onSecondaryLongPressMoveUpdate;

  /// 辅助长按抬起
  final GestureLongPressUpCallback onSecondaryLongPressUp;

  /// 辅助长按结束
  final GestureLongPressEndCallback onSecondaryLongPressEnd;

  /// 垂直拖动 按下
  final GestureDragDownCallback onVerticalDragDown;

  /// 垂直拖动开始
  final GestureDragStartCallback onVerticalDragStart;

  /// 垂直拖动更新
  final GestureDragUpdateCallback onVerticalDragUpdate;

  /// 垂直拖动结束
  final GestureDragEndCallback onVerticalDragEnd;

  /// 垂直拖动取消
  final GestureDragCancelCallback onVerticalDragCancel;

  /// 横向拖动按下
  final GestureDragDownCallback onHorizontalDragDown;

  /// 横向拖动开始
  final GestureDragStartCallback onHorizontalDragStart;

  /// 横向拖动更新
  final GestureDragUpdateCallback onHorizontalDragUpdate;

  /// 横向拖动结束
  final GestureDragEndCallback onHorizontalDragEnd;

  /// 横向拖动取消
  final GestureDragCancelCallback onHorizontalDragCancel;

  /// 接触屏幕，并且可能开始移动
  final GestureDragDownCallback onPanDown;

  /// 指针已通过主按钮接触屏幕并开始移动。
  final GestureDragStartCallback onPanStart;

  /// 通过主按钮与屏幕接触并移动的指针再次移动。
  final GestureDragUpdateCallback onPanUpdate;

  /// 以前通过主按钮与屏幕接触并移动的指针不再与屏幕接触，并且在停止接触屏幕时以特定速度移动。
  final GestureDragEndCallback onPanEnd;

  /// 先前触发[onPanDown]的指针未完成。
  final GestureDragCancelCallback onPanCancel;

  /// 缩放开始
  final GestureScaleStartCallback onScaleStart;

  /// 缩放更新
  final GestureScaleUpdateCallback onScaleUpdate;

  /// 缩放结束
  final GestureScaleEndCallback onScaleEnd;

  /// 指针与屏幕接触，并用足够的力进行按压以启动压力按压
  final GestureForcePressStartCallback onForcePressStart;

  /// 指针与屏幕接触并以最大的力按下。力的大小至少为[ForcePressGestureRecognizer.peakPressure].
  final GestureForcePressPeakCallback onForcePressPeak;

  /// 指针与屏幕接触，之前已通过[ForcePressGestureRecognizer.startPressure]，并且正在屏幕平面上移动，以变化的力按压屏幕，或者两者同时发生.
  final GestureForcePressUpdateCallback onForcePressUpdate;

  /// 指针不再与屏幕接触。
  final GestureForcePressEndCallback onForcePressEnd;

  /// 此手势检测器在命中测试期间应如何表现。
  final HitTestBehavior behavior;

  /// 是否从语义树中排除这些手势。例如，由于工具提示本身直接包含在语义树中，因此排除了用于显示工具提示的长按手势，因此具有显示该工具提示的手势将导致信息重复。
  final bool excludeFromSemantics;

  /// 拖动开始行为
  final DragStartBehavior dragStartBehavior;

  @override
  Widget build(BuildContext context) {
    final Map<Type, GestureRecognizerFactory> gestures = <Type, GestureRecognizerFactory>{};

    if (onTapDown != null ||
        onTapUp != null ||
        onTap != null ||
        onTapCancel != null ||
        onSecondaryTap != null ||
        onSecondaryTapDown != null ||
        onSecondaryTapUp != null ||
        onSecondaryTapCancel != null||
        onTertiaryTapDown != null ||
        onTertiaryTapUp != null ||
        onTertiaryTapCancel != null
    ) {
      gestures[TapGestureRecognizer] = GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(debugOwner: this),
        (TapGestureRecognizer instance) {
          instance
            ..onTapDown = onTapDown
            ..onTapUp = onTapUp
            ..onTap = onTap
            ..onTapCancel = onTapCancel
            ..onSecondaryTap = onSecondaryTap
            ..onSecondaryTapDown = onSecondaryTapDown
            ..onSecondaryTapUp = onSecondaryTapUp
            ..onSecondaryTapCancel = onSecondaryTapCancel
            ..onTertiaryTapDown = onTertiaryTapDown
            ..onTertiaryTapUp = onTertiaryTapUp
            ..onTertiaryTapCancel = onTertiaryTapCancel;
        },
      );
    }

    if (onDoubleTap != null) {
      gestures[DoubleTapGestureRecognizer] = GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
        () => DoubleTapGestureRecognizer(debugOwner: this),
        (DoubleTapGestureRecognizer instance) {
          instance
            ..onDoubleTapDown = onDoubleTapDown
            ..onDoubleTap = onDoubleTap
            ..onDoubleTapCancel = onDoubleTapCancel;
        },
      );
    }

    if (onLongPress != null ||
        onLongPressUp != null ||
        onLongPressStart != null ||
        onLongPressMoveUpdate != null ||
        onLongPressEnd != null ||
        onSecondaryLongPress != null ||
        onSecondaryLongPressUp != null ||
        onSecondaryLongPressStart != null ||
        onSecondaryLongPressMoveUpdate != null ||
        onSecondaryLongPressEnd != null) {
      gestures[LongPressGestureRecognizer] = GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
        () => LongPressGestureRecognizer(debugOwner: this),
        (LongPressGestureRecognizer instance) {
          instance
            ..onLongPress = onLongPress
            ..onLongPressStart = onLongPressStart
            ..onLongPressMoveUpdate = onLongPressMoveUpdate
            ..onLongPressEnd = onLongPressEnd
            ..onLongPressUp = onLongPressUp
            ..onSecondaryLongPress = onSecondaryLongPress
            ..onSecondaryLongPressStart = onSecondaryLongPressStart
            ..onSecondaryLongPressMoveUpdate = onSecondaryLongPressMoveUpdate
            ..onSecondaryLongPressEnd = onSecondaryLongPressEnd
            ..onSecondaryLongPressUp = onSecondaryLongPressUp;
        },
      );
    }

    if (onVerticalDragDown != null ||
        onVerticalDragStart != null ||
        onVerticalDragUpdate != null ||
        onVerticalDragEnd != null ||
        onVerticalDragCancel != null) {
      gestures[VerticalDragGestureRecognizer] = GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
        () => VerticalDragGestureRecognizer(debugOwner: this),
        (VerticalDragGestureRecognizer instance) {
          instance
            ..onDown = onVerticalDragDown
            ..onStart = onVerticalDragStart
            ..onUpdate = onVerticalDragUpdate
            ..onEnd = onVerticalDragEnd
            ..onCancel = onVerticalDragCancel
            ..dragStartBehavior = dragStartBehavior;
        },
      );
    }

    if (onHorizontalDragDown != null ||
        onHorizontalDragStart != null ||
        onHorizontalDragUpdate != null ||
        onHorizontalDragEnd != null ||
        onHorizontalDragCancel != null) {
      gestures[HorizontalDragGestureRecognizer] = GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
        () => HorizontalDragGestureRecognizer(debugOwner: this),
        (HorizontalDragGestureRecognizer instance) {
          instance
            ..onDown = onHorizontalDragDown
            ..onStart = onHorizontalDragStart
            ..onUpdate = onHorizontalDragUpdate
            ..onEnd = onHorizontalDragEnd
            ..onCancel = onHorizontalDragCancel
            ..dragStartBehavior = dragStartBehavior;
        },
      );
    }

    if (onPanDown != null ||
        onPanStart != null ||
        onPanUpdate != null ||
        onPanEnd != null ||
        onPanCancel != null) {
      gestures[PanGestureRecognizer] = GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
        () => PanGestureRecognizer(debugOwner: this),
        (PanGestureRecognizer instance) {
          instance
            ..onDown = onPanDown
            ..onStart = onPanStart
            ..onUpdate = onPanUpdate
            ..onEnd = onPanEnd
            ..onCancel = onPanCancel
            ..dragStartBehavior = dragStartBehavior;
        },
      );
    }

    if (onScaleStart != null || onScaleUpdate != null || onScaleEnd != null) {
      gestures[ScaleGestureRecognizer] = GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
        () => ScaleGestureRecognizer(debugOwner: this),
        (ScaleGestureRecognizer instance) {
          instance
            ..onStart = onScaleStart
            ..onUpdate = onScaleUpdate
            ..onEnd = onScaleEnd;
        },
      );
    }

    if (onForcePressStart != null ||
        onForcePressPeak != null ||
        onForcePressUpdate != null ||
        onForcePressEnd != null) {
      gestures[ForcePressGestureRecognizer] = GestureRecognizerFactoryWithHandlers<ForcePressGestureRecognizer>(
        () => ForcePressGestureRecognizer(debugOwner: this),
        (ForcePressGestureRecognizer instance) {
          instance
            ..onStart = onForcePressStart
            ..onPeak = onForcePressPeak
            ..onUpdate = onForcePressUpdate
            ..onEnd = onForcePressEnd;
        },
      );
    }

    return RawGestureDetector(
      gestures: gestures,
      behavior: behavior,
      excludeFromSemantics: excludeFromSemantics,
      child: child,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<DragStartBehavior>('startBehavior', dragStartBehavior));
  }
}

/// 一个小部件，用于检测由给定手势工厂描述的手势。
class RawGestureDetector extends StatefulWidget {
  /// 创建一个检测手势的小部件。
  const RawGestureDetector({
    Key key,
    this.child,
    this.gestures = const <Type, GestureRecognizerFactory>{},
    this.behavior,
    this.excludeFromSemantics = false,
    this.semantics,
  }) : super(key: key);

  /// 子组件
  final Widget child;

  /// 该小部件将尝试识别的手势
  final Map<Type, GestureRecognizerFactory> gestures;

  /// 此手势检测器在命中测试期间应如何表现。
  final HitTestBehavior behavior;

  /// 是否从语义树中排除这些手势
  final bool excludeFromSemantics;

  /// 描述应添加到基础渲染对象[RenderSemanticsGestureHandler]的语义符号。如果[excludeFromSemantics]为true，则无效。
  final SemanticsGestureDelegate semantics;

  @override
  RawGestureDetectorState createState() => RawGestureDetectorState();
}

/// State for a [RawGestureDetector].
class RawGestureDetectorState extends State<RawGestureDetector> {
  Map<Type, GestureRecognizer> _recognizers = const <Type, GestureRecognizer>{};
  SemanticsGestureDelegate _semantics;

  @override
  void initState() {
    super.initState();
    _semantics = widget.semantics ?? _DefaultSemanticsGestureDelegate(this);
    _syncAll(widget.gestures);
  }

  @override
  void didUpdateWidget(RawGestureDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!(oldWidget.semantics == null && widget.semantics == null)) {
      _semantics = widget.semantics ?? _DefaultSemanticsGestureDelegate(this);
    }
    _syncAll(widget.gestures);
  }

  /// 可以在构建阶段之后，在手势检测器的最接近后代[RenderObjectWidget]的布局期间调用此方法，以更新活动手势识别器的列表。
  void replaceGestureRecognizers(Map<Type, GestureRecognizerFactory> gestures) {
    _syncAll(gestures);
    if (!widget.excludeFromSemantics) {
      final RenderSemanticsGestureHandler semanticsGestureHandler = context.findRenderObject() as RenderSemanticsGestureHandler;
      _updateSemanticsForRenderObject(semanticsGestureHandler);
    }
  }

  /// 创建渲染对象后，可以调用此方法以过滤可用语义动作的列表。
  void replaceSemanticsActions(Set<SemanticsAction> actions) {
    if (widget.excludeFromSemantics)
      return;
    final RenderSemanticsGestureHandler semanticsGestureHandler = context.findRenderObject() as RenderSemanticsGestureHandler;
    semanticsGestureHandler.validActions = actions; // will call _markNeedsSemanticsUpdate(), if required.
  }

  @override
  void dispose() {
    for (final GestureRecognizer recognizer in _recognizers.values)
      recognizer.dispose();
    _recognizers = null;
    super.dispose();
  }

  void _syncAll(Map<Type, GestureRecognizerFactory> gestures) {
    final Map<Type, GestureRecognizer> oldRecognizers = _recognizers;
    _recognizers = <Type, GestureRecognizer>{};
    for (final Type type in gestures.keys) {
      _recognizers[type] = oldRecognizers[type] ?? gestures[type].constructor();
      gestures[type].initializer(_recognizers[type]);
    }
    for (final Type type in oldRecognizers.keys) {
      if (!_recognizers.containsKey(type))
        oldRecognizers[type].dispose();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    for (final GestureRecognizer recognizer in _recognizers.values)
      recognizer.addPointer(event);
  }

  HitTestBehavior get _defaultBehavior {
    return widget.child == null ? HitTestBehavior.translucent : HitTestBehavior.deferToChild;
  }

  void _updateSemanticsForRenderObject(RenderSemanticsGestureHandler renderObject) {
    _semantics.assignSemantics(renderObject);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = Listener(
      onPointerDown: _handlePointerDown,
      behavior: widget.behavior ?? _defaultBehavior,
      child: widget.child,
    );
    if (!widget.excludeFromSemantics)
      result = _GestureSemantics(
        child: result,
        assignSemantics: _updateSemanticsForRenderObject,
      );
    return result;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    if (_recognizers == null) {
      properties.add(DiagnosticsNode.message('DISPOSED'));
    } else {
      final List<String> gestures = _recognizers.values.map<String>((GestureRecognizer recognizer) => recognizer.debugDescription).toList();
      properties.add(IterableProperty<String>('gestures', gestures, ifEmpty: '<none>'));
      properties.add(IterableProperty<GestureRecognizer>('recognizers', _recognizers.values, level: DiagnosticLevel.fine));
      properties.add(DiagnosticsProperty<bool>('excludeFromSemantics', widget.excludeFromSemantics, defaultValue: false));
      if (!widget.excludeFromSemantics) {
        properties.add(DiagnosticsProperty<SemanticsGestureDelegate>('semantics', widget.semantics, defaultValue: null));
      }
    }
    properties.add(EnumProperty<HitTestBehavior>('behavior', widget.behavior, defaultValue: null));
  }
}

typedef _AssignSemantics = void Function(RenderSemanticsGestureHandler);

class _GestureSemantics extends SingleChildRenderObjectWidget {
  const _GestureSemantics({
    Key key,
    Widget child,
    @required this.assignSemantics,
  }) : assert(assignSemantics != null),
       super(key: key, child: child);

  final _AssignSemantics assignSemantics;

  @override
  RenderSemanticsGestureHandler createRenderObject(BuildContext context) {
    final RenderSemanticsGestureHandler renderObject = RenderSemanticsGestureHandler();
    assignSemantics(renderObject);
    return renderObject;
  }

  @override
  void updateRenderObject(BuildContext context, RenderSemanticsGestureHandler renderObject) {
    assignSemantics(renderObject);
  }
}

/// A base class that describes what semantics notations a [RawGestureDetector]
/// should add to the render object [RenderSemanticsGestureHandler].
///
/// It is used to allow custom [GestureDetector]s to add semantics notations.
abstract class SemanticsGestureDelegate {
  /// Create a delegate of gesture semantics.
  const SemanticsGestureDelegate();

  /// Assigns semantics notations to the [RenderSemanticsGestureHandler] render
  /// object of the gesture detector.
  ///
  /// This method is called when the widget is created, updated, or during
  /// [RawGestureDetectorState.replaceGestureRecognizers].
  void assignSemantics(RenderSemanticsGestureHandler renderObject);

  @override
  String toString() => '${objectRuntimeType(this, 'SemanticsGestureDelegate')}()';
}

// The default semantics delegate of [RawGestureDetector]. Its behavior is
// described in [RawGestureDetector.semantics].
//
// For readers who come here to learn how to write custom semantics delegates:
// this is not a proper sample code. It has access to the detector state as well
// as its private properties, which are inaccessible normally. It is designed
// this way in order to work independently in a [RawGestureRecognizer] to
// preserve existing behavior.
//
// Instead, a normal delegate will store callbacks as properties, and use them
// in `assignSemantics`.
class _DefaultSemanticsGestureDelegate extends SemanticsGestureDelegate {
  _DefaultSemanticsGestureDelegate(this.detectorState);

  final RawGestureDetectorState detectorState;

  @override
  void assignSemantics(RenderSemanticsGestureHandler renderObject) {
    assert(!detectorState.widget.excludeFromSemantics);
    final Map<Type, GestureRecognizer> recognizers = detectorState._recognizers;
    renderObject
      ..onTap = _getTapHandler(recognizers)
      ..onLongPress = _getLongPressHandler(recognizers)
      ..onHorizontalDragUpdate = _getHorizontalDragUpdateHandler(recognizers)
      ..onVerticalDragUpdate = _getVerticalDragUpdateHandler(recognizers);
  }

  GestureTapCallback _getTapHandler(Map<Type, GestureRecognizer> recognizers) {
    final TapGestureRecognizer tap = recognizers[TapGestureRecognizer] as TapGestureRecognizer;
    if (tap == null)
      return null;
    assert(tap is TapGestureRecognizer);

    return () {
      assert(tap != null);
      if (tap.onTapDown != null)
        tap.onTapDown(TapDownDetails());
      if (tap.onTapUp != null)
        tap.onTapUp(TapUpDetails(kind: PointerDeviceKind.unknown));
      if (tap.onTap != null)
        tap.onTap();
    };
  }

  GestureLongPressCallback _getLongPressHandler(Map<Type, GestureRecognizer> recognizers) {
    final LongPressGestureRecognizer longPress = recognizers[LongPressGestureRecognizer] as LongPressGestureRecognizer;
    if (longPress == null)
      return null;

    return () {
      assert(longPress is LongPressGestureRecognizer);
      if (longPress.onLongPressStart != null)
        longPress.onLongPressStart(const LongPressStartDetails());
      if (longPress.onLongPress != null)
        longPress.onLongPress();
      if (longPress.onLongPressEnd != null)
        longPress.onLongPressEnd(const LongPressEndDetails());
      if (longPress.onLongPressUp != null)
        longPress.onLongPressUp();
    };
  }

  GestureDragUpdateCallback _getHorizontalDragUpdateHandler(Map<Type, GestureRecognizer> recognizers) {
    final HorizontalDragGestureRecognizer horizontal = recognizers[HorizontalDragGestureRecognizer] as HorizontalDragGestureRecognizer;
    final PanGestureRecognizer pan = recognizers[PanGestureRecognizer] as PanGestureRecognizer;

    final GestureDragUpdateCallback horizontalHandler = horizontal == null ?
      null :
      (DragUpdateDetails details) {
        assert(horizontal is HorizontalDragGestureRecognizer);
        if (horizontal.onDown != null)
          horizontal.onDown(DragDownDetails());
        if (horizontal.onStart != null)
          horizontal.onStart(DragStartDetails());
        if (horizontal.onUpdate != null)
          horizontal.onUpdate(details);
        if (horizontal.onEnd != null)
          horizontal.onEnd(DragEndDetails(primaryVelocity: 0.0));
      };

    final GestureDragUpdateCallback panHandler = pan == null ?
      null :
      (DragUpdateDetails details) {
        assert(pan is PanGestureRecognizer);
        if (pan.onDown != null)
          pan.onDown(DragDownDetails());
        if (pan.onStart != null)
          pan.onStart(DragStartDetails());
        if (pan.onUpdate != null)
          pan.onUpdate(details);
        if (pan.onEnd != null)
          pan.onEnd(DragEndDetails());
      };

    if (horizontalHandler == null && panHandler == null)
      return null;
    return (DragUpdateDetails details) {
      if (horizontalHandler != null)
        horizontalHandler(details);
      if (panHandler != null)
        panHandler(details);
    };
  }

  GestureDragUpdateCallback _getVerticalDragUpdateHandler(Map<Type, GestureRecognizer> recognizers) {
    final VerticalDragGestureRecognizer vertical = recognizers[VerticalDragGestureRecognizer] as VerticalDragGestureRecognizer;
    final PanGestureRecognizer pan = recognizers[PanGestureRecognizer] as PanGestureRecognizer;

    final GestureDragUpdateCallback verticalHandler = vertical == null ?
      null :
      (DragUpdateDetails details) {
        assert(vertical is VerticalDragGestureRecognizer);
        if (vertical.onDown != null)
          vertical.onDown(DragDownDetails());
        if (vertical.onStart != null)
          vertical.onStart(DragStartDetails());
        if (vertical.onUpdate != null)
          vertical.onUpdate(details);
        if (vertical.onEnd != null)
          vertical.onEnd(DragEndDetails(primaryVelocity: 0.0));
      };

    final GestureDragUpdateCallback panHandler = pan == null ?
      null :
      (DragUpdateDetails details) {
        assert(pan is PanGestureRecognizer);
        if (pan.onDown != null)
          pan.onDown(DragDownDetails());
        if (pan.onStart != null)
          pan.onStart(DragStartDetails());
        if (pan.onUpdate != null)
          pan.onUpdate(details);
        if (pan.onEnd != null)
          pan.onEnd(DragEndDetails());
      };

    if (verticalHandler == null && panHandler == null)
      return null;
    return (DragUpdateDetails details) {
      if (verticalHandler != null)
        verticalHandler(details);
      if (panHandler != null)
        panHandler(details);
    };
  }
}
