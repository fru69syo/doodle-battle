import 'package:flutter/material.dart';

import 'family_setup.dart';

/// Team colours: あか (side a) and あお (side b).
Color familyColour(FamilySide side) =>
    side == FamilySide.a ? const Color(0xFFD7263D) : const Color(0xFF1E6FD9);
