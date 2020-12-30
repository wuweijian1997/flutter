// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'debug.dart';
import 'focus_manager.dart';
import 'inherited_model.dart';

export 'dart:ui' show hashValues, hashList;

export 'package:flutter/foundation.dart' show
  factory,
  immutable,
  mustCallSuper,
  optionalTypeArgs,
  protected,
  required,
  visibleForTesting;
export 'package:flutter/foundation.dart' show FlutterError, ErrorSummary, ErrorDescription, ErrorHint, debugPrint, debugPrintStack;
export 'package:flutter/foundation.dart' show VoidCallback, ValueChanged, ValueGetter, ValueSetter;
export 'package:flutter/foundation.dart' show DiagnosticsNode, DiagnosticLevel;
export 'package:flutter/foundation.dart' show Key, LocalKey, ValueKey;
export 'package:flutter/rendering.dart' show RenderObject, RenderBox, debugDumpRenderTree, debugDumpLayerTree;

// Examples can assume:
// late BuildContext context;
// void setState(VoidCallback fn) { }
// abstract class RenderFrogJar extends RenderObject { }
// abstract class FrogJar extends RenderObjectWidget { }
// abstract class FrogJarParentData extends ParentData { late Size size; }

// KEYS

/// A key that is only equal to itself.
///
/// This cannot be created with a const constructor because that implies that
/// all instantiated keys would be the same instance and therefore not be unique.
class UniqueKey extends LocalKey {
  /// Creates a key that is equal only to itself.
  ///
  /// The key cannot be created with a const constructor because that implies
  /// that all instantiated keys would be the same instance and therefore not
  /// be unique.
  // ignore: prefer_const_constructors_in_immutables , never use const for this class
  UniqueKey();

  @override
  String toString() => '[#${shortHash(this)}]';
}

/// A key that takes its identity from the object used as its value.
///
/// Used to tie the identity of a widget to the identity of an object used to
/// generate that widget.
///
/// See also:
///
///  * [Key], the base class for all keys.
///  * The discussion at [Widget.key] for more information about how widgets use
///    keys.
class ObjectKey extends LocalKey {
  /// Creates a key that uses [identical] on [value] for its [operator==].
  const ObjectKey(this.value);

  /// The object whose identity is used by this key's [operator==].
  final Object? value;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType)
      return false;
    return other is ObjectKey
        && identical(other.value, value);
  }

  @override
  int get hashCode => hashValues(runtimeType, identityHashCode(value));

  @override
  String toString() {
    if (runtimeType == ObjectKey)
      return '[${describeIdentity(value)}]';
    return '[${objectRuntimeType(this, 'ObjectKey')} ${describeIdentity(value)}]';
  }
}

/// A key that is unique across the entire app.
///
/// Global keys uniquely identify elements. Global keys provide access to other
/// objects that are associated with those elements, such as [BuildContext].
/// For [StatefulWidget]s, global keys also provide access to [State].
///
/// Widgets that have global keys reparent their subtrees when they are moved
/// from one location in the tree to another location in the tree. In order to
/// reparent its subtree, a widget must arrive at its new location in the tree
/// in the same animation frame in which it was removed from its old location in
/// the tree.
///
/// Reparenting an [Element] using a global key is relatively expensive, as
/// this operation will trigger a call to [State.deactivate] on the associated
/// [State] and all of its descendants; then force all widgets that depends
/// on an [InheritedWidget] to rebuild.
///
/// If you don't need any of the features listed above, consider using a [Key],
/// [ValueKey], [ObjectKey], or [UniqueKey] instead.
///
/// You cannot simultaneously include two widgets in the tree with the same
/// global key. Attempting to do so will assert at runtime.
///
/// ## Pitfalls
/// GlobalKeys should not be re-created on every build. They should usually be
/// long-lived objects owned by a [State] object, for example.
///
/// Creating a new GlobalKey on every build will throw away the state of the
/// subtree associated with the old key and create a new fresh subtree for the
/// new key. Besides harming performance, this can also cause unexpected
/// behavior in widgets in the subtree. For example, a [GestureDetector] in the
/// subtree will be unable to track ongoing gestures since it will be recreated
/// on each build.
///
/// Instead, a good practice is to let a State object own the GlobalKey, and
/// instantiate it outside the build method, such as in [State.initState].
///
/// See also:
///
///  * The discussion at [Widget.key] for more information about how widgets use
///    keys.
@optionalTypeArgs
abstract class GlobalKey<T extends State<StatefulWidget>> extends Key {
  /// Creates a [LabeledGlobalKey], which is a [GlobalKey] with a label used for
  /// debugging.
  ///
  /// The label is purely for debugging and not used for comparing the identity
  /// of the key.
  factory GlobalKey({ String? debugLabel }) => LabeledGlobalKey<T>(debugLabel);

  /// Creates a global key without a label.
  ///
  /// Used by subclasses because the factory constructor shadows the implicit
  /// constructor.
  const GlobalKey.constructor() : super.empty();

  static final Map<GlobalKey, Element> _registry = <GlobalKey, Element>{};
  static final Set<Element> _debugIllFatedElements = HashSet<Element>();
  // This map keeps track which child reserves the global key with the parent.
  // Parent, child -> global key.
  // This provides us a way to remove old reservation while parent rebuilds the
  // child in the same slot.
  static final Map<Element, Map<Element, GlobalKey>> _debugReservations = <Element, Map<Element, GlobalKey>>{};

  static void _debugRemoveReservationFor(Element parent, Element child) {
    assert(() {
      assert(parent != null);
      assert(child != null);
      _debugReservations[parent]?.remove(child);
      return true;
    }());
  }

  void _register(Element element) {
    assert(() {
      if (_registry.containsKey(this)) {
        assert(element.widget != null);
        final Element oldElement = _registry[this]!;
        assert(oldElement.widget != null);
        assert(element.widget.runtimeType != oldElement.widget.runtimeType);
        _debugIllFatedElements.add(oldElement);
      }
      return true;
    }());
    _registry[this] = element;
  }

  void _unregister(Element element) {
    assert(() {
      if (_registry.containsKey(this) && _registry[this] != element) {
        assert(element.widget != null);
        final Element oldElement = _registry[this]!;
        assert(oldElement.widget != null);
        assert(element.widget.runtimeType != oldElement.widget.runtimeType);
      }
      return true;
    }());
    if (_registry[this] == element)
      _registry.remove(this);
  }

  void _debugReserveFor(Element parent, Element child) {
    assert(() {
      assert(parent != null);
      assert(child != null);
      _debugReservations[parent] ??= <Element, GlobalKey>{};
      _debugReservations[parent]![child] = this;
      return true;
    }());
  }

  static void _debugVerifyGlobalKeyReservation() {
    assert(() {
      final Map<GlobalKey, Element> keyToParent = <GlobalKey, Element>{};
      _debugReservations.forEach((Element parent, Map<Element, GlobalKey> childToKey) {
        // We ignore parent that are unmounted or detached.
        if (parent._lifecycleState == _ElementLifecycle.defunct || parent.renderObject?.attached == false)
          return;
        childToKey.forEach((Element child, GlobalKey key) {
          // If parent = null, the node is deactivated by its parent and is
          // not re-attached to other part of the tree. We should ignore this
          // node.
          if (child._parent == null)
            return;
          // It is possible the same key registers to the same parent twice
          // with different children. That is illegal, but it is not in the
          // scope of this check. Such error will be detected in
          // _debugVerifyIllFatedPopulation or
          // _debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans.
          if (keyToParent.containsKey(key) && keyToParent[key] != parent) {
            // We have duplication reservations for the same global key.
            final Element older = keyToParent[key]!;
            final Element newer = parent;
            final FlutterError error;
            if (older.toString() != newer.toString()) {
              error = FlutterError.fromParts(<DiagnosticsNode>[
                ErrorSummary('Multiple widgets used the same GlobalKey.'),
                ErrorDescription(
                  'The key $key was used by multiple widgets. The parents of those widgets were:\n'
                    '- ${older.toString()}\n'
                    '- ${newer.toString()}\n'
                    'A GlobalKey can only be specified on one widget at a time in the widget tree.'
                ),
              ]);
            } else {
              error = FlutterError.fromParts(<DiagnosticsNode>[
                ErrorSummary('Multiple widgets used the same GlobalKey.'),
                ErrorDescription(
                  'The key $key was used by multiple widgets. The parents of those widgets were '
                    'different widgets that both had the following description:\n'
                    '  ${parent.toString()}\n'
                    'A GlobalKey can only be specified on one widget at a time in the widget tree.'
                ),
              ]);
            }
            // Fix the tree by removing the duplicated child from one of its
            // parents to resolve the duplicated key issue. This allows us to
            // tear down the tree during testing without producing additional
            // misleading exceptions.
            if (child._parent != older) {
              older.visitChildren((Element currentChild) {
                if (currentChild == child)
                  older.forgetChild(child);
              });
            }
            if (child._parent != newer) {
              newer.visitChildren((Element currentChild) {
                if (currentChild == child)
                  newer.forgetChild(child);
              });
            }
            throw error;
          } else {
            keyToParent[key] = parent;
          }
        });
      });
      _debugReservations.clear();
      return true;
    }());
  }

  static void _debugVerifyIllFatedPopulation() {
    assert(() {
      Map<GlobalKey, Set<Element>>? duplicates;
      for (final Element element in _debugIllFatedElements) {
        if (element._lifecycleState != _ElementLifecycle.defunct) {
          assert(element != null);
          assert(element.widget != null);
          assert(element.widget.key != null);
          final GlobalKey key = element.widget.key! as GlobalKey;
          assert(_registry.containsKey(key));
          duplicates ??= <GlobalKey, Set<Element>>{};
          // Uses ordered set to produce consistent error message.
          final Set<Element> elements = duplicates.putIfAbsent(key, () => LinkedHashSet<Element>());
          elements.add(element);
          elements.add(_registry[key]!);
        }
      }
      _debugIllFatedElements.clear();
      if (duplicates != null) {
        final List<DiagnosticsNode> information = <DiagnosticsNode>[];
        information.add(ErrorSummary('Multiple widgets used the same GlobalKey.'));
        for (final GlobalKey key in duplicates.keys) {
          final Set<Element> elements = duplicates[key]!;
          // TODO(jacobr): this will omit the '- ' before each widget name and
          // use the more standard whitespace style instead. Please let me know
          // if the '- ' style is a feature we want to maintain and we can add
          // another tree style that supports it. I also see '* ' in some places
          // so it would be nice to unify and normalize.
          information.add(Element.describeElements('The key $key was used by ${elements.length} widgets', elements));
        }
        information.add(ErrorDescription('A GlobalKey can only be specified on one widget at a time in the widget tree.'));
        throw FlutterError.fromParts(information);
      }
      return true;
    }());
  }

  Element? get _currentElement => _registry[this];

  /// The build context in which the widget with this key builds.
  ///
  /// The current context is null if there is no widget in the tree that matches
  /// this global key.
  BuildContext? get currentContext => _currentElement;

  /// The widget in the tree that currently has this global key.
  ///
  /// The current widget is null if there is no widget in the tree that matches
  /// this global key.
  Widget? get currentWidget => _currentElement?.widget;

  /// The [State] for the widget in the tree that currently has this global key.
  ///
  /// The current state is null if (1) there is no widget in the tree that
  /// matches this global key, (2) that widget is not a [StatefulWidget], or the
  /// associated [State] object is not a subtype of `T`.
  T? get currentState {
    final Element? element = _currentElement;
    if (element is StatefulElement) {
      final StatefulElement statefulElement = element;
      final State state = statefulElement.state;
      if (state is T)
        return state;
    }
    return null;
  }
}

/// A global key with a debugging label.
///
/// The debug label is useful for documentation and for debugging. The label
/// does not affect the key's identity.
@optionalTypeArgs
class LabeledGlobalKey<T extends State<StatefulWidget>> extends GlobalKey<T> {
  /// Creates a global key with a debugging label.
  ///
  /// The label does not affect the key's identity.
  // ignore: prefer_const_constructors_in_immutables , never use const for this class
  LabeledGlobalKey(this._debugLabel) : super.constructor();

  final String? _debugLabel;

  @override
  String toString() {
    final String label = _debugLabel != null ? ' $_debugLabel' : '';
    if (runtimeType == LabeledGlobalKey)
      return '[GlobalKey#${shortHash(this)}$label]';
    return '[${describeIdentity(this)}$label]';
  }
}

/// A global key that takes its identity from the object used as its value.
///
/// Used to tie the identity of a widget to the identity of an object used to
/// generate that widget.
///
/// If the object is not private, then it is possible that collisions will occur
/// where independent widgets will reuse the same object as their
/// [GlobalObjectKey] value in a different part of the tree, leading to a global
/// key conflict. To avoid this problem, create a private [GlobalObjectKey]
/// subclass, as in:
///
/// ```dart
/// class _MyKey extends GlobalObjectKey {
///   const _MyKey(Object value) : super(value);
/// }
/// ```
///
/// Since the [runtimeType] of the key is part of its identity, this will
/// prevent clashes with other [GlobalObjectKey]s even if they have the same
/// value.
///
/// Any [GlobalObjectKey] created for the same value will match.
@optionalTypeArgs
class GlobalObjectKey<T extends State<StatefulWidget>> extends GlobalKey<T> {
  /// Creates a global key that uses [identical] on [value] for its [operator==].
  const GlobalObjectKey(this.value) : super.constructor();

  /// The object whose identity is used by this key's [operator==].
  final Object value;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType)
      return false;
    return other is GlobalObjectKey<T>
        && identical(other.value, value);
  }

  @override
  int get hashCode => identityHashCode(value);

  @override
  String toString() {
    String selfType = objectRuntimeType(this, 'GlobalObjectKey');
    // The runtimeType string of a GlobalObjectKey() returns 'GlobalObjectKey<State<StatefulWidget>>'
    // because GlobalObjectKey is instantiated to its bounds. To avoid cluttering the output
    // we remove the suffix.
    const String suffix = '<State<StatefulWidget>>';
    if (selfType.endsWith(suffix)) {
      selfType = selfType.substring(0, selfType.length - suffix.length);
    }
    return '[$selfType ${describeIdentity(value)}]';
  }
}

/// This class is a work-around for the "is" operator not accepting a variable value as its right operand.
///
/// This class is deprecated. It will be deleted soon.
// TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
@Deprecated(
  'TypeMatcher has been deprecated because it is no longer used in framework(only in deprecated methods). '
  'This feature was deprecated after v1.12.1.'
)
@optionalTypeArgs
class TypeMatcher<T> {
  /// Creates a type matcher for the given type parameter.
  const TypeMatcher();

  /// Returns true if the given object is of type `T`.
  bool check(dynamic object) => object is T;
}

/// Describes the configuration for an [Element].
///
/// Widgets are the central class hierarchy in the Flutter framework. A widget
/// is an immutable description of part of a user interface. Widgets can be
/// inflated into elements, which manage the underlying render tree.
///
/// Widgets themselves have no mutable state (all their fields must be final).
/// If you wish to associate mutable state with a widget, consider using a
/// [StatefulWidget], which creates a [State] object (via
/// [StatefulWidget.createState]) whenever it is inflated into an element and
/// incorporated into the tree.
///
/// A given widget can be included in the tree zero or more times. In particular
/// a given widget can be placed in the tree multiple times. Each time a widget
/// is placed in the tree, it is inflated into an [Element], which means a
/// widget that is incorporated into the tree multiple times will be inflated
/// multiple times.
///
/// The [key] property controls how one widget replaces another widget in the
/// tree. If the [runtimeType] and [key] properties of the two widgets are
/// [operator==], respectively, then the new widget replaces the old widget by
/// updating the underlying element (i.e., by calling [Element.update] with the
/// new widget). Otherwise, the old element is removed from the tree, the new
/// widget is inflated into an element, and the new element is inserted into the
/// tree.
///
/// See also:
///
///  * [StatefulWidget] and [State], for widgets that can build differently
///    several times over their lifetime.
///  * [InheritedWidget], for widgets that introduce ambient state that can
///    be read by descendant widgets.
///  * [StatelessWidget], for widgets that always build the same way given a
///    particular configuration and ambient state.
@immutable
abstract class Widget extends DiagnosticableTree {
  /// Initializes [key] for subclasses.
  const Widget({ this.key });

  /// Controls how one widget replaces another widget in the tree.
  ///
  /// If the [runtimeType] and [key] properties of the two widgets are
  /// [operator==], respectively, then the new widget replaces the old widget by
  /// updating the underlying element (i.e., by calling [Element.update] with the
  /// new widget). Otherwise, the old element is removed from the tree, the new
  /// widget is inflated into an element, and the new element is inserted into the
  /// tree.
  ///
  /// In addition, using a [GlobalKey] as the widget's [key] allows the element
  /// to be moved around the tree (changing parent) without losing state. When a
  /// new widget is found (its key and type do not match a previous widget in
  /// the same location), but there was a widget with that same global key
  /// elsewhere in the tree in the previous frame, then that widget's element is
  /// moved to the new location.
  ///
  /// Generally, a widget that is the only child of another widget does not need
  /// an explicit key.
  ///
  /// See also:
  ///
  ///  * The discussions at [Key] and [GlobalKey].
  final Key? key;

  /// Inflates this configuration to a concrete instance.
  ///
  /// A given widget can be included in the tree zero or more times. In particular
  /// a given widget can be placed in the tree multiple times. Each time a widget
  /// is placed in the tree, it is inflated into an [Element], which means a
  /// widget that is incorporated into the tree multiple times will be inflated
  /// multiple times.
  @protected
  @factory
  Element createElement();

  /// A short, textual description of this widget.
  @override
  String toStringShort() {
    final String type = objectRuntimeType(this, 'Widget');
    return key == null ? type : '$type-$key';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.defaultDiagnosticsTreeStyle = DiagnosticsTreeStyle.dense;
  }

  @override
  @nonVirtual
  bool operator ==(Object other) => super == other;

  @override
  @nonVirtual
  int get hashCode => super.hashCode;

  /// Whether the `newWidget` can be used to update an [Element] that currently
  /// has the `oldWidget` as its configuration.
  ///
  /// An element that uses a given widget as its configuration can be updated to
  /// use another widget as its configuration if, and only if, the two widgets
  /// have [runtimeType] and [key] properties that are [operator==].
  ///
  /// If the widgets have no key (their key is null), then they are considered a
  /// match if they have the same type, even if their children are completely
  /// different.
  static bool canUpdate(Widget oldWidget, Widget newWidget) {
    return oldWidget.runtimeType == newWidget.runtimeType
        && oldWidget.key == newWidget.key;
  }

  // Return a numeric encoding of the specific `Widget` concrete subtype.
  // This is used in `Element.updateChild` to determine if a hot reload modified the
  // superclass of a mounted element's configuration. The encoding of each `Widget`
  // must match the corresponding `Element` encoding in `Element._debugConcreteSubtype`.
  static int _debugConcreteSubtype(Widget widget) {
    return widget is StatefulWidget ? 1 :
           widget is StatelessWidget ? 2 :
           0;
    }
}

/// A widget that does not require mutable state.
///
/// A stateless widget is a widget that describes part of the user interface by
/// building a constellation of other widgets that describe the user interface
/// more concretely. The building process continues recursively until the
/// description of the user interface is fully concrete (e.g., consists
/// entirely of [RenderObjectWidget]s, which describe concrete [RenderObject]s).
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=wE7khGHVkYY}
///
/// Stateless widget are useful when the part of the user interface you are
/// describing does not depend on anything other than the configuration
/// information in the object itself and the [BuildContext] in which the widget
/// is inflated. For compositions that can change dynamically, e.g. due to
/// having an internal clock-driven state, or depending on some system state,
/// consider using [StatefulWidget].
///
/// ## Performance considerations
///
/// The [build] method of a stateless widget is typically only called in three
/// situations: the first time the widget is inserted in the tree, when the
/// widget's parent changes its configuration, and when an [InheritedWidget] it
/// depends on changes.
///
/// If a widget's parent will regularly change the widget's configuration, or if
/// it depends on inherited widgets that frequently change, then it is important
/// to optimize the performance of the [build] method to maintain a fluid
/// rendering performance.
///
/// There are several techniques one can use to minimize the impact of
/// rebuilding a stateless widget:
///
///  * Minimize the number of nodes transitively created by the build method and
///    any widgets it creates. For example, instead of an elaborate arrangement
///    of [Row]s, [Column]s, [Padding]s, and [SizedBox]es to position a single
///    child in a particularly fancy manner, consider using just an [Align] or a
///    [CustomSingleChildLayout]. Instead of an intricate layering of multiple
///    [Container]s and with [Decoration]s to draw just the right graphical
///    effect, consider a single [CustomPaint] widget.
///
///  * Use `const` widgets where possible, and provide a `const` constructor for
///    the widget so that users of the widget can also do so.
///
///  * Consider refactoring the stateless widget into a stateful widget so that
///    it can use some of the techniques described at [StatefulWidget], such as
///    caching common parts of subtrees and using [GlobalKey]s when changing the
///    tree structure.
///
///  * If the widget is likely to get rebuilt frequently due to the use of
///    [InheritedWidget]s, consider refactoring the stateless widget into
///    multiple widgets, with the parts of the tree that change being pushed to
///    the leaves. For example instead of building a tree with four widgets, the
///    inner-most widget depending on the [Theme], consider factoring out the
///    part of the build function that builds the inner-most widget into its own
///    widget, so that only the inner-most widget needs to be rebuilt when the
///    theme changes.
///
/// {@tool snippet}
///
/// The following is a skeleton of a stateless widget subclass called `GreenFrog`.
///
/// Normally, widgets have more constructor arguments, each of which corresponds
/// to a `final` property.
///
/// ```dart
/// class GreenFrog extends StatelessWidget {
///   const GreenFrog({ Key? key }) : super(key: key);
///
///   @override
///   Widget build(BuildContext context) {
///     return Container(color: const Color(0xFF2DBD3A));
///   }
/// }
/// ```
/// {@end-tool}
///
/// {@tool snippet}
///
/// This next example shows the more generic widget `Frog` which can be given
/// a color and a child:
///
/// ```dart
/// class Frog extends StatelessWidget {
///   const Frog({
///     Key? key,
///     this.color = const Color(0xFF2DBD3A),
///     this.child,
///   }) : super(key: key);
///
///   final Color color;
///   final Widget? child;
///
///   @override
///   Widget build(BuildContext context) {
///     return Container(color: color, child: child);
///   }
/// }
/// ```
/// {@end-tool}
///
/// By convention, widget constructors only use named arguments. Named arguments
/// can be marked as required using [@required]. Also by convention, the first
/// argument is [key], and the last argument is `child`, `children`, or the
/// equivalent.
///
/// See also:
///
///  * [StatefulWidget] and [State], for widgets that can build differently
///    several times over their lifetime.
///  * [InheritedWidget], for widgets that introduce ambient state that can
///    be read by descendant widgets.
abstract class StatelessWidget extends Widget {
  /// Initializes [key] for subclasses.
  const StatelessWidget({ Key? key }) : super(key: key);

  /// Creates a [StatelessElement] to manage this widget's location in the tree.
  ///
  /// It is uncommon for subclasses to override this method.
  @override
  StatelessElement createElement() => StatelessElement(this);

  /// Describes the part of the user interface represented by this widget.
  ///
  /// The framework calls this method when this widget is inserted into the tree
  /// in a given [BuildContext] and when the dependencies of this widget change
  /// (e.g., an [InheritedWidget] referenced by this widget changes). This
  /// method can potentially be called in every frame and should not have any side
  /// effects beyond building a widget.
  ///
  /// The framework replaces the subtree below this widget with the widget
  /// returned by this method, either by updating the existing subtree or by
  /// removing the subtree and inflating a new subtree, depending on whether the
  /// widget returned by this method can update the root of the existing
  /// subtree, as determined by calling [Widget.canUpdate].
  ///
  /// Typically implementations return a newly created constellation of widgets
  /// that are configured with information from this widget's constructor and
  /// from the given [BuildContext].
  ///
  /// The given [BuildContext] contains information about the location in the
  /// tree at which this widget is being built. For example, the context
  /// provides the set of inherited widgets for this location in the tree. A
  /// given widget might be built with multiple different [BuildContext]
  /// arguments over time if the widget is moved around the tree or if the
  /// widget is inserted into the tree in multiple places at once.
  ///
  /// The implementation of this method must only depend on:
  ///
  /// * the fields of the widget, which themselves must not change over time,
  ///   and
  /// * any ambient state obtained from the `context` using
  ///   [BuildContext.dependOnInheritedWidgetOfExactType].
  ///
  /// If a widget's [build] method is to depend on anything else, use a
  /// [StatefulWidget] instead.
  ///
  /// See also:
  ///
  ///  * [StatelessWidget], which contains the discussion on performance considerations.
  @protected
  Widget build(BuildContext context);
}

/// A widget that has mutable state.
///
/// State is information that (1) can be read synchronously when the widget is
/// built and (2) might change during the lifetime of the widget. It is the
/// responsibility of the widget implementer to ensure that the [State] is
/// promptly notified when such state changes, using [State.setState].
///
/// A stateful widget is a widget that describes part of the user interface by
/// building a constellation of other widgets that describe the user interface
/// more concretely. The building process continues recursively until the
/// description of the user interface is fully concrete (e.g., consists
/// entirely of [RenderObjectWidget]s, which describe concrete [RenderObject]s).
///
/// Stateful widgets are useful when the part of the user interface you are
/// describing can change dynamically, e.g. due to having an internal
/// clock-driven state, or depending on some system state. For compositions that
/// depend only on the configuration information in the object itself and the
/// [BuildContext] in which the widget is inflated, consider using
/// [StatelessWidget].
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=AqCMFXEmf3w}
///
/// [StatefulWidget] instances themselves are immutable and store their mutable
/// state either in separate [State] objects that are created by the
/// [createState] method, or in objects to which that [State] subscribes, for
/// example [Stream] or [ChangeNotifier] objects, to which references are stored
/// in final fields on the [StatefulWidget] itself.
///
/// The framework calls [createState] whenever it inflates a
/// [StatefulWidget], which means that multiple [State] objects might be
/// associated with the same [StatefulWidget] if that widget has been inserted
/// into the tree in multiple places. Similarly, if a [StatefulWidget] is
/// removed from the tree and later inserted in to the tree again, the framework
/// will call [createState] again to create a fresh [State] object, simplifying
/// the lifecycle of [State] objects.
///
/// A [StatefulWidget] keeps the same [State] object when moving from one
/// location in the tree to another if its creator used a [GlobalKey] for its
/// [key]. Because a widget with a [GlobalKey] can be used in at most one
/// location in the tree, a widget that uses a [GlobalKey] has at most one
/// associated element. The framework takes advantage of this property when
/// moving a widget with a global key from one location in the tree to another
/// by grafting the (unique) subtree associated with that widget from the old
/// location to the new location (instead of recreating the subtree at the new
/// location). The [State] objects associated with [StatefulWidget] are grafted
/// along with the rest of the subtree, which means the [State] object is reused
/// (instead of being recreated) in the new location. However, in order to be
/// eligible for grafting, the widget must be inserted into the new location in
/// the same animation frame in which it was removed from the old location.
///
/// ## Performance considerations
///
/// There are two primary categories of [StatefulWidget]s.
///
/// The first is one which allocates resources in [State.initState] and disposes
/// of them in [State.dispose], but which does not depend on [InheritedWidget]s
/// or call [State.setState]. Such widgets are commonly used at the root of an
/// application or page, and communicate with subwidgets via [ChangeNotifier]s,
/// [Stream]s, or other such objects. Stateful widgets following such a pattern
/// are relatively cheap (in terms of CPU and GPU cycles), because they are
/// built once then never update. They can, therefore, have somewhat complicated
/// and deep build methods.
///
/// The second category is widgets that use [State.setState] or depend on
/// [InheritedWidget]s. These will typically rebuild many times during the
/// application's lifetime, and it is therefore important to minimize the impact
/// of rebuilding such a widget. (They may also use [State.initState] or
/// [State.didChangeDependencies] and allocate resources, but the important part
/// is that they rebuild.)
///
/// There are several techniques one can use to minimize the impact of
/// rebuilding a stateful widget:
///
///  * Push the state to the leaves. For example, if your page has a ticking
///    clock, rather than putting the state at the top of the page and
///    rebuilding the entire page each time the clock ticks, create a dedicated
///    clock widget that only updates itself.
///
///  * Minimize the number of nodes transitively created by the build method and
///    any widgets it creates. Ideally, a stateful widget would only create a
///    single widget, and that widget would be a [RenderObjectWidget].
///    (Obviously this isn't always practical, but the closer a widget gets to
///    this ideal, the more efficient it will be.)
///
///  * If a subtree does not change, cache the widget that represents that
///    subtree and re-use it each time it can be used. It is massively more
///    efficient for a widget to be re-used than for a new (but
///    identically-configured) widget to be created. Factoring out the stateful
///    part into a widget that takes a child argument is a common way of doing
///    this.
///
///  * Use `const` widgets where possible. (This is equivalent to caching a
///    widget and re-using it.)
///
///  * Avoid changing the depth of any created subtrees or changing the type of
///    any widgets in the subtree. For example, rather than returning either the
///    child or the child wrapped in an [IgnorePointer], always wrap the child
///    widget in an [IgnorePointer] and control the [IgnorePointer.ignoring]
///    property. This is because changing the depth of the subtree requires
///    rebuilding, laying out, and painting the entire subtree, whereas just
///    changing the property will require the least possible change to the
///    render tree (in the case of [IgnorePointer], for example, no layout or
///    repaint is necessary at all).
///
///  * If the depth must be changed for some reason, consider wrapping the
///    common parts of the subtrees in widgets that have a [GlobalKey] that
///    remains consistent for the life of the stateful widget. (The
///    [KeyedSubtree] widget may be useful for this purpose if no other widget
///    can conveniently be assigned the key.)
///
/// {@tool snippet}
///
/// This is a skeleton of a stateful widget subclass called `YellowBird`.
///
/// In this example. the [State] has no actual state. State is normally
/// represented as private member fields. Also, normally widgets have more
/// constructor arguments, each of which corresponds to a `final` property.
///
/// ```dart
/// class YellowBird extends StatefulWidget {
///   const YellowBird({ Key? key }) : super(key: key);
///
///   @override
///   _YellowBirdState createState() => _YellowBirdState();
/// }
///
/// class _YellowBirdState extends State<YellowBird> {
///   @override
///   Widget build(BuildContext context) {
///     return Container(color: const Color(0xFFFFE306));
///   }
/// }
/// ```
/// {@end-tool}
/// {@tool snippet}
///
/// This example shows the more generic widget `Bird` which can be given a
/// color and a child, and which has some internal state with a method that
/// can be called to mutate it:
///
/// ```dart
/// class Bird extends StatefulWidget {
///   const Bird({
///     Key? key,
///     this.color = const Color(0xFFFFE306),
///     this.child,
///   }) : super(key: key);
///
///   final Color color;
///   final Widget? child;
///
///   _BirdState createState() => _BirdState();
/// }
///
/// class _BirdState extends State<Bird> {
///   double _size = 1.0;
///
///   void grow() {
///     setState(() { _size += 0.1; });
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return Container(
///       color: widget.color,
///       transform: Matrix4.diagonal3Values(_size, _size, 1.0),
///       child: widget.child,
///     );
///   }
/// }
/// ```
/// {@end-tool}
///
/// By convention, widget constructors only use named arguments. Named arguments
/// can be marked as required using [@required]. Also by convention, the first
/// argument is [key], and the last argument is `child`, `children`, or the
/// equivalent.
///
/// See also:
///
///  * [State], where the logic behind a [StatefulWidget] is hosted.
///  * [StatelessWidget], for widgets that always build the same way given a
///    particular configuration and ambient state.
///  * [InheritedWidget], for widgets that introduce ambient state that can
///    be read by descendant widgets.
abstract class StatefulWidget extends Widget {
  /// Initializes [key] for subclasses.
  const StatefulWidget({ Key? key }) : super(key: key);

  /// Creates a [StatefulElement] to manage this widget's location in the tree.
  ///
  /// It is uncommon for subclasses to override this method.
  @override
  StatefulElement createElement() => StatefulElement(this);

  /// Creates the mutable state for this widget at a given location in the tree.
  ///
  /// Subclasses should override this method to return a newly created
  /// instance of their associated [State] subclass:
  ///
  /// ```dart
  /// @override
  /// _MyState createState() => _MyState();
  /// ```
  ///
  /// The framework can call this method multiple times over the lifetime of
  /// a [StatefulWidget]. For example, if the widget is inserted into the tree
  /// in multiple locations, the framework will create a separate [State] object
  /// for each location. Similarly, if the widget is removed from the tree and
  /// later inserted into the tree again, the framework will call [createState]
  /// again to create a fresh [State] object, simplifying the lifecycle of
  /// [State] objects.
  @protected
  @factory
  State createState(); // ignore: no_logic_in_create_state, this is the original sin
}

/// Tracks the lifecycle of [State] objects when asserts are enabled.
enum _StateLifecycle {
  /// The [State] object has been created. [State.initState] is called at this
  /// time.
  created,

  /// The [State.initState] method has been called but the [State] object is
  /// not yet ready to build. [State.didChangeDependencies] is called at this time.
  initialized,

  /// The [State] object is ready to build and [State.dispose] has not yet been
  /// called.
  ready,

  /// The [State.dispose] method has been called and the [State] object is
  /// no longer able to build.
  defunct,
}

/// The signature of [State.setState] functions.
typedef StateSetter = void Function(VoidCallback fn);

/// The logic and internal state for a [StatefulWidget].
///
/// State is information that (1) can be read synchronously when the widget is
/// built and (2) might change during the lifetime of the widget. It is the
/// responsibility of the widget implementer to ensure that the [State] is
/// promptly notified when such state changes, using [State.setState].
///
/// [State] objects are created by the framework by calling the
/// [StatefulWidget.createState] method when inflating a [StatefulWidget] to
/// insert it into the tree. Because a given [StatefulWidget] instance can be
/// inflated multiple times (e.g., the widget is incorporated into the tree in
/// multiple places at once), there might be more than one [State] object
/// associated with a given [StatefulWidget] instance. Similarly, if a
/// [StatefulWidget] is removed from the tree and later inserted in to the tree
/// again, the framework will call [StatefulWidget.createState] again to create
/// a fresh [State] object, simplifying the lifecycle of [State] objects.
///
/// [State] objects have the following lifecycle:
///
///  * The framework creates a [State] object by calling
///    [StatefulWidget.createState].
///  * The newly created [State] object is associated with a [BuildContext].
///    This association is permanent: the [State] object will never change its
///    [BuildContext]. However, the [BuildContext] itself can be moved around
///    the tree along with its subtree. At this point, the [State] object is
///    considered [mounted].
///  * The framework calls [initState]. Subclasses of [State] should override
///    [initState] to perform one-time initialization that depends on the
///    [BuildContext] or the widget, which are available as the [context] and
///    [widget] properties, respectively, when the [initState] method is
///    called.
///  * The framework calls [didChangeDependencies]. Subclasses of [State] should
///    override [didChangeDependencies] to perform initialization involving
///    [InheritedWidget]s. If [BuildContext.dependOnInheritedWidgetOfExactType] is
///    called, the [didChangeDependencies] method will be called again if the
///    inherited widgets subsequently change or if the widget moves in the tree.
///  * At this point, the [State] object is fully initialized and the framework
///    might call its [build] method any number of times to obtain a
///    description of the user interface for this subtree. [State] objects can
///    spontaneously request to rebuild their subtree by callings their
///    [setState] method, which indicates that some of their internal state
///    has changed in a way that might impact the user interface in this
///    subtree.
///  * During this time, a parent widget might rebuild and request that this
///    location in the tree update to display a new widget with the same
///    [runtimeType] and [Widget.key]. When this happens, the framework will
///    update the [widget] property to refer to the new widget and then call the
///    [didUpdateWidget] method with the previous widget as an argument. [State]
///    objects should override [didUpdateWidget] to respond to changes in their
///    associated widget (e.g., to start implicit animations). The framework
///    always calls [build] after calling [didUpdateWidget], which means any
///    calls to [setState] in [didUpdateWidget] are redundant.
///  * During development, if a hot reload occurs (whether initiated from the
///    command line `flutter` tool by pressing `r`, or from an IDE), the
///    [reassemble] method is called. This provides an opportunity to
///    reinitialize any data that was prepared in the [initState] method.
///  * If the subtree containing the [State] object is removed from the tree
///    (e.g., because the parent built a widget with a different [runtimeType]
///    or [Widget.key]), the framework calls the [deactivate] method. Subclasses
///    should override this method to clean up any links between this object
///    and other elements in the tree (e.g. if you have provided an ancestor
///    with a pointer to a descendant's [RenderObject]).
///  * At this point, the framework might reinsert this subtree into another
///    part of the tree. If that happens, the framework will ensure that it
///    calls [build] to give the [State] object a chance to adapt to its new
///    location in the tree. If the framework does reinsert this subtree, it
///    will do so before the end of the animation frame in which the subtree was
///    removed from the tree. For this reason, [State] objects can defer
///    releasing most resources until the framework calls their [dispose]
///    method.
///  * If the framework does not reinsert this subtree by the end of the current
///    animation frame, the framework will call [dispose], which indicates that
///    this [State] object will never build again. Subclasses should override
///    this method to release any resources retained by this object (e.g.,
///    stop any active animations).
///  * After the framework calls [dispose], the [State] object is considered
///    unmounted and the [mounted] property is false. It is an error to call
///    [setState] at this point. This stage of the lifecycle is terminal: there
///    is no way to remount a [State] object that has been disposed.
///
/// See also:
///
///  * [StatefulWidget], where the current configuration of a [State] is hosted,
///    and whose documentation has sample code for [State].
///  * [StatelessWidget], for widgets that always build the same way given a
///    particular configuration and ambient state.
///  * [InheritedWidget], for widgets that introduce ambient state that can
///    be read by descendant widgets.
///  * [Widget], for an overview of widgets in general.
@optionalTypeArgs
abstract class State<T extends StatefulWidget> with Diagnosticable {
  /// The current configuration.
  ///
  /// A [State] object's configuration is the corresponding [StatefulWidget]
  /// instance. This property is initialized by the framework before calling
  /// [initState]. If the parent updates this location in the tree to a new
  /// widget with the same [runtimeType] and [Widget.key] as the current
  /// configuration, the framework will update this property to refer to the new
  /// widget and then call [didUpdateWidget], passing the old configuration as
  /// an argument.
  T get widget => _widget!;
  T? _widget;

  /// The current stage in the lifecycle for this state object.
  ///
  /// This field is used by the framework when asserts are enabled to verify
  /// that [State] objects move through their lifecycle in an orderly fashion.
  _StateLifecycle _debugLifecycleState = _StateLifecycle.created;

  /// Verifies that the [State] that was created is one that expects to be
  /// created for that particular [Widget].
  bool _debugTypesAreRight(Widget widget) => widget is T;

  /// The location in the tree where this widget builds.
  ///
  /// The framework associates [State] objects with a [BuildContext] after
  /// creating them with [StatefulWidget.createState] and before calling
  /// [initState]. The association is permanent: the [State] object will never
  /// change its [BuildContext]. However, the [BuildContext] itself can be moved
  /// around the tree.
  ///
  /// After calling [dispose], the framework severs the [State] object's
  /// connection with the [BuildContext].
  BuildContext get context {
    assert(() {
      if (_element == null) {
        throw FlutterError(
          'This widget has been unmounted, so the State no longer has a context (and should be considered defunct). \n'
          'Consider canceling any active work during "dispose" or using the "mounted" getter to determine if the State is still active.'
        );
      }
      return true;
    }());
    return _element!;
  }
  StatefulElement? _element;

  /// Whether this [State] object is currently in a tree.
  ///
  /// After creating a [State] object and before calling [initState], the
  /// framework "mounts" the [State] object by associating it with a
  /// [BuildContext]. The [State] object remains mounted until the framework
  /// calls [dispose], after which time the framework will never ask the [State]
  /// object to [build] again.
  ///
  /// It is an error to call [setState] unless [mounted] is true.
  bool get mounted => _element != null;

  /// Called when this object is inserted into the tree.
  ///
  /// The framework will call this method exactly once for each [State] object
  /// it creates.
  ///
  /// Override this method to perform initialization that depends on the
  /// location at which this object was inserted into the tree (i.e., [context])
  /// or on the widget used to configure this object (i.e., [widget]).
  ///
  /// {@template flutter.widgets.State.initState}
  /// If a [State]'s [build] method depends on an object that can itself
  /// change state, for example a [ChangeNotifier] or [Stream], or some
  /// other object to which one can subscribe to receive notifications, then
  /// be sure to subscribe and unsubscribe properly in [initState],
  /// [didUpdateWidget], and [dispose]:
  ///
  ///  * In [initState], subscribe to the object.
  ///  * In [didUpdateWidget] unsubscribe from the old object and subscribe
  ///    to the new one if the updated widget configuration requires
  ///    replacing the object.
  ///  * In [dispose], unsubscribe from the object.
  ///
  /// {@endtemplate}
  ///
  /// You cannot use [BuildContext.dependOnInheritedWidgetOfExactType] from this
  /// method. However, [didChangeDependencies] will be called immediately
  /// following this method, and [BuildContext.dependOnInheritedWidgetOfExactType] can
  /// be used there.
  ///
  /// If you override this, make sure your method starts with a call to
  /// super.initState().
  @protected
  @mustCallSuper
  void initState() {
    assert(_debugLifecycleState == _StateLifecycle.created);
  }

  /// Called whenever the widget configuration changes.
  ///
  /// If the parent widget rebuilds and request that this location in the tree
  /// update to display a new widget with the same [runtimeType] and
  /// [Widget.key], the framework will update the [widget] property of this
  /// [State] object to refer to the new widget and then call this method
  /// with the previous widget as an argument.
  ///
  /// Override this method to respond when the [widget] changes (e.g., to start
  /// implicit animations).
  ///
  /// The framework always calls [build] after calling [didUpdateWidget], which
  /// means any calls to [setState] in [didUpdateWidget] are redundant.
  ///
  /// {@macro flutter.widgets.State.initState}
  ///
  /// If you override this, make sure your method starts with a call to
  /// super.didUpdateWidget(oldWidget).
  @mustCallSuper
  @protected
  void didUpdateWidget(covariant T oldWidget) { }

  /// {@macro flutter.widgets.Element.reassemble}
  ///
  /// In addition to this method being invoked, it is guaranteed that the
  /// [build] method will be invoked when a reassemble is signaled. Most
  /// widgets therefore do not need to do anything in the [reassemble] method.
  ///
  /// See also:
  ///
  ///  * [Element.reassemble]
  ///  * [BindingBase.reassembleApplication]
  ///  * [Image], which uses this to reload images.
  @protected
  @mustCallSuper
  void reassemble() { }

  /// Notify the framework that the internal state of this object has changed.
  ///
  /// Whenever you change the internal state of a [State] object, make the
  /// change in a function that you pass to [setState]:
  ///
  /// ```dart
  /// setState(() { _myState = newValue; });
  /// ```
  ///
  /// The provided callback is immediately called synchronously. It must not
  /// return a future (the callback cannot be `async`), since then it would be
  /// unclear when the state was actually being set.
  ///
  /// Calling [setState] notifies the framework that the internal state of this
  /// object has changed in a way that might impact the user interface in this
  /// subtree, which causes the framework to schedule a [build] for this [State]
  /// object.
  ///
  /// If you just change the state directly without calling [setState], the
  /// framework might not schedule a [build] and the user interface for this
  /// subtree might not be updated to reflect the new state.
  ///
  /// Generally it is recommended that the `setState` method only be used to
  /// wrap the actual changes to the state, not any computation that might be
  /// associated with the change. For example, here a value used by the [build]
  /// function is incremented, and then the change is written to disk, but only
  /// the increment is wrapped in the `setState`:
  ///
  /// ```dart
  /// Future<void> _incrementCounter() async {
  ///   setState(() {
  ///     _counter++;
  ///   });
  ///   Directory directory = await getApplicationDocumentsDirectory();
  ///   final String dirName = directory.path;
  ///   await File('$dir/counter.txt').writeAsString('$_counter');
  /// }
  /// ```
  ///
  /// It is an error to call this method after the framework calls [dispose].
  /// You can determine whether it is legal to call this method by checking
  /// whether the [mounted] property is true.
  @protected
  void setState(VoidCallback fn) {
    assert(fn != null);
    assert(() {
      if (_debugLifecycleState == _StateLifecycle.defunct) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('setState() called after dispose(): $this'),
          ErrorDescription(
            'This error happens if you call setState() on a State object for a widget that '
            'no longer appears in the widget tree (e.g., whose parent widget no longer '
            'includes the widget in its build). This error can occur when code calls '
            'setState() from a timer or an animation callback.'
          ),
          ErrorHint(
            'The preferred solution is '
            'to cancel the timer or stop listening to the animation in the dispose() '
            'callback. Another solution is to check the "mounted" property of this '
            'object before calling setState() to ensure the object is still in the '
            'tree.'
          ),
          ErrorHint(
            'This error might indicate a memory leak if setState() is being called '
            'because another object is retaining a reference to this State object '
            'after it has been removed from the tree. To avoid memory leaks, '
            'consider breaking the reference to this object during dispose().'
          ),
        ]);
      }
      if (_debugLifecycleState == _StateLifecycle.created && !mounted) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('setState() called in constructor: $this'),
          ErrorHint(
            'This happens when you call setState() on a State object for a widget that '
            "hasn't been inserted into the widget tree yet. It is not necessary to call "
            'setState() in the constructor, since the state is already assumed to be dirty '
            'when it is initially created.'
          ),
        ]);
      }
      return true;
    }());
    final dynamic result = fn() as dynamic;
    assert(() {
      if (result is Future) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('setState() callback argument returned a Future.'),
          ErrorDescription(
            'The setState() method on $this was called with a closure or method that '
            'returned a Future. Maybe it is marked as "async".'
          ),
          ErrorHint(
            'Instead of performing asynchronous work inside a call to setState(), first '
            'execute the work (without updating the widget state), and then synchronously '
           'update the state inside a call to setState().'
          ),
        ]);
      }
      // We ignore other types of return values so that you can do things like:
      //   setState(() => x = 3);
      return true;
    }());
    _element!.markNeedsBuild();
  }

  /// Called when this object is removed from the tree.
  ///
  /// The framework calls this method whenever it removes this [State] object
  /// from the tree. In some cases, the framework will reinsert the [State]
  /// object into another part of the tree (e.g., if the subtree containing this
  /// [State] object is grafted from one location in the tree to another). If
  /// that happens, the framework will ensure that it calls [build] to give the
  /// [State] object a chance to adapt to its new location in the tree. If
  /// the framework does reinsert this subtree, it will do so before the end of
  /// the animation frame in which the subtree was removed from the tree. For
  /// this reason, [State] objects can defer releasing most resources until the
  /// framework calls their [dispose] method.
  ///
  /// Subclasses should override this method to clean up any links between
  /// this object and other elements in the tree (e.g. if you have provided an
  /// ancestor with a pointer to a descendant's [RenderObject]).
  ///
  /// If you override this, make sure to end your method with a call to
  /// super.deactivate().
  ///
  /// See also:
  ///
  ///  * [dispose], which is called after [deactivate] if the widget is removed
  ///    from the tree permanently.
  @protected
  @mustCallSuper
  void deactivate() { }

  /// Called when this object is removed from the tree permanently.
  ///
  /// The framework calls this method when this [State] object will never
  /// build again. After the framework calls [dispose], the [State] object is
  /// considered unmounted and the [mounted] property is false. It is an error
  /// to call [setState] at this point. This stage of the lifecycle is terminal:
  /// there is no way to remount a [State] object that has been disposed.
  ///
  /// Subclasses should override this method to release any resources retained
  /// by this object (e.g., stop any active animations).
  ///
  /// {@macro flutter.widgets.State.initState}
  ///
  /// If you override this, make sure to end your method with a call to
  /// super.dispose().
  ///
  /// See also:
  ///
  ///  * [deactivate], which is called prior to [dispose].
  @protected
  @mustCallSuper
  void dispose() {
    assert(_debugLifecycleState == _StateLifecycle.ready);
    assert(() {
      _debugLifecycleState = _StateLifecycle.defunct;
      return true;
    }());
  }

  /// Describes the part of the user interface represented by this widget.
  ///
  /// The framework calls this method in a number of different situations. For
  /// example:
  ///
  ///  * After calling [initState].
  ///  * After calling [didUpdateWidget].
  ///  * After receiving a call to [setState].
  ///  * After a dependency of this [State] object changes (e.g., an
  ///    [InheritedWidget] referenced by the previous [build] changes).
  ///  * After calling [deactivate] and then reinserting the [State] object into
  ///    the tree at another location.
  ///
  /// This method can potentially be called in every frame and should not have
  /// any side effects beyond building a widget.
  ///
  /// The framework replaces the subtree below this widget with the widget
  /// returned by this method, either by updating the existing subtree or by
  /// removing the subtree and inflating a new subtree, depending on whether the
  /// widget returned by this method can update the root of the existing
  /// subtree, as determined by calling [Widget.canUpdate].
  ///
  /// Typically implementations return a newly created constellation of widgets
  /// that are configured with information from this widget's constructor, the
  /// given [BuildContext], and the internal state of this [State] object.
  ///
  /// The given [BuildContext] contains information about the location in the
  /// tree at which this widget is being built. For example, the context
  /// provides the set of inherited widgets for this location in the tree. The
  /// [BuildContext] argument is always the same as the [context] property of
  /// this [State] object and will remain the same for the lifetime of this
  /// object. The [BuildContext] argument is provided redundantly here so that
  /// this method matches the signature for a [WidgetBuilder].
  ///
  /// ## Design discussion
  ///
  /// ### Why is the [build] method on [State], and not [StatefulWidget]?
  ///
  /// Putting a `Widget build(BuildContext context)` method on [State] rather
  /// than putting a `Widget build(BuildContext context, State state)` method
  /// on [StatefulWidget] gives developers more flexibility when subclassing
  /// [StatefulWidget].
  ///
  /// For example, [AnimatedWidget] is a subclass of [StatefulWidget] that
  /// introduces an abstract `Widget build(BuildContext context)` method for its
  /// subclasses to implement. If [StatefulWidget] already had a [build] method
  /// that took a [State] argument, [AnimatedWidget] would be forced to provide
  /// its [State] object to subclasses even though its [State] object is an
  /// internal implementation detail of [AnimatedWidget].
  ///
  /// Conceptually, [StatelessWidget] could also be implemented as a subclass of
  /// [StatefulWidget] in a similar manner. If the [build] method were on
  /// [StatefulWidget] rather than [State], that would not be possible anymore.
  ///
  /// Putting the [build] function on [State] rather than [StatefulWidget] also
  /// helps avoid a category of bugs related to closures implicitly capturing
  /// `this`. If you defined a closure in a [build] function on a
  /// [StatefulWidget], that closure would implicitly capture `this`, which is
  /// the current widget instance, and would have the (immutable) fields of that
  /// instance in scope:
  ///
  /// ```dart
  /// class MyButton extends StatefulWidget {
  ///   ...
  ///   final Color color;
  ///
  ///   @override
  ///   Widget build(BuildContext context, MyButtonState state) {
  ///     ... () { print("color: $color"); } ...
  ///   }
  /// }
  /// ```
  ///
  /// For example, suppose the parent builds `MyButton` with `color` being blue,
  /// the `$color` in the print function refers to blue, as expected. Now,
  /// suppose the parent rebuilds `MyButton` with green. The closure created by
  /// the first build still implicitly refers to the original widget and the
  /// `$color` still prints blue even through the widget has been updated to
  /// green.
  ///
  /// In contrast, with the [build] function on the [State] object, closures
  /// created during [build] implicitly capture the [State] instance instead of
  /// the widget instance:
  ///
  /// ```dart
  /// class MyButtonState extends State<MyButton> {
  ///   ...
  ///   @override
  ///   Widget build(BuildContext context) {
  ///     ... () { print("color: ${widget.color}"); } ...
  ///   }
  /// }
  /// ```
  ///
  /// Now when the parent rebuilds `MyButton` with green, the closure created by
  /// the first build still refers to [State] object, which is preserved across
  /// rebuilds, but the framework has updated that [State] object's [widget]
  /// property to refer to the new `MyButton` instance and `${widget.color}`
  /// prints green, as expected.
  ///
  /// See also:
  ///
  ///  * [StatefulWidget], which contains the discussion on performance considerations.
  @protected
  Widget build(BuildContext context);

  /// Called when a dependency of this [State] object changes.
  ///
  /// For example, if the previous call to [build] referenced an
  /// [InheritedWidget] that later changed, the framework would call this
  /// method to notify this object about the change.
  ///
  /// This method is also called immediately after [initState]. It is safe to
  /// call [BuildContext.dependOnInheritedWidgetOfExactType] from this method.
  ///
  /// Subclasses rarely override this method because the framework always
  /// calls [build] after a dependency changes. Some subclasses do override
  /// this method because they need to do some expensive work (e.g., network
  /// fetches) when their dependencies change, and that work would be too
  /// expensive to do for every build.
  @protected
  @mustCallSuper
  void didChangeDependencies() { }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    assert(() {
      properties.add(EnumProperty<_StateLifecycle>('lifecycle state', _debugLifecycleState, defaultValue: _StateLifecycle.ready));
      return true;
    }());
    properties.add(ObjectFlagProperty<T>('_widget', _widget, ifNull: 'no widget'));
    properties.add(ObjectFlagProperty<StatefulElement>('_element', _element, ifNull: 'not mounted'));
  }
}

/// A widget that has a child widget provided to it, instead of building a new
/// widget.
///
/// Useful as a base class for other widgets, such as [InheritedWidget] and
/// [ParentDataWidget].
///
/// See also:
///
///  * [InheritedWidget], for widgets that introduce ambient state that can
///    be read by descendant widgets.
///  * [ParentDataWidget], for widgets that populate the
///    [RenderObject.parentData] slot of their child's [RenderObject] to
///    configure the parent widget's layout.
///  * [StatefulWidget] and [State], for widgets that can build differently
///    several times over their lifetime.
///  * [StatelessWidget], for widgets that always build the same way given a
///    particular configuration and ambient state.
///  * [Widget], for an overview of widgets in general.
abstract class ProxyWidget extends Widget {
  /// Creates a widget that has exactly one child widget.
  const ProxyWidget({ Key? key, required this.child }) : super(key: key);

  /// The widget below this widget in the tree.
  ///
  /// {@template flutter.widgets.ProxyWidget.child}
  /// This widget can only have one child. To lay out multiple children, let this
  /// widget's child be a widget such as [Row], [Column], or [Stack], which have a
  /// `children` property, and then provide the children to that widget.
  /// {@endtemplate}
  final Widget child;
}

/// Base class for widgets that hook [ParentData] information to children of
/// [RenderObjectWidget]s.
///
/// This can be used to provide per-child configuration for
/// [RenderObjectWidget]s with more than one child. For example, [Stack] uses
/// the [Positioned] parent data widget to position each child.
///
/// A [ParentDataWidget] is specific to a particular kind of [ParentData]. That
/// class is `T`, the [ParentData] type argument.
///
/// {@tool snippet}
///
/// This example shows how you would build a [ParentDataWidget] to configure a
/// `FrogJar` widget's children by specifying a [Size] for each one.
///
/// ```dart
/// class FrogSize extends ParentDataWidget<FrogJarParentData> {
///   FrogSize({
///     Key? key,
///     required this.size,
///     required Widget child,
///   }) : super(key: key, child: child);
///
///   final Size size;
///
///   @override
///   void applyParentData(RenderObject renderObject) {
///     final FrogJarParentData parentData = renderObject.parentData! as FrogJarParentData;
///     if (parentData.size != size) {
///       parentData.size = size;
///       final RenderFrogJar targetParent = renderObject.parent! as RenderFrogJar;
///       targetParent.markNeedsLayout();
///     }
///   }
///
///   @override
///   Type get debugTypicalAncestorWidgetClass => FrogJar;
/// }
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [RenderObject], the superclass for layout algorithms.
///  * [RenderObject.parentData], the slot that this class configures.
///  * [ParentData], the superclass of the data that will be placed in
///    [RenderObject.parentData] slots. The `T` type parameter for
///    [ParentDataWidget] is a [ParentData].
///  * [RenderObjectWidget], the class for widgets that wrap [RenderObject]s.
///  * [StatefulWidget] and [State], for widgets that can build differently
///    several times over their lifetime.
abstract class ParentDataWidget<T extends ParentData> extends ProxyWidget {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const ParentDataWidget({ Key? key, required Widget child })
    : super(key: key, child: child);

  @override
  ParentDataElement<T> createElement() => ParentDataElement<T>(this);

  /// Checks if this widget can apply its parent data to the provided
  /// `renderObject`.
  ///
  /// The [RenderObject.parentData] of the provided `renderObject` is
  /// typically set up by an ancestor [RenderObjectWidget] of the type returned
  /// by [debugTypicalAncestorWidgetClass].
  ///
  /// This is called just before [applyParentData] is invoked with the same
  /// [RenderObject] provided to that method.
  bool debugIsValidRenderObject(RenderObject renderObject) {
    assert(T != dynamic);
    assert(T != ParentData);
    return renderObject.parentData is T;
  }

  /// The [RenderObjectWidget] that is typically used to set up the [ParentData]
  /// that [applyParentData] will write to.
  ///
  /// This is only used in error messages to tell users what widget typically
  /// wraps this ParentDataWidget.
  Type get debugTypicalAncestorWidgetClass;

  Iterable<DiagnosticsNode> _debugDescribeIncorrectParentDataType({
    required ParentData? parentData,
    RenderObjectWidget? parentDataCreator,
    DiagnosticsNode? ownershipChain,
  }) sync* {
    assert(T != dynamic);
    assert(T != ParentData);
    assert(debugTypicalAncestorWidgetClass != null);

    final String description = 'The ParentDataWidget $this wants to apply ParentData of type $T to a RenderObject';
    if (parentData == null) {
      yield ErrorDescription(
        '$description, which has not been set up to receive any ParentData.'
      );
    } else {
      yield ErrorDescription(
        '$description, which has been set up to accept ParentData of incompatible type ${parentData.runtimeType}.'
      );
    }
    yield ErrorHint(
      'Usually, this means that the $runtimeType widget has the wrong ancestor RenderObjectWidget. '
      'Typically, $runtimeType widgets are placed directly inside $debugTypicalAncestorWidgetClass widgets.'
    );
    if (parentDataCreator != null) {
      yield ErrorHint(
        'The offending $runtimeType is currently placed inside a ${parentDataCreator.runtimeType} widget.'
      );
    }
    if (ownershipChain != null) {
      yield ErrorDescription(
        'The ownership chain for the RenderObject that received the incompatible parent data was:\n  $ownershipChain'
      );
    }
  }

  /// Write the data from this widget into the given render object's parent data.
  ///
  /// The framework calls this function whenever it detects that the
  /// [RenderObject] associated with the [child] has outdated
  /// [RenderObject.parentData]. For example, if the render object was recently
  /// inserted into the render tree, the render object's parent data might not
  /// match the data in this widget.
  ///
  /// Subclasses are expected to override this function to copy data from their
  /// fields into the [RenderObject.parentData] field of the given render
  /// object. The render object's parent is guaranteed to have been created by a
  /// widget of type `T`, which usually means that this function can assume that
  /// the render object's parent data object inherits from a particular class.
  ///
  /// If this function modifies data that can change the parent's layout or
  /// painting, this function is responsible for calling
  /// [RenderObject.markNeedsLayout] or [RenderObject.markNeedsPaint] on the
  /// parent, as appropriate.
  @protected
  void applyParentData(RenderObject renderObject);

  /// Whether the [ParentDataElement.applyWidgetOutOfTurn] method is allowed
  /// with this widget.
  ///
  /// This should only return true if this widget represents a [ParentData]
  /// configuration that will have no impact on the layout or paint phase.
  ///
  /// See also:
  ///
  ///  * [ParentDataElement.applyWidgetOutOfTurn], which verifies this in debug
  ///    mode.
  @protected
  bool debugCanApplyOutOfTurn() => false;
}

/// Base class for widgets that efficiently propagate information down the tree.
///
/// To obtain the nearest instance of a particular type of inherited widget from
/// a build context, use [BuildContext.dependOnInheritedWidgetOfExactType].
///
/// Inherited widgets, when referenced in this way, will cause the consumer to
/// rebuild when the inherited widget itself changes state.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=Zbm3hjPjQMk}
///
/// {@tool snippet}
///
/// The following is a skeleton of an inherited widget called `FrogColor`:
///
/// ```dart
/// class FrogColor extends InheritedWidget {
///   const FrogColor({
///     Key? key,
///     required this.color,
///     required Widget child,
///   }) : super(key: key, child: child);
///
///   final Color color;
///
///   static FrogColor of(BuildContext context) {
///     final FrogColor? result = context.dependOnInheritedWidgetOfExactType<FrogColor>();
///     assert(result != null, 'No FrogColor found in context');
///     return result!;
///   }
///
///   @override
///   bool updateShouldNotify(FrogColor old) => color != old.color;
/// }
/// ```
/// {@end-tool}
///
/// ## Implementing the `of` method
///
/// The convention is to provide a static method `of` on the [InheritedWidget]
/// which does the call to [BuildContext.dependOnInheritedWidgetOfExactType]. This
/// allows the class to define its own fallback logic in case there isn't
/// a widget in scope. In the example above, the value returned will be
/// null in that case, but it could also have defaulted to a value.
///
/// Sometimes, the `of` method returns the data rather than the inherited
/// widget; for example, in this case it could have returned a [Color] instead
/// of the `FrogColor` widget.
///
/// Occasionally, the inherited widget is an implementation detail of another
/// class, and is therefore private. The `of` method in that case is typically
/// put on the public class instead. For example, [Theme] is implemented as a
/// [StatelessWidget] that builds a private inherited widget; [Theme.of] looks
/// for that inherited widget using [BuildContext.dependOnInheritedWidgetOfExactType]
/// and then returns the [ThemeData].
///
/// ## Calling the `of` method
///
/// When using the `of` method, the `context` must be a descendant of the
/// [InheritedWidget], meaning it must be "below" the [InheritedWidget] in the
/// tree.
///
/// {@tool snippet}
///
/// In this example, the `context` used is the one from the [Builder], which is
/// a child of the FrogColor widget, so this works.
///
/// ```dart
/// class MyPage extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       body: FrogColor(
///         color: Colors.green,
///         child: Builder(
///           builder: (BuildContext innerContext) {
///             return Text(
///               'Hello Frog',
///               style: TextStyle(color: FrogColor.of(innerContext).color),
///             );
///           },
///         ),
///       ),
///     );
///   }
/// }
/// ```
/// {@end-tool}
///
/// {@tool snippet}
///
/// In this example, the `context` used is the one from the MyOtherPage widget,
/// which is a parent of the FrogColor widget, so this does not work.
///
/// ```dart
/// class MyOtherPage extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       body: FrogColor(
///         color: Colors.green,
///         child: Text(
///           'Hello Frog',
///           style: TextStyle(color: FrogColor.of(context).color),
///         ),
///       ),
///     );
///   }
/// }
/// ```
/// {@end-tool}
/// {@youtube 560 315 https://www.youtube.com/watch?v=1t-8rBCGBYw}
///
/// See also:
///
///  * [StatefulWidget] and [State], for widgets that can build differently
///    several times over their lifetime.
///  * [StatelessWidget], for widgets that always build the same way given a
///    particular configuration and ambient state.
///  * [Widget], for an overview of widgets in general.
///  * [InheritedNotifier], an inherited widget whose value can be a
///    [Listenable], and which will notify dependents whenever the value
///    sends notifications.
///  * [InheritedModel], an inherited widget that allows clients to subscribe
///    to changes for subparts of the value.
abstract class InheritedWidget extends ProxyWidget {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const InheritedWidget({ Key? key, required Widget child })
    : super(key: key, child: child);

  @override
  InheritedElement createElement() => InheritedElement(this);

  /// Whether the framework should notify widgets that inherit from this widget.
  ///
  /// When this widget is rebuilt, sometimes we need to rebuild the widgets that
  /// inherit from this widget but sometimes we do not. For example, if the data
  /// held by this widget is the same as the data held by `oldWidget`, then we
  /// do not need to rebuild the widgets that inherited the data held by
  /// `oldWidget`.
  ///
  /// The framework distinguishes these cases by calling this function with the
  /// widget that previously occupied this location in the tree as an argument.
  /// The given widget is guaranteed to have the same [runtimeType] as this
  /// object.
  @protected
  bool updateShouldNotify(covariant InheritedWidget oldWidget);
}

/// RenderObjectWidgets provide the configuration for [RenderObjectElement]s,
/// which wrap [RenderObject]s, which provide the actual rendering of the
/// application.
abstract class RenderObjectWidget extends Widget {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const RenderObjectWidget({ Key? key }) : super(key: key);

  /// RenderObjectWidgets always inflate to a [RenderObjectElement] subclass.
  @override
  @factory
  RenderObjectElement createElement();

  /// Creates an instance of the [RenderObject] class that this
  /// [RenderObjectWidget] represents, using the configuration described by this
  /// [RenderObjectWidget].
  ///
  /// This method should not do anything with the children of the render object.
  /// That should instead be handled by the method that overrides
  /// [RenderObjectElement.mount] in the object rendered by this object's
  /// [createElement] method. See, for example,
  /// [SingleChildRenderObjectElement.mount].
  @protected
  @factory
  RenderObject createRenderObject(BuildContext context);

  /// Copies the configuration described by this [RenderObjectWidget] to the
  /// given [RenderObject], which will be of the same type as returned by this
  /// object's [createRenderObject].
  ///
  /// This method should not do anything to update the children of the render
  /// object. That should instead be handled by the method that overrides
  /// [RenderObjectElement.update] in the object rendered by this object's
  /// [createElement] method. See, for example,
  /// [SingleChildRenderObjectElement.update].
  @protected
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) { }

  /// A render object previously associated with this widget has been removed
  /// from the tree. The given [RenderObject] will be of the same type as
  /// returned by this object's [createRenderObject].
  @protected
  void didUnmountRenderObject(covariant RenderObject renderObject) { }
}

/// A superclass for RenderObjectWidgets that configure RenderObject subclasses
/// that have no children.
abstract class LeafRenderObjectWidget extends RenderObjectWidget {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const LeafRenderObjectWidget({ Key? key }) : super(key: key);

  @override
  LeafRenderObjectElement createElement() => LeafRenderObjectElement(this);
}

/// A superclass for [RenderObjectWidget]s that configure [RenderObject] subclasses
/// that have a single child slot. (This superclass only provides the storage
/// for that child, it doesn't actually provide the updating logic.)
///
/// Typically, the render object assigned to this widget will make use of
/// [RenderObjectWithChildMixin] to implement a single-child model. The mixin
/// exposes a [RenderObjectWithChildMixin.child] property that allows
/// retrieving the render object belonging to the [child] widget.
abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const SingleChildRenderObjectWidget({ Key? key, this.child }) : super(key: key);

  /// The widget below this widget in the tree.
  ///
  /// {@macro flutter.widgets.ProxyWidget.child}
  final Widget? child;

  @override
  SingleChildRenderObjectElement createElement() => SingleChildRenderObjectElement(this);
}

/// A superclass for [RenderObjectWidget]s that configure [RenderObject] subclasses
/// that have a single list of children. (This superclass only provides the
/// storage for that child list, it doesn't actually provide the updating
/// logic.)
///
/// Subclasses must return a [RenderObject] that mixes in
/// [ContainerRenderObjectMixin], which provides the necessary functionality to
/// visit the children of the container render object (the render object
/// belonging to the [children] widgets). Typically, subclasses will return a
/// [RenderBox] that mixes in both [ContainerRenderObjectMixin] and
/// [RenderBoxContainerDefaultsMixin].
///
/// See also:
///
///  * [Stack], which uses [MultiChildRenderObjectWidget].
///  * [RenderStack], for an example implementation of the associated render object.
abstract class MultiChildRenderObjectWidget extends RenderObjectWidget {
  /// Initializes fields for subclasses.
  ///
  /// The [children] argument must not be null and must not contain any null
  /// objects.
  MultiChildRenderObjectWidget({ Key? key, this.children = const <Widget>[] })
    : assert(children != null),
      super(key: key) {
    assert(() {
      for (int index = 0; index < children.length; index++) {
        // TODO(a14n): remove this check to have a lot more const widget
        if (children[index] == null) { // ignore: dead_code
          throw FlutterError(
              "$runtimeType's children must not contain any null values, "
                  'but a null value was found at index $index'
          );
        }
      }
      return true;
    }()); // https://github.com/dart-lang/sdk/issues/29276
  }

  /// The widgets below this widget in the tree.
  ///
  /// If this list is going to be mutated, it is usually wise to put a [Key] on
  /// each of the child widgets, so that the framework can match old
  /// configurations to new configurations and maintain the underlying render
  /// objects.
  ///
  /// Also, a [Widget] in Flutter is immutable, so directly modifying the
  /// [children] such as `someMultiChildRenderObjectWidget.children.add(...)` or
  /// as the example code below will result in incorrect behaviors. Whenever the
  /// children list is modified, a new list object should be provided.
  ///
  /// ```dart
  /// class SomeWidgetState extends State<SomeWidget> {
  ///   List<Widget> _children;
  ///
  ///   void initState() {
  ///     _children = [];
  ///   }
  ///
  ///   void someHandler() {
  ///     setState(() {
  ///         _children.add(...);
  ///     });
  ///   }
  ///
  ///   Widget build(...) {
  ///     // Reusing `List<Widget> _children` here is problematic.
  ///     return Row(children: _children);
  ///   }
  /// }
  /// ```
  ///
  /// The following code corrects the problem mentioned above.
  ///
  /// ```dart
  /// class SomeWidgetState extends State<SomeWidget> {
  ///   List<Widget> _children;
  ///
  ///   void initState() {
  ///     _children = [];
  ///   }
  ///
  ///   void someHandler() {
  ///     setState(() {
  ///       // The key here allows Flutter to reuse the underlying render
  ///       // objects even if the children list is recreated.
  ///       _children.add(ChildWidget(key: ...));
  ///     });
  ///   }
  ///
  ///   Widget build(...) {
  ///     // Always create a new list of children as a Widget is immutable.
  ///     return Row(children: List.from(_children));
  ///   }
  /// }
  /// ```
  final List<Widget> children;

  @override
  MultiChildRenderObjectElement createElement() => MultiChildRenderObjectElement(this);
}


// ELEMENTS

enum _ElementLifecycle {
  initial,
  active,
  inactive,
  defunct,
}

class _InactiveElements {
  bool _locked = false;
  final Set<Element> _elements = HashSet<Element>();

  void _unmount(Element element) {
    assert(element._lifecycleState == _ElementLifecycle.inactive);
    assert(() {
      if (debugPrintGlobalKeyedWidgetLifecycle) {
        if (element.widget.key is GlobalKey)
          debugPrint('Discarding $element from inactive elements list.');
      }
      return true;
    }());
    element.visitChildren((Element child) {
      assert(child._parent == element);
      _unmount(child);
    });
    element.unmount();
    assert(element._lifecycleState == _ElementLifecycle.defunct);
  }

  void _unmountAll() {
    _locked = true;
    final List<Element> elements = _elements.toList()..sort(Element._sort);
    _elements.clear();
    try {
      elements.reversed.forEach(_unmount);
    } finally {
      assert(_elements.isEmpty);
      _locked = false;
    }
  }

  static void _deactivateRecursively(Element element) {
    assert(element._lifecycleState == _ElementLifecycle.active);
    element.deactivate();
    assert(element._lifecycleState == _ElementLifecycle.inactive);
    element.visitChildren(_deactivateRecursively);
    assert(() {
      element.debugDeactivated();
      return true;
    }());
  }

  void add(Element element) {
    assert(!_locked);
    assert(!_elements.contains(element));
    assert(element._parent == null);
    if (element._lifecycleState == _ElementLifecycle.active)
      _deactivateRecursively(element);
    _elements.add(element);
  }

  void remove(Element element) {
    assert(!_locked);
    assert(_elements.contains(element));
    assert(element._parent == null);
    _elements.remove(element);
    assert(element._lifecycleState != _ElementLifecycle.active);
  }

  bool debugContains(Element element) {
    late bool result;
    assert(() {
      result = _elements.contains(element);
      return true;
    }());
    return result;
  }
}

/// Signature for the callback to [BuildContext.visitChildElements].
///
/// The argument is the child being visited.
///
/// It is safe to call `element.visitChildElements` reentrantly within
/// this callback.
typedef ElementVisitor = void Function(Element element);

/// A handle to the location of a widget in the widget tree.
///
/// This class presents a set of methods that can be used from
/// [StatelessWidget.build] methods and from methods on [State] objects.
///
/// [BuildContext] objects are passed to [WidgetBuilder] functions (such as
/// [StatelessWidget.build]), and are available from the [State.context] member.
/// Some static functions (e.g. [showDialog], [Theme.of], and so forth) also
/// take build contexts so that they can act on behalf of the calling widget, or
/// obtain data specifically for the given context.
///
/// Each widget has its own [BuildContext], which becomes the parent of the
/// widget returned by the [StatelessWidget.build] or [State.build] function.
/// (And similarly, the parent of any children for [RenderObjectWidget]s.)
///
/// In particular, this means that within a build method, the build context of
/// the widget of the build method is not the same as the build context of the
/// widgets returned by that build method. This can lead to some tricky cases.
/// For example, [Theme.of(context)] looks for the nearest enclosing [Theme] of
/// the given build context. If a build method for a widget Q includes a [Theme]
/// within its returned widget tree, and attempts to use [Theme.of] passing its
/// own context, the build method for Q will not find that [Theme] object. It
/// will instead find whatever [Theme] was an ancestor to the widget Q. If the
/// build context for a subpart of the returned tree is needed, a [Builder]
/// widget can be used: the build context passed to the [Builder.builder]
/// callback will be that of the [Builder] itself.
///
/// For example, in the following snippet, the [ScaffoldState.showBottomSheet]
/// method is called on the [Scaffold] widget that the build method itself
/// creates. If a [Builder] had not been used, and instead the `context`
/// argument of the build method itself had been used, no [Scaffold] would have
/// been found, and the [Scaffold.of] function would have returned null.
///
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   // here, Scaffold.of(context) returns null
///   return Scaffold(
///     appBar: const AppBar(title: Text('Demo')),
///     body: Builder(
///       builder: (BuildContext context) {
///         return TextButton(
///           child: const Text('BUTTON'),
///           onPressed: () {
///             Scaffold.of(context).showBottomSheet<void>(
///               (BuildContext context) {
///                 return Container(
///                   alignment: Alignment.center,
///                   height: 200,
///                   color: Colors.amber,
///                   child: Center(
///                     child: Column(
///                       mainAxisSize: MainAxisSize.min,
///                       children: <Widget>[
///                         const Text('BottomSheet'),
///                         ElevatedButton(
///                           child: const Text('Close BottomSheet'),
///                           onPressed: () {
///                             Navigator.pop(context),
///                           },
///                         )
///                       ],
///                     ),
///                   ),
///                 );
///               },
///             );
///           },
///         );
///       },
///     )
///   );
/// }
/// ```
///
/// The [BuildContext] for a particular widget can change location over time as
/// the widget is moved around the tree. Because of this, values returned from
/// the methods on this class should not be cached beyond the execution of a
/// single synchronous function.
///
/// [BuildContext] objects are actually [Element] objects. The [BuildContext]
/// interface is used to discourage direct manipulation of [Element] objects.
abstract class BuildContext {
  /// The current configuration of the [Element] that is this [BuildContext].
  Widget get widget;

  /// The [BuildOwner] for this context. The [BuildOwner] is in charge of
  /// managing the rendering pipeline for this context.
  BuildOwner? get owner;

  /// Whether the [widget] is currently updating the widget or render tree.
  ///
  /// For [StatefulWidget]s and [StatelessWidget]s this flag is true while
  /// their respective build methods are executing.
  /// [RenderObjectWidget]s set this to true while creating or configuring their
  /// associated [RenderObject]s.
  /// Other [Widget] types may set this to true for conceptually similar phases
  /// of their lifecycle.
  ///
  /// When this is true, it is safe for [widget] to establish a dependency to an
  /// [InheritedWidget] by calling [dependOnInheritedElement] or
  /// [dependOnInheritedWidgetOfExactType].
  ///
  /// Accessing this flag in release mode is not valid.
  bool get debugDoingBuild;

  /// The current [RenderObject] for the widget. If the widget is a
  /// [RenderObjectWidget], this is the render object that the widget created
  /// for itself. Otherwise, it is the render object of the first descendant
  /// [RenderObjectWidget].
  ///
  /// This method will only return a valid result after the build phase is
  /// complete. It is therefore not valid to call this from a build method.
  /// It should only be called from interaction event handlers (e.g.
  /// gesture callbacks) or layout or paint callbacks.
  ///
  /// If the render object is a [RenderBox], which is the common case, then the
  /// size of the render object can be obtained from the [size] getter. This is
  /// only valid after the layout phase, and should therefore only be examined
  /// from paint callbacks or interaction event handlers (e.g. gesture
  /// callbacks).
  ///
  /// For details on the different phases of a frame, see the discussion at
  /// [WidgetsBinding.drawFrame].
  ///
  /// Calling this method is theoretically relatively expensive (O(N) in the
  /// depth of the tree), but in practice is usually cheap because the tree
  /// usually has many render objects and therefore the distance to the nearest
  /// render object is usually short.
  RenderObject? findRenderObject();

  /// The size of the [RenderBox] returned by [findRenderObject].
  ///
  /// This getter will only return a valid result after the layout phase is
  /// complete. It is therefore not valid to call this from a build method.
  /// It should only be called from paint callbacks or interaction event
  /// handlers (e.g. gesture callbacks).
  ///
  /// For details on the different phases of a frame, see the discussion at
  /// [WidgetsBinding.drawFrame].
  ///
  /// This getter will only return a valid result if [findRenderObject] actually
  /// returns a [RenderBox]. If [findRenderObject] returns a render object that
  /// is not a subtype of [RenderBox] (e.g., [RenderView]), this getter will
  /// throw an exception in checked mode and will return null in release mode.
  ///
  /// Calling this getter is theoretically relatively expensive (O(N) in the
  /// depth of the tree), but in practice is usually cheap because the tree
  /// usually has many render objects and therefore the distance to the nearest
  /// render object is usually short.
  Size? get size;

  /// Registers this build context with [ancestor] such that when
  /// [ancestor]'s widget changes this build context is rebuilt.
  ///
  /// This method is deprecated. Please use [dependOnInheritedElement] instead.
  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use dependOnInheritedElement instead. '
    'This feature was deprecated after v1.12.1.'
  )
  InheritedWidget inheritFromElement(InheritedElement ancestor, { Object aspect });

  /// Registers this build context with [ancestor] such that when
  /// [ancestor]'s widget changes this build context is rebuilt.
  ///
  /// Returns `ancestor.widget`.
  ///
  /// This method is rarely called directly. Most applications should use
  /// [dependOnInheritedWidgetOfExactType], which calls this method after finding
  /// the appropriate [InheritedElement] ancestor.
  ///
  /// All of the qualifications about when [dependOnInheritedWidgetOfExactType] can
  /// be called apply to this method as well.
  InheritedWidget dependOnInheritedElement(InheritedElement ancestor, { Object aspect });

  /// Obtains the nearest widget of the given type, which must be the type of a
  /// concrete [InheritedWidget] subclass, and registers this build context with
  /// that widget such that when that widget changes (or a new widget of that
  /// type is introduced, or the widget goes away), this build context is
  /// rebuilt so that it can obtain new values from that widget.
  ///
  /// This method is deprecated. Please use [dependOnInheritedWidgetOfExactType] instead.
  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use dependOnInheritedWidgetOfExactType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  InheritedWidget? inheritFromWidgetOfExactType(Type targetType, { Object? aspect });

  /// Obtains the nearest widget of the given type `T`, which must be the type of a
  /// concrete [InheritedWidget] subclass, and registers this build context with
  /// that widget such that when that widget changes (or a new widget of that
  /// type is introduced, or the widget goes away), this build context is
  /// rebuilt so that it can obtain new values from that widget.
  ///
  /// This is typically called implicitly from `of()` static methods, e.g.
  /// [Theme.of].
  ///
  /// This method should not be called from widget constructors or from
  /// [State.initState] methods, because those methods would not get called
  /// again if the inherited value were to change. To ensure that the widget
  /// correctly updates itself when the inherited value changes, only call this
  /// (directly or indirectly) from build methods, layout and paint callbacks, or
  /// from [State.didChangeDependencies].
  ///
  /// This method should not be called from [State.dispose] because the element
  /// tree is no longer stable at that time. To refer to an ancestor from that
  /// method, save a reference to the ancestor in [State.didChangeDependencies].
  /// It is safe to use this method from [State.deactivate], which is called
  /// whenever the widget is removed from the tree.
  ///
  /// It is also possible to call this method from interaction event handlers
  /// (e.g. gesture callbacks) or timers, to obtain a value once, if that value
  /// is not going to be cached and reused later.
  ///
  /// Calling this method is O(1) with a small constant factor, but will lead to
  /// the widget being rebuilt more often.
  ///
  /// Once a widget registers a dependency on a particular type by calling this
  /// method, it will be rebuilt, and [State.didChangeDependencies] will be
  /// called, whenever changes occur relating to that widget until the next time
  /// the widget or one of its ancestors is moved (for example, because an
  /// ancestor is added or removed).
  ///
  /// The [aspect] parameter is only used when `T` is an
  /// [InheritedWidget] subclasses that supports partial updates, like
  /// [InheritedModel]. It specifies what "aspect" of the inherited
  /// widget this context depends on.
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>({ Object? aspect });

  /// Obtains the element corresponding to the nearest widget of the given type,
  /// which must be the type of a concrete [InheritedWidget] subclass.
  ///
  /// This method is deprecated. Please use [getElementForInheritedWidgetOfExactType] instead.
  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use getElementForInheritedWidgetOfExactType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  InheritedElement? ancestorInheritedElementForWidgetOfExactType(Type targetType);

  /// Obtains the element corresponding to the nearest widget of the given type `T`,
  /// which must be the type of a concrete [InheritedWidget] subclass.
  ///
  /// Returns null if no such element is found.
  ///
  /// Calling this method is O(1) with a small constant factor.
  ///
  /// This method does not establish a relationship with the target in the way
  /// that [dependOnInheritedWidgetOfExactType] does.
  ///
  /// This method should not be called from [State.dispose] because the element
  /// tree is no longer stable at that time. To refer to an ancestor from that
  /// method, save a reference to the ancestor by calling
  /// [dependOnInheritedWidgetOfExactType] in [State.didChangeDependencies]. It is
  /// safe to use this method from [State.deactivate], which is called whenever
  /// the widget is removed from the tree.
  InheritedElement? getElementForInheritedWidgetOfExactType<T extends InheritedWidget>();

  /// Returns the nearest ancestor widget of the given type, which must be the
  /// type of a concrete [Widget] subclass.
  ///
  /// This method is deprecated. Please use [findAncestorWidgetOfExactType] instead.
  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use findAncestorWidgetOfExactType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  Widget? ancestorWidgetOfExactType(Type targetType);

  /// Returns the nearest ancestor widget of the given type `T`, which must be the
  /// type of a concrete [Widget] subclass.
  ///
  /// In general, [dependOnInheritedWidgetOfExactType] is more useful, since
  /// inherited widgets will trigger consumers to rebuild when they change. This
  /// method is appropriate when used in interaction event handlers (e.g.
  /// gesture callbacks) or for performing one-off tasks such as asserting that
  /// you have or don't have a widget of a specific type as an ancestor. The
  /// return value of a Widget's build method should not depend on the value
  /// returned by this method, because the build context will not rebuild if the
  /// return value of this method changes. This could lead to a situation where
  /// data used in the build method changes, but the widget is not rebuilt.
  ///
  /// Calling this method is relatively expensive (O(N) in the depth of the
  /// tree). Only call this method if the distance from this widget to the
  /// desired ancestor is known to be small and bounded.
  ///
  /// This method should not be called from [State.deactivate] or [State.dispose]
  /// because the widget tree is no longer stable at that time. To refer to
  /// an ancestor from one of those methods, save a reference to the ancestor
  /// by calling [findAncestorWidgetOfExactType] in [State.didChangeDependencies].
  ///
  /// Returns null if a widget of the requested type does not appear in the
  /// ancestors of this context.
  T? findAncestorWidgetOfExactType<T extends Widget>();

  /// Returns the [State] object of the nearest ancestor [StatefulWidget] widget
  /// that matches the given [TypeMatcher].
  ///
  /// This method is deprecated. Please use [findAncestorStateOfType] instead.
  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use findAncestorStateOfType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  State? ancestorStateOfType(TypeMatcher matcher);

  /// Returns the [State] object of the nearest ancestor [StatefulWidget] widget
  /// that is an instance of the given type `T`.
  ///
  /// This should not be used from build methods, because the build context will
  /// not be rebuilt if the value that would be returned by this method changes.
  /// In general, [dependOnInheritedWidgetOfExactType] is more appropriate for such
  /// cases. This method is useful for changing the state of an ancestor widget in
  /// a one-off manner, for example, to cause an ancestor scrolling list to
  /// scroll this build context's widget into view, or to move the focus in
  /// response to user interaction.
  ///
  /// In general, though, consider using a callback that triggers a stateful
  /// change in the ancestor rather than using the imperative style implied by
  /// this method. This will usually lead to more maintainable and reusable code
  /// since it decouples widgets from each other.
  ///
  /// Calling this method is relatively expensive (O(N) in the depth of the
  /// tree). Only call this method if the distance from this widget to the
  /// desired ancestor is known to be small and bounded.
  ///
  /// This method should not be called from [State.deactivate] or [State.dispose]
  /// because the widget tree is no longer stable at that time. To refer to
  /// an ancestor from one of those methods, save a reference to the ancestor
  /// by calling [findAncestorStateOfType] in [State.didChangeDependencies].
  ///
  /// {@tool snippet}
  ///
  /// ```dart
  /// ScrollableState? scrollable = context.findAncestorStateOfType<ScrollableState>();
  /// ```
  /// {@end-tool}
  T? findAncestorStateOfType<T extends State>();

  /// Returns the [State] object of the furthest ancestor [StatefulWidget] widget
  /// that matches the given [TypeMatcher].
  ///
  /// This method is deprecated. Please use [findRootAncestorStateOfType] instead.
  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use findRootAncestorStateOfType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  State? rootAncestorStateOfType(TypeMatcher matcher);

  /// Returns the [State] object of the furthest ancestor [StatefulWidget] widget
  /// that is an instance of the given type `T`.
  ///
  /// Functions the same way as [findAncestorStateOfType] but keeps visiting subsequent
  /// ancestors until there are none of the type instance of `T` remaining.
  /// Then returns the last one found.
  ///
  /// This operation is O(N) as well though N is the entire widget tree rather than
  /// a subtree.
  T? findRootAncestorStateOfType<T extends State>();

  /// Returns the [RenderObject] object of the nearest ancestor [RenderObjectWidget] widget
  /// that matches the given [TypeMatcher].
  ///
  /// This method is deprecated. Please use [findAncestorRenderObjectOfType] instead.
  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use findAncestorRenderObjectOfType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  RenderObject? ancestorRenderObjectOfType(TypeMatcher matcher);

  /// Returns the [RenderObject] object of the nearest ancestor [RenderObjectWidget] widget
  /// that is an instance of the given type `T`.
  ///
  /// This should not be used from build methods, because the build context will
  /// not be rebuilt if the value that would be returned by this method changes.
  /// In general, [dependOnInheritedWidgetOfExactType] is more appropriate for such
  /// cases. This method is useful only in esoteric cases where a widget needs
  /// to cause an ancestor to change its layout or paint behavior. For example,
  /// it is used by [Material] so that [InkWell] widgets can trigger the ink
  /// splash on the [Material]'s actual render object.
  ///
  /// Calling this method is relatively expensive (O(N) in the depth of the
  /// tree). Only call this method if the distance from this widget to the
  /// desired ancestor is known to be small and bounded.
  ///
  /// This method should not be called from [State.deactivate] or [State.dispose]
  /// because the widget tree is no longer stable at that time. To refer to
  /// an ancestor from one of those methods, save a reference to the ancestor
  /// by calling [findAncestorRenderObjectOfType] in [State.didChangeDependencies].
  T? findAncestorRenderObjectOfType<T extends RenderObject>();

  /// Walks the ancestor chain, starting with the parent of this build context's
  /// widget, invoking the argument for each ancestor. The callback is given a
  /// reference to the ancestor widget's corresponding [Element] object. The
  /// walk stops when it reaches the root widget or when the callback returns
  /// false. The callback must not return null.
  ///
  /// This is useful for inspecting the widget tree.
  ///
  /// Calling this method is relatively expensive (O(N) in the depth of the tree).
  ///
  /// This method should not be called from [State.deactivate] or [State.dispose]
  /// because the element tree is no longer stable at that time. To refer to
  /// an ancestor from one of those methods, save a reference to the ancestor
  /// by calling [visitAncestorElements] in [State.didChangeDependencies].
  void visitAncestorElements(bool visitor(Element element));

  /// Walks the children of this widget.
  ///
  /// This is useful for applying changes to children after they are built
  /// without waiting for the next frame, especially if the children are known,
  /// and especially if there is exactly one child (as is always the case for
  /// [StatefulWidget]s or [StatelessWidget]s).
  ///
  /// Calling this method is very cheap for build contexts that correspond to
  /// [StatefulWidget]s or [StatelessWidget]s (O(1), since there's only one
  /// child).
  ///
  /// Calling this method is potentially expensive for build contexts that
  /// correspond to [RenderObjectWidget]s (O(N) in the number of children).
  ///
  /// Calling this method recursively is extremely expensive (O(N) in the number
  /// of descendants), and should be avoided if possible. Generally it is
  /// significantly cheaper to use an [InheritedWidget] and have the descendants
  /// pull data down, than it is to use [visitChildElements] recursively to push
  /// data down to them.
  void visitChildElements(ElementVisitor visitor);

  /// Returns a description of an [Element] from the current build context.
  DiagnosticsNode describeElement(String name, {DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty});

  /// Returns a description of the [Widget] associated with the current build context.
  DiagnosticsNode describeWidget(String name, {DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty});

  /// Adds a description of a specific type of widget missing from the current
  /// build context's ancestry tree.
  ///
  /// You can find an example of using this method in [debugCheckHasMaterial].
  List<DiagnosticsNode> describeMissingAncestor({ required Type expectedAncestorType });

  /// Adds a description of the ownership chain from a specific [Element]
  /// to the error report.
  ///
  /// The ownership chain is useful for debugging the source of an element.
  DiagnosticsNode describeOwnershipChain(String name);
}

/// Manager class for the widgets framework.
///
/// This class tracks which widgets need rebuilding, and handles other tasks
/// that apply to widget trees as a whole, such as managing the inactive element
/// list for the tree and triggering the "reassemble" command when necessary
/// during hot reload when debugging.
///
/// The main build owner is typically owned by the [WidgetsBinding], and is
/// driven from the operating system along with the rest of the
/// build/layout/paint pipeline.
///
/// Additional build owners can be built to manage off-screen widget trees.
///
/// To assign a build owner to a tree, use the
/// [RootRenderObjectElement.assignOwner] method on the root element of the
/// widget tree.
class BuildOwner {
  /// Creates an object that manages widgets.
  BuildOwner({ this.onBuildScheduled, FocusManager? focusManager }) :
      focusManager = focusManager ?? FocusManager();

  /// Called on each build pass when the first buildable element is marked
  /// dirty.
  VoidCallback? onBuildScheduled;

  final _InactiveElements _inactiveElements = _InactiveElements();

  final List<Element> _dirtyElements = <Element>[];
  bool _scheduledFlushDirtyElements = false;

  /// Whether [_dirtyElements] need to be sorted again as a result of more
  /// elements becoming dirty during the build.
  ///
  /// This is necessary to preserve the sort order defined by [Element._sort].
  ///
  /// This field is set to null when [buildScope] is not actively rebuilding
  /// the widget tree.
  bool? _dirtyElementsNeedsResorting;

  /// Whether [buildScope] is actively rebuilding the widget tree.
  ///
  /// [scheduleBuildFor] should only be called when this value is true.
  bool get _debugIsInBuildScope => _dirtyElementsNeedsResorting != null;

  /// The object in charge of the focus tree.
  ///
  /// Rarely used directly. Instead, consider using [FocusScope.of] to obtain
  /// the [FocusScopeNode] for a given [BuildContext].
  ///
  /// See [FocusManager] for more details.
  FocusManager focusManager;

  /// Adds an element to the dirty elements list so that it will be rebuilt
  /// when [WidgetsBinding.drawFrame] calls [buildScope].
  void scheduleBuildFor(Element element) {
    assert(element != null);
    assert(element.owner == this);
    assert(() {
      if (debugPrintScheduleBuildForStacks)
        debugPrintStack(label: 'scheduleBuildFor() called for $element${_dirtyElements.contains(element) ? " (ALREADY IN LIST)" : ""}');
      if (!element.dirty) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('scheduleBuildFor() called for a widget that is not marked as dirty.'),
          element.describeElement('The method was called for the following element'),
          ErrorDescription(
            'This element is not current marked as dirty. Make sure to set the dirty flag before '
            'calling scheduleBuildFor().'),
          ErrorHint(
            'If you did not attempt to call scheduleBuildFor() yourself, then this probably '
            'indicates a bug in the widgets framework. Please report it:\n'
            '  https://github.com/flutter/flutter/issues/new?template=2_bug.md'
          ),
        ]);
      }
      return true;
    }());
    if (element._inDirtyList) {
      assert(() {
        if (debugPrintScheduleBuildForStacks)
          debugPrintStack(label: 'BuildOwner.scheduleBuildFor() called; _dirtyElementsNeedsResorting was $_dirtyElementsNeedsResorting (now true); dirty list is: $_dirtyElements');
        if (!_debugIsInBuildScope) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('BuildOwner.scheduleBuildFor() called inappropriately.'),
            ErrorHint(
              'The BuildOwner.scheduleBuildFor() method should only be called while the '
              'buildScope() method is actively rebuilding the widget tree.'
            ),
          ]);
        }
        return true;
      }());
      _dirtyElementsNeedsResorting = true;
      return;
    }
    if (!_scheduledFlushDirtyElements && onBuildScheduled != null) {
      _scheduledFlushDirtyElements = true;
      onBuildScheduled!();
    }
    _dirtyElements.add(element);
    element._inDirtyList = true;
    assert(() {
      if (debugPrintScheduleBuildForStacks)
        debugPrint('...dirty list is now: $_dirtyElements');
      return true;
    }());
  }

  int _debugStateLockLevel = 0;
  bool get _debugStateLocked => _debugStateLockLevel > 0;

  /// Whether this widget tree is in the build phase.
  ///
  /// Only valid when asserts are enabled.
  bool get debugBuilding => _debugBuilding;
  bool _debugBuilding = false;
  Element? _debugCurrentBuildTarget;

  /// Establishes a scope in which calls to [State.setState] are forbidden, and
  /// calls the given `callback`.
  ///
  /// This mechanism is used to ensure that, for instance, [State.dispose] does
  /// not call [State.setState].
  void lockState(void callback()) {
    assert(callback != null);
    assert(_debugStateLockLevel >= 0);
    assert(() {
      _debugStateLockLevel += 1;
      return true;
    }());
    try {
      callback();
    } finally {
      assert(() {
        _debugStateLockLevel -= 1;
        return true;
      }());
    }
    assert(_debugStateLockLevel >= 0);
  }

  /// Establishes a scope for updating the widget tree, and calls the given
  /// `callback`, if any. Then, builds all the elements that were marked as
  /// dirty using [scheduleBuildFor], in depth order.
  ///
  /// This mechanism prevents build methods from transitively requiring other
  /// build methods to run, potentially causing infinite loops.
  ///
  /// The dirty list is processed after `callback` returns, building all the
  /// elements that were marked as dirty using [scheduleBuildFor], in depth
  /// order. If elements are marked as dirty while this method is running, they
  /// must be deeper than the `context` node, and deeper than any
  /// previously-built node in this pass.
  ///
  /// To flush the current dirty list without performing any other work, this
  /// function can be called with no callback. This is what the framework does
  /// each frame, in [WidgetsBinding.drawFrame].
  ///
  /// Only one [buildScope] can be active at a time.
  ///
  /// A [buildScope] implies a [lockState] scope as well.
  ///
  /// To print a console message every time this method is called, set
  /// [debugPrintBuildScope] to true. This is useful when debugging problems
  /// involving widgets not getting marked dirty, or getting marked dirty too
  /// often.
  void buildScope(Element context, [ VoidCallback? callback ]) {
    if (callback == null && _dirtyElements.isEmpty)
      return;
    assert(context != null);
    assert(_debugStateLockLevel >= 0);
    assert(!_debugBuilding);
    assert(() {
      if (debugPrintBuildScope)
        debugPrint('buildScope called with context $context; dirty list is: $_dirtyElements');
      _debugStateLockLevel += 1;
      _debugBuilding = true;
      return true;
    }());
    Timeline.startSync('Build', arguments: timelineArgumentsIndicatingLandmarkEvent);
    try {
      _scheduledFlushDirtyElements = true;
      if (callback != null) {
        assert(_debugStateLocked);
        Element? debugPreviousBuildTarget;
        assert(() {
          context._debugSetAllowIgnoredCallsToMarkNeedsBuild(true);
          debugPreviousBuildTarget = _debugCurrentBuildTarget;
          _debugCurrentBuildTarget = context;
          return true;
        }());
        _dirtyElementsNeedsResorting = false;
        try {
          callback();
        } finally {
          assert(() {
            context._debugSetAllowIgnoredCallsToMarkNeedsBuild(false);
            assert(_debugCurrentBuildTarget == context);
            _debugCurrentBuildTarget = debugPreviousBuildTarget;
            _debugElementWasRebuilt(context);
            return true;
          }());
        }
      }
      _dirtyElements.sort(Element._sort);
      _dirtyElementsNeedsResorting = false;
      int dirtyCount = _dirtyElements.length;
      int index = 0;
      while (index < dirtyCount) {
        assert(_dirtyElements[index] != null);
        assert(_dirtyElements[index]._inDirtyList);
        assert(() {
          if (_dirtyElements[index]._lifecycleState == _ElementLifecycle.active && !_dirtyElements[index]._debugIsInScope(context)) {
            throw FlutterError.fromParts(<DiagnosticsNode>[
              ErrorSummary('Tried to build dirty widget in the wrong build scope.'),
              ErrorDescription(
                'A widget which was marked as dirty and is still active was scheduled to be built, '
                'but the current build scope unexpectedly does not contain that widget.',
              ),
              ErrorHint(
                'Sometimes this is detected when an element is removed from the widget tree, but the '
                'element somehow did not get marked as inactive. In that case, it might be caused by '
                'an ancestor element failing to implement visitChildren correctly, thus preventing '
                'some or all of its descendants from being correctly deactivated.',
              ),
              DiagnosticsProperty<Element>(
                'The root of the build scope was',
                context,
                style: DiagnosticsTreeStyle.errorProperty,
              ),
              DiagnosticsProperty<Element>(
                'The offending element (which does not appear to be a descendant of the root of the build scope) was',
                _dirtyElements[index],
                style: DiagnosticsTreeStyle.errorProperty,
              ),
            ]);
          }
          return true;
        }());
        try {
          _dirtyElements[index].rebuild();
        } catch (e, stack) {
          _debugReportException(
            ErrorDescription('while rebuilding dirty elements'),
            e,
            stack,
            informationCollector: () sync* {
              if (index < _dirtyElements.length) {
                yield DiagnosticsDebugCreator(DebugCreator(_dirtyElements[index]));
                yield _dirtyElements[index].describeElement('The element being rebuilt at the time was index $index of $dirtyCount');
              } else {
                yield ErrorHint('The element being rebuilt at the time was index $index of $dirtyCount, but _dirtyElements only had ${_dirtyElements.length} entries. This suggests some confusion in the framework internals.');
              }
            },
          );
        }
        index += 1;
        if (dirtyCount < _dirtyElements.length || _dirtyElementsNeedsResorting!) {
          _dirtyElements.sort(Element._sort);
          _dirtyElementsNeedsResorting = false;
          dirtyCount = _dirtyElements.length;
          while (index > 0 && _dirtyElements[index - 1].dirty) {
            // It is possible for previously dirty but inactive widgets to move right in the list.
            // We therefore have to move the index left in the list to account for this.
            // We don't know how many could have moved. However, we do know that the only possible
            // change to the list is that nodes that were previously to the left of the index have
            // now moved to be to the right of the right-most cleaned node, and we do know that
            // all the clean nodes were to the left of the index. So we move the index left
            // until just after the right-most clean node.
            index -= 1;
          }
        }
      }
      assert(() {
        if (_dirtyElements.any((Element element) => element._lifecycleState == _ElementLifecycle.active && element.dirty)) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('buildScope missed some dirty elements.'),
            ErrorHint('This probably indicates that the dirty list should have been resorted but was not.'),
            Element.describeElements('The list of dirty elements at the end of the buildScope call was', _dirtyElements),
          ]);
        }
        return true;
      }());
    } finally {
      for (final Element element in _dirtyElements) {
        assert(element._inDirtyList);
        element._inDirtyList = false;
      }
      _dirtyElements.clear();
      _scheduledFlushDirtyElements = false;
      _dirtyElementsNeedsResorting = null;
      Timeline.finishSync();
      assert(_debugBuilding);
      assert(() {
        _debugBuilding = false;
        _debugStateLockLevel -= 1;
        if (debugPrintBuildScope)
          debugPrint('buildScope finished');
        return true;
      }());
    }
    assert(_debugStateLockLevel >= 0);
  }

  Map<Element, Set<GlobalKey>>? _debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans;

  void _debugTrackElementThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans(Element node, GlobalKey key) {
    _debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans ??= HashMap<Element, Set<GlobalKey>>();
    final Set<GlobalKey> keys = _debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans!
      .putIfAbsent(node, () => HashSet<GlobalKey>());
    keys.add(key);
  }

  void _debugElementWasRebuilt(Element node) {
    _debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans?.remove(node);
  }

  /// Complete the element build pass by unmounting any elements that are no
  /// longer active.
  ///
  /// This is called by [WidgetsBinding.drawFrame].
  ///
  /// In debug mode, this also runs some sanity checks, for example checking for
  /// duplicate global keys.
  ///
  /// After the current call stack unwinds, a microtask that notifies listeners
  /// about changes to global keys will run.
  void finalizeTree() {
    Timeline.startSync('Finalize tree', arguments: timelineArgumentsIndicatingLandmarkEvent);
    try {
      lockState(() {
        _inactiveElements._unmountAll(); // this unregisters the GlobalKeys
      });
      assert(() {
        try {
          GlobalKey._debugVerifyGlobalKeyReservation();
          GlobalKey._debugVerifyIllFatedPopulation();
          if (_debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans != null &&
              _debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans!.isNotEmpty) {
            final Set<GlobalKey> keys = HashSet<GlobalKey>();
            for (final Element element in _debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans!.keys) {
              if (element._lifecycleState != _ElementLifecycle.defunct)
                keys.addAll(_debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans![element]!);
            }
            if (keys.isNotEmpty) {
              final Map<String, int> keyStringCount = HashMap<String, int>();
              for (final String key in keys.map<String>((GlobalKey key) => key.toString())) {
                if (keyStringCount.containsKey(key)) {
                  keyStringCount.update(key, (int value) => value + 1);
                } else {
                  keyStringCount[key] = 1;
                }
              }
              final List<String> keyLabels = <String>[];
              keyStringCount.forEach((String key, int count) {
                if (count == 1) {
                  keyLabels.add(key);
                } else {
                  keyLabels.add('$key ($count different affected keys had this toString representation)');
                }
              });
              final Iterable<Element> elements = _debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans!.keys;
              final Map<String, int> elementStringCount = HashMap<String, int>();
              for (final String element in elements.map<String>((Element element) => element.toString())) {
                if (elementStringCount.containsKey(element)) {
                  elementStringCount.update(element, (int value) => value + 1);
                } else {
                  elementStringCount[element] = 1;
                }
              }
              final List<String> elementLabels = <String>[];
              elementStringCount.forEach((String element, int count) {
                if (count == 1) {
                  elementLabels.add(element);
                } else {
                  elementLabels.add('$element ($count different affected elements had this toString representation)');
                }
              });
              assert(keyLabels.isNotEmpty);
              final String the = keys.length == 1 ? ' the' : '';
              final String s = keys.length == 1 ? '' : 's';
              final String were = keys.length == 1 ? 'was' : 'were';
              final String their = keys.length == 1 ? 'its' : 'their';
              final String respective = elementLabels.length == 1 ? '' : ' respective';
              final String those = keys.length == 1 ? 'that' : 'those';
              final String s2 = elementLabels.length == 1 ? '' : 's';
              final String those2 = elementLabels.length == 1 ? 'that' : 'those';
              final String they = elementLabels.length == 1 ? 'it' : 'they';
              final String think = elementLabels.length == 1 ? 'thinks' : 'think';
              final String are = elementLabels.length == 1 ? 'is' : 'are';
              // TODO(jacobr): make this error more structured to better expose which widgets had problems.
              throw FlutterError.fromParts(<DiagnosticsNode>[
                ErrorSummary('Duplicate GlobalKey$s detected in widget tree.'),
                // TODO(jacobr): refactor this code so the elements are clickable
                // in GUI debug tools.
                ErrorDescription(
                  'The following GlobalKey$s $were specified multiple times in the widget tree. This will lead to '
                  'parts of the widget tree being truncated unexpectedly, because the second time a key is seen, '
                  'the previous instance is moved to the new location. The key$s $were:\n'
                  '- ${keyLabels.join("\n  ")}\n'
                  'This was determined by noticing that after$the widget$s with the above global key$s $were moved '
                  'out of $their$respective previous parent$s2, $those2 previous parent$s2 never updated during this frame, meaning '
                  'that $they either did not update at all or updated before the widget$s $were moved, in either case '
                  'implying that $they still $think that $they should have a child with $those global key$s.\n'
                  'The specific parent$s2 that did not update after having one or more children forcibly removed '
                  'due to GlobalKey reparenting $are:\n'
                  '- ${elementLabels.join("\n  ")}'
                  '\nA GlobalKey can only be specified on one widget at a time in the widget tree.'
                ),
              ]);
            }
          }
        } finally {
          _debugElementsThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans?.clear();
        }
        return true;
      }());
    } catch (e, stack) {
      // Catching the exception directly to avoid activating the ErrorWidget.
      // Since the tree is in a broken state, adding the ErrorWidget would
      // cause more exceptions.
      _debugReportException(ErrorSummary('while finalizing the widget tree'), e, stack);
    } finally {
      Timeline.finishSync();
    }
  }

  /// Cause the entire subtree rooted at the given [Element] to be entirely
  /// rebuilt. This is used by development tools when the application code has
  /// changed and is being hot-reloaded, to cause the widget tree to pick up any
  /// changed implementations.
  ///
  /// This is expensive and should not be called except during development.
  void reassemble(Element root) {
    Timeline.startSync('Dirty Element Tree');
    try {
      assert(root._parent == null);
      assert(root.owner == this);
      root.reassemble();
    } finally {
      Timeline.finishSync();
    }
  }
}

/// An instantiation of a [Widget] at a particular location in the tree.
///
/// Widgets describe how to configure a subtree but the same widget can be used
/// to configure multiple subtrees simultaneously because widgets are immutable.
/// An [Element] represents the use of a widget to configure a specific location
/// in the tree. Over time, the widget associated with a given element can
/// change, for example, if the parent widget rebuilds and creates a new widget
/// for this location.
///
/// Elements form a tree. Most elements have a unique child, but some widgets
/// (e.g., subclasses of [RenderObjectElement]) can have multiple children.
///
/// Elements have the following lifecycle:
///
///  * The framework creates an element by calling [Widget.createElement] on the
///    widget that will be used as the element's initial configuration.
///  * The framework calls [mount] to add the newly created element to the tree
///    at a given slot in a given parent. The [mount] method is responsible for
///    inflating any child widgets and calling [attachRenderObject] as
///    necessary to attach any associated render objects to the render tree.
///  * At this point, the element is considered "active" and might appear on
///    screen.
///  * At some point, the parent might decide to change the widget used to
///    configure this element, for example because the parent rebuilt with new
///    state. When this happens, the framework will call [update] with the new
///    widget. The new widget will always have the same [runtimeType] and key as
///    old widget. If the parent wishes to change the [runtimeType] or key of
///    the widget at this location in the tree, it can do so by unmounting this
///    element and inflating the new widget at this location.
///  * At some point, an ancestor might decide to remove this element (or an
///    intermediate ancestor) from the tree, which the ancestor does by calling
///    [deactivateChild] on itself. Deactivating the intermediate ancestor will
///    remove that element's render object from the render tree and add this
///    element to the [owner]'s list of inactive elements, causing the framework
///    to call [deactivate] on this element.
///  * At this point, the element is considered "inactive" and will not appear
///    on screen. An element can remain in the inactive state only until
///    the end of the current animation frame. At the end of the animation
///    frame, any elements that are still inactive will be unmounted.
///  * If the element gets reincorporated into the tree (e.g., because it or one
///    of its ancestors has a global key that is reused), the framework will
///    remove the element from the [owner]'s list of inactive elements, call
///    [activate] on the element, and reattach the element's render object to
///    the render tree. (At this point, the element is again considered "active"
///    and might appear on screen.)
///  * If the element does not get reincorporated into the tree by the end of
///    the current animation frame, the framework will call [unmount] on the
///    element.
///  * At this point, the element is considered "defunct" and will not be
///    incorporated into the tree in the future.
abstract class Element extends DiagnosticableTree implements BuildContext {
  /// Creates an element that uses the given widget as its configuration.
  ///
  /// Typically called by an override of [Widget.createElement].
  Element(Widget widget)
    : assert(widget != null),
      _widget = widget;

  Element? _parent;

  // Custom implementation of `operator ==` optimized for the ".of" pattern
  // used with `InheritedWidgets`.
  @nonVirtual
  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) => identical(this, other);

  // Custom implementation of hash code optimized for the ".of" pattern used
  // with `InheritedWidgets`.
  //
  // `Element.dependOnInheritedWidgetOfExactType` relies heavily on hash-based
  // `Set` look-ups, putting this getter on the performance critical path.
  //
  // The value is designed to fit within the SMI representation. This makes
  // the cached value use less memory (one field and no extra heap objects) and
  // cheap to compare (no indirection).
  //
  // See also:
  //
  //  * https://dart.dev/articles/dart-vm/numeric-computation, which
  //    explains how numbers are represented in Dart.
  @nonVirtual
  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => _cachedHash;
  final int _cachedHash = _nextHashCode = (_nextHashCode + 1) % 0xffffff;
  static int _nextHashCode = 1;

  /// Information set by parent to define where this child fits in its parent's
  /// child list.
  ///
  /// Subclasses of Element that only have one child should use null for
  /// the slot for that child.
  dynamic get slot => _slot;
  dynamic _slot;

  /// An integer that is guaranteed to be greater than the parent's, if any.
  /// The element at the root of the tree must have a depth greater than 0.
  int get depth {
    assert(() {
      if (_lifecycleState == _ElementLifecycle.initial) {
        throw FlutterError('Depth is only available when element has been mounted.');
      }
      return true;
    }());
    return _depth;
  }
  late int _depth;

  static int _sort(Element a, Element b) {
    if (a.depth < b.depth)
      return -1;
    if (b.depth < a.depth)
      return 1;
    if (b.dirty && !a.dirty)
      return -1;
    if (a.dirty && !b.dirty)
      return 1;
    return 0;
  }

  // Return a numeric encoding of the specific `Element` concrete subtype.
  // This is used in `Element.updateChild` to determine if a hot reload modified the
  // superclass of a mounted element's configuration. The encoding of each `Element`
  // must match the corresponding `Widget` encoding in `Widget._debugConcreteSubtype`.
  static int _debugConcreteSubtype(Element element) {
    return element is StatefulElement ? 1 :
           element is StatelessElement ? 2 :
           0;
  }

  /// The configuration for this element.
  @override
  Widget get widget => _widget;
  Widget _widget;

  /// The object that manages the lifecycle of this element.
  @override
  BuildOwner? get owner => _owner;
  BuildOwner? _owner;

  /// {@template flutter.widgets.Element.reassemble}
  /// Called whenever the application is reassembled during debugging, for
  /// example during hot reload.
  ///
  /// This method should rerun any initialization logic that depends on global
  /// state, for example, image loading from asset bundles (since the asset
  /// bundle may have changed).
  ///
  /// This function will only be called during development. In release builds,
  /// the `ext.flutter.reassemble` hook is not available, and so this code will
  /// never execute.
  ///
  /// Implementers should not rely on any ordering for hot reload source update,
  /// reassemble, and build methods after a hot reload has been initiated. It is
  /// possible that a [Timer] (e.g. an [Animation]) or a debugging session
  /// attached to the isolate could trigger a build with reloaded code _before_
  /// reassemble is called. Code that expects preconditions to be set by
  /// reassemble after a hot reload must be resilient to being called out of
  /// order, e.g. by fizzling instead of throwing. That said, once reassemble is
  /// called, build will be called after it at least once.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [State.reassemble]
  ///  * [BindingBase.reassembleApplication]
  ///  * [Image], which uses this to reload images.
  @mustCallSuper
  @protected
  void reassemble() {
    markNeedsBuild();
    visitChildren((Element child) {
      child.reassemble();
    });
  }

  bool _debugIsInScope(Element target) {
    Element? current = this;
    while (current != null) {
      if (target == current)
        return true;
      current = current._parent;
    }
    return false;
  }

  /// The render object at (or below) this location in the tree.
  ///
  /// If this object is a [RenderObjectElement], the render object is the one at
  /// this location in the tree. Otherwise, this getter will walk down the tree
  /// until it finds a [RenderObjectElement].
  RenderObject? get renderObject {
    RenderObject? result;
    void visit(Element element) {
      assert(result == null); // this verifies that there's only one child
      if (element is RenderObjectElement)
        result = element.renderObject;
      else
        element.visitChildren(visit);
    }
    visit(this);
    return result;
  }

  @override
  List<DiagnosticsNode> describeMissingAncestor({ required Type expectedAncestorType }) {
    final List<DiagnosticsNode> information = <DiagnosticsNode>[];
    final List<Element> ancestors = <Element>[];
    visitAncestorElements((Element element) {
      ancestors.add(element);
      return true;
    });

    information.add(DiagnosticsProperty<Element>(
      'The specific widget that could not find a $expectedAncestorType ancestor was',
      this,
      style: DiagnosticsTreeStyle.errorProperty,
    ));

    if (ancestors.isNotEmpty) {
      information.add(describeElements('The ancestors of this widget were', ancestors));
    } else {
      information.add(ErrorDescription(
        'This widget is the root of the tree, so it has no '
        'ancestors, let alone a "$expectedAncestorType" ancestor.'
      ));
    }
    return information;
  }

  /// Returns a list of [Element]s from the current build context to the error report.
  static DiagnosticsNode describeElements(String name, Iterable<Element> elements) {
    return DiagnosticsBlock(
      name: name,
      children: elements.map<DiagnosticsNode>((Element element) => DiagnosticsProperty<Element>('', element)).toList(),
      allowTruncate: true,
    );
  }

  @override
  DiagnosticsNode describeElement(String name, {DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty}) {
    return DiagnosticsProperty<Element>(name, this, style: style);
  }

  @override
  DiagnosticsNode describeWidget(String name, {DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty}) {
    return DiagnosticsProperty<Element>(name, this, style: style);
  }

  @override
  DiagnosticsNode describeOwnershipChain(String name) {
    // TODO(jacobr): make this structured so clients can support clicks on
    // individual entries. For example, is this an iterable with arrows as
    // separators?
    return StringProperty(name, debugGetCreatorChain(10));
  }

  // This is used to verify that Element objects move through life in an
  // orderly fashion.
  _ElementLifecycle _lifecycleState = _ElementLifecycle.initial;

  /// Calls the argument for each child. Must be overridden by subclasses that
  /// support having children.
  ///
  /// There is no guaranteed order in which the children will be visited, though
  /// it should be consistent over time.
  ///
  /// Calling this during build is dangerous: the child list might still be
  /// being updated at that point, so the children might not be constructed yet,
  /// or might be old children that are going to be replaced. This method should
  /// only be called if it is provable that the children are available.
  void visitChildren(ElementVisitor visitor) { }

  /// Calls the argument for each child considered onstage.
  ///
  /// Classes like [Offstage] and [Overlay] override this method to hide their
  /// children.
  ///
  /// Being onstage affects the element's discoverability during testing when
  /// you use Flutter's [Finder] objects. For example, when you instruct the
  /// test framework to tap on a widget, by default the finder will look for
  /// onstage elements and ignore the offstage ones.
  ///
  /// The default implementation defers to [visitChildren] and therefore treats
  /// the element as onstage.
  ///
  /// See also:
  ///
  ///  * [Offstage] widget that hides its children.
  ///  * [Finder] that skips offstage widgets by default.
  ///  * [RenderObject.visitChildrenForSemantics], in contrast to this method,
  ///    designed specifically for excluding parts of the UI from the semantics
  ///    tree.
  void debugVisitOnstageChildren(ElementVisitor visitor) => visitChildren(visitor);

  /// Wrapper around [visitChildren] for [BuildContext].
  @override
  void visitChildElements(ElementVisitor visitor) {
    assert(() {
      if (owner == null || !owner!._debugStateLocked)
        return true;
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('visitChildElements() called during build.'),
        ErrorDescription(
          "The BuildContext.visitChildElements() method can't be called during "
          'build because the child list is still being updated at that point, '
          'so the children might not be constructed yet, or might be old children '
          'that are going to be replaced.'
        ),
      ]);
    }());
    visitChildren(visitor);
  }

  /// Update the given child with the given new configuration.
  ///
  /// This method is the core of the widgets system. It is called each time we
  /// are to add, update, or remove a child based on an updated configuration.
  ///
  /// The `newSlot` argument specifies the new value for this element's [slot].
  ///
  /// If the `child` is null, and the `newWidget` is not null, then we have a new
  /// child for which we need to create an [Element], configured with `newWidget`.
  ///
  /// If the `newWidget` is null, and the `child` is not null, then we need to
  /// remove it because it no longer has a configuration.
  ///
  /// If neither are null, then we need to update the `child`'s configuration to
  /// be the new configuration given by `newWidget`. If `newWidget` can be given
  /// to the existing child (as determined by [Widget.canUpdate]), then it is so
  /// given. Otherwise, the old child needs to be disposed and a new child
  /// created for the new configuration.
  ///
  /// If both are null, then we don't have a child and won't have a child, so we
  /// do nothing.
  ///
  /// The [updateChild] method returns the new child, if it had to create one,
  /// or the child that was passed in, if it just had to update the child, or
  /// null, if it removed the child and did not replace it.
  ///
  /// The following table summarizes the above:
  ///
  /// |                     | **newWidget == null**  | **newWidget != null**   |
  /// | :-----------------: | :--------------------- | :---------------------- |
  /// |  **child == null**  |  Returns null.         |  Returns new [Element]. |
  /// |  **child != null**  |  Old child is removed, returns null. | Old child updated if possible, returns child or new [Element]. |
  ///
  /// The `newSlot` argument is used only if `newWidget` is not null. If `child`
  /// is null (or if the old child cannot be updated), then the `newSlot` is
  /// given to the new [Element] that is created for the child, via
  /// [inflateWidget]. If `child` is not null (and the old child _can_ be
  /// updated), then the `newSlot` is given to [updateSlotForChild] to update
  /// its slot, in case it has moved around since it was last built.
  ///
  /// See the [RenderObjectElement] documentation for more information on slots.
  @protected
  Element? updateChild(Element? child, Widget? newWidget, dynamic newSlot) {
    if (newWidget == null) {
      if (child != null)
        deactivateChild(child);
      return null;
    }
    final Element newChild;
    if (child != null) {
      bool hasSameSuperclass = true;
      // When the type of a widget is changed between Stateful and Stateless via
      // hot reload, the element tree will end up in a partially invalid state.
      // That is, if the widget was a StatefulWidget and is now a StatelessWidget,
      // then the element tree currently contains a StatefulElement that is incorrectly
      // referencing a StatelessWidget (and likewise with StatelessElement).
      //
      // To avoid crashing due to type errors, we need to gently guide the invalid
      // element out of the tree. To do so, we ensure that the `hasSameSuperclass` condition
      // returns false which prevents us from trying to update the existing element
      // incorrectly.
      //
      // For the case where the widget becomes Stateful, we also need to avoid
      // accessing `StatelessElement.widget` as the cast on the getter will
      // cause a type error to be thrown. Here we avoid that by short-circuiting
      // the `Widget.canUpdate` check once `hasSameSuperclass` is false.
      assert(() {
        final int oldElementClass = Element._debugConcreteSubtype(child);
        final int newWidgetClass = Widget._debugConcreteSubtype(newWidget);
        hasSameSuperclass = oldElementClass == newWidgetClass;
        return true;
      }());
      if (hasSameSuperclass && child.widget == newWidget) {
        if (child.slot != newSlot)
          updateSlotForChild(child, newSlot);
        newChild = child;
      } else if (hasSameSuperclass && Widget.canUpdate(child.widget, newWidget)) {
        if (child.slot != newSlot)
          updateSlotForChild(child, newSlot);
        child.update(newWidget);
        assert(child.widget == newWidget);
        assert(() {
          child.owner!._debugElementWasRebuilt(child);
          return true;
        }());
        newChild = child;
      } else {
        deactivateChild(child);
        assert(child._parent == null);
        newChild = inflateWidget(newWidget, newSlot);
      }
    } else {
      newChild = inflateWidget(newWidget, newSlot);
    }

    assert(() {
      if (child != null)
        _debugRemoveGlobalKeyReservation(child);
      final Key? key = newWidget.key;
      if (key is GlobalKey) {
        key._debugReserveFor(this, newChild);
      }
      return true;
    }());

    return newChild;
  }

  /// Add this element to the tree in the given slot of the given parent.
  ///
  /// The framework calls this function when a newly created element is added to
  /// the tree for the first time. Use this method to initialize state that
  /// depends on having a parent. State that is independent of the parent can
  /// more easily be initialized in the constructor.
  ///
  /// This method transitions the element from the "initial" lifecycle state to
  /// the "active" lifecycle state.
  ///
  /// Subclasses that override this method are likely to want to also override
  /// [update], [visitChildren], [RenderObjectElement.insertRenderObjectChild],
  /// [RenderObjectElement.moveRenderObjectChild], and
  /// [RenderObjectElement.removeRenderObjectChild].
  @mustCallSuper
  void mount(Element? parent, dynamic newSlot) {
    _parent = parent;
    _slot = newSlot;
    _lifecycleState = _ElementLifecycle.active;
    _depth = _parent != null ? _parent!.depth + 1 : 1;
    if (parent != null) // Only assign ownership if the parent is non-null
      _owner = parent.owner;
    final Key? key = widget.key;
    if (key is GlobalKey) {
      key._register(this);
    }
    _updateInheritance();
  }

  void _debugRemoveGlobalKeyReservation(Element child) {
    GlobalKey._debugRemoveReservationFor(this, child);
  }

  /// Change the widget used to configure this element.
  ///
  /// The framework calls this function when the parent wishes to use a
  /// different widget to configure this element. The new widget is guaranteed
  /// to have the same [runtimeType] as the old widget.
  ///
  /// This function is called only during the "active" lifecycle state.
  @mustCallSuper
  void update(covariant Widget newWidget) {
    // This code is hot when hot reloading, so we try to
    // only call _AssertionError._evaluateAssertion once.
    assert(_lifecycleState == _ElementLifecycle.active
        && widget != null
        && newWidget != null
        && newWidget != widget
        && depth != null
        && Widget.canUpdate(widget, newWidget));
    // This Element was told to update and we can now release all the global key
    // reservations of forgotten children. We cannot do this earlier because the
    // forgotten children still represent global key duplications if the element
    // never updates (the forgotten children are not removed from the tree
    // until the call to update happens)
    assert(() {
      _debugForgottenChildrenWithGlobalKey.forEach(_debugRemoveGlobalKeyReservation);
      _debugForgottenChildrenWithGlobalKey.clear();
      return true;
    }());
    _widget = newWidget;
  }

  /// Change the slot that the given child occupies in its parent.
  ///
  /// Called by [MultiChildRenderObjectElement], and other [RenderObjectElement]
  /// subclasses that have multiple children, when child moves from one position
  /// to another in this element's child list.
  @protected
  void updateSlotForChild(Element child, dynamic newSlot) {
    assert(_lifecycleState == _ElementLifecycle.active);
    assert(child != null);
    assert(child._parent == this);
    void visit(Element element) {
      element._updateSlot(newSlot);
      if (element is! RenderObjectElement)
        element.visitChildren(visit);
    }
    visit(child);
  }

  void _updateSlot(dynamic newSlot) {
    assert(_lifecycleState == _ElementLifecycle.active);
    assert(widget != null);
    assert(_parent != null);
    assert(_parent!._lifecycleState == _ElementLifecycle.active);
    assert(depth != null);
    _slot = newSlot;
  }

  void _updateDepth(int parentDepth) {
    final int expectedDepth = parentDepth + 1;
    if (_depth < expectedDepth) {
      _depth = expectedDepth;
      visitChildren((Element child) {
        child._updateDepth(expectedDepth);
      });
    }
  }

  /// Remove [renderObject] from the render tree.
  ///
  /// The default implementation of this function simply calls
  /// [detachRenderObject] recursively on each child. The
  /// [RenderObjectElement.detachRenderObject] override does the actual work of
  /// removing [renderObject] from the render tree.
  ///
  /// This is called by [deactivateChild].
  void detachRenderObject() {
    visitChildren((Element child) {
      child.detachRenderObject();
    });
    _slot = null;
  }

  /// Add [renderObject] to the render tree at the location specified by `newSlot`.
  ///
  /// The default implementation of this function simply calls
  /// [attachRenderObject] recursively on each child. The
  /// [RenderObjectElement.attachRenderObject] override does the actual work of
  /// adding [renderObject] to the render tree.
  ///
  /// The `newSlot` argument specifies the new value for this element's [slot].
  void attachRenderObject(dynamic newSlot) {
    assert(_slot == null);
    visitChildren((Element child) {
      child.attachRenderObject(newSlot);
    });
    _slot = newSlot;
  }

  Element? _retakeInactiveElement(GlobalKey key, Widget newWidget) {
    // The "inactivity" of the element being retaken here may be forward-looking: if
    // we are taking an element with a GlobalKey from an element that currently has
    // it as a child, then we know that element will soon no longer have that
    // element as a child. The only way that assumption could be false is if the
    // global key is being duplicated, and we'll try to track that using the
    // _debugTrackElementThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans call below.
    final Element? element = key._currentElement;
    if (element == null)
      return null;
    if (!Widget.canUpdate(element.widget, newWidget))
      return null;
    assert(() {
      if (debugPrintGlobalKeyedWidgetLifecycle)
        debugPrint('Attempting to take $element from ${element._parent ?? "inactive elements list"} to put in $this.');
      return true;
    }());
    final Element? parent = element._parent;
    if (parent != null) {
      assert(() {
        if (parent == this) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary("A GlobalKey was used multiple times inside one widget's child list."),
            DiagnosticsProperty<GlobalKey>('The offending GlobalKey was', key),
            parent.describeElement('The parent of the widgets with that key was'),
            element.describeElement('The first child to get instantiated with that key became'),
            DiagnosticsProperty<Widget>('The second child that was to be instantiated with that key was', widget, style: DiagnosticsTreeStyle.errorProperty),
            ErrorDescription('A GlobalKey can only be specified on one widget at a time in the widget tree.'),
          ]);
        }
        parent.owner!._debugTrackElementThatWillNeedToBeRebuiltDueToGlobalKeyShenanigans(
          parent,
          key,
        );
        return true;
      }());
      parent.forgetChild(element);
      parent.deactivateChild(element);
    }
    assert(element._parent == null);
    owner!._inactiveElements.remove(element);
    return element;
  }

  /// Create an element for the given widget and add it as a child of this
  /// element in the given slot.
  ///
  /// This method is typically called by [updateChild] but can be called
  /// directly by subclasses that need finer-grained control over creating
  /// elements.
  ///
  /// If the given widget has a global key and an element already exists that
  /// has a widget with that global key, this function will reuse that element
  /// (potentially grafting it from another location in the tree or reactivating
  /// it from the list of inactive elements) rather than creating a new element.
  ///
  /// The `newSlot` argument specifies the new value for this element's [slot].
  ///
  /// The element returned by this function will already have been mounted and
  /// will be in the "active" lifecycle state.
  @protected
  Element inflateWidget(Widget newWidget, dynamic newSlot) {
    assert(newWidget != null);
    final Key? key = newWidget.key;
    if (key is GlobalKey) {
      final Element? newChild = _retakeInactiveElement(key, newWidget);
      if (newChild != null) {
        assert(newChild._parent == null);
        assert(() {
          _debugCheckForCycles(newChild);
          return true;
        }());
        newChild._activateWithParent(this, newSlot);
        final Element? updatedChild = updateChild(newChild, newWidget, newSlot);
        assert(newChild == updatedChild);
        return updatedChild!;
      }
    }
    final Element newChild = newWidget.createElement();
    assert(() {
      _debugCheckForCycles(newChild);
      return true;
    }());
    newChild.mount(this, newSlot);
    assert(newChild._lifecycleState == _ElementLifecycle.active);
    return newChild;
  }

  void _debugCheckForCycles(Element newChild) {
    assert(newChild._parent == null);
    assert(() {
      Element node = this;
      while (node._parent != null)
        node = node._parent!;
      assert(node != newChild); // indicates we are about to create a cycle
      return true;
    }());
  }

  /// Move the given element to the list of inactive elements and detach its
  /// render object from the render tree.
  ///
  /// This method stops the given element from being a child of this element by
  /// detaching its render object from the render tree and moving the element to
  /// the list of inactive elements.
  ///
  /// This method (indirectly) calls [deactivate] on the child.
  ///
  /// The caller is responsible for removing the child from its child model.
  /// Typically [deactivateChild] is called by the element itself while it is
  /// updating its child model; however, during [GlobalKey] reparenting, the new
  /// parent proactively calls the old parent's [deactivateChild], first using
  /// [forgetChild] to cause the old parent to update its child model.
  @protected
  void deactivateChild(Element child) {
    assert(child != null);
    assert(child._parent == this);
    child._parent = null;
    child.detachRenderObject();
    owner!._inactiveElements.add(child); // this eventually calls child.deactivate()
    assert(() {
      if (debugPrintGlobalKeyedWidgetLifecycle) {
        if (child.widget.key is GlobalKey)
          debugPrint('Deactivated $child (keyed child of $this)');
      }
      return true;
    }());
  }

  // The children that have been forgotten by forgetChild. This will be used in
  // [update] to remove the global key reservations of forgotten children.
  final Set<Element> _debugForgottenChildrenWithGlobalKey = HashSet<Element>();

  /// Remove the given child from the element's child list, in preparation for
  /// the child being reused elsewhere in the element tree.
  ///
  /// This updates the child model such that, e.g., [visitChildren] does not
  /// walk that child anymore.
  ///
  /// The element will still have a valid parent when this is called, and the
  /// child's [Element.slot] value will be valid in the context of that parent.
  /// After this is called, [deactivateChild] is called to sever the link to
  /// this object.
  ///
  /// The [update] is responsible for updating or creating the new child that
  /// will replace this [child].
  @protected
  @mustCallSuper
  void forgetChild(Element child) {
    // This method is called on the old parent when the given child (with a
    // global key) is given a new parent. We cannot remove the global key
    // reservation directly in this method because the forgotten child is not
    // removed from the tree until this Element is updated in [update]. If
    // [update] is never called, the forgotten child still represents a global
    // key duplication that we need to catch.
    assert(() {
      if (child.widget.key is GlobalKey)
        _debugForgottenChildrenWithGlobalKey.add(child);
      return true;
    }());
  }

  void _activateWithParent(Element parent, dynamic newSlot) {
    assert(_lifecycleState == _ElementLifecycle.inactive);
    _parent = parent;
    assert(() {
      if (debugPrintGlobalKeyedWidgetLifecycle)
        debugPrint('Reactivating $this (now child of $_parent).');
      return true;
    }());
    _updateDepth(_parent!.depth);
    _activateRecursively(this);
    attachRenderObject(newSlot);
    assert(_lifecycleState == _ElementLifecycle.active);
  }

  static void _activateRecursively(Element element) {
    assert(element._lifecycleState == _ElementLifecycle.inactive);
    element.activate();
    assert(element._lifecycleState == _ElementLifecycle.active);
    element.visitChildren(_activateRecursively);
  }

  /// Transition from the "inactive" to the "active" lifecycle state.
  ///
  /// The framework calls this method when a previously deactivated element has
  /// been reincorporated into the tree. The framework does not call this method
  /// the first time an element becomes active (i.e., from the "initial"
  /// lifecycle state). Instead, the framework calls [mount] in that situation.
  ///
  /// See the lifecycle documentation for [Element] for additional information.
  @mustCallSuper
  void activate() {
    assert(_lifecycleState == _ElementLifecycle.inactive);
    assert(widget != null);
    assert(owner != null);
    assert(depth != null);
    final bool hadDependencies = (_dependencies != null && _dependencies!.isNotEmpty) || _hadUnsatisfiedDependencies;
    _lifecycleState = _ElementLifecycle.active;
    // We unregistered our dependencies in deactivate, but never cleared the list.
    // Since we're going to be reused, let's clear our list now.
    _dependencies?.clear();
    _hadUnsatisfiedDependencies = false;
    _updateInheritance();
    if (_dirty)
      owner!.scheduleBuildFor(this);
    if (hadDependencies)
      didChangeDependencies();
  }

  /// Transition from the "active" to the "inactive" lifecycle state.
  ///
  /// The framework calls this method when a previously active element is moved
  /// to the list of inactive elements. While in the inactive state, the element
  /// will not appear on screen. The element can remain in the inactive state
  /// only until the end of the current animation frame. At the end of the
  /// animation frame, if the element has not be reactivated, the framework will
  /// unmount the element.
  ///
  /// This is (indirectly) called by [deactivateChild].
  ///
  /// See the lifecycle documentation for [Element] for additional information.
  @mustCallSuper
  void deactivate() {
    assert(_lifecycleState == _ElementLifecycle.active);
    assert(_widget != null); // Use the private property to avoid a CastError during hot reload.
    assert(depth != null);
    if (_dependencies != null && _dependencies!.isNotEmpty) {
      for (final InheritedElement dependency in _dependencies!)
        dependency._dependents.remove(this);
      // For expediency, we don't actually clear the list here, even though it's
      // no longer representative of what we are registered with. If we never
      // get re-used, it doesn't matter. If we do, then we'll clear the list in
      // activate(). The benefit of this is that it allows Element's activate()
      // implementation to decide whether to rebuild based on whether we had
      // dependencies here.
    }
    _inheritedWidgets = null;
    _lifecycleState = _ElementLifecycle.inactive;
  }

  /// Called, in debug mode, after children have been deactivated (see [deactivate]).
  ///
  /// This method is not called in release builds.
  @mustCallSuper
  void debugDeactivated() {
    assert(_lifecycleState == _ElementLifecycle.inactive);
  }

  /// Transition from the "inactive" to the "defunct" lifecycle state.
  ///
  /// Called when the framework determines that an inactive element will never
  /// be reactivated. At the end of each animation frame, the framework calls
  /// [unmount] on any remaining inactive elements, preventing inactive elements
  /// from remaining inactive for longer than a single animation frame.
  ///
  /// After this function is called, the element will not be incorporated into
  /// the tree again.
  ///
  /// See the lifecycle documentation for [Element] for additional information.
  @mustCallSuper
  void unmount() {
    assert(_lifecycleState == _ElementLifecycle.inactive);
    assert(_widget != null); // Use the private property to avoid a CastError during hot reload.
    assert(depth != null);
    // Use the private property to avoid a CastError during hot reload.
    final Key? key = _widget.key;
    if (key is GlobalKey) {
      key._unregister(this);
    }
    _lifecycleState = _ElementLifecycle.defunct;
  }

  @override
  RenderObject? findRenderObject() => renderObject;

  @override
  Size? get size {
    assert(() {
      if (_lifecycleState != _ElementLifecycle.active) {
        // TODO(jacobr): is this a good separation into contract and violation?
        // I have added a line of white space.
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('Cannot get size of inactive element.'),
          ErrorDescription(
            'In order for an element to have a valid size, the element must be '
            'active, which means it is part of the tree.\n'
            'Instead, this element is in the $_lifecycleState state.'
          ),
          describeElement('The size getter was called for the following element'),
        ]);
      }
      if (owner!._debugBuilding) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('Cannot get size during build.'),
          ErrorDescription(
            'The size of this render object has not yet been determined because '
            'the framework is still in the process of building widgets, which '
            'means the render tree for this frame has not yet been determined. '
            'The size getter should only be called from paint callbacks or '
            'interaction event handlers (e.g. gesture callbacks).'
          ),
          ErrorSpacer(),
          ErrorHint(
            'If you need some sizing information during build to decide which '
            'widgets to build, consider using a LayoutBuilder widget, which can '
            'tell you the layout constraints at a given location in the tree. See '
            '<https://api.flutter.dev/flutter/widgets/LayoutBuilder-class.html> '
            'for more details.'
          ),
          ErrorSpacer(),
          describeElement('The size getter was called for the following element'),
        ]);
      }
      return true;
    }());
    final RenderObject? renderObject = findRenderObject();
    assert(() {
      if (renderObject == null) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('Cannot get size without a render object.'),
          ErrorHint(
            'In order for an element to have a valid size, the element must have '
            'an associated render object. This element does not have an associated '
            'render object, which typically means that the size getter was called '
            'too early in the pipeline (e.g., during the build phase) before the '
            'framework has created the render tree.'
          ),
          describeElement('The size getter was called for the following element'),
        ]);
      }
      if (renderObject is RenderSliver) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('Cannot get size from a RenderSliver.'),
          ErrorHint(
            'The render object associated with this element is a '
            '${renderObject.runtimeType}, which is a subtype of RenderSliver. '
            'Slivers do not have a size per se. They have a more elaborate '
            'geometry description, which can be accessed by calling '
            'findRenderObject and then using the "geometry" getter on the '
            'resulting object.'
          ),
          describeElement('The size getter was called for the following element'),
          renderObject.describeForError('The associated render sliver was'),
        ]);
      }
      if (renderObject is! RenderBox) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('Cannot get size from a render object that is not a RenderBox.'),
          ErrorHint(
            'Instead of being a subtype of RenderBox, the render object associated '
            'with this element is a ${renderObject.runtimeType}. If this type of '
            'render object does have a size, consider calling findRenderObject '
            'and extracting its size manually.'
          ),
          describeElement('The size getter was called for the following element'),
          renderObject.describeForError('The associated render object was'),
        ]);
      }
      final RenderBox box = renderObject;
      if (!box.hasSize) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('Cannot get size from a render object that has not been through layout.'),
          ErrorHint(
            'The size of this render object has not yet been determined because '
            'this render object has not yet been through layout, which typically '
            'means that the size getter was called too early in the pipeline '
            '(e.g., during the build phase) before the framework has determined '
           'the size and position of the render objects during layout.'
          ),
          describeElement('The size getter was called for the following element'),
          box.describeForError('The render object from which the size was to be obtained was'),
        ]);
      }
      if (box.debugNeedsLayout) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('Cannot get size from a render object that has been marked dirty for layout.'),
          ErrorHint(
            'The size of this render object is ambiguous because this render object has '
            'been modified since it was last laid out, which typically means that the size '
            'getter was called too early in the pipeline (e.g., during the build phase) '
            'before the framework has determined the size and position of the render '
            'objects during layout.'
          ),
          describeElement('The size getter was called for the following element'),
          box.describeForError('The render object from which the size was to be obtained was'),
          ErrorHint(
            'Consider using debugPrintMarkNeedsLayoutStacks to determine why the render '
            'object in question is dirty, if you did not expect this.'
          ),
        ]);
      }
      return true;
    }());
    if (renderObject is RenderBox)
      return renderObject.size;
    return null;
  }

  Map<Type, InheritedElement>? _inheritedWidgets;
  Set<InheritedElement>? _dependencies;
  bool _hadUnsatisfiedDependencies = false;

  bool _debugCheckStateIsActiveForAncestorLookup() {
    assert(() {
      if (_lifecycleState != _ElementLifecycle.active) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary("Looking up a deactivated widget's ancestor is unsafe."),
          ErrorDescription(
            "At this point the state of the widget's element tree is no longer "
            'stable.'
          ),
          ErrorHint(
            "To safely refer to a widget's ancestor in its dispose() method, "
            'save a reference to the ancestor by calling dependOnInheritedWidgetOfExactType() '
            "in the widget's didChangeDependencies() method."
          ),
        ]);
      }
      return true;
    }());
    return true;
  }

  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use dependOnInheritedElement instead. '
    'This feature was deprecated after v1.12.1.'
  )
  @override
  InheritedWidget inheritFromElement(InheritedElement ancestor, { Object? aspect }) {
    return dependOnInheritedElement(ancestor, aspect: aspect);
  }

  @override
  InheritedWidget dependOnInheritedElement(InheritedElement ancestor, { Object? aspect }) {
    assert(ancestor != null);
    _dependencies ??= HashSet<InheritedElement>();
    _dependencies!.add(ancestor);
    ancestor.updateDependencies(this, aspect);
    return ancestor.widget;
  }

  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use dependOnInheritedWidgetOfExactType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  @override
  InheritedWidget? inheritFromWidgetOfExactType(Type targetType, { Object? aspect }) {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    final InheritedElement? ancestor = _inheritedWidgets == null ? null : _inheritedWidgets![targetType];
    if (ancestor != null) {
      assert(ancestor is InheritedElement);
      return inheritFromElement(ancestor, aspect: aspect);
    }
    _hadUnsatisfiedDependencies = true;
    return null;
  }

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>({Object? aspect}) {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    final InheritedElement? ancestor = _inheritedWidgets == null ? null : _inheritedWidgets![T];
    if (ancestor != null) {
      assert(ancestor is InheritedElement);
      return dependOnInheritedElement(ancestor, aspect: aspect) as T;
    }
    _hadUnsatisfiedDependencies = true;
    return null;
  }

  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use getElementForInheritedWidgetOfExactType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  @override
  InheritedElement? ancestorInheritedElementForWidgetOfExactType(Type targetType) {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    final InheritedElement? ancestor = _inheritedWidgets == null ? null : _inheritedWidgets![targetType];
    return ancestor;
  }

  @override
  InheritedElement? getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    final InheritedElement? ancestor = _inheritedWidgets == null ? null : _inheritedWidgets![T];
    return ancestor;
  }

  void _updateInheritance() {
    assert(_lifecycleState == _ElementLifecycle.active);
    _inheritedWidgets = _parent?._inheritedWidgets;
  }

  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use findAncestorWidgetOfExactType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  @override
  Widget? ancestorWidgetOfExactType(Type targetType) {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    Element? ancestor = _parent;
    while (ancestor != null && ancestor.widget.runtimeType != targetType)
      ancestor = ancestor._parent;
    return ancestor?.widget;
  }

  @override
  T? findAncestorWidgetOfExactType<T extends Widget>() {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    Element? ancestor = _parent;
    while (ancestor != null && ancestor.widget.runtimeType != T)
      ancestor = ancestor._parent;
    return ancestor?.widget as T?;
  }

  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use findAncestorStateOfType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  @override
  State? ancestorStateOfType(TypeMatcher matcher) {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    Element? ancestor = _parent;
    while (ancestor != null) {
      if (ancestor is StatefulElement && matcher.check(ancestor.state))
        break;
      ancestor = ancestor._parent;
    }
    final StatefulElement? statefulAncestor = ancestor as StatefulElement?;
    return statefulAncestor?.state;
  }

  @override
  T? findAncestorStateOfType<T extends State<StatefulWidget>>() {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    Element? ancestor = _parent;
    while (ancestor != null) {
      if (ancestor is StatefulElement && ancestor.state is T)
        break;
      ancestor = ancestor._parent;
    }
    final StatefulElement? statefulAncestor = ancestor as StatefulElement?;
    return statefulAncestor?.state as T?;
  }

  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use findRootAncestorStateOfType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  @override
  State? rootAncestorStateOfType(TypeMatcher matcher) {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    Element? ancestor = _parent;
    StatefulElement? statefulAncestor;
    while (ancestor != null) {
      if (ancestor is StatefulElement && matcher.check(ancestor.state))
        statefulAncestor = ancestor;
      ancestor = ancestor._parent;
    }
    return statefulAncestor?.state;
  }

  @override
  T? findRootAncestorStateOfType<T extends State<StatefulWidget>>() {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    Element? ancestor = _parent;
    StatefulElement? statefulAncestor;
    while (ancestor != null) {
      if (ancestor is StatefulElement && ancestor.state is T)
        statefulAncestor = ancestor;
      ancestor = ancestor._parent;
    }
    return statefulAncestor?.state as T?;
  }

  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use findAncestorRenderObjectOfType instead. '
    'This feature was deprecated after v1.12.1.'
  )
  @override
  RenderObject? ancestorRenderObjectOfType(TypeMatcher matcher) {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    Element? ancestor = _parent;
    while (ancestor != null) {
      if (ancestor is RenderObjectElement && matcher.check(ancestor.renderObject))
        return ancestor.renderObject;
      ancestor = ancestor._parent;
    }
    return null;
  }

  @override
  T? findAncestorRenderObjectOfType<T extends RenderObject>() {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    Element? ancestor = _parent;
    while (ancestor != null) {
      if (ancestor is RenderObjectElement && ancestor.renderObject is T)
        return ancestor.renderObject as T;
      ancestor = ancestor._parent;
    }
    return null;
  }

  @override
  void visitAncestorElements(bool visitor(Element element)) {
    assert(_debugCheckStateIsActiveForAncestorLookup());
    Element? ancestor = _parent;
    while (ancestor != null && visitor(ancestor))
      ancestor = ancestor._parent;
  }

  /// Called when a dependency of this element changes.
  ///
  /// The [dependOnInheritedWidgetOfExactType] registers this element as depending on
  /// inherited information of the given type. When the information of that type
  /// changes at this location in the tree (e.g., because the [InheritedElement]
  /// updated to a new [InheritedWidget] and
  /// [InheritedWidget.updateShouldNotify] returned true), the framework calls
  /// this function to notify this element of the change.
  @mustCallSuper
  void didChangeDependencies() {
    assert(_lifecycleState == _ElementLifecycle.active); // otherwise markNeedsBuild is a no-op
    assert(_debugCheckOwnerBuildTargetExists('didChangeDependencies'));
    markNeedsBuild();
  }

  bool _debugCheckOwnerBuildTargetExists(String methodName) {
    assert(() {
      if (owner!._debugCurrentBuildTarget == null) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            '$methodName for ${widget.runtimeType} was called at an '
            'inappropriate time.'
          ),
          ErrorDescription('It may only be called while the widgets are being built.'),
          ErrorHint(
            'A possible cause of this error is when $methodName is called during '
            'one of:\n'
            ' * network I/O event\n'
            ' * file I/O event\n'
            ' * timer\n'
            ' * microtask (caused by Future.then, async/await, scheduleMicrotask)'
          ),
        ]);
      }
      return true;
    }());
    return true;
  }

  /// Returns a description of what caused this element to be created.
  ///
  /// Useful for debugging the source of an element.
  String debugGetCreatorChain(int limit) {
    final List<String> chain = <String>[];
    Element? node = this;
    while (chain.length < limit && node != null) {
      chain.add(node.toStringShort());
      node = node._parent;
    }
    if (node != null)
      chain.add('\u22EF');
    return chain.join(' \u2190 ');
  }

  /// Returns the parent chain from this element back to the root of the tree.
  ///
  /// Useful for debug display of a tree of Elements with only nodes in the path
  /// from the root to this Element expanded.
  List<Element> debugGetDiagnosticChain() {
    final List<Element> chain = <Element>[this];
    Element? node = _parent;
    while (node != null) {
      chain.add(node);
      node = node._parent;
    }
    return chain;
  }

  /// A short, textual description of this element.
  @override
  String toStringShort() => widget.toStringShort();

  @override
  DiagnosticsNode toDiagnosticsNode({ String? name, DiagnosticsTreeStyle? style }) {
    return _ElementDiagnosticableTreeNode(
      name: name,
      value: this,
      style: style,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.defaultDiagnosticsTreeStyle= DiagnosticsTreeStyle.dense;
    if (_lifecycleState != _ElementLifecycle.initial) {
      properties.add(ObjectFlagProperty<int>('depth', depth, ifNull: 'no depth'));
    }
    properties.add(ObjectFlagProperty<Widget>('widget', widget, ifNull: 'no widget'));
    properties.add(DiagnosticsProperty<Key>('key', widget.key, showName: false, defaultValue: null, level: DiagnosticLevel.hidden));
    widget.debugFillProperties(properties);
    properties.add(FlagProperty('dirty', value: dirty, ifTrue: 'dirty'));
    if (_dependencies != null && _dependencies!.isNotEmpty) {
      final List<DiagnosticsNode> diagnosticsDependencies = _dependencies!
        .map((InheritedElement element) => element.widget.toDiagnosticsNode(style: DiagnosticsTreeStyle.sparse))
        .toList();
      properties.add(DiagnosticsProperty<List<DiagnosticsNode>>('dependencies', diagnosticsDependencies));
    }
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() {
    final List<DiagnosticsNode> children = <DiagnosticsNode>[];
    visitChildren((Element child) {
      children.add(child.toDiagnosticsNode());
    });
    return children;
  }

  /// Returns true if the element has been marked as needing rebuilding.
  bool get dirty => _dirty;
  bool _dirty = true;

  // Whether this is in owner._dirtyElements. This is used to know whether we
  // should be adding the element back into the list when it's reactivated.
  bool _inDirtyList = false;

  // Whether we've already built or not. Set in [rebuild].
  bool _debugBuiltOnce = false;

  // We let widget authors call setState from initState, didUpdateWidget, and
  // build even when state is locked because its convenient and a no-op anyway.
  // This flag ensures that this convenience is only allowed on the element
  // currently undergoing initState, didUpdateWidget, or build.
  bool _debugAllowIgnoredCallsToMarkNeedsBuild = false;
  bool _debugSetAllowIgnoredCallsToMarkNeedsBuild(bool value) {
    assert(_debugAllowIgnoredCallsToMarkNeedsBuild == !value);
    _debugAllowIgnoredCallsToMarkNeedsBuild = value;
    return true;
  }

  /// Marks the element as dirty and adds it to the global list of widgets to
  /// rebuild in the next frame.
  ///
  /// Since it is inefficient to build an element twice in one frame,
  /// applications and widgets should be structured so as to only mark
  /// widgets dirty during event handlers before the frame begins, not during
  /// the build itself.
  void markNeedsBuild() {
    assert(_lifecycleState != _ElementLifecycle.defunct);
    if (_lifecycleState != _ElementLifecycle.active)
      return;
    assert(owner != null);
    assert(_lifecycleState == _ElementLifecycle.active);
    assert(() {
      if (owner!._debugBuilding) {
        assert(owner!._debugCurrentBuildTarget != null);
        assert(owner!._debugStateLocked);
        if (_debugIsInScope(owner!._debugCurrentBuildTarget!))
          return true;
        if (!_debugAllowIgnoredCallsToMarkNeedsBuild) {
          final List<DiagnosticsNode> information = <DiagnosticsNode>[
            ErrorSummary('setState() or markNeedsBuild() called during build.'),
            ErrorDescription(
              'This ${widget.runtimeType} widget cannot be marked as needing to build because the framework '
              'is already in the process of building widgets.  A widget can be marked as '
              'needing to be built during the build phase only if one of its ancestors '
              'is currently building. This exception is allowed because the framework '
              'builds parent widgets before children, which means a dirty descendant '
              'will always be built. Otherwise, the framework might not visit this '
              'widget during this build phase.'
            ),
            describeElement(
              'The widget on which setState() or markNeedsBuild() was called was',
            ),
          ];
          if (owner!._debugCurrentBuildTarget != null)
            information.add(owner!._debugCurrentBuildTarget!.describeWidget('The widget which was currently being built when the offending call was made was'));
          throw FlutterError.fromParts(information);
        }
        assert(dirty); // can only get here if we're not in scope, but ignored calls are allowed, and our call would somehow be ignored (since we're already dirty)
      } else if (owner!._debugStateLocked) {
        assert(!_debugAllowIgnoredCallsToMarkNeedsBuild);
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('setState() or markNeedsBuild() called when widget tree was locked.'),
          ErrorDescription(
            'This ${widget.runtimeType} widget cannot be marked as needing to build '
            'because the framework is locked.'
          ),
          describeElement('The widget on which setState() or markNeedsBuild() was called was'),
        ]);
      }
      return true;
    }());
    if (dirty)
      return;
    _dirty = true;
    owner!.scheduleBuildFor(this);
  }

  /// Called by the [BuildOwner] when [BuildOwner.scheduleBuildFor] has been
  /// called to mark this element dirty, by [mount] when the element is first
  /// built, and by [update] when the widget has changed.
  void rebuild() {
    assert(_lifecycleState != _ElementLifecycle.initial);
    if (_lifecycleState != _ElementLifecycle.active || !_dirty)
      return;
    assert(() {
      if (debugOnRebuildDirtyWidget != null) {
        debugOnRebuildDirtyWidget!(this, _debugBuiltOnce);
      }
      if (debugPrintRebuildDirtyWidgets) {
        if (!_debugBuiltOnce) {
          debugPrint('Building $this');
          _debugBuiltOnce = true;
        } else {
          debugPrint('Rebuilding $this');
        }
      }
      return true;
    }());
    assert(_lifecycleState == _ElementLifecycle.active);
    assert(owner!._debugStateLocked);
    Element? debugPreviousBuildTarget;
    assert(() {
      debugPreviousBuildTarget = owner!._debugCurrentBuildTarget;
      owner!._debugCurrentBuildTarget = this;
      return true;
    }());
    performRebuild();
    assert(() {
      assert(owner!._debugCurrentBuildTarget == this);
      owner!._debugCurrentBuildTarget = debugPreviousBuildTarget;
      return true;
    }());
    assert(!_dirty);
  }

  /// Called by rebuild() after the appropriate checks have been made.
  @protected
  void performRebuild();
}

class _ElementDiagnosticableTreeNode extends DiagnosticableTreeNode {
  _ElementDiagnosticableTreeNode({
    String? name,
    required Element value,
    required DiagnosticsTreeStyle? style,
    this.stateful = false,
  }) : super(
    name: name,
    value: value,
    style: style,
  );

  final bool stateful;

  @override
  Map<String, Object?> toJsonMap(DiagnosticsSerializationDelegate delegate) {
    final Map<String, Object?> json = super.toJsonMap(delegate);
    final Element element = value as Element;
    json['widgetRuntimeType'] = element.widget.runtimeType.toString();
    json['stateful'] = stateful;
    return json;
  }
}

/// Signature for the constructor that is called when an error occurs while
/// building a widget.
///
/// The argument provides information regarding the cause of the error.
///
/// See also:
///
///  * [ErrorWidget.builder], which can be set to override the default
///    [ErrorWidget] builder.
///  * [FlutterError.reportError], which is typically called with the same
///    [FlutterErrorDetails] object immediately prior to [ErrorWidget.builder]
///    being called.
typedef ErrorWidgetBuilder = Widget Function(FlutterErrorDetails details);

/// A widget that renders an exception's message.
///
/// This widget is used when a build method fails, to help with determining
/// where the problem lies. Exceptions are also logged to the console, which you
/// can read using `flutter logs`. The console will also include additional
/// information such as the stack trace for the exception.
///
/// It is possible to override this widget.
///
/// {@tool sample --template=freeform}
/// ```dart
/// import 'package:flutter/material.dart';
///
/// void main() {
///   ErrorWidget.builder = (FlutterErrorDetails details) {
///     bool inDebug = false;
///     assert(() { inDebug = true; return true; }());
///     // In debug mode, use the normal error widget which shows
///     // the error message:
///     if (inDebug)
///       return ErrorWidget(details.exception);
///     // In release builds, show a yellow-on-blue message instead:
///     return Container(
///       alignment: Alignment.center,
///       child: Text(
///         'Error!',
///         style: TextStyle(color: Colors.yellow),
///         textDirection: TextDirection.ltr,
///       ),
///     );
///   };
///   // Here we would normally runApp() the root widget, but to demonstrate
///   // the error handling we artificially fail:
///   return runApp(Builder(
///     builder: (BuildContext context) {
///       throw 'oh no, an error';
///     },
///   ));
/// }
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [FlutterError.onError], which can be set to a method that exits the
///    application if that is preferable to showing an error message.
///  * <https://flutter.dev/docs/testing/errors>, more information about error
///    handling in Flutter.
class ErrorWidget extends LeafRenderObjectWidget {
  /// Creates a widget that displays the given exception.
  ///
  /// The message will be the stringification of the given exception, unless
  /// computing that value itself throws an exception, in which case it will
  /// be the string "Error".
  ///
  /// If this object is inspected from an IDE or the devtools, and the original
  /// exception is a [FlutterError] object, the original exception itself will
  /// be shown in the inspection output.
  ErrorWidget(Object exception)
    : message = _stringify(exception),
      _flutterError = exception is FlutterError ? exception : null,
      super(key: UniqueKey());

  /// Creates a widget that displays the given error message.
  ///
  /// An explicit [FlutterError] can be provided to be reported to inspection
  /// tools. It need not match the message.
  ErrorWidget.withDetails({ this.message = '', FlutterError? error })
    : _flutterError = error,
      super(key: UniqueKey());

  /// The configurable factory for [ErrorWidget].
  ///
  /// When an error occurs while building a widget, the broken widget is
  /// replaced by the widget returned by this function. By default, an
  /// [ErrorWidget] is returned.
  ///
  /// The system is typically in an unstable state when this function is called.
  /// An exception has just been thrown in the middle of build (and possibly
  /// layout), so surrounding widgets and render objects may be in a rather
  /// fragile state. The framework itself (especially the [BuildOwner]) may also
  /// be confused, and additional exceptions are quite likely to be thrown.
  ///
  /// Because of this, it is highly recommended that the widget returned from
  /// this function perform the least amount of work possible. A
  /// [LeafRenderObjectWidget] is the best choice, especially one that
  /// corresponds to a [RenderBox] that can handle the most absurd of incoming
  /// constraints. The default constructor maps to a [RenderErrorBox].
  ///
  /// The default behavior is to show the exception's message in debug mode,
  /// and to show nothing but a gray background in release builds.
  ///
  /// See also:
  ///
  ///  * [FlutterError.onError], which is typically called with the same
  ///    [FlutterErrorDetails] object immediately prior to this callback being
  ///    invoked, and which can also be configured to control how errors are
  ///    reported.
  ///  * <https://flutter.dev/docs/testing/errors>, more information about error
  ///    handling in Flutter.
  static ErrorWidgetBuilder builder = _defaultErrorWidgetBuilder;

  static Widget _defaultErrorWidgetBuilder(FlutterErrorDetails details) {
    String message = '';
    assert(() {
      message = _stringify(details.exception) + '\nSee also: https://flutter.dev/docs/testing/errors';
      return true;
    }());
    final Object exception = details.exception;
    return ErrorWidget.withDetails(message: message, error: exception is FlutterError ? exception : null);
  }

  static String _stringify(dynamic exception) {
    try {
      return exception.toString();
    } catch (e) {
      // intentionally left empty.
    }
    return 'Error';
  }

  /// The message to display.
  final String message;
  final FlutterError? _flutterError;

  @override
  RenderBox createRenderObject(BuildContext context) => RenderErrorBox(message);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    if (_flutterError == null)
      properties.add(StringProperty('message', message, quoted: false));
    else
      properties.add(_flutterError!.toDiagnosticsNode(style: DiagnosticsTreeStyle.whitespace));
  }
}

/// Signature for a function that creates a widget, e.g. [StatelessWidget.build]
/// or [State.build].
///
/// Used by [Builder.builder], [OverlayEntry.builder], etc.
///
/// See also:
///
///  * [IndexedWidgetBuilder], which is similar but also takes an index.
///  * [TransitionBuilder], which is similar but also takes a child.
///  * [ValueWidgetBuilder], which is similar but takes a value and a child.
typedef WidgetBuilder = Widget Function(BuildContext context);

/// Signature for a function that creates a widget for a given index, e.g., in a
/// list.
///
/// Used by [ListView.builder] and other APIs that use lazily-generated widgets.
///
/// See also:
///
///  * [WidgetBuilder], which is similar but only takes a [BuildContext].
///  * [TransitionBuilder], which is similar but also takes a child.
///  * [NullableIndexedWidgetBuilder], which is similar but may return null.
typedef IndexedWidgetBuilder = Widget Function(BuildContext context, int index);

/// Signature for a function that creates a widget for a given index, e.g., in a
/// list, but may return null.
///
/// Used by [SliverChildBuilderDelegate.builder] and other APIs that
/// use lazily-generated widgets where the child count is not known
/// ahead of time.
///
/// Unlike most builders, this callback can return null, indicating the index
/// is out of range. Whether and when this is valid depends on the semantics
/// of the builder. For example, [SliverChildBuilderDelegate.builder] returns
/// null when the index is out of range, where the range is defined by the
/// [SliverChildBuilderDelegate.childCount]; so in that case the `index`
/// parameter's value may determine whether returning null is valid or not.
///
/// See also:
///
///  * [WidgetBuilder], which is similar but only takes a [BuildContext].
///  * [TransitionBuilder], which is similar but also takes a child.
///  * [IndexedWidgetBuilder], which is similar but not nullable.
typedef NullableIndexedWidgetBuilder = Widget? Function(BuildContext context, int index);

/// A builder that builds a widget given a child.
///
/// The child should typically be part of the returned widget tree.
///
/// Used by [AnimatedBuilder.builder], as well as [WidgetsApp.builder] and
/// [MaterialApp.builder].
///
/// See also:
///
///  * [WidgetBuilder], which is similar but only takes a [BuildContext].
///  * [IndexedWidgetBuilder], which is similar but also takes an index.
///  * [ValueWidgetBuilder], which is similar but takes a value and a child.
typedef TransitionBuilder = Widget Function(BuildContext context, Widget? child);

/// A builder that creates a widget given the two callbacks `onStepContinue` and
/// `onStepCancel`.
///
/// Used by [Stepper.controlsBuilder].
///
/// See also:
///
///  * [WidgetBuilder], which is similar but only takes a [BuildContext].
typedef ControlsWidgetBuilder = Widget Function(BuildContext context, { VoidCallback? onStepContinue, VoidCallback? onStepCancel });

/// An [Element] that composes other [Element]s.
///
/// Rather than creating a [RenderObject] directly, a [ComponentElement] creates
/// [RenderObject]s indirectly by creating other [Element]s.
///
/// Contrast with [RenderObjectElement].
abstract class ComponentElement extends Element {
  /// Creates an element that uses the given widget as its configuration.
  ComponentElement(Widget widget) : super(widget);

  Element? _child;

  bool _debugDoingBuild = false;
  @override
  bool get debugDoingBuild => _debugDoingBuild;

  @override
  void mount(Element? parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    assert(_child == null);
    assert(_lifecycleState == _ElementLifecycle.active);
    _firstBuild();
    assert(_child != null);
  }

  void _firstBuild() {
    rebuild();
  }

  /// Calls the [StatelessWidget.build] method of the [StatelessWidget] object
  /// (for stateless widgets) or the [State.build] method of the [State] object
  /// (for stateful widgets) and then updates the widget tree.
  ///
  /// Called automatically during [mount] to generate the first build, and by
  /// [rebuild] when the element needs updating.
  @override
  void performRebuild() {
    if (!kReleaseMode && debugProfileBuildsEnabled)
      Timeline.startSync('${widget.runtimeType}',  arguments: timelineArgumentsIndicatingLandmarkEvent);

    assert(_debugSetAllowIgnoredCallsToMarkNeedsBuild(true));
    Widget? built;
    try {
      assert(() {
        _debugDoingBuild = true;
        return true;
      }());
      built = build();
      assert(() {
        _debugDoingBuild = false;
        return true;
      }());
      debugWidgetBuilderValue(widget, built);
    } catch (e, stack) {
      _debugDoingBuild = false;
      built = ErrorWidget.builder(
        _debugReportException(
          ErrorDescription('building $this'),
          e,
          stack,
          informationCollector: () sync* {
            yield DiagnosticsDebugCreator(DebugCreator(this));
          },
        ),
      );
    } finally {
      // We delay marking the element as clean until after calling build() so
      // that attempts to markNeedsBuild() during build() will be ignored.
      _dirty = false;
      assert(_debugSetAllowIgnoredCallsToMarkNeedsBuild(false));
    }
    try {
      _child = updateChild(_child, built, slot);
      assert(_child != null);
    } catch (e, stack) {
      built = ErrorWidget.builder(
        _debugReportException(
          ErrorDescription('building $this'),
          e,
          stack,
          informationCollector: () sync* {
            yield DiagnosticsDebugCreator(DebugCreator(this));
          },
        ),
      );
      _child = updateChild(null, built, slot);
    }

    if (!kReleaseMode && debugProfileBuildsEnabled)
      Timeline.finishSync();
  }

  /// Subclasses should override this function to actually call the appropriate
  /// `build` function (e.g., [StatelessWidget.build] or [State.build]) for
  /// their widget.
  @protected
  Widget build();

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_child != null)
      visitor(_child!);
  }

  @override
  void forgetChild(Element child) {
    assert(child == _child);
    _child = null;
    super.forgetChild(child);
  }
}

/// An [Element] that uses a [StatelessWidget] as its configuration.
class StatelessElement extends ComponentElement {
  /// Creates an element that uses the given widget as its configuration.
  StatelessElement(StatelessWidget widget) : super(widget);

  @override
  StatelessWidget get widget => super.widget as StatelessWidget;

  @override
  Widget build() => widget.build(this);

  @override
  void update(StatelessWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    _dirty = true;
    rebuild();
  }
}

/// An [Element] that uses a [StatefulWidget] as its configuration.
class StatefulElement extends ComponentElement {
  /// Creates an element that uses the given widget as its configuration.
  StatefulElement(StatefulWidget widget)
      : state = widget.createState(),
        super(widget) {
    assert(() {
      if (!state._debugTypesAreRight(widget)) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('StatefulWidget.createState must return a subtype of State<${widget.runtimeType}>'),
          ErrorDescription(
            'The createState function for ${widget.runtimeType} returned a state '
            'of type ${state.runtimeType}, which is not a subtype of '
            'State<${widget.runtimeType}>, violating the contract for createState.'
          ),
        ]);
      }
      return true;
    }());
    assert(state._element == null);
    state._element = this;
    assert(
      state._widget == null,
      'The createState function for $widget returned an old or invalid state '
      'instance: ${state._widget}, which is not null, violating the contract '
      'for createState.',
    );
    state._widget = widget;
    assert(state._debugLifecycleState == _StateLifecycle.created);
  }

  @override
  Widget build() => state.build(this);

  /// The [State] instance associated with this location in the tree.
  ///
  /// There is a one-to-one relationship between [State] objects and the
  /// [StatefulElement] objects that hold them. The [State] objects are created
  /// by [StatefulElement] in [mount].
  final State<StatefulWidget> state;

  @override
  void reassemble() {
    state.reassemble();
    super.reassemble();
  }

  @override
  void _firstBuild() {
    assert(state._debugLifecycleState == _StateLifecycle.created);
    try {
      _debugSetAllowIgnoredCallsToMarkNeedsBuild(true);
      final dynamic debugCheckForReturnedFuture = state.initState() as dynamic;
      assert(() {
        if (debugCheckForReturnedFuture is Future) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('${state.runtimeType}.initState() returned a Future.'),
            ErrorDescription('State.initState() must be a void method without an `async` keyword.'),
            ErrorHint(
              'Rather than awaiting on asynchronous work directly inside of initState, '
              'call a separate method to do this work without awaiting it.'
            ),
          ]);
        }
        return true;
      }());
    } finally {
      _debugSetAllowIgnoredCallsToMarkNeedsBuild(false);
    }
    assert(() {
      state._debugLifecycleState = _StateLifecycle.initialized;
      return true;
    }());
    state.didChangeDependencies();
    assert(() {
      state._debugLifecycleState = _StateLifecycle.ready;
      return true;
    }());
    super._firstBuild();
  }

  @override
  void performRebuild() {
    if (_didChangeDependencies) {
      state.didChangeDependencies();
      _didChangeDependencies = false;
    }
    super.performRebuild();
  }

  @override
  void update(StatefulWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    final StatefulWidget oldWidget = state._widget!;
    // We mark ourselves as dirty before calling didUpdateWidget to
    // let authors call setState from within didUpdateWidget without triggering
    // asserts.
    _dirty = true;
    state._widget = widget as StatefulWidget;
    try {
      _debugSetAllowIgnoredCallsToMarkNeedsBuild(true);
      final dynamic debugCheckForReturnedFuture = state.didUpdateWidget(oldWidget) as dynamic;
      assert(() {
        if (debugCheckForReturnedFuture is Future) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('${state.runtimeType}.didUpdateWidget() returned a Future.'),
            ErrorDescription( 'State.didUpdateWidget() must be a void method without an `async` keyword.'),
            ErrorHint(
              'Rather than awaiting on asynchronous work directly inside of didUpdateWidget, '
              'call a separate method to do this work without awaiting it.'
            ),
          ]);
        }
        return true;
      }());
    } finally {
      _debugSetAllowIgnoredCallsToMarkNeedsBuild(false);
    }
    rebuild();
  }

  @override
  void activate() {
    super.activate();
    // Since the State could have observed the deactivate() and thus disposed of
    // resources allocated in the build method, we have to rebuild the widget
    // so that its State can reallocate its resources.
    assert(_lifecycleState == _ElementLifecycle.active); // otherwise markNeedsBuild is a no-op
    markNeedsBuild();
  }

  @override
  void deactivate() {
    state.deactivate();
    super.deactivate();
  }

  @override
  void unmount() {
    super.unmount();
    state.dispose();
    assert(() {
      if (state._debugLifecycleState == _StateLifecycle.defunct)
        return true;
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('${state.runtimeType}.dispose failed to call super.dispose.'),
        ErrorDescription(
          'dispose() implementations must always call their superclass dispose() method, to ensure '
         'that all the resources used by the widget are fully released.'
        ),
      ]);
    }());
    state._element = null;
  }

  // TODO(a14n): Remove this when it goes to stable, https://github.com/flutter/flutter/pull/44189
  @Deprecated(
    'Use dependOnInheritedElement instead. '
    'This feature was deprecated after v1.12.1.'
  )
  @override
  InheritedWidget inheritFromElement(Element ancestor, { Object? aspect }) {
    return dependOnInheritedElement(ancestor, aspect: aspect);
  }

  @override
  InheritedWidget dependOnInheritedElement(Element ancestor, { Object? aspect }) {
    assert(ancestor != null);
    assert(() {
      final Type targetType = ancestor.widget.runtimeType;
      if (state._debugLifecycleState == _StateLifecycle.created) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('dependOnInheritedWidgetOfExactType<$targetType>() or dependOnInheritedElement() was called before ${state.runtimeType}.initState() completed.'),
          ErrorDescription(
            'When an inherited widget changes, for example if the value of Theme.of() changes, '
            "its dependent widgets are rebuilt. If the dependent widget's reference to "
            'the inherited widget is in a constructor or an initState() method, '
            'then the rebuilt dependent widget will not reflect the changes in the '
            'inherited widget.',
          ),
          ErrorHint(
            'Typically references to inherited widgets should occur in widget build() methods. Alternatively, '
            'initialization based on inherited widgets can be placed in the didChangeDependencies method, which '
            'is called after initState and whenever the dependencies change thereafter.'
          ),
        ]);
      }
      if (state._debugLifecycleState == _StateLifecycle.defunct) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('dependOnInheritedWidgetOfExactType<$targetType>() or dependOnInheritedElement() was called after dispose(): $this'),
          ErrorDescription(
            'This error happens if you call dependOnInheritedWidgetOfExactType() on the '
            'BuildContext for a widget that no longer appears in the widget tree '
            '(e.g., whose parent widget no longer includes the widget in its '
            'build). This error can occur when code calls '
            'dependOnInheritedWidgetOfExactType() from a timer or an animation callback.'
          ),
          ErrorHint(
            'The preferred solution is to cancel the timer or stop listening to the '
            'animation in the dispose() callback. Another solution is to check the '
            '"mounted" property of this object before calling '
            'dependOnInheritedWidgetOfExactType() to ensure the object is still in the '
            'tree.'
          ),
          ErrorHint(
            'This error might indicate a memory leak if '
            'dependOnInheritedWidgetOfExactType() is being called because another object '
            'is retaining a reference to this State object after it has been '
            'removed from the tree. To avoid memory leaks, consider breaking the '
            'reference to this object during dispose().'
          ),
        ]);
      }
      return true;
    }());
    return super.dependOnInheritedElement(ancestor as InheritedElement, aspect: aspect);
  }

  /// This controls whether we should call [State.didChangeDependencies] from
  /// the start of [build], to avoid calls when the [State] will not get built.
  /// This can happen when the widget has dropped out of the tree, but depends
  /// on an [InheritedWidget] that is still in the tree.
  ///
  /// It is set initially to false, since [_firstBuild] makes the initial call
  /// on the [state]. When it is true, [build] will call
  /// `state.didChangeDependencies` and then sets it to false. Subsequent calls
  /// to [didChangeDependencies] set it to true.
  bool _didChangeDependencies = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _didChangeDependencies = true;
  }

  @override
  DiagnosticsNode toDiagnosticsNode({ String? name, DiagnosticsTreeStyle? style }) {
    return _ElementDiagnosticableTreeNode(
      name: name,
      value: this,
      style: style,
      stateful: true,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<State<StatefulWidget>>('state', state, defaultValue: null));
  }
}

/// An [Element] that uses a [ProxyWidget] as its configuration.
abstract class ProxyElement extends ComponentElement {
  /// Initializes fields for subclasses.
  ProxyElement(ProxyWidget widget) : super(widget);

  @override
  ProxyWidget get widget => super.widget as ProxyWidget;

  @override
  Widget build() => widget.child;

  @override
  void update(ProxyWidget newWidget) {
    final ProxyWidget oldWidget = widget;
    assert(widget != null);
    assert(widget != newWidget);
    super.update(newWidget);
    assert(widget == newWidget);
    updated(oldWidget);
    _dirty = true;
    rebuild();
  }

  /// Called during build when the [widget] has changed.
  ///
  /// By default, calls [notifyClients]. Subclasses may override this method to
  /// avoid calling [notifyClients] unnecessarily (e.g. if the old and new
  /// widgets are equivalent).
  @protected
  void updated(covariant ProxyWidget oldWidget) {
    notifyClients(oldWidget);
  }

  /// Notify other objects that the widget associated with this element has
  /// changed.
  ///
  /// Called during [update] (via [updated]) after changing the widget
  /// associated with this element but before rebuilding this element.
  @protected
  void notifyClients(covariant ProxyWidget oldWidget);
}

/// An [Element] that uses a [ParentDataWidget] as its configuration.
class ParentDataElement<T extends ParentData> extends ProxyElement {
  /// Creates an element that uses the given widget as its configuration.
  ParentDataElement(ParentDataWidget<T> widget) : super(widget);

  @override
  ParentDataWidget<T> get widget => super.widget as ParentDataWidget<T>;

  void _applyParentData(ParentDataWidget<T> widget) {
    void applyParentDataToChild(Element child) {
      if (child is RenderObjectElement) {
        child._updateParentData(widget);
      } else {
        assert(child is! ParentDataElement<ParentData>);
        child.visitChildren(applyParentDataToChild);
      }
    }
    visitChildren(applyParentDataToChild);
  }

  /// Calls [ParentDataWidget.applyParentData] on the given widget, passing it
  /// the [RenderObject] whose parent data this element is ultimately
  /// responsible for.
  ///
  /// This allows a render object's [RenderObject.parentData] to be modified
  /// without triggering a build. This is generally ill-advised, but makes sense
  /// in situations such as the following:
  ///
  ///  * Build and layout are currently under way, but the [ParentData] in question
  ///    does not affect layout, and the value to be applied could not be
  ///    determined before build and layout (e.g. it depends on the layout of a
  ///    descendant).
  ///
  ///  * Paint is currently under way, but the [ParentData] in question does not
  ///    affect layout or paint, and the value to be applied could not be
  ///    determined before paint (e.g. it depends on the compositing phase).
  ///
  /// In either case, the next build is expected to cause this element to be
  /// configured with the given new widget (or a widget with equivalent data).
  ///
  /// Only [ParentDataWidget]s that return true for
  /// [ParentDataWidget.debugCanApplyOutOfTurn] can be applied this way.
  ///
  /// The new widget must have the same child as the current widget.
  ///
  /// An example of when this is used is the [AutomaticKeepAlive] widget. If it
  /// receives a notification during the build of one of its descendants saying
  /// that its child must be kept alive, it will apply a [KeepAlive] widget out
  /// of turn. This is safe, because by definition the child is already alive,
  /// and therefore this will not change the behavior of the parent this frame.
  /// It is more efficient than requesting an additional frame just for the
  /// purpose of updating the [KeepAlive] widget.
  void applyWidgetOutOfTurn(ParentDataWidget<T> newWidget) {
    assert(newWidget != null);
    assert(newWidget.debugCanApplyOutOfTurn());
    assert(newWidget.child == widget.child);
    _applyParentData(newWidget);
  }

  @override
  void notifyClients(ParentDataWidget<T> oldWidget) {
    _applyParentData(widget);
  }
}

/// An [Element] that uses an [InheritedWidget] as its configuration.
class InheritedElement extends ProxyElement {
  /// Creates an element that uses the given widget as its configuration.
  InheritedElement(InheritedWidget widget) : super(widget);

  @override
  InheritedWidget get widget => super.widget as InheritedWidget;

  final Map<Element, Object?> _dependents = HashMap<Element, Object?>();

  @override
  void _updateInheritance() {
    assert(_lifecycleState == _ElementLifecycle.active);
    final Map<Type, InheritedElement>? incomingWidgets = _parent?._inheritedWidgets;
    if (incomingWidgets != null)
      _inheritedWidgets = HashMap<Type, InheritedElement>.from(incomingWidgets);
    else
      _inheritedWidgets = HashMap<Type, InheritedElement>();
    _inheritedWidgets![widget.runtimeType] = this;
  }

  @override
  void debugDeactivated() {
    assert(() {
      assert(_dependents.isEmpty);
      return true;
    }());
    super.debugDeactivated();
  }

  /// Returns the dependencies value recorded for [dependent]
  /// with [setDependencies].
  ///
  /// Each dependent element is mapped to a single object value
  /// which represents how the element depends on this
  /// [InheritedElement]. This value is null by default and by default
  /// dependent elements are rebuilt unconditionally.
  ///
  /// Subclasses can manage these values with [updateDependencies]
  /// so that they can selectively rebuild dependents in
  /// [notifyDependent].
  ///
  /// This method is typically only called in overrides of [updateDependencies].
  ///
  /// See also:
  ///
  ///  * [updateDependencies], which is called each time a dependency is
  ///    created with [dependOnInheritedWidgetOfExactType].
  ///  * [setDependencies], which sets dependencies value for a dependent
  ///    element.
  ///  * [notifyDependent], which can be overridden to use a dependent's
  ///    dependencies value to decide if the dependent needs to be rebuilt.
  ///  * [InheritedModel], which is an example of a class that uses this method
  ///    to manage dependency values.
  @protected
  Object? getDependencies(Element dependent) {
    return _dependents[dependent];
  }

  /// Sets the value returned by [getDependencies] value for [dependent].
  ///
  /// Each dependent element is mapped to a single object value
  /// which represents how the element depends on this
  /// [InheritedElement]. The [updateDependencies] method sets this value to
  /// null by default so that dependent elements are rebuilt unconditionally.
  ///
  /// Subclasses can manage these values with [updateDependencies]
  /// so that they can selectively rebuild dependents in [notifyDependent].
  ///
  /// This method is typically only called in overrides of [updateDependencies].
  ///
  /// See also:
  ///
  ///  * [updateDependencies], which is called each time a dependency is
  ///    created with [dependOnInheritedWidgetOfExactType].
  ///  * [getDependencies], which returns the current value for a dependent
  ///    element.
  ///  * [notifyDependent], which can be overridden to use a dependent's
  ///    [getDependencies] value to decide if the dependent needs to be rebuilt.
  ///  * [InheritedModel], which is an example of a class that uses this method
  ///    to manage dependency values.
  @protected
  void setDependencies(Element dependent, Object? value) {
    _dependents[dependent] = value;
  }

  /// Called by [dependOnInheritedWidgetOfExactType] when a new [dependent] is added.
  ///
  /// Each dependent element can be mapped to a single object value with
  /// [setDependencies]. This method can lookup the existing dependencies with
  /// [getDependencies].
  ///
  /// By default this method sets the inherited dependencies for [dependent]
  /// to null. This only serves to record an unconditional dependency on
  /// [dependent].
  ///
  /// Subclasses can manage their own dependencies values so that they
  /// can selectively rebuild dependents in [notifyDependent].
  ///
  /// See also:
  ///
  ///  * [getDependencies], which returns the current value for a dependent
  ///    element.
  ///  * [setDependencies], which sets the value for a dependent element.
  ///  * [notifyDependent], which can be overridden to use a dependent's
  ///    dependencies value to decide if the dependent needs to be rebuilt.
  ///  * [InheritedModel], which is an example of a class that uses this method
  ///    to manage dependency values.
  @protected
  void updateDependencies(Element dependent, Object? aspect) {
    setDependencies(dependent, null);
  }

  /// Called by [notifyClients] for each dependent.
  ///
  /// Calls `dependent.didChangeDependencies()` by default.
  ///
  /// Subclasses can override this method to selectively call
  /// [didChangeDependencies] based on the value of [getDependencies].
  ///
  /// See also:
  ///
  ///  * [updateDependencies], which is called each time a dependency is
  ///    created with [dependOnInheritedWidgetOfExactType].
  ///  * [getDependencies], which returns the current value for a dependent
  ///    element.
  ///  * [setDependencies], which sets the value for a dependent element.
  ///  * [InheritedModel], which is an example of a class that uses this method
  ///    to manage dependency values.
  @protected
  void notifyDependent(covariant InheritedWidget oldWidget, Element dependent) {
    dependent.didChangeDependencies();
  }

  /// Calls [Element.didChangeDependencies] of all dependent elements, if
  /// [InheritedWidget.updateShouldNotify] returns true.
  ///
  /// Called by [update], immediately prior to [build].
  ///
  /// Calls [notifyClients] to actually trigger the notifications.
  @override
  void updated(InheritedWidget oldWidget) {
    if (widget.updateShouldNotify(oldWidget))
      super.updated(oldWidget);
  }

  /// Notifies all dependent elements that this inherited widget has changed, by
  /// calling [Element.didChangeDependencies].
  ///
  /// This method must only be called during the build phase. Usually this
  /// method is called automatically when an inherited widget is rebuilt, e.g.
  /// as a result of calling [State.setState] above the inherited widget.
  ///
  /// See also:
  ///
  ///  * [InheritedNotifier], a subclass of [InheritedWidget] that also calls
  ///    this method when its [Listenable] sends a notification.
  @override
  void notifyClients(InheritedWidget oldWidget) {
    assert(_debugCheckOwnerBuildTargetExists('notifyClients'));
    for (final Element dependent in _dependents.keys) {
      assert(() {
        // check that it really is our descendant
        Element? ancestor = dependent._parent;
        while (ancestor != this && ancestor != null)
          ancestor = ancestor._parent;
        return ancestor == this;
      }());
      // check that it really depends on us
      assert(dependent._dependencies!.contains(this));
      notifyDependent(oldWidget, dependent);
    }
  }
}

///使用[RenderObjectWidget]作为其配置的[Element]。
abstract class RenderObjectElement extends Element {
  /// Creates an element that uses the given widget as its configuration.
  RenderObjectElement(RenderObjectWidget widget) : super(widget);

  @override
  RenderObjectWidget get widget => super.widget as RenderObjectWidget;

  /// The underlying [RenderObject] for this element.
  @override
  RenderObject get renderObject => _renderObject;
  late RenderObject _renderObject;

  bool _debugDoingBuild = false;
  @override
  bool get debugDoingBuild => _debugDoingBuild;

  RenderObjectElement? _ancestorRenderObjectElement;

  RenderObjectElement? _findAncestorRenderObjectElement() {
    Element? ancestor = _parent;
    while (ancestor != null && ancestor is! RenderObjectElement)
      ancestor = ancestor._parent;
    return ancestor as RenderObjectElement?;
  }

  ParentDataElement<ParentData>? _findAncestorParentDataElement() {
    Element? ancestor = _parent;
    ParentDataElement<ParentData>? result;
    while (ancestor != null && ancestor is! RenderObjectElement) {
      if (ancestor is ParentDataElement<ParentData>) {
        result = ancestor;
        break;
      }
      ancestor = ancestor._parent;
    }
    assert(() {
      if (result == null || ancestor == null) {
        return true;
      }
      // Check that no other ParentDataWidgets want to provide parent data.
      final List<ParentDataElement<ParentData>> badAncestors = <ParentDataElement<ParentData>>[];
      ancestor = ancestor!._parent;
      while (ancestor != null && ancestor is! RenderObjectElement) {
        if (ancestor is ParentDataElement<ParentData>) {
          badAncestors.add(ancestor! as ParentDataElement<ParentData>);
        }
        ancestor = ancestor!._parent;
      }
      if (badAncestors.isNotEmpty) {
        badAncestors.insert(0, result);
        try {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('Incorrect use of ParentDataWidget.'),
            ErrorDescription('The following ParentDataWidgets are providing parent data to the same RenderObject:'),
            for (final ParentDataElement<ParentData> ancestor in badAncestors)
              ErrorDescription('- ${ancestor.widget} (typically placed directly inside a ${ancestor.widget.debugTypicalAncestorWidgetClass} widget)'),
            ErrorDescription('However, a RenderObject can only receive parent data from at most one ParentDataWidget.'),
            ErrorHint('Usually, this indicates that at least one of the offending ParentDataWidgets listed above is not placed directly inside a compatible ancestor widget.'),
            ErrorDescription('The ownership chain for the RenderObject that received the parent data was:\n  ${debugGetCreatorChain(10)}'),
          ]);
        } on FlutterError catch (e) {
          _debugReportException(ErrorSummary('while looking for parent data.'), e, e.stackTrace);
        }
      }
      return true;
    }());
    return result;
  }

  @override
  void mount(Element? parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    _renderObject = widget.createRenderObject(this);
    attachRenderObject(newSlot);
    _dirty = false;
  }

  @override
  void update(covariant RenderObjectWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    assert(() {
      _debugUpdateRenderObjectOwner();
      return true;
    }());
    assert(() {
      _debugDoingBuild = true;
      return true;
    }());
    widget.updateRenderObject(this, renderObject);
    assert(() {
      _debugDoingBuild = false;
      return true;
    }());
    _dirty = false;
  }

  void _debugUpdateRenderObjectOwner() {
    assert(() {
      _renderObject.debugCreator = DebugCreator(this);
      return true;
    }());
  }

  @override
  void performRebuild() {
    assert(() {
      _debugDoingBuild = true;
      return true;
    }());
    widget.updateRenderObject(this, renderObject);
    assert(() {
      _debugDoingBuild = false;
      return true;
    }());
    _dirty = false;
  }

  /// Updates the children of this element to use new widgets.
  ///
  /// Attempts to update the given old children list using the given new
  /// widgets, removing obsolete elements and introducing new ones as necessary,
  /// and then returns the new child list.
  ///
  /// During this function the `oldChildren` list must not be modified. If the
  /// caller wishes to remove elements from `oldChildren` re-entrantly while
  /// this function is on the stack, the caller can supply a `forgottenChildren`
  /// argument, which can be modified while this function is on the stack.
  /// Whenever this function reads from `oldChildren`, this function first
  /// checks whether the child is in `forgottenChildren`. If it is, the function
  /// acts as if the child was not in `oldChildren`.
  ///
  /// This function is a convenience wrapper around [updateChild], which updates
  /// each individual child. When calling [updateChild], this function uses an
  /// [IndexedSlot<Element>] as the value for the `newSlot` argument.
  /// [IndexedSlot.index] is set to the index that the currently processed
  /// `child` corresponds to in the `newWidgets` list and [IndexedSlot.value] is
  /// set to the [Element] of the previous widget in that list (or null if it is
  /// the first child).
  ///
  /// When the [slot] value of an [Element] changes, its
  /// associated [renderObject] needs to move to a new position in the child
  /// list of its parents. If that [RenderObject] organizes its children in a
  /// linked list (as is done by the [ContainerRenderObjectMixin]) this can
  /// be implemented by re-inserting the child [RenderObject] into the
  /// list after the [RenderObject] associated with the [Element] provided as
  /// [IndexedSlot.value] in the [slot] object.
  ///
  /// Simply using the previous sibling as a [slot] is not enough, though, because
  /// child [RenderObject]s are only moved around when the [slot] of their
  /// associated [RenderObjectElement]s is updated. When the order of child
  /// [Element]s is changed, some elements in the list may move to a new index
  /// but still have the same previous sibling. For example, when
  /// `[e1, e2, e3, e4]` is changed to `[e1, e3, e4, e2]` the element e4
  /// continues to have e3 as a previous sibling even though its index in the list
  /// has changed and its [RenderObject] needs to move to come before e2's
  /// [RenderObject]. In order to trigger this move, a new [slot] value needs to
  /// be assigned to its [Element] whenever its index in its
  /// parent's child list changes. Using an [IndexedSlot<Element>] achieves
  /// exactly that and also ensures that the underlying parent [RenderObject]
  /// knows where a child needs to move to in a linked list by providing its new
  /// previous sibling.
  @protected
  List<Element> updateChildren(List<Element> oldChildren, List<Widget> newWidgets, { Set<Element>? forgottenChildren }) {
    assert(oldChildren != null);
    assert(newWidgets != null);

    Element? replaceWithNullIfForgotten(Element child) {
      return forgottenChildren != null && forgottenChildren.contains(child) ? null : child;
    }

    // This attempts to diff the new child list (newWidgets) with
    // the old child list (oldChildren), and produce a new list of elements to
    // be the new list of child elements of this element. The called of this
    // method is expected to update this render object accordingly.

    // The cases it tries to optimize for are:
    //  - the old list is empty
    //  - the lists are identical
    //  - there is an insertion or removal of one or more widgets in
    //    only one place in the list
    // If a widget with a key is in both lists, it will be synced.
    // Widgets without keys might be synced but there is no guarantee.

    // The general approach is to sync the entire new list backwards, as follows:
    // 1. Walk the lists from the top, syncing nodes, until you no longer have
    //    matching nodes.
    // 2. Walk the lists from the bottom, without syncing nodes, until you no
    //    longer have matching nodes. We'll sync these nodes at the end. We
    //    don't sync them now because we want to sync all the nodes in order
    //    from beginning to end.
    // At this point we narrowed the old and new lists to the point
    // where the nodes no longer match.
    // 3. Walk the narrowed part of the old list to get the list of
    //    keys and sync null with non-keyed items.
    // 4. Walk the narrowed part of the new list forwards:
    //     * Sync non-keyed items with null
    //     * Sync keyed items with the source if it exists, else with null.
    // 5. Walk the bottom of the list again, syncing the nodes.
    // 6. Sync null with any items in the list of keys that are still
    //    mounted.

    int newChildrenTop = 0;
    int oldChildrenTop = 0;
    int newChildrenBottom = newWidgets.length - 1;
    int oldChildrenBottom = oldChildren.length - 1;

    final List<Element> newChildren = oldChildren.length == newWidgets.length ?
        oldChildren : List<Element>.filled(newWidgets.length, _NullElement.instance, growable: false);

    Element? previousChild;

    // Update the top of the list.
    while ((oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom)) {
      final Element? oldChild = replaceWithNullIfForgotten(oldChildren[oldChildrenTop]);
      final Widget newWidget = newWidgets[newChildrenTop];
      assert(oldChild == null || oldChild._lifecycleState == _ElementLifecycle.active);
      if (oldChild == null || !Widget.canUpdate(oldChild.widget, newWidget))
        break;
      final Element newChild = updateChild(oldChild, newWidget, IndexedSlot<Element?>(newChildrenTop, previousChild))!;
      assert(newChild._lifecycleState == _ElementLifecycle.active);
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
      oldChildrenTop += 1;
    }

    // Scan the bottom of the list.
    while ((oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom)) {
      final Element? oldChild = replaceWithNullIfForgotten(oldChildren[oldChildrenBottom]);
      final Widget newWidget = newWidgets[newChildrenBottom];
      assert(oldChild == null || oldChild._lifecycleState == _ElementLifecycle.active);
      if (oldChild == null || !Widget.canUpdate(oldChild.widget, newWidget))
        break;
      oldChildrenBottom -= 1;
      newChildrenBottom -= 1;
    }

    // Scan the old children in the middle of the list.
    final bool haveOldChildren = oldChildrenTop <= oldChildrenBottom;
    Map<Key, Element>? oldKeyedChildren;
    if (haveOldChildren) {
      oldKeyedChildren = <Key, Element>{};
      while (oldChildrenTop <= oldChildrenBottom) {
        final Element? oldChild = replaceWithNullIfForgotten(oldChildren[oldChildrenTop]);
        assert(oldChild == null || oldChild._lifecycleState == _ElementLifecycle.active);
        if (oldChild != null) {
          if (oldChild.widget.key != null)
            oldKeyedChildren[oldChild.widget.key!] = oldChild;
          else
            deactivateChild(oldChild);
        }
        oldChildrenTop += 1;
      }
    }

    // Update the middle of the list.
    while (newChildrenTop <= newChildrenBottom) {
      Element? oldChild;
      final Widget newWidget = newWidgets[newChildrenTop];
      if (haveOldChildren) {
        final Key? key = newWidget.key;
        if (key != null) {
          oldChild = oldKeyedChildren![key];
          if (oldChild != null) {
            if (Widget.canUpdate(oldChild.widget, newWidget)) {
              // we found a match!
              // remove it from oldKeyedChildren so we don't unsync it later
              oldKeyedChildren.remove(key);
            } else {
              // Not a match, let's pretend we didn't see it for now.
              oldChild = null;
            }
          }
        }
      }
      assert(oldChild == null || Widget.canUpdate(oldChild.widget, newWidget));
      final Element newChild = updateChild(oldChild, newWidget, IndexedSlot<Element?>(newChildrenTop, previousChild))!;
      assert(newChild._lifecycleState == _ElementLifecycle.active);
      assert(oldChild == newChild || oldChild == null || oldChild._lifecycleState != _ElementLifecycle.active);
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
    }

    // We've scanned the whole list.
    assert(oldChildrenTop == oldChildrenBottom + 1);
    assert(newChildrenTop == newChildrenBottom + 1);
    assert(newWidgets.length - newChildrenTop == oldChildren.length - oldChildrenTop);
    newChildrenBottom = newWidgets.length - 1;
    oldChildrenBottom = oldChildren.length - 1;

    // Update the bottom of the list.
    while ((oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom)) {
      final Element oldChild = oldChildren[oldChildrenTop];
      assert(replaceWithNullIfForgotten(oldChild) != null);
      assert(oldChild._lifecycleState == _ElementLifecycle.active);
      final Widget newWidget = newWidgets[newChildrenTop];
      assert(Widget.canUpdate(oldChild.widget, newWidget));
      final Element newChild = updateChild(oldChild, newWidget, IndexedSlot<Element?>(newChildrenTop, previousChild))!;
      assert(newChild._lifecycleState == _ElementLifecycle.active);
      assert(oldChild == newChild || oldChild == null || oldChild._lifecycleState != _ElementLifecycle.active);
      newChildren[newChildrenTop] = newChild;
      previousChild = newChild;
      newChildrenTop += 1;
      oldChildrenTop += 1;
    }

    // Clean up any of the remaining middle nodes from the old list.
    if (haveOldChildren && oldKeyedChildren!.isNotEmpty) {
      for (final Element oldChild in oldKeyedChildren.values) {
        if (forgottenChildren == null || !forgottenChildren.contains(oldChild))
          deactivateChild(oldChild);
      }
    }
    assert(newChildren.every((Element element) => element is! _NullElement));
    return newChildren;
  }

  @override
  void deactivate() {
    super.deactivate();
    assert(!renderObject.attached,
      'A RenderObject was still attached when attempting to deactivate its '
      'RenderObjectElement: $renderObject');
  }

  @override
  void unmount() {
    super.unmount();
    assert(!renderObject.attached,
      'A RenderObject was still attached when attempting to unmount its '
      'RenderObjectElement: $renderObject');
    widget.didUnmountRenderObject(renderObject);
  }

  void _updateParentData(ParentDataWidget<ParentData> parentDataWidget) {
    bool applyParentData = true;
    assert(() {
      try {
        if (!parentDataWidget.debugIsValidRenderObject(renderObject)) {
          applyParentData = false;
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary('Incorrect use of ParentDataWidget.'),
            ...parentDataWidget._debugDescribeIncorrectParentDataType(
              parentData: renderObject.parentData,
              parentDataCreator: _ancestorRenderObjectElement!.widget,
              ownershipChain: ErrorDescription(debugGetCreatorChain(10)),
            ),
          ]);
        }
      } on FlutterError catch (e) {
        // Catching the exception directly to avoid activating the ErrorWidget.
        // Since the tree is in a broken state, adding the ErrorWidget would
        // cause more exceptions.
        _debugReportException(ErrorSummary('while applying parent data.'), e, e.stackTrace);
      }
      return true;
    }());
    if (applyParentData)
      parentDataWidget.applyParentData(renderObject);
  }

  @override
  void _updateSlot(dynamic newSlot) {
    final dynamic oldSlot = slot;
    assert(oldSlot != newSlot);
    super._updateSlot(newSlot);
    assert(slot == newSlot);
    _ancestorRenderObjectElement!.moveRenderObjectChild(renderObject, oldSlot, slot);
  }

  @override
  void attachRenderObject(dynamic newSlot) {
    assert(_ancestorRenderObjectElement == null);
    _slot = newSlot;
    _ancestorRenderObjectElement = _findAncestorRenderObjectElement();
    _ancestorRenderObjectElement?.insertRenderObjectChild(renderObject, newSlot);
    final ParentDataElement<ParentData>? parentDataElement = _findAncestorParentDataElement();
    if (parentDataElement != null)
      _updateParentData(parentDataElement.widget);
  }

  @override
  void detachRenderObject() {
    if (_ancestorRenderObjectElement != null) {
      _ancestorRenderObjectElement!.removeRenderObjectChild(renderObject, slot);
      _ancestorRenderObjectElement = null;
    }
    _slot = null;
  }

  /// Insert the given child into [renderObject] at the given slot.
  ///
  /// {@macro flutter.widgets.RenderObjectElement.insertRenderObjectChild}
  ///
  /// ## Deprecation
  ///
  /// This method has been deprecated in favor of [insertRenderObjectChild].
  ///
  /// The reason for the deprecation is to provide the `oldSlot` argument to
  /// the [moveRenderObjectChild] method (such an argument was missing from
  /// the now-deprecated [moveChildRenderObject] method) and the `slot`
  /// argument to the [removeRenderObjectChild] method (such an argument was
  /// missing from the now-deprecated [removeChildRenderObject] method). While
  /// no argument was added to [insertRenderObjectChild], the name change (and
  /// corresponding deprecation) was made to maintain naming parity with the
  /// other two methods.
  ///
  /// To migrate, simply override [insertRenderObjectChild] instead of
  /// [insertChildRenderObject]. The arguments stay the same. Subclasses should
  /// _not_ call `super.insertRenderObjectChild(...)`.
  @protected
  @mustCallSuper
  @Deprecated(
    'Override insertRenderObjectChild instead. '
    'This feature was deprecated after v1.21.0-9.0.pre.'
  )
  void insertChildRenderObject(covariant RenderObject child, covariant dynamic slot) {
    assert(() {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('RenderObjectElement.insertChildRenderObject() is deprecated.'),
        toDiagnosticsNode(
          name: 'insertChildRenderObject() was called on this Element',
          style: DiagnosticsTreeStyle.shallow,
        ),
        ErrorDescription('insertChildRenderObject() has been deprecated in favor of '
          'insertRenderObjectChild(). See https://github.com/flutter/flutter/issues/63269 '
          'for details.'),
        ErrorHint('Rather than overriding insertChildRenderObject() in your '
          'RenderObjectElement subclass, override insertRenderObjectChild() instead, '
          "and DON'T call super.insertRenderObjectChild(). If you're implementing a "
          'new RenderObjectElement, you should override/implement '
          'insertRenderObjectChild(), moveRenderObjectChild(), and '
          'removeRenderObjectChild().'),
      ]);
    }());
  }

  /// Insert the given child into [renderObject] at the given slot.
  ///
  /// {@template flutter.widgets.RenderObjectElement.insertRenderObjectChild}
  /// The semantics of `slot` are determined by this element. For example, if
  /// this element has a single child, the slot should always be null. If this
  /// element has a list of children, the previous sibling element wrapped in an
  /// [IndexedSlot] is a convenient value for the slot.
  /// {@endtemplate}
  @protected
  void insertRenderObjectChild(covariant RenderObject child, covariant dynamic slot) {
    insertChildRenderObject(child, slot);
  }

  /// Move the given child to the given slot.
  ///
  /// The given child is guaranteed to have [renderObject] as its parent.
  ///
  /// {@macro flutter.widgets.RenderObjectElement.insertRenderObjectChild}
  ///
  /// This method is only ever called if [updateChild] can end up being called
  /// with an existing [Element] child and a `slot` that differs from the slot
  /// that element was previously given. [MultiChildRenderObjectElement] does this,
  /// for example. [SingleChildRenderObjectElement] does not (since the `slot` is
  /// always null). An [Element] that has a specific set of slots with each child
  /// always having the same slot (and where children in different slots are never
  /// compared against each other for the purposes of updating one slot with the
  /// element from another slot) would never call this.
  ///
  /// ## Deprecation
  ///
  /// This method has been deprecated in favor of [moveRenderObjectChild].
  ///
  /// The reason for the deprecation is to provide the `oldSlot` argument to
  /// the [moveRenderObjectChild] method (such an argument was missing from
  /// the now-deprecated [moveChildRenderObject] method) and the `slot`
  /// argument to the [removeRenderObjectChild] method (such an argument was
  /// missing from the now-deprecated [removeChildRenderObject] method). While
  /// no argument was added to [insertRenderObjectChild], the name change (and
  /// corresponding deprecation) was made to maintain naming parity with the
  /// other two methods.
  ///
  /// To migrate, simply override [moveRenderObjectChild] instead of
  /// [moveChildRenderObject]. The `slot` argument becomes the `newSlot`
  /// argument, and the method will now take a new `oldSlot` argument that
  /// subclasses may find useful. Subclasses should _not_ call
  /// `super.moveRenderObjectChild(...)`.
  @protected
  @mustCallSuper
  @Deprecated(
    'Override moveRenderObjectChild instead. '
    'This feature was deprecated after v1.21.0-9.0.pre.'
  )
  void moveChildRenderObject(covariant RenderObject child, covariant dynamic slot) {
    assert(() {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('RenderObjectElement.moveChildRenderObject() is deprecated.'),
        toDiagnosticsNode(
          name: 'super.moveChildRenderObject() was called on this Element',
          style: DiagnosticsTreeStyle.shallow,
        ),
        ErrorDescription('moveChildRenderObject() has been deprecated in favor of '
            'moveRenderObjectChild(). See https://github.com/flutter/flutter/issues/63269 '
            'for details.'),
        ErrorHint('Rather than overriding moveChildRenderObject() in your '
            'RenderObjectElement subclass, override moveRenderObjectChild() instead, '
            "and DON'T call super.moveRenderObjectChild(). If you're implementing a "
            'new RenderObjectElement, you should override/implement '
            'insertRenderObjectChild(), moveRenderObjectChild(), and '
            'removeRenderObjectChild().'),
      ]);
    }());
  }

  /// Move the given child from the given old slot to the given new slot.
  ///
  /// The given child is guaranteed to have [renderObject] as its parent.
  ///
  /// {@macro flutter.widgets.RenderObjectElement.insertRenderObjectChild}
  ///
  /// This method is only ever called if [updateChild] can end up being called
  /// with an existing [Element] child and a `slot` that differs from the slot
  /// that element was previously given. [MultiChildRenderObjectElement] does this,
  /// for example. [SingleChildRenderObjectElement] does not (since the `slot` is
  /// always null). An [Element] that has a specific set of slots with each child
  /// always having the same slot (and where children in different slots are never
  /// compared against each other for the purposes of updating one slot with the
  /// element from another slot) would never call this.
  @protected
  void moveRenderObjectChild(covariant RenderObject child, covariant dynamic oldSlot, covariant dynamic newSlot) {
    moveChildRenderObject(child, newSlot);
  }

  /// Remove the given child from [renderObject].
  ///
  /// The given child is guaranteed to have [renderObject] as its parent.
  ///
  /// ## Deprecation
  ///
  /// This method has been deprecated in favor of [removeRenderObjectChild].
  ///
  /// The reason for the deprecation is to provide the `oldSlot` argument to
  /// the [moveRenderObjectChild] method (such an argument was missing from
  /// the now-deprecated [moveChildRenderObject] method) and the `slot`
  /// argument to the [removeRenderObjectChild] method (such an argument was
  /// missing from the now-deprecated [removeChildRenderObject] method). While
  /// no argument was added to [insertRenderObjectChild], the name change (and
  /// corresponding deprecation) was made to maintain naming parity with the
  /// other two methods.
  ///
  /// To migrate, simply override [removeRenderObjectChild] instead of
  /// [removeChildRenderObject]. The method will now take a new `slot` argument
  /// that subclasses may find useful. Subclasses should _not_ call
  /// `super.removeRenderObjectChild(...)`.
  @protected
  @mustCallSuper
  @Deprecated(
    'Override removeRenderObjectChild instead. '
    'This feature was deprecated after v1.21.0-9.0.pre.'
  )
  void removeChildRenderObject(covariant RenderObject child) {
    assert(() {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('RenderObjectElement.removeChildRenderObject() is deprecated.'),
        toDiagnosticsNode(
          name: 'super.removeChildRenderObject() was called on this Element',
          style: DiagnosticsTreeStyle.shallow,
        ),
        ErrorDescription('removeChildRenderObject() has been deprecated in favor of '
            'removeRenderObjectChild(). See https://github.com/flutter/flutter/issues/63269 '
            'for details.'),
        ErrorHint('Rather than overriding removeChildRenderObject() in your '
            'RenderObjectElement subclass, override removeRenderObjectChild() instead, '
            "and DON'T call super.removeRenderObjectChild(). If you're implementing a "
            'new RenderObjectElement, you should override/implement '
            'insertRenderObjectChild(), moveRenderObjectChild(), and '
            'removeRenderObjectChild().'),
      ]);
    }());
  }

  /// Remove the given child from [renderObject].
  ///
  /// The given child is guaranteed to have been inserted at the given `slot`
  /// and have [renderObject] as its parent.
  @protected
  void removeRenderObjectChild(covariant RenderObject child, covariant dynamic slot) {
    removeChildRenderObject(child);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<RenderObject>('renderObject', renderObject, defaultValue: null));
  }
}

/// The element at the root of the tree.
///
/// Only root elements may have their owner set explicitly. All other
/// elements inherit their owner from their parent.
abstract class RootRenderObjectElement extends RenderObjectElement {
  /// Initializes fields for subclasses.
  RootRenderObjectElement(RenderObjectWidget widget) : super(widget);

  /// Set the owner of the element. The owner will be propagated to all the
  /// descendants of this element.
  ///
  /// The owner manages the dirty elements list.
  ///
  /// The [WidgetsBinding] introduces the primary owner,
  /// [WidgetsBinding.buildOwner], and assigns it to the widget tree in the call
  /// to [runApp]. The binding is responsible for driving the build pipeline by
  /// calling the build owner's [BuildOwner.buildScope] method. See
  /// [WidgetsBinding.drawFrame].
  void assignOwner(BuildOwner owner) {
    _owner = owner;
  }

  @override
  void mount(Element? parent, dynamic newSlot) {
    // Root elements should never have parents.
    assert(parent == null);
    assert(newSlot == null);
    super.mount(parent, newSlot);
  }
}

/// An [Element] that uses a [LeafRenderObjectWidget] as its configuration.
class LeafRenderObjectElement extends RenderObjectElement {
  /// Creates an element that uses the given widget as its configuration.
  LeafRenderObjectElement(LeafRenderObjectWidget widget) : super(widget);

  @override
  void forgetChild(Element child) {
    assert(false);
    super.forgetChild(child);
  }

  @override
  void insertRenderObjectChild(RenderObject child, dynamic slot) {
    assert(false);
  }

  @override
  void moveRenderObjectChild(RenderObject child, dynamic oldSlot, dynamic newSlot) {
    assert(false);
  }

  @override
  void removeRenderObjectChild(RenderObject child, dynamic slot) {
    assert(false);
  }

  @override
  List<DiagnosticsNode> debugDescribeChildren() {
    return widget.debugDescribeChildren();
  }
}

/// An [Element] that uses a [SingleChildRenderObjectWidget] as its configuration.
///
/// The child is optional.
///
/// This element subclass can be used for RenderObjectWidgets whose
/// RenderObjects use the [RenderObjectWithChildMixin] mixin. Such widgets are
/// expected to inherit from [SingleChildRenderObjectWidget].
class SingleChildRenderObjectElement extends RenderObjectElement {
  /// Creates an element that uses the given widget as its configuration.
  SingleChildRenderObjectElement(SingleChildRenderObjectWidget widget) : super(widget);

  @override
  SingleChildRenderObjectWidget get widget => super.widget as SingleChildRenderObjectWidget;

  Element? _child;

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_child != null)
      visitor(_child!);
  }

  @override
  void forgetChild(Element child) {
    assert(child == _child);
    _child = null;
    super.forgetChild(child);
  }

  @override
  void mount(Element? parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    _child = updateChild(_child, widget.child, null);
  }

  @override
  void update(SingleChildRenderObjectWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    _child = updateChild(_child, widget.child, null);
  }

  @override
  void insertRenderObjectChild(RenderObject child, dynamic slot) {
    final RenderObjectWithChildMixin<RenderObject> renderObject = this.renderObject as RenderObjectWithChildMixin<RenderObject>;
    assert(slot == null);
    assert(renderObject.debugValidateChild(child));
    renderObject.child = child;
    assert(renderObject == this.renderObject);
  }

  @override
  void moveRenderObjectChild(RenderObject child, dynamic oldSlot, dynamic newSlot) {
    assert(false);
  }

  @override
  void removeRenderObjectChild(RenderObject child, dynamic slot) {
    final RenderObjectWithChildMixin<RenderObject> renderObject = this.renderObject as RenderObjectWithChildMixin<RenderObject>;
    assert(slot == null);
    assert(renderObject.child == child);
    renderObject.child = null;
    assert(renderObject == this.renderObject);
  }
}

/// An [Element] that uses a [MultiChildRenderObjectWidget] as its configuration.
///
/// This element subclass can be used for RenderObjectWidgets whose
/// RenderObjects use the [ContainerRenderObjectMixin] mixin with a parent data
/// type that implements [ContainerParentDataMixin<RenderObject>]. Such widgets
/// are expected to inherit from [MultiChildRenderObjectWidget].
///
/// See also:
///
/// * [IndexedSlot], which is used as [Element.slot]s for the children of a
///   [MultiChildRenderObjectElement].
/// * [RenderObjectElement.updateChildren], which discusses why [IndexedSlot]
///   is used for the slots of the children.
class MultiChildRenderObjectElement extends RenderObjectElement {
  /// Creates an element that uses the given widget as its configuration.
  MultiChildRenderObjectElement(MultiChildRenderObjectWidget widget)
    : assert(!debugChildrenHaveDuplicateKeys(widget, widget.children)),
      super(widget);

  @override
  MultiChildRenderObjectWidget get widget => super.widget as MultiChildRenderObjectWidget;

  @override
  ContainerRenderObjectMixin<RenderObject, ContainerParentDataMixin<RenderObject>> get renderObject {
    return super.renderObject as ContainerRenderObjectMixin<RenderObject, ContainerParentDataMixin<RenderObject>>;
  }

  /// The current list of children of this element.
  ///
  /// This list is filtered to hide elements that have been forgotten (using
  /// [forgetChild]).
  @protected
  @visibleForTesting
  Iterable<Element> get children => _children.where((Element child) => !_forgottenChildren.contains(child));

  late List<Element> _children;
  // We keep a set of forgotten children to avoid O(n^2) work walking _children
  // repeatedly to remove children.
  final Set<Element> _forgottenChildren = HashSet<Element>();

  @override
  void insertRenderObjectChild(RenderObject child, IndexedSlot<Element?> slot) {
    final ContainerRenderObjectMixin<RenderObject, ContainerParentDataMixin<RenderObject>> renderObject = this.renderObject;
    assert(renderObject.debugValidateChild(child));
    renderObject.insert(child, after: slot.value?.renderObject);
    assert(renderObject == this.renderObject);
  }

  @override
  void moveRenderObjectChild(RenderObject child, IndexedSlot<Element?> oldSlot, IndexedSlot<Element?> newSlot) {
    final ContainerRenderObjectMixin<RenderObject, ContainerParentDataMixin<RenderObject>> renderObject = this.renderObject;
    assert(child.parent == renderObject);
    renderObject.move(child, after: newSlot.value?.renderObject);
    assert(renderObject == this.renderObject);
  }

  @override
  void removeRenderObjectChild(RenderObject child, dynamic slot) {
    final ContainerRenderObjectMixin<RenderObject, ContainerParentDataMixin<RenderObject>> renderObject = this.renderObject;
    assert(child.parent == renderObject);
    renderObject.remove(child);
    assert(renderObject == this.renderObject);
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    for (final Element child in _children) {
      if (!_forgottenChildren.contains(child))
        visitor(child);
    }
  }

  @override
  void forgetChild(Element child) {
    assert(_children.contains(child));
    assert(!_forgottenChildren.contains(child));
    _forgottenChildren.add(child);
    super.forgetChild(child);
  }

  @override
  void mount(Element? parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    final List<Element> children = List<Element>.filled(widget.children.length, _NullElement.instance, growable: false);
    Element? previousChild;
    for (int i = 0; i < children.length; i += 1) {
      final Element newChild = inflateWidget(widget.children[i], IndexedSlot<Element?>(i, previousChild));
      children[i] = newChild;
      previousChild = newChild;
    }
    _children = children;
  }

  @override
  void update(MultiChildRenderObjectWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    _children = updateChildren(_children, widget.children, forgottenChildren: _forgottenChildren);
    _forgottenChildren.clear();
  }
}

/// A wrapper class for the [Element] that is the creator of a [RenderObject].
///
/// Attaching a [DebugCreator] attach the [RenderObject] will lead to better error
/// message.
class DebugCreator {
  /// Create a [DebugCreator] instance with input [Element].
  DebugCreator(this.element);

  /// The creator of the [RenderObject].
  final Element element;

  @override
  String toString() => element.debugGetCreatorChain(12);
}

FlutterErrorDetails _debugReportException(
  DiagnosticsNode context,
  Object exception,
  StackTrace? stack, {
  InformationCollector? informationCollector,
}) {
  final FlutterErrorDetails details = FlutterErrorDetails(
    exception: exception,
    stack: stack,
    library: 'widgets library',
    context: context,
    informationCollector: informationCollector,
  );
  FlutterError.reportError(details);
  return details;
}

/// A value for [Element.slot] used for children of
/// [MultiChildRenderObjectElement]s.
///
/// A slot for a [MultiChildRenderObjectElement] consists of an [index]
/// identifying where the child occupying this slot is located in the
/// [MultiChildRenderObjectElement]'s child list and an arbitrary [value] that
/// can further define where the child occupying this slot fits in its
/// parent's child list.
///
/// See also:
///
///  * [RenderObjectElement.updateChildren], which discusses why this class is
///    used as slot values for the children of a [MultiChildRenderObjectElement].
@immutable
class IndexedSlot<T> {
  /// Creates an [IndexedSlot] with the provided [index] and slot [value].
  const IndexedSlot(this.index, this.value);

  /// Information to define where the child occupying this slot fits in its
  /// parent's child list.
  final T value;

  /// The index of this slot in the parent's child list.
  final int index;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType)
      return false;
    return other is IndexedSlot
        && index == other.index
        && value == other.value;
  }

  @override
  int get hashCode => hashValues(index, value);
}

class _NullElement extends Element {
  _NullElement() : super(_NullWidget());

  static _NullElement instance = _NullElement();

  @override
  bool get debugDoingBuild => throw UnimplementedError();

  @override
  void performRebuild() { }
}

class _NullWidget extends Widget {
  @override
  Element createElement() => throw UnimplementedError();
}
