import 'package:flutter/material.dart';

import '../../domain/battle/battle.dart';

/// Team colours: あか (side a) and あお (side b).
Color familyColour(Side side) =>
    side == Side.a ? const Color(0xFFD7263D) : const Color(0xFF1E6FD9);
