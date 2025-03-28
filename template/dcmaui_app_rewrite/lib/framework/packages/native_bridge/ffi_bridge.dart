import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'native_bridge.dart';
import 'dart:developer' as developer;

/// FFI-based implementation of NativeBridge for iOS/macOS
class FFINativeBridge implements NativeBridge {
  late final DynamicLibrary _nativeLib;

  // Function pointers for native UI operations (ONLY)
  late final int Function() _initialize;
  late final int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)
      _createView;
  late final int Function(Pointer<Utf8>, Pointer<Utf8>) _updateView;
  late final int Function(Pointer<Utf8>) _deleteView;
  late final int Function(Pointer<Utf8>, Pointer<Utf8>, int) _attachView;
  late final int Function(Pointer<Utf8>, Pointer<Utf8>) _setChildren;

  // Event functions are removed from FFI completely

  // Event callback
  Function(String viewId, String eventType, Map<String, dynamic> eventData)?
      _eventHandler;

  // Method channel for events - PUBLIC so it can be accessed directly
  static const MethodChannel eventChannel = MethodChannel('com.dcmaui.events');

  // Sets up communication with native code
  FFINativeBridge() {
    // Load the native library
    if (Platform.isIOS || Platform.isMacOS) {
      _nativeLib = DynamicLibrary.process();
    } else {
      throw UnsupportedError('FFI bridge only supports iOS and macOS');
    }

    // Get function pointers for UI operations ONLY
    _initialize = _nativeLib
        .lookupFunction<Int8 Function(), int Function()>('dcmaui_initialize');

    _createView = _nativeLib.lookupFunction<
        Int8 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(
            Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>('dcmaui_create_view');

    _updateView = _nativeLib.lookupFunction<
        Int8 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)>('dcmaui_update_view');

    _deleteView = _nativeLib.lookupFunction<Int8 Function(Pointer<Utf8>),
        int Function(Pointer<Utf8>)>('dcmaui_delete_view');

    _attachView = _nativeLib.lookupFunction<
        Int8 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, Pointer<Utf8>, int)>('dcmaui_attach_view');

    _setChildren = _nativeLib.lookupFunction<
        Int8 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)>('dcmaui_set_children');

    // Event listener functions completely removed from FFI

    // Set up method channel for handling events
    _setupMethodChannelEventHandling();
  }

  // Set up method channel for event handling
  void _setupMethodChannelEventHandling() {
    eventChannel.setMethodCallHandler((call) async {
      if (call.method == 'onEvent') {
        final Map<dynamic, dynamic> args = call.arguments;
        final String viewId = args['viewId'];
        final String eventType = args['eventType'];
        final Map<String, dynamic> eventData =
            Map<String, dynamic>.from(args['eventData']);

        developer.log(
            'Event received in Dart through method channel: $viewId - $eventType - Data: $eventData',
            name: 'FFI');

        if (_eventHandler != null) {
          _eventHandler!(viewId, eventType, eventData);
        }
      }
      return null;
    });

    developer.log('Method channel event handling initialized', name: 'FFI');
  }

  @override
  Future<bool> initialize() async {
    try {
      developer.log('Initializing FFI bridge', name: 'FFI');
      final result = _initialize() != 0;
      developer.log('FFI bridge initialization result: $result', name: 'FFI');
      return result;
    } catch (e) {
      developer.log('Failed to initialize FFI bridge: $e', name: 'FFI');
      return false;
    }
  }

  @override
  Future<bool> createView(
      String viewId, String type, Map<String, dynamic> props) async {
    try {
      developer.log('Creating view via FFI: $viewId, $type', name: 'FFI');
      return using((arena) {
        // Preprocess props to handle special types before encoding to JSON
        final processedProps = _preprocessProps(props);

        final viewIdPointer = viewId.toNativeUtf8(allocator: arena);
        final typePointer = type.toNativeUtf8(allocator: arena);
        final propsJson = jsonEncode(processedProps);
        final propsPointer = propsJson.toNativeUtf8(allocator: arena);

        final result = _createView(viewIdPointer, typePointer, propsPointer);
        developer.log('FFI createView result: $result', name: 'FFI');
        return result != 0;
      });
    } catch (e) {
      developer.log('FFI createView error: $e', name: 'FFI');
      return false;
    }
  }

  @override
  Future<bool> updateView(
      String viewId, Map<String, dynamic> propPatches) async {
    developer.log('FFI updateView: viewId=$viewId, props=$propPatches',
        name: 'FFI');

    return using((arena) {
      final viewIdPointer = viewId.toNativeUtf8(allocator: arena);

      // Process props for updates
      final processedProps = _preprocessProps(propPatches);
      final propsJson = jsonEncode(processedProps);

      developer.log('FFI updateView sending JSON: $propsJson', name: 'FFI');

      final propsPointer = propsJson.toNativeUtf8(allocator: arena);

      final result = _updateView(viewIdPointer, propsPointer);
      developer.log('FFI updateView result: $result', name: 'FFI');
      return result != 0;
    });
  }

  @override
  Future<bool> deleteView(String viewId) async {
    return using((arena) {
      final viewIdPointer = viewId.toNativeUtf8(allocator: arena);

      final result = _deleteView(viewIdPointer);
      return result != 0; // Change from == 1 to != 0
    });
  }

  @override
  Future<bool> attachView(String childId, String parentId, int index) async {
    return using((arena) {
      final childIdPointer = childId.toNativeUtf8(allocator: arena);
      final parentIdPointer = parentId.toNativeUtf8(allocator: arena);

      final result = _attachView(childIdPointer, parentIdPointer, index);
      return result != 0; // Change from == 1 to != 0
    });
  }

  @override
  Future<bool> setChildren(String viewId, List<String> childrenIds) async {
    return using((arena) {
      final viewIdPointer = viewId.toNativeUtf8(allocator: arena);
      final childrenJson = jsonEncode(childrenIds);
      final childrenPointer = childrenJson.toNativeUtf8(allocator: arena);

      final result = _setChildren(viewIdPointer, childrenPointer);
      return result != 0; // Change from == 1 to != 0
    });
  }

  @override
  Future<bool> addEventListeners(String viewId, List<String> eventTypes) async {
    developer.log('Registering for events: $viewId, $eventTypes', name: 'FFI');

    // DIRECT METHOD CHANNEL ONLY - No FFI for events
    try {
      final result = await eventChannel.invokeMethod<bool>('registerEvents', {
        'viewId': viewId,
        'eventTypes': eventTypes,
      });

      if (result == true) {
        developer.log('Event registration succeeded via method channel',
            name: 'FFI');
        return true;
      } else {
        developer.log('Method channel event registration failed', name: 'FFI');
        return false;
      }
    } catch (e) {
      developer.log('Method channel event registration error: $e', name: 'FFI');
      return false;
    }
  }

  @override
  Future<bool> removeEventListeners(
      String viewId, List<String> eventTypes) async {
    // DIRECT METHOD CHANNEL ONLY - No FFI for events
    try {
      final result = await eventChannel.invokeMethod<bool>('unregisterEvents', {
        'viewId': viewId,
        'eventTypes': eventTypes,
      });

      if (result == true) {
        return true;
      } else {
        developer.log('Method channel event unregistration failed',
            name: 'FFI');
        return false;
      }
    } catch (e) {
      developer.log('Method channel event unregistration error: $e',
          name: 'FFI');
      return false;
    }
  }

  @override
  void setEventHandler(
      Function(String viewId, String eventType, Map<String, dynamic> eventData)
          handler) {
    _eventHandler = handler;
  }

  // Helper method to preprocess props for JSON serialization
  Map<String, dynamic> _preprocessProps(Map<String, dynamic> props) {
    final processedProps = <String, dynamic>{};

    props.forEach((key, value) {
      if (value is Function) {
        // Handle event handlers
        if (key.startsWith('on')) {
          final eventType = key.substring(2).toLowerCase();
          processedProps['_has${key.substring(2)}Handler'] = true;
          developer.log('Found function handler for event: $eventType',
              name: 'FFI');
        }
      } else if (value is Color) {
        // Convert Color objects to hex strings
        final hexValue = value.value & 0xFFFFFF;
        processedProps[key] = '#${hexValue.toRadixString(16).padLeft(6, '0')}';
      } else if (value == double.infinity) {
        // Convert infinity to 100% string for percentage sizing
        processedProps[key] = '100%';
      } else if (value == double.negativeInfinity) {
        // Just in case someone tries to use negative infinity
        processedProps[key] = '0%';
      } else if (key == 'transform' && value is Map<String, dynamic>) {
        // Special handling for transform to ensure all values are processed correctly
        final processedTransform = <String, dynamic>{};

        value.forEach((transformKey, transformValue) {
          // Make sure numeric values are properly converted
          if (transformValue is num) {
            processedTransform[transformKey] = transformValue.toDouble();
            developer.log('Processing transform $transformKey: $transformValue',
                name: 'FFI');
          } else {
            processedTransform[transformKey] = transformValue;
          }
        });

        processedProps[key] = processedTransform;
      } else if (value != null) {
        // Ensure numeric values like marginTop are properly processed
        if (value is num &&
            (key == 'marginTop' ||
                key == 'marginBottom' ||
                key == 'marginLeft' ||
                key == 'marginRight')) {
          processedProps[key] = value.toDouble();
          developer.log('Processing margin $key: $value', name: 'FFI');
        } else {
          processedProps[key] = value;
        }
      }
    });

    return processedProps;
  }
}
