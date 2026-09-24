import 'package:flutter/foundation.dart';

import '../models/transurfing_brain.dart';

class BrainReflectionStore {
  BrainReflectionStore._();

  static final BrainReflectionStore instance = BrainReflectionStore._();

  final ValueNotifier<BrainReflection?> reflection = ValueNotifier(null);

  BrainReflection? get current => reflection.value;

  void update(BrainReflection next) {
    reflection.value = next;
  }

  void clear() {
    reflection.value = null;
  }
}
