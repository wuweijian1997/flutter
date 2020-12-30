// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'framework.dart';
import 'notification_listener.dart';
import 'sliver.dart';

/// 允许子树请求保留在懒惰列表中。
class AutomaticKeepAlive extends StatefulWidget {
  /// Creates a widget that listens to [KeepAliveNotification]s and maintains a
  /// [KeepAlive] widget appropriately.
  const AutomaticKeepAlive({
    Key? key,
    this.child,
  }) : super(key: key);

  /// 子组件
  final Widget? child;

  @override
  _AutomaticKeepAliveState createState() => _AutomaticKeepAliveState();
}

class _AutomaticKeepAliveState extends State<AutomaticKeepAlive> {
  Map<Listenable, VoidCallback>? _handles;
  Widget? _child;
  bool _keepingAlive = false;

  @override
  void initState() {
    super.initState();
    _updateChild();
  }

  @override
  void didUpdateWidget(AutomaticKeepAlive oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateChild();
  }

  void _updateChild() {
    _child = NotificationListener<KeepAliveNotification>(
      onNotification: _addClient,
      child: widget.child!,
    );
  }

  @override
  void dispose() {
    if (_handles != null) {
      for (final Listenable handle in _handles!.keys)
        handle.removeListener(_handles![handle]!);
    }
    super.dispose();
  }

  bool _addClient(KeepAliveNotification notification) {
    final Listenable handle = notification.handle;
    _handles ??= <Listenable, VoidCallback>{};
    _handles![handle] = _createCallback(handle);
    handle.addListener(_handles![handle]!);
    if (!_keepingAlive) {
      _keepingAlive = true;
      final ParentDataElement<KeepAliveParentDataMixin>? childElement = _getChildElement();
      if (childElement != null) {
        _updateParentDataOfChild(childElement);
      } else {
        SchedulerBinding.instance!.addPostFrameCallback((Duration timeStamp) {
          if (!mounted) {
            return;
          }
          final ParentDataElement<KeepAliveParentDataMixin>? childElement = _getChildElement();
          _updateParentDataOfChild(childElement!);
        });
      }
    }
    return false;
  }

  /// Get the [Element] for the only [KeepAlive] child.
  ///
  /// While this widget is guaranteed to have a child, this may return null if
  /// the first build of that child has not completed yet.
  ParentDataElement<KeepAliveParentDataMixin>? _getChildElement() {
    assert(mounted);
    final Element element = context as Element;
    Element? childElement;
    element.visitChildren((Element child) {
      childElement = child;
    });
    return childElement as ParentDataElement<KeepAliveParentDataMixin>?;
  }

  void _updateParentDataOfChild(ParentDataElement<KeepAliveParentDataMixin> childElement) {
    childElement.applyWidgetOutOfTurn(build(context) as ParentDataWidget<KeepAliveParentDataMixin>);
  }

  VoidCallback _createCallback(Listenable handle) {
    return () {
      _handles!.remove(handle);
      if (_handles!.isEmpty) {
        if (SchedulerBinding.instance!.schedulerPhase.index < SchedulerPhase.persistentCallbacks.index) {
          setState(() { _keepingAlive = false; });
        } else {
          _keepingAlive = false;
          scheduleMicrotask(() {
            if (mounted && _handles!.isEmpty) {
              setState(() {
                assert(!_keepingAlive);
              });
            }
          });
        }
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    assert(_child != null);
    return KeepAlive(
      keepAlive: _keepingAlive,
      child: _child!,
    );
  }


  @override
  void debugFillProperties(DiagnosticPropertiesBuilder description) {
    super.debugFillProperties(description);
    description.add(FlagProperty('_keepingAlive', value: _keepingAlive, ifTrue: 'keeping subtree alive'));
    description.add(DiagnosticsProperty<Map<Listenable, VoidCallback>>(
      'handles',
      _handles,
      description: _handles != null ?
        '${_handles!.length} active client${ _handles!.length == 1 ? "" : "s" }' :
        null,
      ifNull: 'no notifications ever received',
    ));
  }
}

/// Indicates that the subtree through which this notification bubbles must be
/// kept alive even if it would normally be discarded as an optimization.
///
/// For example, a focused text field might fire this notification to indicate
/// that it should not be disposed even if the user scrolls the field off
/// screen.
///
/// Each [KeepAliveNotification] is configured with a [handle] that consists of
/// a [Listenable] that is triggered when the subtree no longer needs to be kept
/// alive.
///
/// The [handle] should be triggered any time the sending widget is removed from
/// the tree (in [State.deactivate]). If the widget is then rebuilt and still
/// needs to be kept alive, it should immediately send a new notification
/// (possible with the very same [Listenable]) during build.
///
/// This notification is listened to by the [AutomaticKeepAlive] widget, which
/// is added to the tree automatically by [SliverList] (and [ListView]) and
/// [SliverGrid] (and [GridView]) widgets.
///
/// Failure to trigger the [handle] in the manner described above will likely
/// cause the [AutomaticKeepAlive] to lose track of whether the widget should be
/// kept alive or not, leading to memory leaks or lost data. For example, if the
/// widget that requested keepalive is removed from the subtree but doesn't
/// trigger its [Listenable] on the way out, then the subtree will continue to
/// be kept alive until the list itself is disposed. Similarly, if the
/// [Listenable] is triggered while the widget needs to be kept alive, but a new
/// [KeepAliveNotification] is not immediately sent, then the widget risks being
/// garbage collected while it wants to be kept alive.
///
/// It is an error to use the same [handle] in two [KeepAliveNotification]s
/// within the same [AutomaticKeepAlive] without triggering that [handle] before
/// the second notification is sent.
///
/// For a more convenient way to interact with [AutomaticKeepAlive] widgets,
/// consider using [AutomaticKeepAliveClientMixin], which uses
/// [KeepAliveNotification] internally.
class KeepAliveNotification extends Notification {
  /// Creates a notification to indicate that a subtree must be kept alive.
  ///
  /// The [handle] must not be null.
  const KeepAliveNotification(this.handle) : assert(handle != null);

  /// A [Listenable] that will inform its clients when the widget that fired the
  /// notification no longer needs to be kept alive.
  ///
  /// The [Listenable] should be triggered any time the sending widget is
  /// removed from the tree (in [State.deactivate]). If the widget is then
  /// rebuilt and still needs to be kept alive, it should immediately send a new
  /// notification (possible with the very same [Listenable]) during build.
  ///
  /// See also:
  ///
  ///  * [KeepAliveHandle], a convenience class for use with this property.
  final Listenable handle;
}

/// A [Listenable] which can be manually triggered.
///
/// Used with [KeepAliveNotification] objects as their
/// [KeepAliveNotification.handle].
///
/// For a more convenient way to interact with [AutomaticKeepAlive] widgets,
/// consider using [AutomaticKeepAliveClientMixin], which uses a
/// [KeepAliveHandle] internally.
class KeepAliveHandle extends ChangeNotifier {
  /// Trigger the listeners to indicate that the widget
  /// no longer needs to be kept alive.
  void release() {
    notifyListeners();
  }
}

///
@optionalTypeArgs
mixin AutomaticKeepAliveClientMixin<T extends StatefulWidget> on State<T> {
  KeepAliveHandle? _keepAliveHandle;

  void _ensureKeepAlive() {
    _keepAliveHandle = KeepAliveHandle();
    KeepAliveNotification(_keepAliveHandle!).dispatch(context);
  }

  void _releaseKeepAlive() {
    _keepAliveHandle!.release();
    _keepAliveHandle = null;
  }

  /// Whether the current instance should be kept alive.
  ///
  /// Call [updateKeepAlive] whenever this getter's value changes.
  @protected
  bool get wantKeepAlive;

  /// Ensures that any [AutomaticKeepAlive] ancestors are in a good state, by
  /// firing a [KeepAliveNotification] or triggering the [KeepAliveHandle] as
  /// appropriate.
  @protected
  void updateKeepAlive() {
    if (wantKeepAlive) {
      if (_keepAliveHandle == null)
        _ensureKeepAlive();
    } else {
      if (_keepAliveHandle != null)
        _releaseKeepAlive();
    }
  }

  @override
  void initState() {
    super.initState();
    if (wantKeepAlive)
      _ensureKeepAlive();
  }

  @override
  void deactivate() {
    if (_keepAliveHandle != null)
      _releaseKeepAlive();
    super.deactivate();
  }

  @mustCallSuper
  @override
  Widget build(BuildContext context) {
    if (wantKeepAlive && _keepAliveHandle == null)
      _ensureKeepAlive();
    return const _NullWidget();
  }
}

class _NullWidget extends StatelessWidget {
  const _NullWidget();

  @override
  Widget build(BuildContext context) {
    throw FlutterError(
      'Widgets that mix AutomaticKeepAliveClientMixin into their State must '
      'call super.build() but must ignore the return value of the superclass.'
    );
  }
}
